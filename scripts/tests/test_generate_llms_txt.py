#!/usr/bin/env python3
"""Unit tests for scripts/generate-llms-txt.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

The generator turns Swift Symbol Graph JSON into llms.txt, the AI-facing API
reference (CONTRACT.md 契約点 6). These tests feed it hand-written symbol
graphs so each filtering rule can be checked without a full Swift build.
"""

import importlib.util
import sys
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-llms-txt.py"
_spec = importlib.util.spec_from_file_location("generate_llms_txt", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_llms_txt"] = gen
_spec.loader.exec_module(gen)


# ---------------------------------------------------------------------------
# Symbol graph fixtures
# ---------------------------------------------------------------------------


def frag(kind: str, spelling: str) -> dict:
    return {"kind": kind, "spelling": spelling}


def symbol(kind: str, path: list[str], fragments: list[dict],
           doc_lines: list[str] | None = None) -> dict:
    sym = {
        "kind": {"identifier": kind},
        "names": {"title": path[-1]},
        "pathComponents": path,
        "declarationFragments": fragments,
        "identifier": {"precise": "s:" + ".".join(path)},
    }
    if doc_lines is not None:
        sym["docComment"] = {"lines": [{"text": t} for t in doc_lines]}
    return sym


def method(path: list[str], signature: str, doc_lines: list[str] | None = None) -> dict:
    """A `func <name><signature>` member, e.g. method(["SIMD2", "dot(_:)"], ...)."""
    return symbol(gen.KIND_METHOD, path, [
        frag("keyword", "func"),
        frag("text", " "),
        frag("identifier", gen.method_base_name(path[-1])),
        frag("text", signature),
    ], doc_lines)


def module(*symbols: dict) -> dict:
    return {"symbols": list(symbols), "relationships": []}


def render(**modules: dict) -> str:
    return gen.generate_llms_txt(modules, package_version="1.2.3")


# `@MainActor @propertyWrapper final class Param<Value>` — the shape emitted for
# Sources/MetaphorCore/Parameters/Param.swift.
PARAM_WRAPPER = symbol(gen.KIND_CLASS, ["Param"], [
    frag("attribute", "@"),
    frag("attribute", "MainActor"),
    frag("text", " "),
    frag("attribute", "@propertyWrapper"),
    frag("text", " "),
    frag("keyword", "final"),
    frag("text", " "),
    frag("keyword", "class"),
    frag("text", " "),
    frag("identifier", "Param"),
    frag("text", "<"),
    frag("genericParameter", "Value"),
    frag("text", ">"),
], ["宣言したプロパティをストアへ公開します。"])

# `extension SIMD2 where Scalar == Float` — the block symbol emitted by
# swift-symbolgraph-extract with -emit-extension-block-symbols. The extended
# type itself (Swift.SIMD2) is never a symbol in our own graphs.
SIMD2_EXTENSION = symbol(gen.KIND_EXTENSION, ["SIMD2"], [
    frag("keyword", "extension"),
    frag("text", " "),
    frag("typeIdentifier", "SIMD2"),
    frag("text", " "),
    frag("keyword", "where"),
    frag("text", " "),
    frag("typeIdentifier", "Scalar"),
    frag("text", " == "),
    frag("typeIdentifier", "Float"),
])
SIMD2_EXTENSION["swiftExtension"] = {"extendedModule": "Swift",
                                     "typeKind": "swift.struct"}


class PropertyWrapperTests(unittest.TestCase):
    """@Param is written at the declaration site, so it appears in no signature."""

    def test_property_wrapper_is_included_though_unreferenced(self):
        out = render(MetaphorCore=module(PARAM_WRAPPER))
        self.assertIn("class Param<Value>", out)

    def test_property_wrapper_attribute_survives_in_the_heading(self):
        # Other attributes stay stripped: @MainActor is noise for a sketch
        # author, @propertyWrapper is the whole point of the declaration.
        out = render(MetaphorCore=module(PARAM_WRAPPER))
        self.assertIn("### `@propertyWrapper final class Param<Value>`", out)
        self.assertNotIn("MainActor", out)

    def test_unreferenced_plain_type_is_still_excluded(self):
        # Guards the inclusion rule against widening into "emit every type".
        internal = symbol(gen.KIND_STRUCT, ["FrameBudget"], [
            frag("keyword", "struct"),
            frag("text", " "),
            frag("identifier", "FrameBudget"),
        ])
        out = render(MetaphorCore=module(internal))
        self.assertNotIn("FrameBudget", out)


class ForeignExtensionTests(unittest.TestCase):
    """Extensions on types declared outside the package (SIMD2, Float, …)."""

    def test_members_are_emitted_under_the_extension_declaration(self):
        out = render(MetaphorCore=module(
            SIMD2_EXTENSION,
            method(["SIMD2", "normalized()"], "() -> SIMD2<Float>",
                   ["単位ベクトルを返します。"]),
        ))
        self.assertIn("### `extension SIMD2 where Scalar == Float`", out)
        self.assertIn("- `func normalized() -> SIMD2<Float>` -- 単位ベクトルを返します。",
                      out)

    def test_members_are_dropped_without_a_block_symbol(self):
        # Without -emit-extension-block-symbols there is nothing to title the
        # section with, and a bare "### SIMD2" would misreport a stdlib type as
        # a metaphor type. Prefer omission.
        out = render(MetaphorCore=module(
            method(["SIMD2", "normalized()"], "() -> SIMD2<Float>"),
        ))
        self.assertNotIn("SIMD2", out)

    def test_extension_does_not_override_a_type_declared_here(self):
        # BlendMode is ours *and* extended elsewhere — the real declaration wins,
        # even though the extension block is seen first.
        own = symbol(gen.KIND_ENUM, ["BlendMode"], [
            frag("keyword", "enum"),
            frag("text", " "),
            frag("identifier", "BlendMode"),
        ])
        ext = symbol(gen.KIND_EXTENSION, ["BlendMode"], [
            frag("keyword", "extension"),
            frag("text", " "),
            frag("typeIdentifier", "BlendMode"),
        ])
        out = render(MetaphorCore=module(
            ext, method(["BlendMode", "isSeparable()"], "() -> Bool"), own))
        self.assertIn("### `enum BlendMode`", out)
        self.assertNotIn("extension BlendMode", out)


class DocSummaryTests(unittest.TestCase):
    def test_parameter_list_items_are_not_used_as_the_summary(self):
        # `- Parameters:` blocks with no abstract must yield no summary rather
        # than leaking the first parameter's description.
        sym = method(["Widget", "resize(to:)"], "(_ size: Float)",
                     ["- Parameters:", "  - size: 新しい大きさ。"])
        self.assertEqual(gen.get_doc_summary(sym), "")

    def test_abstract_is_used_when_present(self):
        sym = method(["Widget", "resize(to:)"], "(_ size: Float)",
                     ["大きさを変更します。", "- Parameters:", "  - size: 新しい大きさ。"])
        self.assertEqual(gen.get_doc_summary(sym), "大きさを変更します。")


if __name__ == "__main__":
    unittest.main()
