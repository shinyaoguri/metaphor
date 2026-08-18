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

    def test_docc_symbol_links_are_flattened_to_plain_code_spans(self):
        # ``foo()`` is DocC symbol-link syntax. llms.txt is not DocC, so the
        # doubled delimiter carries no meaning there — only noise (#786).
        sym = method(["Widget", "reset()"], "()",
                     ["``configure(_:)`` を呼び直します。"])
        self.assertEqual(gen.get_doc_summary(sym), "`configure(_:)` を呼び直します。")


# Swift lets a keyword be used as an identifier by escaping it in backticks,
# so the *declaration itself* carries backticks that the surrounding code span
# has to clear. `case `default`` (ArcMode) and `static let `return`` (KeyCode)
# are the two real ones (#961).
ESCAPED_CASE = symbol(gen.KIND_ENUM_CASE, ["ArcMode", "default"], [
    frag("keyword", "case"),
    frag("text", " "),
    frag("identifier", "`default`"),
], ["mode 省略時のデフォルト。"])

ESCAPED_TYPE = symbol(gen.KIND_STRUCT, ["`default`"], [
    frag("keyword", "struct"),
    frag("text", " "),
    frag("identifier", "`default`"),
], ["キーワード名の型。"])


class CodeSpanTests(unittest.TestCase):
    """Declarations containing backticks must still delimit their code span.

    CommonMark closes a code span at the first backtick run of the *same*
    length as the opener, so a single-backtick fence around `case `default``
    used to end right after `case `, leaving the rest as prose — the reader
    could no longer see where the declaration stopped (#961).
    """

    def test_a_plain_declaration_keeps_a_single_backtick_fence(self):
        self.assertEqual(gen.code_span("func circle(x:y:d:)"),
                         "`func circle(x:y:d:)`")

    def test_an_inner_backtick_lengthens_the_fence(self):
        self.assertEqual(gen.code_span("static let `return`: UInt16"),
                         "``static let `return`: UInt16``")

    def test_the_fence_clears_the_longest_run_inside(self):
        self.assertEqual(gen.code_span("a ``b`` c"), "```a ``b`` c```")

    def test_a_trailing_backtick_is_padded_on_both_sides(self):
        # CommonMark strips one space from each end only when *both* ends carry
        # one, so the pad has to be symmetric. Padding only the touching side
        # would leave a stray space inside the rendered declaration.
        self.assertEqual(gen.code_span("case `default`"),
                         "`` case `default` ``")

    def test_a_leading_backtick_is_padded_on_both_sides(self):
        self.assertEqual(gen.code_span("`default` は既定値"),
                         "`` `default` は既定値 ``")


class EscapedIdentifierRenderingTests(unittest.TestCase):
    """Every place a declaration is wrapped goes through `code_span` (#961).

    Fixing only `fmt_symbol` would leave the type headings broken, so the
    member line and both heading paths are pinned here too.
    """

    def test_member_line_escapes_a_backticked_identifier(self):
        self.assertEqual(
            gen.fmt_symbol(ESCAPED_CASE),
            "- `` case `default` `` -- mode 省略時のデフォルト。")

    def test_member_line_without_a_summary_escapes_too(self):
        bare = symbol(gen.KIND_ENUM_CASE, ["ArcMode", "default"], [
            frag("keyword", "case"),
            frag("text", " "),
            frag("identifier", "`default`"),
        ])
        self.assertEqual(gen.fmt_symbol(bare), "- `` case `default` ``")

    def test_type_heading_escapes_a_backticked_identifier(self):
        lines: list[str] = []
        gen.emit_type_section("`default`",
                              {"symbol": ESCAPED_TYPE, "members": []},
                              lines, {})
        self.assertEqual(lines[0],
                         "### `` struct `default` `` -- キーワード名の型。")

    def test_type_heading_without_a_summary_escapes_too(self):
        bare = symbol(gen.KIND_STRUCT, ["`default`"], [
            frag("keyword", "struct"),
            frag("text", " "),
            frag("identifier", "`default`"),
        ])
        lines: list[str] = []
        gen.emit_type_section("`default`", {"symbol": bare, "members": []},
                              lines, {})
        self.assertEqual(lines[0], "### `` struct `default` ``")

    def test_condensed_type_heading_escapes_a_backticked_identifier(self):
        lines: list[str] = []
        gen.emit_type_section("`default`",
                              {"symbol": ESCAPED_TYPE, "members": []},
                              lines, {"`default`": "Sketch API を鏡写しにします。"})
        self.assertEqual(
            lines[0],
            "### `` struct `default` `` -- Sketch API を鏡写しにします。")


