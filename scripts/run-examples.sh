#!/bin/bash
# run-examples.sh - Build and run metaphor examples one by one
#
# Usage: ./scripts/run-examples.sh [OPTIONS] [FILTER...]
# See --help for details.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
EXAMPLES_DIR="$ROOT_DIR/Examples"

# State
LAST_SIGINT_TIME=0
ABORT=0
SKIP=0
CHILD_PID=0

# Counters
TOTAL=0
BUILT=0
BUILD_FAILED=0
RAN=0
SKIPPED=0

# Result arrays
PASSED_LIST=()
FAILED_LIST=()
SKIPPED_LIST=()
NOTED_LIST=()
NOTE_VALUES=()

# Options
INCLUDE_LEGACY=0
LEGACY_ONLY=0
BUILD_ONLY=0
LIST_ONLY=0
USE_COLOR=1
LOG_FILE="/tmp/metaphor-examples.log"
REPORT_FILE=""
NO_PROMPT=0
FILTERS=()

# ─── Usage ────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Usage: run-examples.sh [OPTIONS] [FILTER...]

Run metaphor examples interactively, one at a time.
Each example opens a window. Close the window to proceed to the next example.

Options:
  -h, --help         Show this help message
  -l, --list         List matching examples without building or running
  -b, --build-only   Build each example but do not run it
  -a, --all          Include _Legacy/ examples (excluded by default)
  --legacy-only      Run only _Legacy/ examples
  --no-prompt        Skip the note prompt after each example
  --report FILE      Save review report to FILE (default: examples-report.md)
  --no-color         Disable colored output
  --log FILE         Write build errors to FILE (default: /tmp/metaphor-examples.log)

Filters:
  Positional arguments are matched as path prefixes (relative to Examples/).

  Examples:
    ./scripts/run-examples.sh Basics/Color       # all Color examples
    ./scripts/run-examples.sh Basics Topics/GUI   # multiple filters
    ./scripts/run-examples.sh ML                  # just ML examples

Controls during run:
  Ctrl+C              Skip the current example and move to the next
  Ctrl+C Ctrl+C       Abort the entire run (two Ctrl+C within 2 seconds)
  Ctrl+\              Abort the entire run immediately

After each example closes, you can leave a mark:
  Enter               OK, move to next
  !  <text>           Flag as issue (e.g. "! crash on resize")
  ?  <text>           Flag as needs investigation
  *  <text>           Flag as notable/good
  <any text>          Free-form note
EOF
}

# ─── Argument parsing ─────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)      usage; exit 0 ;;
        -l|--list)      LIST_ONLY=1; shift ;;
        -b|--build-only) BUILD_ONLY=1; shift ;;
        -a|--all)       INCLUDE_LEGACY=1; shift ;;
        --legacy-only)  LEGACY_ONLY=1; INCLUDE_LEGACY=1; shift ;;
        --no-prompt)    NO_PROMPT=1; shift ;;
        --report)       REPORT_FILE="$2"; shift 2 ;;
        --no-color)     USE_COLOR=0; shift ;;
        --log)          LOG_FILE="$2"; shift 2 ;;
        -*)             echo "Unknown option: $1"; usage; exit 1 ;;
        *)              FILTERS+=("$1"); shift ;;
    esac
done

# ─── Colors ───────────────────────────────────────────────────

