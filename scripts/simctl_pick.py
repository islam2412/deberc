#!/usr/bin/env python3
"""Выбор симулятора iOS для проверки «Деберца».

    python3 scripts/simctl_pick.py <вид> [ios]

Печатает одну строку «UDID<TAB>устройство<TAB>версия iOS». Если подходящего
симулятора нет, создаёт его (`xcrun simctl create`) — модель берётся из
списка, который поддерживает выбранная iOS.

Вид устройства:
  iphone-small  iPhone SE (3-го поколения): экран 4,7″, 375×667 pt — теснее всего
  iphone-big    самый большой iPhone (6,9″, Pro Max) — размер для App Store
  iphone        обычный iPhone (6,1″/6,3″)
  ipad          обычный iPad (A16, 11″)
  ipad-mini     iPad mini
  ipad-13       iPad Pro 13″ — размер для App Store
Точное имя модели можно задать переменной SIM_DEVICE.

iOS: latest (по умолчанию) — самая новая из установленных; oldest — самая старая,
но не ниже минимальной версии приложения (16.4); или номер версии (17.5, 26.4…).
С DOWNLOAD_RUNTIME=1 недостающая версия скачивается через
`xcodebuild -downloadPlatform iOS -buildVersion <версия>`.
"""

import json
import os
import re
import subprocess
import sys

MIN_IOS = (16, 4)

PREFERRED = {
    "iphone-small": [
        "iPhone SE (3rd generation)",
        "iPhone SE (2nd generation)",
        "iPhone 13 mini",
        "iPhone 12 mini",
    ],
    "iphone-big": [
        "iPhone 17 Pro Max",
        "iPhone 16 Pro Max",
        "iPhone 16 Plus",
        "iPhone 15 Pro Max",
        "iPhone 15 Plus",
        "iPhone 14 Pro Max",
        "iPhone 14 Plus",
    ],
    "iphone": [
        "iPhone 17 Pro",
        "iPhone 17",
        "iPhone 16 Pro",
        "iPhone 16",
        "iPhone 15 Pro",
        "iPhone 15",
        "iPhone 14",
    ],
    "ipad": [
        "iPad (A16)",
        "iPad Air 11-inch (M4)",
        "iPad Air 11-inch (M3)",
        "iPad Air 11-inch (M2)",
        "iPad (10th generation)",
        "iPad (9th generation)",
    ],
    "ipad-mini": [
        "iPad mini (A17 Pro)",
        "iPad mini (6th generation)",
    ],
    "ipad-13": [
        "iPad Pro 13-inch (M5)",
        "iPad Pro 13-inch (M4)",
        "iPad Pro (12.9-inch) (6th generation)",
        "iPad Pro (12.9-inch) (5th generation)",
    ],
}

# Запасной вариант, если ни одной модели из списка нет: образец в имени.
FALLBACK_PATTERN = {
    "iphone-small": r"^iPhone (SE|\d+ mini)",
    "iphone-big": r"^iPhone .*(Pro Max|Plus)$",
    "iphone": r"^iPhone",
    "ipad": r"^iPad",
    "ipad-mini": r"^iPad mini",
    "ipad-13": r"^iPad .*(13-inch|12\.9-inch)",
}


class PickError(Exception):
    pass


def version_tuple(text):
    return tuple(int(x) for x in re.findall(r"\d+", text or ""))


def ios_runtimes(data):
    """Доступные рантаймы iOS, от старых к новым."""
    result = []
    for rt in data.get("runtimes", []):
        platform = rt.get("platform") or rt.get("name", "").split(" ")[0]
        if platform != "iOS" or not rt.get("isAvailable", False):
            continue
        result.append(rt)
    result.sort(key=lambda rt: version_tuple(rt.get("version")))
    return result


def pick_runtime(data, want):
    runtimes = ios_runtimes(data)
    if not runtimes:
        raise PickError("Не установлено ни одного рантайма iOS для симулятора")
    if want in ("", "latest"):
        return runtimes[-1]
    if want == "oldest":
        suitable = [rt for rt in runtimes if version_tuple(rt.get("version")) >= MIN_IOS]
        if not suitable:
            raise PickError("Нет рантайма iOS не ниже %d.%d" % MIN_IOS)
        return suitable[0]
    wanted = version_tuple(want)
    matching = [rt for rt in runtimes
                if version_tuple(rt.get("version"))[:len(wanted)] == wanted]
    if not matching:
        return None
    return matching[-1]