class DocCalloutTests(unittest.TestCase):
    """`- Note:` / `- Important:` bodies belong in llms.txt (#786).

    They carry the "call this wrong and it breaks" knowledge that the one-line
    abstract cannot, so an agent reading only llms.txt used to miss it entirely.
    """

    def test_single_line_callout_is_captured(self):
        sym = method(["Widget", "reset()"], "()",
                     ["状態を初期化します。", "", "- Note: 描画中は呼べません。"])
        self.assertEqual(gen.get_doc_callouts(sym), ["Note: 描画中は呼べません。"])

    def test_continuation_lines_are_joined_into_one_callout(self):
        # Two thirds of the real callouts wrap onto indented continuation
        # lines; emitting only the first line would truncate mid-sentence.
        # Japanese wraps mid-sentence, so the seam takes no space.
        sym = method(["Widget", "reset()"], "()",
                     ["状態を初期化します。",
                      "",
                      "- Note: 描画中は呼べません。フレームの外から",
                      "  呼んでください。中から呼ぶと",
                      "  スロットが返りません。"])
        self.assertEqual(
            gen.get_doc_callouts(sym),
            ["Note: 描画中は呼べません。フレームの外から呼んでください。"
             "中から呼ぶとスロットが返りません。"])

    def test_english_continuation_lines_keep_the_word_break(self):
        # The mirror of the case above: dropping the space here would weld two
        # words together ("required for" + "bandEnergy").
        sym = method(["Widget", "reset()"], "()",
                     ["Resets the widget.",
                      "- Note: Leaving this unset makes the call",
                      "  return zero instead of failing."])
        self.assertEqual(
            gen.get_doc_callouts(sym),
            ["Note: Leaving this unset makes the call return zero "
             "instead of failing."])

    def test_a_wrap_between_scripts_keeps_the_space(self):
        # Only a CJK/CJK seam is closed up; a Japanese line wrapping onto an
        # ASCII identifier still needs the separator, matching how the sources
        # write it on one line: `Darwin の ``sys/tty.h`` にある`.
        sym = method(["Widget", "reset()"], "()",
                     ["説明。",
                      "- Note: 先に呼ぶべきなのは",
                      "  `configure(_:)` です。"])
        self.assertEqual(gen.get_doc_callouts(sym),
                         ["Note: 先に呼ぶべきなのは `configure(_:)` です。"])

    def test_a_wrap_after_full_width_punctuation_takes_no_space(self):
        # 。 is full-width and already carries its own padding. The sources
        # write `になります。``metaphor`` は` with no space, so a wrap at that
        # seam must not invent one.
        sym = method(["Widget", "reset()"], "()",
                     ["説明。",
                      "- Note: 呼ばないと失敗します。",
                      "  `configure(_:)` を先に呼びます。"])
        self.assertEqual(gen.get_doc_callouts(sym),
                         ["Note: 呼ばないと失敗します。`configure(_:)` を先に呼びます。"])

    def test_a_wrap_before_full_width_punctuation_takes_no_space(self):
        # The mirror case: a continuation starting with 、 must not be pushed
        # away from the word it attaches to.
        sym = method(["Widget", "reset()"], "()",
                     ["説明。",
                      "- Note: 使えるのは `reset()`",
                      "  、および `clear()` です。"])
        self.assertEqual(gen.get_doc_callouts(sym),
                         ["Note: 使えるのは `reset()`、および `clear()` です。"])

    def test_multiple_callouts_keep_source_order(self):
        sym = method(["Widget", "reset()"], "()",
                     ["説明。", "- Note: 一つ目。", "- Important: 二つ目。"])
        self.assertEqual(gen.get_doc_callouts(sym),
                         ["Note: 一つ目。", "Important: 二つ目。"])

    def test_parameters_block_is_not_a_callout(self):
        # `- Parameters:` and `- Returns:` are structural; the signature above
        # them already says what they say.
        sym = method(["Widget", "resize(to:)"], "(_ size: Float) -> Bool",
                     ["大きさを変更します。",
                      "- Parameters:",
                      "  - size: 新しい大きさ。",
                      "- Returns: 成功したかどうか。"])
        self.assertEqual(gen.get_doc_callouts(sym), [])
        self.assertEqual(gen.get_doc_summary(sym), "大きさを変更します。")

    def test_a_parameter_named_note_is_not_a_callout(self):
        # MIDIManager documents a parameter literally called `note`. Indentation
        # is the only thing separating it from a callout, so this is what stops
        # "Note: The MIDI note number (0-127)." being published as API guidance.
        sym = method(["MIDIManager", "sendNoteOn(_:velocity:)"],
                     "(_ note: UInt8, velocity: UInt8)",
                     ["ノートオンを送ります。",
                      "- Parameters:",
                      "  - note: The MIDI note number (0-127).",
                      "  - velocity: The velocity (0-127)."])
        self.assertEqual(gen.get_doc_callouts(sym), [])

    def test_a_lowercase_callout_is_matched_and_recapitalised(self):
        # DocC renders `- note:` as a Note. Matching case-sensitively here
        # would let a callout show up in the DocC reference but silently vanish
        # from llms.txt — the same class of loss this whole change fixes.
        sym = method(["Widget", "reset()"], "()",
                     ["説明。", "- note: 描画中は呼べません。"])
        self.assertEqual(gen.get_doc_callouts(sym),
                         ["Note: 描画中は呼べません。"])

    def test_an_indented_parameter_child_never_wins_over_indentation(self):
        # The pair to the two tests above: same spelling, different indentation,
        # opposite verdicts. Neither guard alone explains the behaviour.
        top = method(["Widget", "reset()"], "()", ["説明。", "- Note: 効きます。"])
        child = method(["Widget", "reset()"], "()",
                       ["説明。", "- Parameters:", "  - Note: 効きません。"])
        self.assertEqual(gen.get_doc_callouts(top), ["Note: 効きます。"])
        self.assertEqual(gen.get_doc_callouts(child), [])

    def test_seealso_is_not_emitted(self):
        # Every `- SeeAlso:` reaching the symbol graphs comes from Apple's own
        # SwiftUI docs, not from metaphor sources. Navigational, not advisory.
        sym = method(["Widget", "reset()"], "()",
                     ["説明。", "- SeeAlso: ``Widget/configure(_:)``"])
        self.assertEqual(gen.get_doc_callouts(sym), [])

    def test_callout_body_is_flattened_like_the_summary(self):
        sym = method(["Widget", "reset()"], "()",
                     ["説明。", "- Note: ``configure(_:)`` を先に呼びます。"])
        self.assertEqual(gen.get_doc_callouts(sym),
                         ["Note: `configure(_:)` を先に呼びます。"])

    def test_a_bodiless_callout_is_dropped(self):
        # Otherwise the marker alone renders as a dangling "  - Note: ".
        sym = method(["Widget", "reset()"], "()", ["説明。", "- Note:"])
        self.assertEqual(gen.get_doc_callouts(sym), [])

    def test_callout_without_a_summary_is_still_captured(self):
        # Parameter-only docs yield no summary; the callout must survive alone.
        sym = method(["Widget", "reset()"], "()",
                     ["- Parameter size: 大きさ。", "- Important: 破壊的です。"])
        self.assertEqual(gen.get_doc_summary(sym), "")
        self.assertEqual(gen.get_doc_callouts(sym), ["Important: 破壊的です。"])


