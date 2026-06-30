#!/usr/bin/env python3
"""Generate AI-friendly indexes for metaphor examples."""

import argparse
import json
import os
import sys
from pathlib import Path


# Lifecycle status for an example. Drives AI/agent trust (which sketches are
# real, working references) and the Examples CI build gate.
#   supported — fully implemented, expected to build and run
#   partial   — implemented but incomplete / degraded vs the original
#   stub       — placeholder; blocked on a planned metaphor API (will be filled)
#   obsolete   — placeholder for a Processing/OpenGL-specific capability metaphor
#                deliberately will not add (non-goal); excluded from the CI gate
STATUS_VALUES = ("supported", "partial", "stub", "obsolete")
DEFAULT_STATUS = "supported"


KEYWORD_TAGS = {
    "audio": ("audio", "fft", "sound", "beat", "microphone"),
    "video": ("video", "capture", "movie"),
    "shader": ("shader", "metal", "glsl", "fragment"),
    "3d": ("3d", "box", "sphere", "camera", "light", "mesh", "raytracing", "ray tracing"),
    "particles": ("particle", "particles", "emitter"),
    "physics": ("physics", "collision", "gravity", "bounce"),
    "image": ("image", "pixel", "filter", "photo"),
    "typography": ("text", "font", "typography", "letter", "word"),
    "interaction": ("mouse", "keyboard", "input", "drag", "press"),
    "live": ("osc", "midi", "syphon", "vj", "live"),
    "export": ("record", "export", "gif", "video"),
}


