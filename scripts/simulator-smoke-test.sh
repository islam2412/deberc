#!/usr/bin/env bash
# Проверка «Деберца» на симуляторе iOS: экраны, автоигра (за всех играют боты),
# итог сдачи, конец партии, повторный запуск. Скриншоты — в папку результатов.
#
#   scripts/simulator-smoke-test.sh select <вид> [ios]
#       Выбирает (или создаёт) симулятор и начинает загружать его в фоне.
#       Печатает UDID. В GitHub Actions пишет SIM_UDID, SIM_NAME и SIM_OS в $GITHUB_ENV:
#       приложение собирается, пока симулятор грузится.
#   scripts/simulator-smoke-test.sh run <Deberc.app> <вид> <папка результатов>
#       Ставит приложение и проходит сценарии. Падает, если приложение закрылось,
#       автоигра стоит на месте или появился отчёт о сбое (.ips).
#
# Вид устройства и версия iOS — см. scripts/simctl_pick.py
# (iphone-small, iphone-big, iphone, ipad, ipad-mini, ipad-13; latest, oldest, 17.5…).
#
# Переменные окружения (все необязательные):
#   SIM_UDID           готовый симулятор (из шага select); иначе выбирается заново
#   SIM_IOS            версия iOS для выбора, если SIM_UDID не задан (latest)
#   SCENARIOS          сценарии по порядку (по умолчанию: screens autoplay2 autoplay3 summary relaunch);
#                      есть ещё gameover — партия до конца, несколько минут
#   SCREENS            экраны для сценария screens
#                      (menu table settings rules scoresheet stats onboarding)
#   TEXT_SIZE          размер текста на всё время (simctl ui content_size), например extra-extra-extra-large
#   EXTRA_TEXT_SIZE    после screens переснять EXTRA_SCREENS с этим размером (например accessibility-large)
#   EXTRA_SCREENS      экраны для EXTRA_TEXT_SIZE (menu table settings rules)
#   LEVEL_2P, LEVEL_3P уровни ботов в автоигре вдвоём и втроём (master и novice)
#   MIN_DEALS          сколько сдач должна сыграть автоигра (2)
#   AUTOPLAY_TIMEOUT   предел на одну автоигру, с (300)
#   STALL_SECONDS      прогресс не менялся столько секунд — автоигра зависла (150)
#   GAMEOVER_TIMEOUT   предел ожидания конца партии, с (600)
#   KEEP_PNG=1         оставить полноразмерные PNG (для App Store); иначе JPEG до 1400 px
#   STRICT_SCREENS=1   не дождались итога/конца партии — ошибка, а не предупреждение
#
# Совместимо с bash 3.2 (стоит в macOS по умолчанию).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Сообщения — в stderr: GitHub Actions понимает ::error:: и там, а stdout шага select занят UDID.
LAST_ERROR=""
die() {
  LAST_ERROR=$*
  echo "::error::$*" >&2
  exit 1
}

log() { echo "$*" >&2; }

group() { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }

# ---------------------------------------------------------------- select

pick_sim() { # pick_sim <вид> <ios> — задаёт UDID, SIM_NAME, SIM_OS и начинает загрузку
  local kind=$1 ios=$2 line
  line=$(python3 "$SCRIPT_DIR/simctl_pick.py" "$kind" "$ios") || die "Не удалось выбрать симулятор ($kind, iOS $ios)"
  IFS=$'\t' read -r UDID SIM_NAME SIM_OS <<<"$line"
  [ -n "$UDID" ] || die "Пустой UDID симулятора ($kind)"
  log "Симулятор: $SIM_NAME, iOS $SIM_OS ($UDID)"
  # Загрузка идёт в фоне: `bootstatus` в шаге run дождётся её конца.
  nohup xcrun simctl boot "$UDID" >/dev/null 2>&1 &
}

cmd_select() {
  pick_sim "$1" "${2:-latest}"
  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      echo "SIM_UDID=$UDID"
      echo "SIM_NAME=$SIM_NAME"
      echo "SIM_OS=$SIM_OS"
    } >>"$GITHUB_ENV"
  fi
  echo "$UDID"
}

# ---------------------------------------------------------------- run

SIM_NAME=${SIM_NAME:-}
SIM_OS=${SIM_OS:-}
APP=""
KIND=""
OUT=""
UDID=""
BUNDLE_ID=""
PID=""
PROGRESS=""
MARKER=""
RESULTS_FILE=""
CURRENT=""
# 1 — все сценарии пройдены. bash 3.2 при ошибке раскрытия (set -u) выходит из скрипта
# с кодом 0 — без этого флага оборванная проверка выглядела бы успешной.
FINISHED=0

