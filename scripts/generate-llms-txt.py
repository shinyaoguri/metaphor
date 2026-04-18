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

# Extension-file suffixes from system frameworks — always skip
_SYSTEM_EXTENSION_SUFFIXES = {"@Swift", "@simd", "@Metal", "@CoreGraphics",
                              "@Foundation", "@CoreMedia", "@Accelerate"}

# Sketch protocol name (used as the anchor for API-surface detection)
_SKETCH_TYPE = "Sketch"

# Overlap threshold: if a type shares this fraction of its method names with
# Sketch, it is condensed to a one-liner rather than listing every member.
_CONDENSED_OVERLAP_THRESHOLD = 0.60

# ---------------------------------------------------------------------------
# Static header (the only deliberately static section)
# ---------------------------------------------------------------------------

HEADER = """\
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
.package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.1.0")
```
"""

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


def get_declaration(symbol: dict) -> str:
    """Build a clean one-line declaration from declarationFragments."""
    frags = symbol.get("declarationFragments", [])
    if not frags:
        return symbol["names"]["title"]

    parts: list[str] = []
    skip_ws = False
    for f in frags:
        if f["kind"] == "attribute":
            skip_ws = True
            continue
        if skip_ws and f["kind"] == "text" and f["spelling"].strip() == "":
            skip_ws = False
            continue
        skip_ws = False
        parts.append(f["spelling"])
    return "".join(parts).strip()


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


def get_doc_summary(symbol: dict) -> str:
    """Return the first meaningful line of the doc comment."""
    doc = symbol.get("docComment")
    if not doc:
        return ""
    for line in doc.get("lines", []):
        text = line.get("text", "").strip()
        if not text:
            continue
        if text.startswith("- Parameter") or text.startswith("- Returns"):
            continue
        return text
    return ""


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

        if any(stem.endswith(s) for s in _SYSTEM_EXTENSION_SUFFIXES):
            continue

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

    for module_name, mod_data in modules.items():
        for sym in mod_data["symbols"]:
            kind = sym["kind"]["identifier"]
            path = sym.get("pathComponents", [])

            if kind == KIND_EXTENSION or is_deprecated(sym):
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

    # --- Post-processing: determine which types to show / skip / condense ---
    all_sketch_syms = sketch_methods + sketch_properties
    referenced_types = compute_api_referenced_types(all_sketch_syms)

    # Also include types referenced transitively (one level deep) from
    # already-referenced types' init/factory signatures.
    for type_name in list(referenced_types):
        info = types.get(type_name)
        if not info:
            continue
        for m in info["members"]:
            referenced_types |= get_type_references(m)

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
    # represent mode parameters) and protocols (they define plugin contracts).
    filtered_types: dict = {}
    for type_name, info in types.items():
        sym = info.get("symbol")
        if not sym:
            continue
        kind = sym["kind"]["identifier"]
        if kind in {KIND_ENUM, KIND_PROTOCOL}:
            # Enums and protocols are compact and always useful
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
    }


# ---------------------------------------------------------------------------
# Output generation
# ---------------------------------------------------------------------------


def fmt_symbol(sym: dict) -> str:
    """Format a symbol as a markdown list item."""
    decl = get_declaration(sym)
    doc = get_doc_summary(sym)
    if doc:
        return f"- `{decl}` -- {doc}"
    return f"- `{decl}`"


def emit_type_section(name: str, info: dict, lines: list,
                      condensed: dict[str, str], heading: str = "###"):
    """Emit a type and its members."""
    sym = info["symbol"]
    members = info["members"]

    if name in condensed:
        summary = condensed[name]
        if sym:
            decl = get_declaration(sym)
            lines.append(f"{heading} `{decl}` -- {summary}")
        else:
            lines.append(f"{heading} {name} -- {summary}")
        lines.append("")
        return

    if sym:
        doc = get_doc_summary(sym)
        decl = get_declaration(sym)
        lines.append(f"{heading} `{decl}` -- {doc}" if doc
                     else f"{heading} `{decl}`")
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
    """Sort types: protocols → structs → enums → classes → typealias."""
    name, info = item
    sym = info.get("symbol")
    if not sym:
        return (9, name.lower())
    order = {
        KIND_PROTOCOL: 0, KIND_STRUCT: 1, KIND_ENUM: 2,
        KIND_CLASS: 3, KIND_TYPEALIAS: 4,
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


def generate_llms_txt(modules: dict) -> str:
    """Generate the full llms.txt content."""
    module_order = discover_module_order(modules)
    model = build_api_model(modules, module_order)
    lines: list[str] = []

    lines.append(HEADER)

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
            emit_type_section(name, info, lines, model["condensed_types"])

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
            emit_type_section(name, info, lines, model["condensed_types"])

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

    output = generate_llms_txt(modules)

    out_path = Path(args.output)
    out_path.write_text(output, encoding="utf-8")

    line_count = len(output.splitlines())
    print(f"Generated {out_path} ({line_count} lines)", file=sys.stderr)


if __name__ == "__main__":
    main()
