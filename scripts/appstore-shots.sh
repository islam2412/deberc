#!/usr/bin/env bash
# Сырые кадры для скриншотов App Store: полный размер, русский интерфейс, строка состояния 9:41.
#
#   scripts/appstore-shots.sh <имя> <udid симулятора> [доп. аргументы приложения…]
#
# Симулятор должен быть загружен, приложение (сборка Release) — установлено:
#   xcrun simctl install <udid> build/…/Release-iphonesimulator/Deberc.app
# Или задайте APP=<путь к Deberc.app> — скрипт поставит его сам.
# Строку состояния рисует система на языке симулятора (на iPad в ней день и месяц): если он
# не русский, SIM_RU=1 переключит симулятор на русский и перезагрузит его.
#
# Кадры стола — автоигра вдвоём и втроём (торговля, розыгрыш), вдвоём в крупном режиме и вдвоём
# с отменой хода (table-undo-…); экраны — итоги сдачи, запись партии, конец партии, соперники, меню.
# Результат: build/appstore/raw/<имя>/*.png. Лучшие шесть кадров потом отбираются руками
# и оформляются подписями: scripts/frame-shots.py (см. docs/APP_STORE_CONNECT.md).
#
# Размеры для App Store: iPhone 6,9″ (1320×2868) — симулятор iPhone 17 Pro Max,
# iPad 13″ (2064×2752) — симулятор iPad Pro 13″.
#
# Совместимо с bash 3.2 (стоит в macOS по умолчанию).
set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUNDLE_ID=${BUNDLE_ID:-com.islam2412.deberc}
name=$1; U=$2; shift 2
out="$ROOT/build/appstore/raw/$name"
rm -rf "$out"; mkdir -p "$out"

# Язык и регион всего симулятора, а не только приложения: иначе на iPad в строке состояния
# «Tue Sep 29». Дату в --time не передаём: такую simctl рисует по-английски и с чужим днём недели.
lang=$(xcrun simctl spawn "$U" defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",' || true)
case "$lang" in
  ru*) ;;
  *)
    if [ "${SIM_RU:-}" = 1 ]; then
      echo "Симулятор $U: язык ${lang:-?} → русский, перезагрузка…"
      xcrun simctl spawn "$U" defaults write -g AppleLanguages -array ru-RU
      xcrun simctl spawn "$U" defaults write -g AppleLocale ru_RU
      xcrun simctl shutdown "$U"
      xcrun simctl boot "$U"
      xcrun simctl bootstatus "$U" -b >/dev/null
    else
      echo "внимание: язык симулятора — ${lang:-?}, строка состояния будет не по-русски" \
        "(SIM_RU=1 переключит его на русский)" >&2
    fi
    ;;
esac

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

# series <префикс> <пауза, с> — 40 с снимков стола; фаза сдачи — в имени файла.
series() {
  local prefix=$1 pause=$2 end n phase
  end=$((SECONDS + 40)); n=0
  while [ "$SECONDS" -lt "$end" ]; do
    phase=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('phase','x'))" "$P" 2>/dev/null || echo x)
    n=$((n + 1))
    xcrun simctl io "$U" screenshot "$out/$prefix-$(printf %02d "$n")-$phase.png" >/dev/null 2>&1 || true
    sleep "$pause"
  done
}

# autoplay <метка> [аргументы…] — автоигра: за всех ходит компьютер, в ваш ход видны «Ваш ход» и «Совет».
autoplay() {
  local tag=$1
  shift
  L -DebercAutoplay YES -DebercHumanDelay 3500 -DebercSpeed normal "$@"
  series "table-$tag" 1.2
}

# undo <метка> [аргументы…] — за вас ходит компьютер теми же действиями, что и касания: после
# вашего хода, пока соперник не ответил, видна кнопка «Отменить» (в автоигре её нет). Держится она
# пару секунд, поэтому темп медленный, а снимки чаще.
undo() {
  local tag=$1
  shift
  L -DebercScreen table -DebercScriptedHuman YES -DebercHumanDelay 3000 -DebercSpeed slow "$@"
  series "table-undo-$tag" 0.5
}

for players in 2 3; do
  for seed in 3 7; do
    autoplay "p$players-s$seed" -DebercPlayers "$players" -DebercLarge NO -DebercSeed "$seed" "$@"
  done
done
autoplay "p2-large-s3" -DebercPlayers 2 -DebercLarge YES -DebercSeed 3 "$@"
undo "p2-s3" -DebercPlayers 2 -DebercLarge NO -DebercSeed 3 "$@"

for screen in summary scoresheet gameover opponents menu persona; do
  L -DebercScreen "$screen" -DebercPlayers 3 "$@"
  sleep 4
  xcrun simctl io "$U" screenshot "$out/screen-$screen.png" >/dev/null 2>&1 || true
done

echo "$name: $(find "$out" -name '*.png' | wc -l | tr -d ' ') кадров в $out"
