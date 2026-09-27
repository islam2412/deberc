#!/usr/bin/env bash
# Проверка на симуляторе: ставит приложение, запускает автоигру (за всех играют боты)
# и делает скриншоты. Падает, если приложение закрылось.
#
# Использование: scripts/simulator-smoke-test.sh <путь к Deberc.app> <тип устройства: iphone|ipad> <папка для скриншотов>
set -euo pipefail

APP="$1"
KIND="$2"
OUT="$3"
mkdir -p "$OUT"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
echo "Bundle ID: $BUNDLE_ID"

# Выбираем доступное устройство нужного типа с самой новой iOS.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
kind = sys.argv[1]
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in runtime.split("iOS-")[-1].split("-") if x.isdigit())
    for d in devices:
        name = d["name"]
        ok = name.startswith("iPhone") if kind == "iphone" else name.startswith("iPad")
        if ok and (best is None or version > best[0]):
            best = (version, d["udid"], name)
if best is None:
    sys.exit("Нет подходящего симулятора")
print(best[1])
print(best[2], "iOS", ".".join(map(str, best[0])), file=sys.stderr)
' "$KIND")

echo "Симулятор: $UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

is_running() {
  xcrun simctl spawn "$UDID" launchctl list | grep -q "UIKitApplication:$BUNDLE_ID"
}

# 1. Главное меню.
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 6
xcrun simctl io "$UDID" screenshot "$OUT/$KIND-01-menu.png"
is_running || { echo "::error::Приложение закрылось на главном меню ($KIND)"; exit 1; }
xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true

# 2. Автоигра вдвоём и втроём.
for PLAYERS in 2 3; do
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -DebercAutoplay YES -DebercPlayers "$PLAYERS"
  for i in 1 2 3 4 5 6 7 8; do
    sleep 7
    xcrun simctl io "$UDID" screenshot "$OUT/$KIND-${PLAYERS}p-$(printf %02d "$i").png"
    if ! is_running; then
      echo "::error::Приложение закрылось во время автоигры ($KIND, игроков: $PLAYERS)"
      exit 1
    fi
  done
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
done

# 3. Повторный запуск после автоигры — проверяем, что сохранённая партия читается.
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 5
xcrun simctl io "$UDID" screenshot "$OUT/$KIND-99-relaunch.png"
is_running || { echo "::error::Приложение закрылось при повторном запуске ($KIND)"; exit 1; }

xcrun simctl shutdown "$UDID" || true
echo "Готово: скриншоты в $OUT"
