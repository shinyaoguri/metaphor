#!/usr/bin/env python3
"""
Generate llms.txt from Swift Symbol Graph JSON files.

Reads Symbol Graph JSON produced by swift-symbolgraph-extract and generates
a compact API reference optimised for LLM consumption.

All module names, type lists, and categories are derived dynamically from
the symbol graphs — no hardcoded identifiers that break when the API evolves.

Usage:
    python3 scripts/generate-llms-txt.py [--symbol-graph-dir DIR] [-o FILE]
"""

import argparse
import json
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

# ---------------------------------------------------------------------------
# Symbol kind constants (part of the Symbol Graph spec, not project-specific)
# ---------------------------------------------------------------------------

KIND_METHOD = "swift.method"
KIND_PROPERTY = "swift.property"
KIND_TYPE_METHOD = "swift.type.method"
KIND_TYPE_PROPERTY = "swift.type.property"
KIND_FUNC = "swift.func"
KIND_FUNC_OP = "swift.func.op"
KIND_VAR = "swift.var"
KIND_INIT = "swift.init"
KIND_ENUM_CASE = "swift.enum.case"
KIND_PROTOCOL = "swift.protocol"
KIND_STRUCT = "swift.struct"
KIND_CLASS = "swift.class"
KIND_ENUM = "swift.enum"
KIND_TYPEALIAS = "swift.typealias"
KIND_EXTENSION = "swift.extension"
KIND_SUBSCRIPT = "swift.subscript"

TYPE_KINDS = {KIND_PROTOCOL, KIND_STRUCT, KIND_CLASS, KIND_ENUM, KIND_TYPEALIAS}
MEMBER_KINDS = {
    KIND_METHOD, KIND_PROPERTY, KIND_TYPE_METHOD, KIND_TYPE_PROPERTY,
    KIND_INIT, KIND_ENUM_CASE, KIND_SUBSCRIPT,
}

# `Module@Other.symbols.json` files hold this library's extensions on types
# declared elsewhere (Swift stdlib SIMD2/SIMD3, simd, Metal, …). They are NOT
# skipped: those members exist only because metaphor adds them, so llms.txt is
# the only place an agent can discover them (#298).

# Attributes are stripped from rendered declarations (mostly concurrency and
# availability noise). These are kept because they tell a sketch author how to
# spell the declaration — a property wrapper is written `@Param` at the use
# site, so dropping the attribute hides the entire point of the type (#421).
_KEPT_ATTRIBUTES = {"@propertyWrapper"}

# Sketch protocol name (used as the anchor for API-surface detection)
_SKETCH_TYPE = "Sketch"

# Overlap threshold: if a type shares this fraction of its method names with
# Sketch, it is condensed to a one-liner rather than listing every member.
_CONDENSED_OVERLAP_THRESHOLD = 0.60

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

def discover_package_version(readme_file: Path, package_file: Path) -> str:
    """Infer the SPM snippet version from repository metadata.

    Stable release automation updates README.md's `from:` example, so that is
    the first choice. The fallback reads `Metaphor.version` from
    Sources/MetaphorCore/Core/MetaphorVersion.swift (bumped on every release,
    prereleases included). Package.swift used to carry the version in its
    Syphon binaryTarget URL; that artifact moved to metaphor-syphon (#792), so
    `package_file` is kept only for the command-line interface.
    """
    try:
        text = readme_file.read_text(encoding="utf-8")
        match = re.search(
            r'github\.com/shinyaoguri/metaphor\.git", from: "([^"]+)"', text)
        if match:
            return match.group(1)
    except OSError:
        pass

    version_file = package_file.parent / "Sources" / "MetaphorCore" / "Core" / "MetaphorVersion.swift"
    try:
        text = version_file.read_text(encoding="utf-8")
    except OSError:
        print(
            "warning: could not read README.md or MetaphorVersion.swift to infer the package "
            "version — falling back to 0.0.0 (the generated SPM snippet will be wrong)",
            file=sys.stderr,
        )
        return "0.0.0"

    match = re.search(r'public static let version = "([^"]+)"', text)
    if match:
        return match.group(1)
    print(
        "warning: no version pattern found in README.md/MetaphorVersion.swift — falling "
        "back to 0.0.0 (the generated SPM snippet will be wrong)",
        file=sys.stderr,
    )
    return "0.0.0"


