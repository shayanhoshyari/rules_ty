#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=== Phase 2: Performance Measurement ==="
echo ""

echo "Building all targets..."
bazel build //:bench_all //app:main 2>&1
echo ""

RUNFILES="bazel-bin/bench_all.runfiles"
FIRST_PARTY="$RUNFILES/_main"

PIP_PATHS=()
for dir in "$RUNFILES"/rules_python++pip+pip_312_*/site-packages; do
    if [ -d "$dir" ]; then
        PIP_PATHS+=(--extra-search-path "$dir")
    fi
done

echo "Pip packages found: $(echo "${PIP_PATHS[@]}" | tr ' ' '\n' | grep -c 'extra-search-path')"
echo ""

run_ty() {
    local label="$1"
    shift
    echo "--- $label ---"
    local start end elapsed
    start=$(python3 -c "import time; print(time.perf_counter())")
    uvx ty check "$@" 2>&1
    end=$(python3 -c "import time; print(time.perf_counter())")
    elapsed=$(python3 -c "print(f'{$end - $start:.3f}s')")
    echo "Time: $elapsed"
    echo ""
}

echo "=== Per-target benchmarks ==="
echo ""

run_ty "1. Leaf library (baseline)" \
    lib_base/base.py --python-version 3.12

run_ty "2. First-party chain (3 deep)" \
    lib_top/top.py --python-version 3.12 \
    --extra-search-path "$FIRST_PARTY"

run_ty "3. Deep first-party chain (25 libs)" \
    bench_deep/deep.py --python-version 3.12 \
    --extra-search-path "$FIRST_PARTY"

run_ty "4. Heavy third-party (pandas + numpy)" \
    bench_heavy/heavy.py --python-version 3.12 \
    --extra-search-path "$FIRST_PARTY" "${PIP_PATHS[@]}"

run_ty "5. Wide third-party (7 packages)" \
    bench_wide/wide.py --python-version 3.12 \
    --extra-search-path "$FIRST_PARTY" "${PIP_PATHS[@]}"

run_ty "6. App (first-party + third-party)" \
    app/main.py --python-version 3.12 \
    --extra-search-path "$FIRST_PARTY" "${PIP_PATHS[@]}"

echo "=== Done ==="
