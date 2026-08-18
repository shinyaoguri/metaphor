#!/usr/bin/env python3
"""Unit tests for scripts/gh-retry.sh.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

What is being pinned is a *classification*, not a wrapper (Issue #949 / #947 /
#960). The three PR metadata gates in ci.yml read title/labels/body from the API
at run time so that fixing a title, adding a label, or pasting an image lets
`gh run rerun --failed` pass without a push. That design is worth keeping; what
it lacked was retrying the call, so GitHub's 2026-08-17 GraphQL outage turned
three clean PRs red and stalled auto-merge.

A retry wrapper is easy to write and easy to get subtly wrong in two directions,
neither of which shows up as a broken check:

  * **Retrying too little** reproduces the original bug — the gate goes red on a
    blip. So a 5xx, a connection error with no HTTP status at all, and a
    GraphQL-level error (HTTP 200 with an `errors` array, which is how GitHub
    reports some transient faults) must all be retried.
  * **Retrying too much** hides real breakage behind a delay: a 403 from a
    missing `permissions:` block (ci.yml has that exact scar) or a 404 will
    never succeed, and burning the budget on them only makes the red slower to
    read. So a definitive 4xx must fail on the first call — while 408/429, which
    do get better on their own, stay retryable.

The third failure mode is silent corruption: callers capture stdout with
`$(...)`, so anything a *failed* attempt printed before dying must never reach
the caller, and the retry notices must go to stderr rather than into the
captured JSON.

`gh` and `sleep` are both stubbed on PATH. Stubbing `sleep` keeps the suite fast
without adding a test-only knob to the script, and it lets the backoff schedule
itself be asserted.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "gh-retry.sh"

# Records every call, then behaves as GH_STUB_PLAN dictates for that attempt
# (colon-separated, one field per attempt; the last field repeats).
_GH_STUB = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_CALLS"
n=$(wc -l < "$GH_STUB_CALLS" | tr -d ' ')
behavior=$(printf '%s' "$GH_STUB_PLAN" | awk -F: -v i="$n" '{print (i <= NF ? $i : $NF)}')
case "$behavior" in
  ok)
    printf '%s' "$GH_STUB_STDOUT"
    exit 0
    ;;
  partial)
    # Dies halfway through writing, as a killed/interrupted call would.
    printf 'PARTIAL-GARBAGE'
    echo "HTTP 503: No server is currently available to service your request. (https://api.github.com/graphql)" >&2
    exit 1
    ;;
  nostatus)
    echo "error connecting to api.github.com: no such host" >&2
    exit 1
    ;;
  graphql)
    # HTTP 200 carrying an errors array — how GitHub reports some transient faults.
    echo "GraphQL: Something went wrong while executing your query." >&2
    exit 1
    ;;
  parens)
    # gh's other status spelling, e.g. `gh: Not Found (HTTP 404)`.
    echo "gh: Not Found (HTTP 404)" >&2
    exit 1
    ;;
  *)
    echo "HTTP ${behavior}: synthetic failure (https://api.github.com/graphql)" >&2
    exit 1
    ;;
esac
"""

# A sleep that records instead of sleeping.
_SLEEP_STUB = r"""#!/usr/bin/env bash
printf '%s\n' "$1" >> "$SLEEP_STUB_CALLS"
"""

_PAYLOAD = '{"title":"ci: retry gh calls","labels":[]}\n'


class GhRetryTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)

        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for name, body in (("gh", _GH_STUB), ("sleep", _SLEEP_STUB)):
            path = self.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(0o755)

        self.gh_calls = self.tmp / "gh-calls"
        self.sleep_calls = self.tmp / "sleep-calls"
        self.gh_calls.touch()
        self.sleep_calls.touch()

    def run_script(self, plan, *args, stdout=_PAYLOAD):
        """Run gh-retry.sh with the stubbed gh following `plan`."""
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["GH_STUB_PLAN"] = plan
        env["GH_STUB_STDOUT"] = stdout
        env["GH_STUB_CALLS"] = str(self.gh_calls)
        env["SLEEP_STUB_CALLS"] = str(self.sleep_calls)
        return subprocess.run(
            [str(_SCRIPT), *(args or ("pr", "view", "123", "--json", "title"))],
            capture_output=True,
            text=True,
            env=env,
        )

    def gh_call_count(self):
        return len(self.gh_calls.read_text(encoding="utf-8").splitlines())

    def sleeps(self):
        return self.sleep_calls.read_text(encoding="utf-8").split()

    # --- transient failures are retried ---------------------------------

    def test_transient_5xx_is_retried_until_it_succeeds(self):
        """The outage shape from #949: two 503s, then the call goes through."""
        result = self.run_script("503:503:ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, _PAYLOAD)
        self.assertEqual(self.gh_call_count(), 3)

    def test_backoff_grows_between_attempts(self):
        """1s then 2s — the schedule the sibling retry helpers already use."""
        self.run_script("503:503:ok")
        self.assertEqual(self.sleeps(), ["1", "2"])

    def test_failure_without_an_http_status_is_retried(self):
        """A connection error carries no status; unknown must mean retryable."""
        result = self.run_script("nostatus:ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.gh_call_count(), 2)

    def test_graphql_level_error_is_retried(self):
        """HTTP 200 + errors array is how GitHub reports some transient faults."""
        result = self.run_script("graphql:ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.gh_call_count(), 2)

    def test_rate_limit_429_is_retried_despite_being_4xx(self):
        """The documented exception to "4xx is definitive"."""
        result = self.run_script("429:429:ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.gh_call_count(), 3)

    # --- definitive failures are not retried ----------------------------

    def test_404_fails_on_the_first_call(self):
        result = self.run_script("404")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.gh_call_count(), 1)
        self.assertEqual(self.sleeps(), [])

    def test_403_fails_on_the_first_call(self):
        """A missing `permissions:` block 403s; waiting cannot fix it."""
        result = self.run_script("403")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.gh_call_count(), 1)
        self.assertIn("not retrying", result.stderr)

    def test_status_is_recognised_in_gh_s_parenthesised_spelling(self):
        """`gh: Not Found (HTTP 404)` must classify the same as `HTTP 404:`."""
        result = self.run_script("parens")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.gh_call_count(), 1)

    # --- exhaustion is a real failure -----------------------------------

    def test_exhausted_retries_fail_loudly(self):
        """A permanent outage stays red — the wrapper never passes silently."""
        result = self.run_script("503")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.gh_call_count(), 3)
        self.assertIn("after 3 attempts", result.stderr)

    # --- stdout is the data channel -------------------------------------

    def test_partial_output_from_a_failed_attempt_is_discarded(self):
        """Anything a dying attempt printed must not reach the caller's $()."""
        result = self.run_script("partial:ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, _PAYLOAD)
        self.assertNotIn("PARTIAL-GARBAGE", result.stdout)

    def test_retry_notices_go_to_stderr_not_stdout(self):
        """`::warning::` on stdout would corrupt the captured JSON."""
        result = self.run_script("503:ok")
        self.assertEqual(result.stdout, _PAYLOAD)
        self.assertIn("::warning::", result.stderr)

    # --- usage ----------------------------------------------------------

    def test_no_arguments_is_a_usage_error(self):
        result = self.run_script("ok", *())
        self.assertEqual(result.returncode, 0)  # sanity: default args are used

        env = dict(os.environ)
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["GH_STUB_PLAN"] = "ok"
        env["GH_STUB_STDOUT"] = ""
        env["GH_STUB_CALLS"] = str(self.gh_calls)
        env["SLEEP_STUB_CALLS"] = str(self.sleep_calls)
        bare = subprocess.run(
            [str(_SCRIPT)], capture_output=True, text=True, env=env
        )
        self.assertEqual(bare.returncode, 2)
        self.assertIn("usage:", bare.stderr)


if __name__ == "__main__":
    unittest.main()
