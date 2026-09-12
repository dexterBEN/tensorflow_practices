#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE_DIR="$PROJECT_DIR/.build/tflite_cortex_a9/tensorflow"
PATCH="$SCRIPT_DIR/patches/tensorflow-2.13-armhf-vfpv3.patch"
PYTHON=/opt/notebooks-venv/bin/python3
TAG=v2.13.0
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || fail 'Run inside the x86_64 notebooks devcontainer.'
[[ -x "$PYTHON" && -f "$PATCH" ]] || fail 'Missing devcontainer Python or patch.'
for tool in git cmake make curl tar xz file readelf; do
    command -v "$tool" >/dev/null || fail "Missing tool: $tool"
done
"$PYTHON" -c 'import sys, numpy, pybind11, wheel, setuptools; assert sys.version_info[:2] == (3,10); assert numpy.__version__ == "1.21.5"'
[[ ${BUILD_NUM_JOBS:-2} =~ ^[1-9][0-9]*$ ]] || fail 'BUILD_NUM_JOBS must be positive.'
mkdir -p "$(dirname -- "$SOURCE_DIR")"
if [[ ! -e "$SOURCE_DIR" ]]; then
    git clone --branch "$TAG" --depth 1 https://github.com/tensorflow/tensorflow.git "$SOURCE_DIR"
fi
[[ -d "$SOURCE_DIR/.git" ]] || fail "Not a checkout: $SOURCE_DIR"
cd "$SOURCE_DIR"
[[ $(git remote get-url origin) == https://github.com/tensorflow/tensorflow.git ]] || fail 'Unexpected origin.'
[[ $(git rev-parse HEAD) == "$(git rev-parse "$TAG^{commit}")" ]] || fail 'Checkout is not v2.13.0.'
git diff --cached --quiet || fail 'Index has local changes.'
if git apply --check "$PATCH"; then
    git diff --quiet || fail 'Checkout has local changes; refusing to patch.'
    git apply "$PATCH"
elif git apply --reverse --check "$PATCH"; then
    echo 'Patch already applied.'
else
    fail 'Patch neither applicable nor already applied; inspect the checkout manually.'
fi
# Do not inherit host compiler flags or alternate package/platform names.
unset CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS BUILD_FLAGS CI_BUILD_HOME
export CI_BUILD_PYTHON="$PYTHON"
export TENSORFLOW_TARGET=armhf_vfpv3
export BUILD_NUM_JOBS="${BUILD_NUM_JOBS:-2}"
export VERSION_SUFFIX="" WHEEL_PROJECT_NAME=tflite_runtime
export WHEEL_PLATFORM_NAME=linux-armv7l BUILD_DEB=n
# The official script recreates its own generated build directory on each run.
tensorflow/lite/tools/pip_package/build_pip_package_with_cmake.sh
DIST="$SOURCE_DIR/tensorflow/lite/tools/pip_package/gen/tflite_pip/$PYTHON/dist"
shopt -s nullglob
wheels=("$DIST"/tflite_runtime-2.13.0-cp310-*-linux_armv7l.whl)
[[ ${#wheels[@]} -eq 1 ]] || fail "Expected exactly one CPython 3.10 ARMv7 wheel in $DIST"
"$SCRIPT_DIR/verify.sh" "${wheels[0]}"
OUTPUT_DIR="$PROJECT_DIR/artifacts/tflite_runtime"
mkdir -p "$OUTPUT_DIR"
cp -- "${wheels[0]}" "$OUTPUT_DIR/"
printf 'Validated wheel: %s/%s\n' "$OUTPUT_DIR" "$(basename -- "${wheels[0]}")"