def build_header(package_version: str) -> str:
    """Build the static introductory section for llms.txt."""
    return """\
# metaphor

> Swift + Metal creative coding library inspired by Processing / p5.js / openFrameworks.
> macOS 14.0+ (Apple Silicon). Swift 5.10+. `import metaphor`

## Quick Start

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "Hello")
    }
    func setup() {
        // called once
    }
    func draw() {
        background(.black)
        fill(.white)
        circle(width / 2, height / 2, 200)
    }
}
```

Build & run an example:
```
cd Examples/Basics/Form/ShapePrimitives && swift build && swift run
```

SPM dependency:
```swift
.package(url: "https://github.com/shinyaoguri/metaphor.git", from: "__PACKAGE_VERSION__")
```

## Architecture Notes

- Multi-target SwiftPM package. Use `import metaphor` for the umbrella module,
  or import individual modules for narrower dependencies.
- User-facing calls flow through `Sketch` protocol extensions to `SketchContext`,
  then into `Canvas2D` / `Canvas3D` Metal backends.
- Each frame renders offscreen first, then blits to the window while preserving
  aspect ratio. Post-processing, RenderGraph, export, and output plugins (the
  live viewer, Syphon via the separate `metaphor-syphon` package) operate on the
  offscreen texture.
- `MetaphorCore` owns rendering, drawing, shaders, sketch lifecycle, resources,
  compute, export, and test support. Tier 1 modules avoid a Core dependency;
  Tier 2 modules build on Core and are bridged by the umbrella target.
""".replace("__PACKAGE_VERSION__", package_version)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def is_deprecated(symbol: dict) -> bool:
    """Check if symbol has @available(*, deprecated, ...)."""
    for f in symbol.get("declarationFragments", []):
        if f["kind"] == "attribute" and "deprecated" in f["spelling"]:
            return True
    for a in symbol.get("availability", []):
        if a.get("isUnconditionallyDeprecated", False):
            return True
        if "deprecated" in a:
            return True
    return False


def is_property_wrapper(symbol: dict) -> bool:
    """Check if a type is declared `@propertyWrapper`."""
    return any(f["kind"] == "attribute" and f["spelling"] == "@propertyWrapper"
               for f in symbol.get("declarationFragments", []))


def get_declaration(symbol: dict) -> str:
    """Build a clean one-line declaration from declarationFragments."""
    frags = symbol.get("declarationFragments", [])
    if not frags:
        return symbol["names"]["title"]

    parts: list[str] = []
    skip_ws = False
    for f in frags:
        if f["kind"] == "attribute":
            if f["spelling"] in _KEPT_ATTRIBUTES:
                parts.append(f["spelling"])
                skip_ws = False
                continue
            skip_ws = True
            continue
        if skip_ws and f["kind"] == "text" and f["spelling"].strip() == "":
            skip_ws = False
            continue
        skip_ws = False
        parts.append(f["spelling"])
    return "".join(parts).strip()


def get_parameter_type_references(symbol: dict) -> set[str]:
    """Type names a caller has to *pass* to this symbol (parameter types only).

    Properties and return types are what a caller *receives*; they are reachable
    by calling members on the value and need no spelling, so they do not widen
    the surface. A type that appears as a parameter (of an init, a method, or a
    protocol requirement) must be constructed by the caller and therefore needs
    its own entry (#1046).
    """
    refs: set[str] = set()
    sig = symbol.get("functionSignature", {})
    for param in sig.get("parameters", []):
        for f in param.get("declarationFragments", []):
            if f["kind"] == "typeIdentifier" and f["spelling"][0].isupper():
                refs.add(f["spelling"])
    return refs


def get_type_references(symbol: dict) -> set[str]:
    """Extract type names referenced in a symbol's declaration fragments."""
    refs: set[str] = set()
    for f in symbol.get("declarationFragments", []):
        if f["kind"] == "typeIdentifier" and f["spelling"][0].isupper():
            refs.add(f["spelling"])
    # Also check functionSignature parameters and return types
    sig = symbol.get("functionSignature", {})
    for param in sig.get("parameters", []):
        for f in param.get("declarationFragments", []):
            if f["kind"] == "typeIdentifier" and f["spelling"][0].isupper():
                refs.add(f["spelling"])
    for f in sig.get("returns", []):
        if f.get("kind") == "typeIdentifier" and f["spelling"][0].isupper():
            refs.add(f["spelling"])
    return refs