def clean_text(value: object, limit: int = 180) -> str:
    text = " ".join(str(value or "").split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "..."


def load_metadata(example_dir: Path) -> dict:
    json_files = sorted(example_dir.glob("*.json"))
    if not json_files:
        return {}

    preferred = [p for p in json_files if p.stem == example_dir.name]
    for path in preferred + json_files:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
    return {}


def status_for(example_dir: Path, metadata: dict) -> str:
    """Resolve an example's lifecycle status.

    Precedence: explicit ``status`` in the example metadata JSON wins; otherwise
    fall back to scanning the sketch source for the ``(Stub)`` marker that
    placeholder examples carry in their SketchConfig title. This keeps stub
    detection automatic (un-stubbing a sketch clears the marker) while letting a
    curator override to ``obsolete``/``partial`` via metadata.
    """
    explicit = str(metadata.get("status", "")).strip().lower()
    if explicit in STATUS_VALUES:
        return explicit

    app = example_dir / example_dir.name / "App.swift"
    sources = [app] if app.exists() else sorted(example_dir.rglob("App.swift"))
    for path in sources:
        try:
            if "(Stub)" in path.read_text(encoding="utf-8"):
                return "stub"
        except OSError:
            continue
    return DEFAULT_STATUS


def tags_for(rel_path: Path, metadata: dict) -> list[str]:
    haystack = " ".join([
        str(rel_path),
        str(metadata.get("title", "")),
        str(metadata.get("name", "")),
        str(metadata.get("description", "")),
        " ".join(str(x) for x in metadata.get("featured", []) or []),
    ]).lower()

    tags: set[str] = set()
    for part in rel_path.parts:
        normalized = part.lower().replace(" ", "-")
        if normalized:
            tags.add(normalized)

    for tag, needles in KEYWORD_TAGS.items():
        if any(needle in haystack for needle in needles):
            tags.add(tag)

    return sorted(tags)


def discover_examples(examples_dir: Path) -> list[dict]:
    examples = []
    package_files: list[Path] = []
    for root, dirnames, filenames in os.walk(examples_dir):
        dirnames[:] = [name for name in dirnames if name not in {".build", ".swiftpm"}]
        if "Package.swift" in filenames:
            package_files.append(Path(root) / "Package.swift")

    for package in sorted(package_files):
        example_dir = package.parent
        rel_path = example_dir.relative_to(examples_dir)
        metadata = load_metadata(example_dir)
        title = clean_text(
            metadata.get("title") or metadata.get("name") or example_dir.name,
            limit=80,
        )
        description = clean_text(metadata.get("description", ""), limit=220)
        parts = rel_path.parts
        group = parts[0] if len(parts) >= 1 else "Other"
        subcategory = parts[1] if len(parts) >= 3 else ""

        examples.append({
            "title": title,
            "path": f"Examples/{rel_path.as_posix()}",
            "group": group,
            "subcategory": subcategory,
            "level": clean_text(metadata.get("level", ""), limit=40),
            "status": status_for(example_dir, metadata),
            "description": description,
            "featured": metadata.get("featured", []) or [],
            "tags": tags_for(rel_path, metadata),
        })
    return examples


def status_counts(examples: list[dict]) -> dict:
    counts = {status: 0 for status in STATUS_VALUES}
    for example in examples:
        counts[example["status"]] = counts.get(example["status"], 0) + 1
    return counts


def render_markdown(examples: list[dict]) -> str:
    lines = [
        "# metaphor Examples Index For AI",
        "",
        "This file is generated from `Examples/**/Package.swift` and adjacent",
        "`*.json` metadata. Use it to find a nearby working sketch before",
        "generating new metaphor content.",
        "",
        f"Example count: {len(examples)}",
        "",
        "Status: " + ", ".join(
            f"{status} {count}" for status, count in status_counts(examples).items()
        ),
        "",
        "## How To Use",
        "",
        "- Pick one or two examples whose tags match the user's request.",
        "- Read the example's `App.swift` before inventing a new structure.",
        "- Prefer adapting existing metaphor idioms over translating p5.js code",
        "  literally.",
        "- Avoid `[stub]` (placeholder, blocked on a planned API) and `[obsolete]`",
        "  (Processing/OpenGL-specific, won't be added) examples as references.",
        "",
    ]

    grouped: dict[str, list[dict]] = {}
    for example in examples:
        grouped.setdefault(example["group"], []).append(example)

    for group in sorted(grouped):
        lines.append(f"## {group}")
        lines.append("")
        for example in grouped[group]:
            link = "../../" + example["path"].replace(" ", "%20")
            title = example["title"]
            level = f" [{example['level']}]" if example["level"] else ""
            status = f" [{example['status']}]" if example["status"] != DEFAULT_STATUS else ""
            subcategory = f" ({example['subcategory']})" if example["subcategory"] else ""
            description = f" -- {example['description']}" if example["description"] else ""
            tags = ", ".join(example["tags"][:8])
            tag_text = f" Tags: {tags}." if tags else ""
            lines.append(f"- [{title}]({link}){level}{status}{subcategory}{description}{tag_text}")
        lines.append("")

    return "\n".join(lines)


def render_json(examples: list[dict]) -> str:
    # Output must be deterministic — the index is checked-in, so any
    # non-deterministic field (e.g. wall-clock time) would cause spurious
    # drift detection in CI / git hooks.
    payload = {
        "count": len(examples),
        "statusCounts": status_counts(examples),
        "examples": examples,
    }
    return json.dumps(payload, indent=2, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--examples-dir", default="Examples")
    parser.add_argument("--output-md", default="docs/ai/examples-index.md")
    parser.add_argument("--output-json", default="docs/ai/examples-index.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    examples_dir = Path(args.examples_dir)
    if not examples_dir.is_dir():
        print(f"examples directory not found: {examples_dir}", file=sys.stderr)
        return 1

    examples = discover_examples(examples_dir)
    markdown = render_markdown(examples)
    json_text = render_json(examples)

    outputs = [
        (Path(args.output_md), markdown),
        (Path(args.output_json), json_text),
    ]

    if args.check:
        ok = True
        for path, expected in outputs:
            try:
                current = path.read_text(encoding="utf-8")
            except OSError:
                print(f"{path} is missing; run scripts/generate-examples-index.py", file=sys.stderr)
                ok = False
                continue
            matches = current == expected
            if not matches:
                print(f"{path} is out of date; run scripts/generate-examples-index.py", file=sys.stderr)
                ok = False
        return 0 if ok else 1

    for path, content in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"Generated {path}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