record() { # record <сценарий> <итог> <подробности>
  printf '| %s | %s | %s |\n' "$1" "$2" "$3" >>"$RESULTS_FILE"
}

launch() { # launch <метка> [аргументы…]
  local tag=$1 out
  shift
  CURRENT=$tag
  out=$(xcrun simctl launch --terminate-running-process \
    --stdout="$OUT/$KIND-$tag.out.log" --stderr="$OUT/$KIND-$tag.err.log" \
    "$UDID" "$BUNDLE_ID" -AppleLanguages "(ru)" -AppleLocale ru_RU "$@") ||
    die "Не удалось запустить приложение ($KIND, $tag)"
  PID=${out##*: }
  case "$PID" in
    '' | *[!0-9]*) die "Не понял PID из «${out}» ($KIND, $tag)" ;;
  esac
  log "Запущено ($tag): PID $PID"
}

is_running() {
  # Приложения симулятора — обычные процессы Mac того же пользователя.
  [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null
}

alive_or_die() { # alive_or_die <что делали>
  is_running || die "Приложение закрылось: $1 ($KIND). Логи и отчёт о сбое — в артефакте"
}

stop_app() {
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  local i=0
  while is_running && [ $i -lt 10 ]; do
    sleep 0.5
    i=$((i + 1))
  done
  PID=""
  CURRENT=""
}

shot() { # shot <имя>
  local png="$OUT/$KIND-$1.png"
  if ! xcrun simctl io "$UDID" screenshot --type=png "$png" >/dev/null 2>&1; then
    echo "::warning::Не получился скриншот $KIND-$1"
    return 0
  fi
  if [ "${KEEP_PNG:-0}" != 1 ]; then
    # Полный PNG iPad весит до 6 МБ; JPEG до 1400 px — около 150 КБ, для проверки глазами хватает.
    if sips -Z 1400 -s format jpeg -s formatOptions 80 "$png" --out "${png%.png}.jpg" >/dev/null 2>&1; then
      rm -f "$png"
    fi
  fi
}

progress() {
  # «сдачи<TAB>партии<TAB>фаза<TAB>время» из Library/Caches/autoplay-progress.json; пусто, если файла нет.
  python3 - "$PROGRESS" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
except Exception:
    sys.exit(0)
print("%s\t%s\t%s\t%s" % (int(d.get("deals", 0)), int(d.get("matches", 0)),
                          str(d.get("phase", "")).replace("\t", " "), d.get("updated", "")))
PY
}

field() { # field <номер 1..4> <строка progress>
  local value
  value=$(printf '%s\n' "$2" | cut -f "$1")
  printf '%s' "$value"
}

set_text_size() {
  xcrun simctl ui "$UDID" content_size "$1" >/dev/null 2>&1 ||
    echo "::warning::Не удалось поставить размер текста $1"
}

scenario_screens() { # scenario_screens <суффикс> <экраны…>
  local suffix=$1 s shown=""
  shift
  for s in "$@"; do
    launch "screen-$s$suffix" -DebercScreen "$s"
    sleep "${SCREEN_WAIT:-6}"
    alive_or_die "экран $s$suffix"
    shot "screen-$s$suffix"
    stop_app
    shown="$shown $s"
  done
  record "экраны$suffix" "OK" "${shown# }"
}

scenario_autoplay() { # scenario_autoplay <игроков> <уровень>
  local players=$1 level=$2
  local tag="auto${players}p"
  local start last_change last="" cur deals=0 matches=0 shots=0 next_shot
  local min_deals=${MIN_DEALS:-2} timeout=${AUTOPLAY_TIMEOUT:-300} stall=${STALL_SECONDS:-150}
  rm -f "$PROGRESS"
  launch "$tag" -DebercAutoplay YES -DebercPlayers "$players" -DebercLevel "$level"
  start=$SECONDS
  last_change=$SECONDS
  next_shot=$((SECONDS + 6))
  while :; do
    sleep 3
    alive_or_die "автоигра, игроков: $players, уровень: $level"
    cur=$(progress)
    if [ "$cur" != "$last" ]; then
      last=$cur
      last_change=$SECONDS
    fi
    if [ -n "$cur" ]; then
      deals=$(field 1 "$cur")
      matches=$(field 2 "$cur")
    fi
    if [ $shots -lt 6 ] && [ $SECONDS -ge $next_shot ]; then
      shots=$((shots + 1))
      shot "$tag-$(printf %02d $shots)"
      next_shot=$((SECONDS + 8))
    fi
    if [ "${deals:-0}" -ge "$min_deals" ] && [ $shots -ge 3 ]; then
      break
    fi
    if [ -z "$cur" ]; then
      if [ $((SECONDS - start)) -gt 60 ]; then
        die "Автоигра за 60 с не создала Library/Caches/autoplay-progress.json ($KIND, игроков: $players)"
      fi
    elif [ $((SECONDS - last_change)) -gt "$stall" ]; then
      die "Автоигра зависла: прогресс не менялся $stall с ($KIND, игроков: $players; сдач: $deals, партий: $matches, фаза: $(field 3 "$last"))"
    fi
    if [ $((SECONDS - start)) -gt "$timeout" ]; then
      die "Автоигра сыграла ${deals:-0} сдач за $timeout с, нужно $min_deals ($KIND, игроков: $players)"
    fi
  done
  record "автоигра, $players игрока, $level" "OK" "сдач: $deals, партий: $matches, $((SECONDS - start)) с"
  stop_app
}

scenario_until() { # scenario_until <экран> <образец фазы> <предел, с>
  local screen=$1 pattern=$2 timeout=$3 start phase="" reached=0
  rm -f "$PROGRESS"
  launch "screen-$screen" -DebercScreen "$screen" -DebercAutoplay YES -DebercPlayers 2 -DebercLevel novice
  start=$SECONDS
  while [ $((SECONDS - start)) -lt "$timeout" ]; do
    sleep 3
    alive_or_die "экран $screen"
    phase=$(field 3 "$(progress)" | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$phase" | grep -Eq "$pattern"; then
      reached=1
      break
    fi
  done
  sleep 3 # лист успевает выехать
  alive_or_die "экран $screen"
  shot "screen-$screen"
  if [ $reached = 1 ]; then
    record "экран $screen" "OK" "фаза «${phase}», $((SECONDS - start)) с"
  elif [ "${STRICT_SCREENS:-0}" = 1 ]; then
    die "Не дождался экрана $screen за $timeout с (фаза: «${phase}»)"
  else
    echo "::warning::Не дождался экрана $screen за $timeout с (фаза: «${phase}»), снят тот кадр, что есть"
    record "экран $screen" "не дождался" "фаза «${phase}» через $timeout с"
  fi
  stop_app
}

scenario_relaunch() {
  launch "relaunch"
  sleep 6
  alive_or_die "повторный запуск"
  shot "relaunch"
  record "повторный запуск" "OK" "без аргументов"
  stop_app

  # Восстановление партии: демо-запуск сохраняет идущую партию (за столом), следующий запуск
  # с -DebercResume открывает её как обычный перезапуск — должен вернуться стол, а не меню.
  launch "resume-prep" -DebercScreen table -DebercPlayers 2
  sleep 6
  alive_or_die "партия для восстановления"
  stop_app
  rm -f "$PROGRESS"
  launch "resume" -DebercResume YES
  sleep 6
  alive_or_die "восстановление партии"
  shot "resume"
  local line phase
  line=$(progress)
  phase=$(printf '%s' "$line" | cut -f3)
  case "$phase" in
    bidding-* | exchange | playing) record "восстановление партии" "OK" "фаза: $phase" ;;
    *) die "После перезапуска не вернулся стол (фаза: ${phase:-нет данных})" ;;
  esac
  if ls "$(dirname "$(dirname "$PROGRESS")")/Application Support/Demo"/*.unreadable-*.json >/dev/null 2>&1; then
    die "Сохранённую партию не удалось прочитать (появился *.unreadable-*.json)"
  fi
  stop_app
}

new_crash_reports() {
  find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 2 -type f \
    \( -name 'Deberc*.ips' -o -name 'Deberc*.crash' \) -newer "$MARKER" 2>/dev/null || true
}

collect_diagnostics() {
  local f
  for f in $(new_crash_reports); do
    cp "$f" "$OUT/" 2>/dev/null || true
  done
  xcrun simctl spawn "$UDID" log show --last 15m --style compact \
    --predicate 'process == "Deberc"' >"$OUT/$KIND-oslog.txt" 2>&1 || true
  group "Вывод приложения ($KIND${CURRENT:+, $CURRENT})"
  for f in "$OUT/$KIND-"*.err.log "$OUT/$KIND-"*.out.log; do
    [ -s "$f" ] || continue
    echo "--- $(basename "$f")"
    tail -n 40 "$f"
  done
  endgroup
}

write_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  {
    echo "### ${SIM_NAME:-$KIND}, iOS ${SIM_OS:-?}${TEXT_SIZE:+, текст: $TEXT_SIZE}"
    echo
    echo "| Сценарий | Итог | Подробности |"
    echo "|---|---|---|"
    cat "$RESULTS_FILE"
    echo
  } >>"$GITHUB_STEP_SUMMARY"
}

on_exit() {
  local rc=$?
  set +e
  if [ $rc -eq 0 ] && [ "$FINISHED" != 1 ]; then
    rc=1
    LAST_ERROR="Скрипт оборвался до конца сценариев${CURRENT:+ (на «${CURRENT}»)}, см. лог шага"
    echo "::error::$LAST_ERROR" >&2
  fi
  if [ $rc -ne 0 ]; then
    record "${CURRENT:-подготовка}" "ОШИБКА" "${LAST_ERROR:-см. лог шага}"
    [ -n "$PID" ] && is_running && shot "failure"
    collect_diagnostics
  fi
  stop_app
  find "$OUT" -maxdepth 1 -name '*.log' -size 0 -delete 2>/dev/null
  [ -n "$RESULTS_FILE" ] && [ -f "$RESULTS_FILE" ] && write_summary
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1
  exit $rc
}

cmd_run() {
  [ $# -eq 3 ] || die "Использование: $0 run <Deberc.app> <вид> <папка>"
  APP=$1
  KIND=$2
  mkdir -p "$3"
  OUT=$(cd "$3" && pwd) # абсолютный путь: --stdout/--stderr открывает симулятор, а не этот скрипт
  [ -f "$APP/Info.plist" ] || die "Нет собранного приложения: $APP"
  BUNDLE_ID=$(python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleIdentifier"])' "$APP/Info.plist")
  log "Bundle ID: $BUNDLE_ID"

  UDID=${SIM_UDID:-}
  if [ -z "$UDID" ]; then
    pick_sim "$KIND" "${SIM_IOS:-latest}"
  fi

  MARKER="$OUT/.$KIND-start"
  touch "$MARKER"
  RESULTS_FILE="$OUT/.$KIND-results.md"
  : >"$RESULTS_FILE"
  trap on_exit EXIT

  group "Загрузка симулятора $UDID"
  if ! xcrun simctl bootstatus "$UDID" -b >"$OUT/$KIND-bootstatus.txt" 2>&1; then
    tail -n 20 "$OUT/$KIND-bootstatus.txt"
    endgroup
    die "Симулятор не загрузился ($KIND)"
  fi
  tail -n 3 "$OUT/$KIND-bootstatus.txt"
  endgroup

  # Одинаковая строка состояния на всех кадрах.
  xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null 2>&1 ||
    echo "::warning::Не удалось подменить строку состояния"
  set_text_size "${TEXT_SIZE:-large}"

  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP" || die "Не удалось установить приложение ($KIND)"
  local data
  data=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data) || die "Нет контейнера данных приложения"
  PROGRESS="$data/Library/Caches/autoplay-progress.json"

  local scenario
  # shellcheck disable=SC2086 # списки через пробел — намеренно
  for scenario in ${SCENARIOS:-screens autoplay2 autoplay3 summary relaunch}; do
    echo "== $KIND: $scenario"
    case "$scenario" in
      screens)
        scenario_screens "" ${SCREENS:-menu table settings rules scoresheet stats onboarding}
        if [ -n "${EXTRA_TEXT_SIZE:-}" ]; then
          set_text_size "$EXTRA_TEXT_SIZE"
          scenario_screens "-$EXTRA_TEXT_SIZE" ${EXTRA_SCREENS:-menu table settings rules}
          set_text_size "${TEXT_SIZE:-large}"
        fi
        ;;
      autoplay2) scenario_autoplay 2 "${LEVEL_2P:-master}" ;;
      autoplay3) scenario_autoplay 3 "${LEVEL_3P:-novice}" ;;
      summary) scenario_until summary 'summary|итог' "${SUMMARY_TIMEOUT:-150}" ;;
      gameover) scenario_until gameover 'gameover|over|конец' "${GAMEOVER_TIMEOUT:-600}" ;;
      relaunch) scenario_relaunch ;;
      *) die "Неизвестный сценарий: $scenario" ;;
    esac
  done

  sleep 2 # отчёт о сбое пишется не мгновенно
  local crashes
  crashes=$(new_crash_reports)
  if [ -n "$crashes" ]; then
    die "Найдены отчёты о сбоях: $(echo "$crashes" | xargs -n1 basename | tr '\n' ' ')"
  fi
  FINISHED=1
  log "Готово: результаты в $OUT"
}

case "${1:-}" in
  select)
    shift
    [ $# -ge 1 ] || die "Использование: $0 select <вид> [ios]"
    cmd_select "$@"
    ;;
  run)
    shift
    cmd_run "$@"
    ;;
  *)
    sed -n '2,34p' "$0"
    exit 2
    ;;
esac