# DocC callouts worth republishing in llms.txt: the ones that constrain *how
# you call the symbol*. `- Parameters:` / `- Parameter x:` / `- Returns:` /
# `- Throws:` are structural — the rendered signature already carries them.
# `- SeeAlso:` is navigational, and every one reaching these symbol graphs comes
# from Apple's SwiftUI docs rather than from metaphor sources (#786).
_CALLOUT_KINDS = (
    "Note", "Important", "Warning", "Attention", "Tip",
    "Precondition", "Postcondition", "Invariant", "Requires", "Complexity",
)

# Matched case-insensitively, as DocC itself does, so a `- note:` renders the
# same way in the DocC reference and here rather than silently vanishing from
# one of them. What separates a callout from a parameter is therefore purely
# indentation: callouts sit at the top level of the comment, while MIDIManager's
# parameter literally named `note` reaches the graph as an *indented* `- note:`
# child of `- Parameters:`. Output is re-spelled to the canonical form.
_CALLOUT_RE = re.compile(
    r"-\s*(" + "|".join(_CALLOUT_KINDS) + r")\s*:\s*(.*)", re.IGNORECASE)
_CANONICAL_CALLOUT = {kind.lower(): kind for kind in _CALLOUT_KINDS}

# ``symbol(_:)`` is a DocC symbol *link*. llms.txt is plain text for an agent,
# where the doubled delimiter carries no meaning — only noise.
_DOCC_SYMBOL_LINK_RE = re.compile(r"``([^`]+)``")


def flatten_doc_text(text: str) -> str:
    """Collapse DocC-only markup that means nothing outside DocC."""
    return _DOCC_SYMBOL_LINK_RE.sub(r"`\1`", text)


def _is_wide(char: str) -> bool:
    """True for CJK ideographs, kana, and full-width forms."""
    return unicodedata.east_asian_width(char) in ("W", "F")


def _is_wide_punctuation(char: str) -> bool:
    return _is_wide(char) and unicodedata.category(char).startswith("P")


def _needs_space(left: str, right: str) -> bool:
    """Decide whether a doc comment's line wrap should re-join with a space.

    The wrap position is arbitrary, so the join has to reproduce what the
    author would have typed on one line. These sources write
    ``Darwin の `sys/tty.h` にある`` (spaced) but ``になります。`metaphor` は``
    (unspaced), so full-width punctuation is what decides it — not the script.
    """
    # Full-width punctuation carries its own visual padding on both sides.
    if _is_wide_punctuation(left) or _is_wide_punctuation(right):
        return False
    # Japanese never spaces between words, but does separate a run of Japanese
    # from an adjacent inline code span or Latin word.
    return not (_is_wide(left) and _is_wide(right))


def _doc_lines(symbol: dict) -> list[str]:
    """Return the raw doc comment lines, indentation intact."""
    doc = symbol.get("docComment")
    if not doc:
        return []
    return [line.get("text", "") for line in doc.get("lines", [])]


def _is_indented(line: str) -> bool:
    return line[:1].isspace()


def _join_wrapped(parts: list[str]) -> str:
    """Re-join lines that a doc comment wrapped, respecting CJK spacing."""
    joined = ""
    for part in parts:
        if not joined:
            joined = part
            continue
        joined += (" " if _needs_space(joined[-1], part[0]) else "") + part
    return joined


def get_doc_summary(symbol: dict) -> str:
    """Return the first meaningful line of the doc comment."""
    for text in _doc_lines(symbol):
        text = text.strip()
        if not text:
            continue
        # Any `- …` line is a DocC list item (`- Parameters:` and its indented
        # children, `- Returns:`, `- Note:`), never the summary. Symbols
        # documented with parameter docs but no abstract have no summary at all
        # — better empty than a stray "- wrappedValue: …" fragment.
        if text.startswith("-"):
            continue
        return flatten_doc_text(text)
    return ""


def get_doc_callouts(symbol: dict) -> list[str]:
    """Return each callout body as `"Note: …"`, in source order.

    The one-line abstract cannot hold "call this wrong and it breaks"
    knowledge, so llms.txt used to drop it entirely (#786). Continuation lines
    are folded back in: two thirds of the real callouts wrap onto indented
    follow-on lines, and first-line-only capture would cut them mid-sentence.
    """
    lines = _doc_lines(symbol)
    callouts: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        index += 1
        if _is_indented(line):
            continue
        match = _CALLOUT_RE.fullmatch(line.strip())
        if not match:
            continue
        kind = _CANONICAL_CALLOUT[match.group(1).lower()]
        first = match.group(2).strip()
        parts = [first] if first else []
        while index < len(lines):
            follow = lines[index]
            # Stops at the blank line ending the callout, at un-indented prose,
            # and at the next list item (`- Parameters:`, another callout).
            if not follow.strip() or not _is_indented(follow) \
                    or follow.strip().startswith("-"):
                break
            parts.append(follow.strip())
            index += 1
        body = _join_wrapped(parts)
        if body:  # a bodiless `- Note:` has nothing to republish
            callouts.append(flatten_doc_text(f"{kind}: {body}"))
    return callouts


