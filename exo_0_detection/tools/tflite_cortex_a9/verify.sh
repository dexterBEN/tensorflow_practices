#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 <wheel.whl|wrapper.so>" >&2; exit 1; }
for tool in file readelf; do command -v "$tool" >/dev/null; done
TEMP_DIR=""
trap 'if [[ -n "$TEMP_DIR" ]]; then rm -rf -- "$TEMP_DIR"; fi' EXIT
SO="$1"
if [[ "$1" == *.whl ]]; then
    TEMP_DIR=$(mktemp -d)
    PYTHON=/opt/notebooks-venv/bin/python3
    [[ -x "$PYTHON" ]] || PYTHON=python3
    "$PYTHON" - "$1" "$TEMP_DIR" <<'PY'
import sys, zipfile
from pathlib import Path
member = 'tflite_runtime/_pywrap_tensorflow_interpreter_wrapper.so'
with zipfile.ZipFile(sys.argv[1]) as archive:
    matches = [info for info in archive.infolist()
               if not info.is_dir() and
               (info.filename == member or info.filename.endswith('/' + member))]
    if len(matches) != 1:
        raise SystemExit(f'Expected exactly one wrapper ending in /{member}; found {len(matches)}')
    print('Wheel wrapper:', matches[0].filename)
    # Write to a fixed temporary filename, never use archive paths as destinations.
    Path(sys.argv[2], 'wrapper.so').write_bytes(archive.read(matches[0]))
PY
    SO="$TEMP_DIR/wrapper.so"
fi
FILE_RESULT=$(file -- "$SO")
printf '%s\n' "$FILE_RESULT"
ATTRIBUTES=$(readelf -A -- "$SO")
printf '%s\n' "$ATTRIBUTES"
echo 'Architecture validation'
RESULT=0
if grep -Eq 'ELF 32-bit.*ARM([,[:space:]]|$)' <<< "$FILE_RESULT"; then
    echo 'ELF 32-bit ARM: PASS'
else
    echo 'ELF 32-bit ARM: FAIL'; RESULT=1
fi
if grep -Eq 'Tag_CPU_arch: v7[[:space:]]*$' <<< "$ATTRIBUTES"; then
    echo 'ARMv7: PASS'
else
    echo 'ARMv7: FAIL'; RESULT=1
fi
if grep -Eq 'Tag_FP_arch: VFPv3[[:space:]]*$' <<< "$ATTRIBUTES"; then
    echo 'VFPv3: PASS'
else
    echo 'VFPv3: FAIL'; RESULT=1
fi
if grep -Eq 'VFPv4' <<< "$ATTRIBUTES"; then
    echo 'VFPv4 absent: FAIL'; RESULT=1
else
    echo 'VFPv4 absent: PASS'
fi
if grep -Eq 'Tag_Advanced_SIMD_arch: NEON(v1)?[[:space:]]*$' <<< "$ATTRIBUTES"; then
    echo 'NEON: PASS'
else
    echo 'NEON: FAIL'; RESULT=1
fi
if grep -Eq 'Tag_ABI_VFP_args: VFP registers[[:space:]]*$' <<< "$ATTRIBUTES"; then
    echo 'Hard-float ABI: PASS'
else
    echo 'Hard-float ABI: FAIL'; RESULT=1
fi
exit "$RESULT"