class CalloutRenderingTests(unittest.TestCase):
    """Callouts are indented one level under the line they annotate."""

    def test_member_callout_follows_its_declaration(self):
        out = render(MetaphorCore=module(
            SIMD2_EXTENSION,
            method(["SIMD2", "normalized()"], "() -> SIMD2<Float>",
                   ["単位ベクトルを返します。", "- Note: 零ベクトルでは零を返します。"]),
        ))
        self.assertIn(
            "- `func normalized() -> SIMD2<Float>` -- 単位ベクトルを返します。\n"
            "  - Note: 零ベクトルでは零を返します。",
            out)

    def test_symbol_without_callouts_stays_a_single_line(self):
        # Guards the existing one-line shape against stray blank lines.
        out = render(MetaphorCore=module(
            SIMD2_EXTENSION,
            method(["SIMD2", "normalized()"], "() -> SIMD2<Float>",
                   ["単位ベクトルを返します。"]),
        ))
        self.assertIn(
            "- `func normalized() -> SIMD2<Float>` -- 単位ベクトルを返します。\n\n",
            out)

    def test_type_level_callout_follows_the_heading(self):
        # KeyCode's `- Important: import Foundation …` is documented on the
        # type, not on a member, so heading-level callouts must render too.
        own = symbol(gen.KIND_ENUM, ["KeyCode"], [
            frag("keyword", "enum"),
            frag("text", " "),
            frag("identifier", "KeyCode"),
        ], ["仮想キーコードの名前空間。",
            "- Important: `import Foundation` と併用すると曖昧になります。"])
        out = render(MetaphorCore=module(own))
        self.assertIn(
            "### `enum KeyCode` -- 仮想キーコードの名前空間。\n"
            "  - Important: `import Foundation` と併用すると曖昧になります。",
            out)


if __name__ == "__main__":
    unittest.main()