def symbol_sort_key(sym: dict) -> tuple:
    """Sort key: properties first, then methods, alphabetically."""
    kind = sym["kind"]["identifier"]
    name = sym["names"]["title"]
    order = {
        KIND_ENUM_CASE: 0,
        KIND_PROPERTY: 1, KIND_TYPE_PROPERTY: 1, KIND_VAR: 1,
        KIND_INIT: 2,
        KIND_METHOD: 3, KIND_TYPE_METHOD: 3, KIND_FUNC: 3,
        KIND_SUBSCRIPT: 4,
    }
    return (order.get(kind, 5), name.lower())


def method_base_name(title: str) -> str:
    """Extract the base name before the first '(' from a symbol title."""
    paren = title.find("(")
    return title[:paren] if paren != -1 else title


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------


def load_symbol_graphs(sg_dir: str) -> dict:
    """Load all symbol graph JSON files, merge by declaring module."""
    modules: dict = {}
    sg_path = Path(sg_dir)

    for json_file in sorted(sg_path.glob("*.symbols.json")):
        stem = json_file.stem

        with open(json_file) as fh:
            data = json.load(fh)

        source_module = stem.split("@")[0] if "@" in stem else \
            data.get("module", {}).get("name", stem)

        if source_module not in modules:
            modules[source_module] = {"symbols": [], "relationships": []}

        for sym in data.get("symbols", []):
            sym["_source_module"] = source_module

        modules[source_module]["symbols"].extend(data.get("symbols", []))
        modules[source_module]["relationships"].extend(
            data.get("relationships", []))

    return modules


def discover_module_order(modules: dict, main_module: str = "MetaphorCore",
                          umbrella_module: str = "metaphor") -> list[str]:
    """Determine module display order dynamically.

    Rules:
      1. main_module first (if present)
      2. umbrella_module second (if present and different from main)
      3. remaining modules in alphabetical order
    """
    names = set(modules.keys())
    order: list[str] = []
    for preferred in (main_module, umbrella_module):
        if preferred in names:
            order.append(preferred)
            names.discard(preferred)
    order.extend(sorted(names))
    return order


# ---------------------------------------------------------------------------
# API-surface analysis
# ---------------------------------------------------------------------------


def compute_api_referenced_types(symbols: list[dict]) -> set[str]:
    """Collect all type names that appear in Sketch method/property signatures."""
    refs: set[str] = set()
    for sym in symbols:
        refs |= get_type_references(sym)
    return refs


def detect_condensed_types(
    all_types: dict[str, dict],
    sketch_method_names: set[str],
    threshold: float = _CONDENSED_OVERLAP_THRESHOLD,
) -> dict[str, str]:
    """Auto-detect types whose members largely mirror Sketch methods."""
    condensed: dict[str, str] = {}
    for type_name, info in all_types.items():
        members = info.get("members", [])
        if len(members) < 10:
            continue
        member_names = {method_base_name(m["names"]["title"]) for m in members
                        if m["kind"]["identifier"] in {KIND_METHOD, KIND_TYPE_METHOD}}
        if not member_names:
            continue
        overlap = len(member_names & sketch_method_names) / len(member_names)
        if overlap >= threshold:
            doc = get_doc_summary(info["symbol"]) if info.get("symbol") else ""
            summary = doc or f"Same drawing API as Sketch ({len(members)} methods)."
            condensed[type_name] = summary
    return condensed


# ---------------------------------------------------------------------------
# Model building
# ---------------------------------------------------------------------------


