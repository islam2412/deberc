#!/usr/bin/env bash
# Сырые кадры для скриншотов App Store: полный размер, русский интерфейс, строка состояния 9:41.
#
#   scripts/appstore-shots.sh <имя> <udid симулятора> [доп. аргументы приложения…]
#
# Симулятор должен быть загружен, приложение (сборка Release) — установлено:
#   xcrun simctl install <udid> build/…/Release-iphonesimulator/Deberc.app
# Или задайте APP=<путь к Deberc.app> — скрипт поставит его сам.
#
# Кадры стола — автоигра вдвоём и втроём (торговля, розыгрыш), и вдвоём в крупном режиме;
# экраны — итоги сдачи, запись партии, конец партии, соперники, меню.
# Результат: build/appstore/raw/<имя>/*.png. Лучшие шесть кадров потом отбираются руками
# и оформляются подписями: scripts/frame-shots.py (см. docs/APP_STORE_CONNECT.md).
#
# Размеры для App Store: iPhone 6,9″ (1320×2868) — симулятор iPhone 17 Pro Max,
# iPad 13″ (2064×2752) — симулятор iPad Pro 13″.
#
# Совместимо с bash 3.2 (стоит в macOS по умолчанию).
set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUNDLE_ID=${BUNDLE_ID:-com.islam2412.deberc}
name=$1; U=$2; shift 2
out="$ROOT/build/appstore/raw/$name"
rm -rf "$out"; mkdir -p "$out"

if [ -n "${APP:-}" ]; then
  xcrun simctl install "$U" "$APP"
fi

xcrun simctl status_bar "$U" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
trap 'xcrun simctl status_bar "$U" clear >/dev/null 2>&1 || true' EXIT

L() { xcrun simctl launch --terminate-running-process "$U" "$BUNDLE_ID" -AppleLanguages "(ru)" -AppleLocale ru_RU "$@" >/dev/null; }
C=$(xcrun simctl get_app_container "$U" "$BUNDLE_ID" data) || {
  echo "Приложение $BUNDLE_ID не установлено на симуляторе $U (задайте APP=…/Deberc.app)" >&2
  exit 1
}
P="$C/Library/Caches/autoplay-progress.json"

# autoplay <метка> [аргументы…] — 40 с автоигры, снимок каждые 1,2 с; фаза сдачи — в имени файла.
autoplay() {
  local tag=$1 end n phase
  shift
  L -DebercAutoplay YES -DebercHumanDelay 3500 -DebercSpeed normal "$@"
  end=$((SECONDS + 40)); n=0
  while [ "$SECONDS" -lt "$end" ]; do
    phase=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('phase','x'))" "$P" 2>/dev/null || echo x)
    n=$((n + 1))
    xcrun simctl io "$U" screenshot "$out/table-$tag-$(printf %02d "$n")-$phase.png" >/dev/null 2>&1 || true
    sleep 1.2
  done
}

for players in 2 3; do
  for seed in 3 7; do
    autoplay "p$players-s$seed" -DebercPlayers "$players" -DebercLarge NO -DebercSeed "$seed" "$@"
  done
done
autoplay "p2-large-s3" -DebercPlayers 2 -DebercLarge YES -DebercSeed 3 "$@"

for screen in summary scoresheet gameover opponents menu persona; do
  L -DebercScreen "$screen" -DebercPlayers 3 "$@"
  sleep 4
  xcrun simctl io "$U" screenshot "$out/screen-$screen.png" >/dev/null 2>&1 || true
done

echo "$name: $(find "$out" -name '*.png' | wc -l | tr -d ' ') кадров в $out"
