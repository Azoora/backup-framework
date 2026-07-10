#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test.sh  --  Backup Framework test runner
#
# Simple test framework without external dependencies.
# Each test file is sourced and defines test_* functions.
# ---------------------------------------------------------------------------
set -Eeuo pipefail

ABF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ABF_ROOT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
_ALREADY_RUN=""

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo "  FAIL: $message"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        return 1
    fi
    return 0
}

assert_neq() {
    local unexpected="$1"
    local actual="$2"
    local message="${3:-}"
    if [[ "$unexpected" == "$actual" ]]; then
        echo "  FAIL: $message"
        echo "    unexpected: $unexpected"
        echo "    actual:     $actual"
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  FAIL: $message"
        echo "    expected to contain: $needle"
        echo "    in: $haystack"
        return 1
    fi
    return 0
}

run_test() {
    local test_name="$1"
    if echo "$_ALREADY_RUN" | grep -qF "$test_name"; then
        return
    fi
    _ALREADY_RUN="${_ALREADY_RUN} ${test_name}"

    TESTS_RUN=$((TESTS_RUN + 1))
    local tmpdir
    tmpdir=$(mktemp -d -t "abf-test-XXXXXX")

    set +e
    (
        set -Eeuo pipefail
        cd "$tmpdir"
        "$test_name"
    )
    local rc=$?
    set -e

    rm -rf "$tmpdir"

    if [[ $rc -eq 0 ]]; then
        echo "  PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: $test_name (exit code: $rc)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

run_test_file() {
    local file="$1"
    local test_name
    test_name=$(basename "$file" .sh)

    echo ""
    echo "=== $test_name ==="

    # shellcheck source=/dev/null
    source "$file"

    local funcs
    funcs=$(declare -F | awk '{print $3}' | grep '^test_' || true)

    if [[ -z "$funcs" ]]; then
        echo "  No test functions found"
        return
    fi

    while IFS= read -r func; do
        [[ -z "$func" ]] && continue
        run_test "$func"
    done <<< "$funcs"
}

# ---- Main ----

main() {
    local test_dir="${ABF_ROOT}/tests"
    local files=()

    if [[ $# -gt 0 ]]; then
        for arg in "$@"; do
            files+=("${test_dir}/${arg}.sh")
        done
    else
        for f in "$test_dir"/*.sh; do
            [[ -f "$f" ]] && files+=("$f")
        done
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No test files found in ${test_dir}"
        exit 0
    fi

    for file in "${files[@]}"; do
        run_test_file "$file"
    done

    echo ""
    echo "=== Results: ${TESTS_PASSED}/${TESTS_RUN} passed, ${TESTS_FAILED} failed ==="
    return "$([ "$TESTS_FAILED" -eq 0 ] && echo 0 || echo 1)"
}

main "$@"