def build_api_model(modules: dict, module_order: list[str]) -> dict:
    """Build a structured API model from raw symbol graphs.

    The main_module (first in module_order) provides the core types.
    All other modules are treated as submodules.
    """
    main_module = module_order[0] if module_order else ""

    sketch_methods: list = []
    sketch_properties: list = []
    top_level_funcs: list = []
    top_level_vars: list = []
    types: dict = {}
    submodule_types: dict = defaultdict(dict)

    seen_sketch_decls: set[str] = set()
    seen_member_decls: dict[str, set[str]] = defaultdict(set)
    seen_top_decls: set[str] = set()
    extension_blocks: dict[tuple[str, str], dict] = {}

    for module_name, mod_data in modules.items():
        for sym in mod_data["symbols"]:
            kind = sym["kind"]["identifier"]
            path = sym.get("pathComponents", [])

            if kind == KIND_EXTENSION:
                # Keep one block per extended type as a stand-in declaration for
                # types this package does not own (back-filled below).
                if len(path) == 1:
                    extension_blocks.setdefault((module_name, path[0]), sym)
                continue

            if is_deprecated(sym):
                continue

            decl = get_declaration(sym)

            # --- Sketch extension members ---
            if len(path) >= 2 and path[0] == _SKETCH_TYPE:
                if kind in {KIND_METHOD, KIND_TYPE_METHOD}:
                    if decl not in seen_sketch_decls:
                        seen_sketch_decls.add(decl)
                        sketch_methods.append(sym)
                elif kind in {KIND_PROPERTY, KIND_TYPE_PROPERTY}:
                    if decl not in seen_sketch_decls:
                        seen_sketch_decls.add(decl)
                        sketch_properties.append(sym)
                continue

            # --- Top-level symbols ---
            if len(path) == 1 and kind not in TYPE_KINDS:
                if kind in {KIND_FUNC, KIND_FUNC_OP}:
                    if decl not in seen_top_decls:
                        seen_top_decls.add(decl)
                        top_level_funcs.append(sym)
                elif kind == KIND_VAR:
                    if decl not in seen_top_decls:
                        seen_top_decls.add(decl)
                        top_level_vars.append(sym)
                continue

            # --- Type definitions ---
            if len(path) == 1 and kind in TYPE_KINDS:
                type_name = path[0]
                is_main = (module_name == main_module)
                target = types if is_main else submodule_types[module_name]
                if type_name not in target:
                    target[type_name] = {"symbol": sym, "members": []}
                elif target[type_name]["symbol"] is None:
                    # Members can arrive before the type itself (e.g. the type is
                    # declared in one file and extended in another). Without this,
                    # the placeholder created by the member branch below would keep
                    # symbol=None and the whole type would be dropped from llms.txt.
                    target[type_name]["symbol"] = sym
                continue

            # --- Type members ---
            if len(path) >= 2 and kind in MEMBER_KINDS:
                type_name = path[0]
                if type_name == _SKETCH_TYPE:
                    continue
                is_main = (module_name == main_module)
                target = types if is_main else submodule_types[module_name]
                if type_name not in target:
                    target[type_name] = {"symbol": None, "members": []}
                if decl not in seen_member_decls[type_name]:
                    seen_member_decls[type_name].add(decl)
                    target[type_name]["members"].append(sym)

    # --- Back-fill extensions on types declared outside this package ---
    # `extension SIMD2 where Scalar == Float` produces members whose owning type
    # symbol lives in the Swift stdlib, so the placeholder created by the member
    # branch above keeps symbol=None and the whole extension is dropped. Adopting
    # the extension block as the stand-in declaration keeps that API — which
    # exists only because metaphor adds it — reachable from llms.txt (#298).
    for (module_name, type_name), ext_sym in extension_blocks.items():
        if type_name == _SKETCH_TYPE:
            continue
        target = types if module_name == main_module \
            else submodule_types[module_name]
        info = target.get(type_name)
        if info is not None and info.get("symbol") is None:
            info["symbol"] = ext_sym

    # --- Post-processing: determine which types to show / skip / condense ---
    all_sketch_syms = sketch_methods + sketch_properties
    referenced_types = compute_api_referenced_types(all_sketch_syms)

    # Also include types referenced transitively (one level deep) from
    # already-referenced types' member signatures — returns and properties
    # included, so what a sketch author *receives* (Canvas3D, TweenManager, …)
    # keeps its entry.
    for type_name in list(referenced_types):
        info = types.get(type_name)
        if not info:
            continue
        for m in info["members"]:
            referenced_types |= get_type_references(m)

    # Then close the graph over *parameter* types: a type a caller has to
    # construct to call something that is already in the surface is part of the
    # surface too, however many hops away. Two hops was not enough —
    # `SketchConfig(plugins:)` → `PluginFactory(requirements:)` →
    # `PluginRequirements` — and the `MetaphorOutputContext` a provider receives
    # is referenced only from a protocol requirement (#1046). Protocols and
    # property wrappers are always emitted, so their members are seeds too. Only
    # parameters are followed from here on: following returns and properties
    # would drag the renderer's internal collaborators (`TextureManager`,
    # `DepthStencilCache`, …) in through `MetaphorPlugin.onAttach(renderer:)`.
    frontier = set(referenced_types)
    for type_name, info in types.items():
        sym = info.get("symbol")
        if sym and (sym["kind"]["identifier"] == KIND_PROTOCOL or is_property_wrapper(sym)):
            frontier.add(type_name)
    while frontier:
        next_frontier: set[str] = set()
        for type_name in frontier:
            info = types.get(type_name)
            if not info:
                continue
            for m in info["members"]:
                for ref in get_parameter_type_references(m):
                    if ref not in referenced_types:
                        referenced_types.add(ref)
                        next_frontier.add(ref)
        frontier = next_frontier

    # Collect protocol precise IDs that are in the referenced set
    referenced_protocol_ids: set[str] = set()
    for type_name in referenced_types:
        info = types.get(type_name)
        if info and info.get("symbol"):
            sym = info["symbol"]
            if sym["kind"]["identifier"] == KIND_PROTOCOL:
                referenced_protocol_ids.add(
                    sym.get("identifier", {}).get("precise", ""))

    # Build a map from precise ID → type name for quick lookup
    precise_to_name: dict[str, str] = {}
    for module_name, mod_data in modules.items():
        for sym in mod_data["symbols"]:
            path = sym.get("pathComponents", [])
            if len(path) == 1 and sym["kind"]["identifier"] in TYPE_KINDS:
                pid = sym.get("identifier", {}).get("precise", "")
                if pid:
                    precise_to_name[pid] = path[0]

    # Include types that conform to an API-referenced protocol
    # (e.g., BloomEffect conforms to PostEffect)
    for module_name, mod_data in modules.items():
        for rel in mod_data.get("relationships", []):
            if rel["kind"] != "conformsTo":
                continue
            if rel["target"] in referenced_protocol_ids:
                source_name = precise_to_name.get(rel["source"])
                if source_name:
                    referenced_types.add(source_name)

    # Filter core types to only API-referenced + always include enums (they
    # represent mode parameters), protocols (they define plugin contracts), and
    # extensions on foreign types (their members exist nowhere else).
    filtered_types: dict = {}
    for type_name, info in types.items():
        sym = info.get("symbol")
        if not sym:
            continue
        kind = sym["kind"]["identifier"]
        if kind in {KIND_ENUM, KIND_PROTOCOL, KIND_EXTENSION}:
            # Enums and protocols are compact and always useful; an extension
            # here means the extended type is declared outside this package
            # (back-filled above), so its members appear nowhere else.
            filtered_types[type_name] = info
        elif is_property_wrapper(sym):
            # Property wrappers are spelled at the declaration site (`@Param var
            # radius: Float`) and so never appear in any Sketch signature — the
            # reference-based filter below can never reach them (#421).
            filtered_types[type_name] = info
        elif type_name in referenced_types:
            filtered_types[type_name] = info
        elif type_name == _SKETCH_TYPE:
            continue  # handled separately
        # else: skip — internal type

    # Auto-detect condensed types (mirror Sketch API)
    sketch_method_names = {method_base_name(s["names"]["title"])
                           for s in sketch_methods}
    condensed = detect_condensed_types(filtered_types, sketch_method_names)

    return {
        "sketch_methods": sorted(sketch_methods, key=symbol_sort_key),
        "sketch_properties": sorted(sketch_properties, key=symbol_sort_key),
        "top_level_funcs": sorted(top_level_funcs, key=symbol_sort_key),
        "top_level_vars": sorted(top_level_vars, key=symbol_sort_key),
        "types": filtered_types,
        "submodule_types": dict(submodule_types),
        "condensed_types": condensed,
        "sketch_method_names": sketch_method_names,
    }


