#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

sdk_path="$(xcrun --show-sdk-path 2>/dev/null || true)"
if [[ -z "$sdk_path" ]]; then
    printf '%s\n' "Error: Failed to locate macOS SDK via xcrun" >&2
    exit 1
fi

# Private, unpredictable directory (macOS $TMPDIR is per-user, mode 0700) so no other
# local user can pre-create or swap the binary between linking and running it.
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/spotpen-tests.XXXXXX")"
# Fixed name: an unbundled binary stores AppKit state (e.g. status item positions) in a
# preferences domain named after the executable, so a stable name avoids one file per run.
test_name="SpotPenTests"
test_bin="${test_dir}/${test_name}"

cleanup() {
    rm -rf "$test_dir"
    # Drop the test-only preference domains (process domain + suites used by the tests),
    # then the empty files cfprefsd leaves behind.
    local domain
    for domain in "$test_name" "${test_name}.B"; do
        defaults delete "$domain" >/dev/null 2>&1 || true
        rm -f "${HOME}/Library/Preferences/${domain}.plist"
    done
}
trap cleanup EXIT INT TERM

# Collect app sources excluding entry points with @main (e.g. Main.swift)
sources=()
while IFS= read -r file; do
    if ! grep -q "@main" "$file" 2>/dev/null; then
        sources+=("$file")
    fi
done < <(find Sources/App -type f -name "*.swift" | sort)

tests=()
while IFS= read -r file; do
    tests+=("$file")
done < <(find Tests/AppTests -type f -name "*.swift" | sort)

if [[ ${#tests[@]} -eq 0 ]]; then
    printf '%s\n' "Error: No test files found under Tests" >&2
    exit 1
fi

printf '%s\n' "Compiling unit test suite ($(uname -m))..."
swiftc -sdk "$sdk_path" \
    -target "$(uname -m)-apple-macos${MIN_MACOS_VERSION}" \
    "${sources[@]}" \
    "${tests[@]}" \
    -o "$test_bin"

test_status=0
"$test_bin" || test_status=$?

if [[ "$test_status" -ne 0 ]]; then
    printf '%s\n' "Error: Swift unit tests failed with status ${test_status}" >&2
    exit "$test_status"
fi
