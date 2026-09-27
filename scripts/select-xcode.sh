#!/usr/bin/env bash
# Выбирает самый новый установленный Xcode нужной мажорной версии (на раннерах GitHub их несколько).
#
#   scripts/select-xcode.sh [мажорная версия, по умолчанию 26]
#
# Без этого берётся Xcode по умолчанию из образа, и при обновлении образа он молча меняется.
# Версия пишется в лог и в сводку запуска.
set -euo pipefail

MAJOR=${1:-26}

XCODE=$(python3 - "$MAJOR" <<'PY'
import glob, os, re, sys
major = sys.argv[1]
best = None
for path in glob.glob("/Applications/Xcode_%s*.app" % major):
    name = os.path.basename(path)
    m = re.match(r"Xcode_(\d+(?:\.\d+)*)", name)
    if not m:
        continue
    nums = tuple(int(x) for x in m.group(1).split("."))
    nums = nums + (0,) * (3 - len(nums))
    # Бета или RC выбирается, только если релиза той же версии нет.
    stable = 0 if re.search(r"beta|rc|release_candidate", name, re.I) else 1
    key = (nums, stable)
    if best is None or key > best[0]:
        best = (key, os.path.realpath(path))
print(best[1] if best else "")
PY
)

if [ -z "$XCODE" ]; then
  echo "::error::На раннере нет Xcode $MAJOR (есть: $(cd /Applications && echo Xcode*.app))" >&2
  exit 1
fi

sudo xcode-select -s "$XCODE/Contents/Developer"
VERSION=$(xcodebuild -version | tr '\n' ' ')
echo "Xcode: $XCODE — $VERSION"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "Xcode: \`$VERSION\`" >>"$GITHUB_STEP_SUMMARY"
fi