# ---------------------------------------------------------------------------
# Output generation
# ---------------------------------------------------------------------------


def code_span(text: str) -> str:
    """Wrap a declaration in a Markdown code span that survives inner backticks.

    Swift spells a keyword used as an identifier with backticks around it
    (`case `default``, `static let `return``), so the declaration itself can
    contain the very delimiter we wrap it in. CommonMark closes a code span at
    the first backtick run of the *same* length as the opener, so a single
    backtick fence would end mid-declaration and spill the rest into prose
    (#961). Widening the fence past the longest inner run fixes that.

    The padding spaces are symmetric on purpose: CommonMark strips one space
    from each end only when *both* ends carry one, so padding just the side
    that touches a backtick would leave a stray space in the rendered output.
    """
    longest = max((len(run) for run in re.findall(r"`+", text)), default=0)
    fence = "`" * (longest + 1)
    pad = " " if text.startswith("`") or text.endswith("`") else ""
    return f"{fence}{pad}{text}{pad}{fence}"


def fmt_callouts(sym: dict) -> list[str]:
    """Render a symbol's callouts as lines nested under its declaration.

    Indented one level so a type's own callout can never be misread as one of
    its members, which sit at column 0.
    """
    return [f"  - {callout}" for callout in get_doc_callouts(sym)]


