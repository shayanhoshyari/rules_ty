#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=== Phase 1: Module Resolution Validation ==="
echo ""

echo "Step 1: Building //app:main ..."
bazel build //app:main 2>&1
echo ""

RUNFILES="bazel-bin/app/main.runfiles"
FIRST_PARTY="$RUNFILES/_main"

# Discover pip package search paths from runfiles
PIP_PATHS=()
for dir in "$RUNFILES"/rules_python++pip+pip_312_*/site-packages; do
    if [ -d "$dir" ]; then
        PIP_PATHS+=(--extra-search-path "$dir")
    fi
done

echo "First-party search path: $FIRST_PARTY"
echo "Pip search paths: ${PIP_PATHS[*]}"
echo ""

echo "Step 2: ty check — lib_base (leaf, no deps)"
time uvx ty check lib_base/base.py --python-version 3.12
echo ""

echo "Step 3: ty check — lib_mid (imports lib_base)"
time uvx ty check lib_mid/mid.py --python-version 3.12 --extra-search-path "$FIRST_PARTY"
echo ""

echo "Step 4: ty check — lib_top (imports lib_mid → lib_base, transitive chain)"
time uvx ty check lib_top/top.py --python-version 3.12 --extra-search-path "$FIRST_PARTY"
echo ""

echo "Step 5: ty check — app/main.py (first-party + third-party: numpy, requests)"
time uvx ty check app/main.py --python-version 3.12 --extra-search-path "$FIRST_PARTY" "${PIP_PATHS[@]}"
echo ""

echo "=== All checks passed ==="