def supported_types(data, runtime):
    """Модели, которые поддерживает рантайм: [(имя, идентификатор)]."""
    types = runtime.get("supportedDeviceTypes")
    if types is None:
        # Старые Xcode не пишут supportedDeviceTypes — берём все модели.
        types = data.get("devicetypes", [])
    return [(t["name"], t["identifier"]) for t in types if "name" in t and "identifier" in t]


def pick_device_type(data, runtime, kind, exact=None):
    types = supported_types(data, runtime)
    by_name = {name: ident for name, ident in types}
    if exact:
        if exact in by_name:
            return exact, by_name[exact]
        raise PickError("iOS %s не поддерживает модель «%s»" % (runtime.get("version"), exact))
    if kind not in PREFERRED:
        raise PickError("Неизвестный вид устройства: %s (есть: %s)" % (kind, ", ".join(sorted(PREFERRED))))
    for name in PREFERRED[kind]:
        if name in by_name:
            return name, by_name[name]
    pattern = re.compile(FALLBACK_PATTERN[kind])
    candidates = [(name, ident) for name, ident in types if pattern.search(name)]
    if not candidates:
        family = "iPad" if kind.startswith("ipad") else "iPhone"
        candidates = [(name, ident) for name, ident in types if name.startswith(family)]
    if not candidates:
        raise PickError("Для iOS %s нет ни одной модели вида %s" % (runtime.get("version"), kind))
    return candidates[-1]


def find_device(data, runtime, type_id, preferred_name):
    devices = data.get("devices", {}).get(runtime["identifier"], [])
    matching = [d for d in devices
                if d.get("deviceTypeIdentifier") == type_id and d.get("isAvailable", True)]
    for d in matching:
        if d.get("name") == preferred_name:
            return d
    return matching[0] if matching else None


def simctl_json():
    fake = os.environ.get("SIMCTL_JSON")
    if fake:
        with open(fake, encoding="utf-8") as f:
            return json.load(f)
    out = subprocess.run(["xcrun", "simctl", "list", "-j"], check=True,
                         capture_output=True, text=True).stdout
    return json.loads(out)


def download_runtime(version):
    print("Скачиваю рантайм iOS %s (xcodebuild -downloadPlatform)…" % version, file=sys.stderr)
    # Вывод xcodebuild — в stderr: stdout этого скрипта читает simulator-smoke-test.sh.
    subprocess.run(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", version],
                   check=True, stdout=sys.stderr)


def create_device(name, type_id, runtime_id):
    out = subprocess.run(["xcrun", "simctl", "create", name, type_id, runtime_id],
                         check=True, capture_output=True, text=True).stdout
    return out.strip().splitlines()[-1].strip()


def pick(kind, want="latest", exact=None, data=None, allow_download=False,
         load=simctl_json, create=create_device, download=download_runtime):
    data = data if data is not None else load()
    runtime = pick_runtime(data, want)
    if runtime is None and allow_download:
        download(want)
        data = load()
        runtime = pick_runtime(data, want)
    if runtime is None:
        installed = ", ".join(rt.get("version", "?") for rt in ios_runtimes(data))
        raise PickError("Нет рантайма iOS %s (установлены: %s). DOWNLOAD_RUNTIME=1 — скачать"
                        % (want, installed or "ни одного"))
    type_name, type_id = pick_device_type(data, runtime, kind, exact)
    own_name = "Deberc %s (iOS %s)" % (kind, runtime.get("version"))
    device = find_device(data, runtime, type_id, own_name)
    if device is not None:
        udid = device["udid"]
    else:
        udid = create(own_name, type_id, runtime["identifier"])
    return udid, type_name, runtime.get("version", "?")


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) >= 2 else 2
    kind = argv[1]
    want = argv[2] if len(argv) > 2 else "latest"
    try:
        udid, name, version = pick(kind, want,
                                   exact=os.environ.get("SIM_DEVICE") or None,
                                   allow_download=os.environ.get("DOWNLOAD_RUNTIME") == "1")
    except PickError as e:
        print("::error::%s" % e, file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print("::error::Команда не выполнилась: %s" % " ".join(e.cmd), file=sys.stderr)
        return 1
    print("%s\t%s\t%s" % (udid, name, version))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