def fmt_symbol(sym: dict) -> str:
    """Format a symbol as a markdown list item, with its callouts beneath."""
    decl = get_declaration(sym)
    doc = get_doc_summary(sym)
    head = (f"- {code_span(decl)} -- {doc}" if doc
            else f"- {code_span(decl)}")
    return "\n".join([head, *fmt_callouts(sym)])


def emit_type_section(name: str, info: dict, lines: list,
                      condensed: dict[str, str], heading: str = "###",
                      sketch_method_names: set | None = None):
    """Emit a type and its members."""
    sym = info["symbol"]
    members = info["members"]

    if name in condensed:
        summary = condensed[name]
        if sym:
            decl = get_declaration(sym)
            lines.append(f"{heading} {code_span(decl)} -- {summary}")
            lines.extend(fmt_callouts(sym))
        else:
            lines.append(f"{heading} {name} -- {summary}")
        lines.append("")
        # Sketch API を鏡写しにするメンバーは 1 行に要約し、型固有のメンバー
        # （addChild 等）だけを列挙する — 固有 API まで畳むと AI から見えなくなる
        mirror_names = sketch_method_names or set()
        unique = [m for m in members
                  if method_base_name(m["names"]["title"]) not in mirror_names]
        mirrored_count = len(members) - len(unique)
        if mirrored_count:
            lines.append(f"- （ほか {mirrored_count} 件の描画・変換メンバーは"
                         " Sketch API と同名・同挙動）")
        for m in sorted(unique, key=symbol_sort_key):
            lines.append(fmt_symbol(m))
        lines.append("")
        return

    if sym:
        doc = get_doc_summary(sym)
        decl = get_declaration(sym)
        lines.append(f"{heading} {code_span(decl)} -- {doc}" if doc
                     else f"{heading} {code_span(decl)}")
        lines.extend(fmt_callouts(sym))
    else:
        lines.append(f"{heading} {name}")

    if not members:
        lines.append("")
        return

    lines.append("")
    for m in sorted(members, key=symbol_sort_key):
        lines.append(fmt_symbol(m))
    lines.append("")


def type_sort_key(item: tuple) -> tuple:
    """Sort types: protocols → structs → enums → classes → typealias → extensions."""
    name, info = item
    sym = info.get("symbol")
    if not sym:
        return (9, name.lower())
    order = {
        KIND_PROTOCOL: 0, KIND_STRUCT: 1, KIND_ENUM: 2,
        KIND_CLASS: 3, KIND_TYPEALIAS: 4, KIND_EXTENSION: 5,
    }
    return (order.get(sym["kind"]["identifier"], 5), name.lower())


def categorize_functions(funcs: list) -> list[tuple[str, list]]:
    """Group top-level functions by broad category using name patterns."""
    categories: dict[str, list] = defaultdict(list)

    # Patterns: (regex, category)
    patterns: list[tuple[re.Pattern, str]] = [
        (re.compile(r"^ease", re.I), "Easing"),
        (re.compile(r"noise|noiseSeed|noiseDetail", re.I), "Noise & Waveforms"),
        (re.compile(r"sine01|cosine01|triangle|sawtooth|square", re.I),
         "Noise & Waveforms"),
        (re.compile(r"color|lerpColor", re.I), "Color"),
        (re.compile(r"millis|second|minute|hour|day|month|year", re.I), "Time"),
    ]

    for sym in funcs:
        name = sym["names"]["title"]
        matched = False
        for pat, cat in patterns:
            if pat.search(name):
                categories[cat].append(sym)
                matched = True
                break
        if not matched:
            categories["Math"].append(sym)

    preferred = ["Math", "Easing", "Noise & Waveforms", "Color", "Time"]
    result: list[tuple[str, list]] = []
    seen: set[str] = set()
    for cat in preferred:
        if cat in categories:
            result.append((cat, sorted(categories[cat], key=symbol_sort_key)))
            seen.add(cat)
    for cat in sorted(categories.keys()):
        if cat not in seen:
            result.append((cat, sorted(categories[cat], key=symbol_sort_key)))
    return result