if [[ "$USE_COLOR" -eq 1 ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' RESET=''
fi

info()    { echo -e "${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
success() { echo -e "  ${GREEN}OK${RESET}   $*"; }
warn()    { echo -e "  ${YELLOW}SKIP${RESET} $*"; }
fail()    { echo -e "  ${RED}FAIL${RESET} $*"; }

# ─── Spinner ─────────────────────────────────────────────────

SPINNER_PID=0

spinner_start() {
    local msg="${1:-Building}"
    if [[ ! -t 1 ]]; then
        # Not a terminal — just print the message without spinner
        echo -ne "  ${DIM}${msg}...${RESET}"
        return
    fi
    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        while true; do
            echo -ne "\r  ${DIM}${frames[$i]} ${msg}...${RESET}\033[K"
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null
}

spinner_stop() {
    if [[ $SPINNER_PID -ne 0 ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=0
        # Clear the spinner line
        if [[ -t 1 ]]; then
            echo -ne "\r\033[K"
        else
            echo ""
        fi
    fi
}

# ─── Signal handlers ─────────────────────────────────────────

handle_sigint() {
    spinner_stop
    local now
    now=$(date +%s)
    if (( now - LAST_SIGINT_TIME <= 2 )); then
        echo ""
        echo -e "${RED}Aborting all examples...${RESET}"
        ABORT=1
        if [[ $CHILD_PID -ne 0 ]]; then
            kill -TERM "$CHILD_PID" 2>/dev/null
        fi
    else
        echo ""
        echo -e "${YELLOW}Skipping... (Ctrl+C again within 2s to abort all)${RESET}"
        SKIP=1
        LAST_SIGINT_TIME=$now
        if [[ $CHILD_PID -ne 0 ]]; then
            kill -TERM "$CHILD_PID" 2>/dev/null
        fi
    fi
}

handle_sigquit() {
    spinner_stop
    echo ""
    echo -e "${RED}Aborting all examples (SIGQUIT)...${RESET}"
    ABORT=1
    if [[ $CHILD_PID -ne 0 ]]; then
        kill -TERM "$CHILD_PID" 2>/dev/null
    fi
}

trap handle_sigint INT
trap handle_sigquit QUIT

# ─── Example discovery ────────────────────────────────────────

discover_examples() {
    while IFS= read -r -d '' pkg; do
        local dir
        dir="$(dirname "$pkg")"
        local rel_path
        rel_path="${dir#$EXAMPLES_DIR/}"

        # Legacy filtering
        if [[ "$LEGACY_ONLY" -eq 1 ]]; then
            [[ "$rel_path" == _Legacy/* ]] || continue
        elif [[ "$INCLUDE_LEGACY" -eq 0 ]]; then
            [[ "$rel_path" == _Legacy/* ]] && continue
        fi

        # Filter matching (prefix match)
        if [[ ${#FILTERS[@]} -gt 0 ]]; then
            local matched=0
            for filter in "${FILTERS[@]}"; do
                if [[ "$rel_path" == "${filter}"* ]] || [[ "$rel_path" == "$filter" ]]; then
                    matched=1
                    break
                fi
            done
            [[ $matched -eq 1 ]] || continue
        fi

        echo "$dir"
    done < <(find "$EXAMPLES_DIR" -name "Package.swift" -print0 | sort -z)
}

# ─── Build ────────────────────────────────────────────────────

build_example() {
    local dir="$1"
    local rel_path="${dir#$EXAMPLES_DIR/}"

    spinner_start "Building"
    local build_output
    build_output=$(cd "$dir" && swift build 2>&1)
    local rc=$?
    spinner_stop

    if [[ $rc -ne 0 ]]; then
        fail "Build failed: $rel_path"
        echo "=== BUILD FAILURE: $rel_path ===" >> "$LOG_FILE"
        echo "$build_output" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        return 1
    fi

    return 0
}

# ─── Run ──────────────────────────────────────────────────────

run_example() {
    local dir="$1"

    SKIP=0

    # Run in background so trap can fire during wait
    (cd "$dir" && exec swift run 2>&1) &
    CHILD_PID=$!

    wait "$CHILD_PID" 2>/dev/null
    local rc=$?

    CHILD_PID=0

    # Restore terminal settings (GUI apps may leave terminal in raw mode)
    stty sane 2>/dev/null

    if [[ "$ABORT" -eq 1 ]]; then
        return 2
    elif [[ "$SKIP" -eq 1 ]]; then
        return 3
    fi

    return 0
}

# ─── Note prompt ──────────────────────────────────────────────

# Prompt user for a note after each example.
# Appends to NOTED_LIST and NOTE_VALUES parallel arrays.
prompt_note() {
    local rel="$1"

    if [[ "$NO_PROMPT" -eq 1 ]]; then
        return
    fi

    # Read from /dev/tty to avoid conflict with piped stdin
    echo -ne "  ${DIM}Note (Enter=OK, !=issue, ?=todo, *=good):${RESET} "
    local note
    read -r note </dev/tty 2>/dev/null || return

    if [[ -n "$note" ]]; then
        NOTED_LIST+=("$rel")
        NOTE_VALUES+=("$note")

        # Classify the mark
        local mark_char="${note:0:1}"
        case "$mark_char" in
            '!') echo -e "  ${RED}!${RESET} Marked as issue" ;;
            '?') echo -e "  ${YELLOW}?${RESET} Marked for investigation" ;;
            '*') echo -e "  ${GREEN}*${RESET} Marked as notable" ;;
            *)   echo -e "  ${DIM}#${RESET} Note saved" ;;
        esac
    fi
}

# ─── Report ───────────────────────────────────────────────────

write_report() {
    local file="$1"
    [[ -z "$file" ]] && return

    {
        echo "# Examples Review Report"
        echo ""
        echo "Date: $(date '+%Y-%m-%d %H:%M')"
        echo ""
        echo "## Summary"
        echo ""
        echo "| | Count |"
        echo "|---|---|"
        echo "| Total | $TOTAL |"
        if [[ "$BUILD_ONLY" -eq 1 ]]; then
            echo "| Build succeeded | $BUILT |"
        else
            echo "| Ran successfully | $RAN |"
        fi
        [[ $BUILD_FAILED -gt 0 ]] && echo "| Build failed | $BUILD_FAILED |"
        [[ $SKIPPED -gt 0 ]] && echo "| Skipped | $SKIPPED |"
        echo "| Notes | ${#NOTED_LIST[@]} |"

        # Notes section
        if [[ ${#NOTED_LIST[@]} -gt 0 ]]; then
            echo ""
            echo "## Notes"
            echo ""

            # Group by mark type
            local has_issues=0 has_todos=0 has_stars=0 has_other=0
            local idx
            for idx in "${!NOTED_LIST[@]}"; do
                local mark="${NOTE_VALUES[$idx]:0:1}"
                case "$mark" in
                    '!') has_issues=1 ;;
                    '?') has_todos=1 ;;
                    '*') has_stars=1 ;;
                    *)   has_other=1 ;;
                esac
            done

            if [[ $has_issues -eq 1 ]]; then
                echo "### Issues (!)"
                echo ""
                for idx in "${!NOTED_LIST[@]}"; do
                    local note="${NOTE_VALUES[$idx]}"
                    [[ "${note:0:1}" == '!' ]] && echo "- **${NOTED_LIST[$idx]}**: ${note:1}" | sed 's/:  /: /'
                done
                echo ""
            fi

            if [[ $has_todos -eq 1 ]]; then
                echo "### Needs Investigation (?)"
                echo ""
                for idx in "${!NOTED_LIST[@]}"; do
                    local note="${NOTE_VALUES[$idx]}"
                    [[ "${note:0:1}" == '?' ]] && echo "- **${NOTED_LIST[$idx]}**: ${note:1}" | sed 's/:  /: /'
                done
                echo ""
            fi

            if [[ $has_stars -eq 1 ]]; then
                echo "### Notable (*)"
                echo ""
                for idx in "${!NOTED_LIST[@]}"; do
                    local note="${NOTE_VALUES[$idx]}"
                    [[ "${note:0:1}" == '*' ]] && echo "- **${NOTED_LIST[$idx]}**: ${note:1}" | sed 's/:  /: /'
                done
                echo ""
            fi

            if [[ $has_other -eq 1 ]]; then
                echo "### Other Notes"
                echo ""
                for idx in "${!NOTED_LIST[@]}"; do
                    local note="${NOTE_VALUES[$idx]}"
                    local mark="${note:0:1}"
                    [[ "$mark" != '!' && "$mark" != '?' && "$mark" != '*' ]] && echo "- **${NOTED_LIST[$idx]}**: $note"
                done
                echo ""
            fi
        fi

        # Build failures
        if [[ $BUILD_FAILED -gt 0 ]]; then
            echo "## Build Failures"
            echo ""
            for name in "${FAILED_LIST[@]}"; do
                echo "- $name"
            done
            echo ""
        fi
    } > "$file"
}

# ─── Summary ──────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Summary${RESET}"
    echo -e "${BOLD}════════════════════════════════════════${RESET}"
    echo ""
    echo "  Total examples:    $TOTAL"

    if [[ "$BUILD_ONLY" -eq 1 ]]; then
        echo -e "  ${GREEN}Build succeeded:   $BUILT${RESET}"
    else
        echo -e "  ${GREEN}Ran successfully:  $RAN${RESET}"
    fi

    if [[ $BUILD_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Build failed:      $BUILD_FAILED${RESET}"
    fi

    if [[ $SKIPPED -gt 0 ]]; then
        echo -e "  ${YELLOW}Skipped:           $SKIPPED${RESET}"
    fi

    local not_reached
    if [[ "$BUILD_ONLY" -eq 1 ]]; then
        not_reached=$(( TOTAL - BUILT - BUILD_FAILED ))
    else
        not_reached=$(( TOTAL - RAN - BUILD_FAILED - SKIPPED ))
    fi
    if [[ $not_reached -gt 0 ]]; then
        echo -e "  ${DIM}Not reached:       $not_reached${RESET}"
    fi

    if [[ $BUILD_FAILED -gt 0 ]]; then
        echo ""
        echo -e "  ${RED}Failed builds:${RESET}"
        for name in "${FAILED_LIST[@]}"; do
            echo "    - $name"
        done
        echo ""
        echo "  Build error details: $LOG_FILE"
    fi

    if [[ $SKIPPED -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}Skipped:${RESET}"
        for name in "${SKIPPED_LIST[@]}"; do
            echo "    - $name"
        done
    fi

    if [[ ${#NOTED_LIST[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${BOLD}Notes (${#NOTED_LIST[@]}):${RESET}"
        local idx
        for idx in "${!NOTED_LIST[@]}"; do
            local rel="${NOTED_LIST[$idx]}"
            local note="${NOTE_VALUES[$idx]}"
            local mark="${note:0:1}"
            case "$mark" in
                '!') echo -e "    ${RED}!${RESET} $rel: ${note:1}" | sed 's/:  /: /' ;;
                '?') echo -e "    ${YELLOW}?${RESET} $rel: ${note:1}" | sed 's/:  /: /' ;;
                '*') echo -e "    ${GREEN}*${RESET} $rel: ${note:1}" | sed 's/:  /: /' ;;
                *)   echo -e "    ${DIM}#${RESET} $rel: $note" ;;
            esac
        done
    fi

    echo ""
}

# ─── Main ─────────────────────────────────────────────────────

main() {
    # Initialize log
    echo "metaphor examples run - $(date)" > "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # Discover examples
    spinner_start "Scanning for examples"
    local example_dirs=()
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && example_dirs+=("$dir")
    done < <(discover_examples)
    spinner_stop

    TOTAL=${#example_dirs[@]}

    if [[ $TOTAL -eq 0 ]]; then
        echo "No examples found matching the given filters."
        exit 1
    fi

    # List mode
    if [[ "$LIST_ONLY" -eq 1 ]]; then
        echo "Found $TOTAL examples:"
        echo ""
        local i=0
        for dir in "${example_dirs[@]}"; do
            (( i++ ))
            local rel="${dir#$EXAMPLES_DIR/}"
            printf "  %3d. %s\n" "$i" "$rel"
        done
        exit 0
    fi

    local mode="Build + Run"
    [[ "$BUILD_ONLY" -eq 1 ]] && mode="Build only"
    info "Starting example runner ($mode, $TOTAL examples)"
    echo ""

    local i=0
    for dir in "${example_dirs[@]}"; do
        (( i++ ))
        local rel="${dir#$EXAMPLES_DIR/}"

        [[ "$ABORT" -eq 1 ]] && break

        echo -e "${BOLD}[$i/$TOTAL]${RESET} ${BLUE}$rel${RESET}"

        # Build
        if ! build_example "$dir"; then
            (( BUILD_FAILED++ ))
            FAILED_LIST+=("$rel")
            continue
        fi
        (( BUILT++ ))

        # Run (unless build-only)
        if [[ "$BUILD_ONLY" -eq 0 ]]; then
            run_example "$dir"
            local rc=$?

            if [[ $rc -eq 2 ]]; then
                SKIPPED_LIST+=("$rel (aborted)")
                (( SKIPPED++ ))
                break
            elif [[ $rc -eq 3 ]]; then
                warn "$rel"
                SKIPPED_LIST+=("$rel")
                (( SKIPPED++ ))
                prompt_note "$rel"
            else
                success "$rel"
                PASSED_LIST+=("$rel")
                (( RAN++ ))
                prompt_note "$rel"
            fi
        else
            success "$rel"
            PASSED_LIST+=("$rel")
        fi
    done

    print_summary

    # Write report file if notes were taken (auto-generate path if not specified)
    if [[ ${#NOTED_LIST[@]} -gt 0 ]] && [[ -z "$REPORT_FILE" ]]; then
        REPORT_FILE="$ROOT_DIR/examples-report.md"
    fi
    if [[ -n "$REPORT_FILE" ]]; then
        write_report "$REPORT_FILE"
        echo -e "  Report saved to: ${BOLD}$REPORT_FILE${RESET}"
        echo ""
    fi
}

main