def generate_llms_txt(modules: dict, package_version: str = "0.0.0") -> str:
    """Generate the full llms.txt content."""
    module_order = discover_module_order(modules)
    model = build_api_model(modules, module_order)
    lines: list[str] = []

    lines.append(build_header(package_version))

    # --- Sketch Protocol ---
    lines.append("## Sketch Protocol")
    lines.append("")
    lines.append(
        "Conform a class to `Sketch` with `@main`. Implement `draw()` (required).")
    lines.append(
        "Optional: `setup()`, `compute()`, input callbacks "
        "(`mousePressed`, `keyPressed`, etc.).")
    lines.append("")

    if model["sketch_properties"]:
        lines.append("### Properties")
        lines.append("")
        for sym in model["sketch_properties"]:
            lines.append(fmt_symbol(sym))
        lines.append("")

    if model["sketch_methods"]:
        lines.append("### Methods")
        lines.append("")
        for sym in model["sketch_methods"]:
            lines.append(fmt_symbol(sym))
        lines.append("")

    # --- Core Types ---
    if model["types"]:
        lines.append("## Core Types")
        lines.append("")
        for name, info in sorted(model["types"].items(), key=type_sort_key):
            emit_type_section(name, info, lines, model["condensed_types"],
                              sketch_method_names=model["sketch_method_names"])

    # --- Top-level Functions ---
    if model["top_level_funcs"]:
        lines.append("## Utility Functions")
        lines.append("")
        for cat_name, funcs in categorize_functions(model["top_level_funcs"]):
            lines.append(f"### {cat_name}")
            lines.append("")
            for sym in funcs:
                lines.append(fmt_symbol(sym))
            lines.append("")

    # --- Constants ---
    if model["top_level_vars"]:
        lines.append("## Constants")
        lines.append("")
        for sym in model["top_level_vars"]:
            lines.append(fmt_symbol(sym))
        lines.append("")

    # --- Submodules (dynamically ordered) ---
    for mod_name in module_order:
        if mod_name not in model["submodule_types"]:
            continue
        lines.append(f"## {mod_name}")
        lines.append("")
        for name, info in sorted(
                model["submodule_types"][mod_name].items()):
            emit_type_section(name, info, lines, model["condensed_types"],
                              sketch_method_names=model["sketch_method_names"])

    lines.append("---")
    lines.append("*Auto-generated from symbol graphs. Do not edit manually.*")
    lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Generate llms.txt from Swift Symbol Graph JSON.")
    parser.add_argument(
        "--symbol-graph-dir", default=".build/symbol-graphs",
        help="Directory containing *.symbols.json files")
    parser.add_argument(
        "-o", "--output", default="llms.txt",
        help="Output file path (default: llms.txt)")
    parser.add_argument(
        "--package-file", default="Package.swift",
        help="Package.swift path used to infer the SPM version snippet")
    parser.add_argument(
        "--readme-file", default="README.md",
        help="README.md path used to infer the stable SPM version snippet")
    args = parser.parse_args()

    sg_dir = Path(args.symbol_graph_dir)
    if not sg_dir.is_dir():
        print(f"Error: symbol graph directory not found: {sg_dir}\n"
              f"Run 'make symbol-graphs' first.", file=sys.stderr)
        sys.exit(1)

    modules = load_symbol_graphs(str(sg_dir))
    if not modules:
        print("Error: no symbol graphs found.", file=sys.stderr)
        sys.exit(1)

    package_version = discover_package_version(
        Path(args.readme_file), Path(args.package_file))
    output = generate_llms_txt(modules, package_version=package_version)

    out_path = Path(args.output)
    out_path.write_text(output, encoding="utf-8")

    line_count = len(output.splitlines())
    print(f"Generated {out_path} ({line_count} lines)", file=sys.stderr)


if __name__ == "__main__":
    main()
