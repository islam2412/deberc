#!/usr/bin/env python3
"""App Store Connect API для выпуска «Деберца» в TestFlight.

Команды:
  write-key   записать ключ .p8 из переменной ASC_KEY_P8 в файл (права 600)
              и добавить ASC_KEY_PATH в $GITHUB_ENV. Не требует сети.
  check       предпроверка перед сборкой: ключ принят, приложение с таким
              Bundle ID есть, номер сборки больше уже загруженных.
  distribute  после загрузки: дождаться обработки сборки, вписать «Что тестировать»,
              добавить во внешнюю группу TestFlight и отправить на проверку
              Beta App Review. Печатает публичную ссылку группы.

Доступ (переменные окружения): ASC_KEY_ID, ASC_ISSUER_ID и ASC_KEY_PATH
(путь к .p8) или ASC_KEY_P8 (содержимое). Для check и distribute нужен
PyJWT с cryptography: pip install -r scripts/requirements.txt.

Примеры:
  python3 scripts/asc.py check --bundle-id com.islam2412.deberc --version 1.0 --build 260927.1805
  python3 scripts/asc.py distribute --bundle-id com.islam2412.deberc --version 1.0 \\
      --build 260927.1805 --whats-new-file docs/WHATS_NEW.txt --group "Семья и друзья" --submit
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
WHATS_NEW_LIMIT = 4000
RETRY_STATUSES = (429, 500, 502, 503, 504)

# Состояния сборки для внешнего тестирования (buildBetaDetails.externalBuildState).
EXTERNAL_STATE_TEXT = {
    "PROCESSING": "обрабатывается",
    "PROCESSING_EXCEPTION": "ошибка обработки",
    "MISSING_EXPORT_COMPLIANCE": "не указано экспортное соответствие",
    "READY_FOR_BETA_TESTING": "готова к тестированию",
    "IN_BETA_TESTING": "уже у тестировщиков",
    "EXPIRED": "срок сборки истёк",
    "READY_FOR_BETA_SUBMISSION": "готова к отправке на проверку",
    "IN_EXPORT_COMPLIANCE_REVIEW": "проверка экспортного соответствия",
    "WAITING_FOR_BETA_REVIEW": "ждёт проверки Beta App Review",
    "IN_BETA_REVIEW": "на проверке Beta App Review",
    "BETA_REJECTED": "отклонена Beta App Review",
    "BETA_APPROVED": "одобрена Beta App Review",
}


class AscError(Exception):
    """Понятная ошибка для человека: печатается как ::error::."""


class ApiError(AscError):
    def __init__(self, status, method, path, errors):
        self.status = status
        self.errors = errors or []
        details = "; ".join(
            " — ".join(x for x in (e.get("title"), e.get("detail")) if x) for e in self.errors
        ) or "без подробностей"
        hint = {
            401: "Ключ API не принят: проверьте секреты ASC_KEY_ID, ASC_ISSUER_ID и ASC_KEY_P8 "
                 "(ключ мог быть отозван в App Store Connect → Пользователи и доступ → Интеграции).",
            403: "Не хватает прав: у ключа API должна быть роль Admin (или App Manager).",
        }.get(status, "")
        message = "App Store Connect %s %s → %d: %s" % (method, path, status, details)
        if hint:
            message += ". " + hint
        super().__init__(message)


# ---------------------------------------------------------------- ключ и токен

def normalize_key(text):
    """Приводит содержимое .p8 к виду, который понимает cryptography."""
    key = (text or "").replace("\r", "")
    if "\n" not in key.strip() and "\\n" in key:
        key = key.replace("\\n", "\n")  # вставили одной строкой с «\n»
    key = key.strip() + "\n"
    if "-----BEGIN PRIVATE KEY-----" not in key or "-----END PRIVATE KEY-----" not in key:
        raise AscError("ASC_KEY_P8 должен содержать весь файл .p8 вместе со строками "
                       "-----BEGIN PRIVATE KEY----- и -----END PRIVATE KEY-----")
    return key


def write_key(env, directory):
    key_id = env.get("ASC_KEY_ID", "").strip()
    if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
        raise AscError("ASC_KEY_ID должен быть из 10 латинских заглавных букв и цифр (Key ID ключа)")
    key = normalize_key(env.get("ASC_KEY_P8", ""))
    os.makedirs(directory, mode=0o700, exist_ok=True)
    path = os.path.join(directory, "AuthKey_%s.p8" % key_id)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(key)
    os.chmod(path, 0o600)
    github_env = env.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a", encoding="utf-8") as f:
            f.write("ASC_KEY_PATH=%s\n" % path)
    return path


def make_token(key_id, issuer_id, private_key, now):
    import jwt  # PyJWT[crypto]

    # Apple принимает токен не дольше 20 минут; iat чуть в прошлом — на случай расхождения часов.
    payload = {
        "iss": issuer_id,
        "iat": int(now) - 30,
        "exp": int(now) + 15 * 60,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})


def credentials_from_env(env):
    key_id = env.get("ASC_KEY_ID", "").strip()
    issuer = env.get("ASC_ISSUER_ID", "").strip()
    missing = [n for n, v in (("ASC_KEY_ID", key_id), ("ASC_ISSUER_ID", issuer)) if not v]
    if env.get("ASC_KEY_PATH"):
        with open(env["ASC_KEY_PATH"], encoding="utf-8") as f:
            key = normalize_key(f.read())
    elif env.get("ASC_KEY_P8"):
        key = normalize_key(env["ASC_KEY_P8"])
    else:
        missing.append("ASC_KEY_PATH или ASC_KEY_P8")
        key = None
    if missing:
        raise AscError("Не заданы: " + ", ".join(missing))
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", issuer):
        raise AscError("ASC_ISSUER_ID похож не на Issuer ID (ожидается UUID вида 69a6de7e-…)")
    return key_id, issuer, key


# ---------------------------------------------------------------- HTTP

def urllib_transport(method, url, headers, data, timeout=60):
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


class Api:
    def __init__(self, key_id, issuer_id, private_key, transport=urllib_transport,
                 sleep=time.sleep, clock=time.time, retries=4):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = private_key
        self.transport = transport
        self.sleep = sleep
        self.clock = clock
        self.retries = retries
        self._token = None
        self._token_time = 0.0

    def token(self):
        now = self.clock()
        if self._token is None or now - self._token_time > 10 * 60:
            self._token = make_token(self.key_id, self.issuer_id, self.private_key, now)
            self._token_time = now
        return self._token

    def request(self, method, path, params=None, body=None):
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params, safe="[],")
        data = json.dumps(body).encode("utf-8") if body is not None else None
        attempt = 0
        while True:
            headers = {"Authorization": "Bearer " + self.token(), "Accept": "application/json"}
            if data is not None:
                headers["Content-Type"] = "application/json"
            try:
                status, raw = self.transport(method, url, headers, data)
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                status, raw = None, str(e).encode()
            if (status is None or status in RETRY_STATUSES) and attempt < self.retries:
                attempt += 1
                self.sleep(min(60, 5 * 2 ** (attempt - 1)))
                continue
            if status is None:
                raise AscError("Нет связи с App Store Connect: %s" % raw.decode(errors="replace"))
            payload = {}
            if raw:
                try:
                    payload = json.loads(raw.decode("utf-8"))
                except ValueError:
                    payload = {"errors": [{"detail": raw.decode("utf-8", errors="replace")[:300]}]}
            if status >= 400:
                raise ApiError(status, method, path, payload.get("errors"))
            return payload

    def get(self, path, **params):
        return self.request("GET", path, params=params or None)

    def get_all(self, path, **params):
        """GET с переходом по страницам (links.next)."""
        result = []
        payload = self.get(path, **params)
        while True:
            result.extend(payload.get("data", []))
            next_url = payload.get("links", {}).get("next")
            if not next_url or not next_url.startswith(API):
                return result
            parsed = urllib.parse.urlsplit(next_url)
            query = dict(urllib.parse.parse_qsl(parsed.query))
            payload = self.get(parsed.path, **query)


# ---------------------------------------------------------------- логика

def version_key(text):
    return tuple(int(x) for x in re.findall(r"\d+", str(text)))


def find_app(api, bundle_id):
    apps = api.get("/v1/apps", **{"filter[bundleId]": bundle_id, "fields[apps]": "name,bundleId"}).get("data", [])
    # filter[bundleId] ищет и по префиксу — нужно точное совпадение.
    apps = [a for a in apps if a.get("attributes", {}).get("bundleId") == bundle_id]
    if not apps:
        raise AscError("В App Store Connect нет приложения с Bundle ID %s. Создайте его: "
                       "docs/TESTFLIGHT.md, шаг 3 (Bundle ID должен совпадать буква в букву)" % bundle_id)
    return apps[0]


def recent_builds(api, app_id, limit=50):
    return api.get("/v1/builds", **{
        "filter[app]": app_id,
        "sort": "-uploadedDate",
        "limit": str(limit),
        "fields[builds]": "version,uploadedDate,processingState",
    }).get("data", [])


def check(api, bundle_id, version=None, build=None, out=print):
    app = find_app(api, bundle_id)
    name = app.get("attributes", {}).get("name", "?")
    out("Приложение: %s (%s), id %s" % (name, bundle_id, app["id"]))
    builds = recent_builds(api, app["id"])
    numbers = [b.get("attributes", {}).get("version") for b in builds]
    numbers = [n for n in numbers if n]
    latest = max(numbers, key=version_key) if numbers else None
    out("Последняя загруженная сборка: %s" % (latest or "нет ни одной"))
    if build and latest and version_key(build) <= version_key(latest):
        raise AscError("Номер сборки %s не больше уже загруженного %s — App Store Connect её не примет"
                       % (build, latest))
    if version and build:
        out("Будет загружена версия %s, сборка %s" % (version, build))
    return {"app_id": app["id"], "name": name, "latest_build": latest}


def wait_for_build(api, app_id, version, build, timeout, interval, clock=time.time, sleep=time.sleep, out=print):
    deadline = clock() + timeout
    last_state = None
    while True:
        data = api.get("/v1/builds", **{
            "filter[app]": app_id,
            "filter[version]": build,
            "filter[preReleaseVersion.version]": version,
            "fields[builds]": "version,processingState,usesNonExemptEncryption,expired",
            "limit": "5",
        }).get("data", [])
        state = data[0]["attributes"].get("processingState") if data else "NOT_FOUND"
        if state != last_state:
            out("Сборка %s (%s): %s" % (build, version, {
                "NOT_FOUND": "ещё не появилась в App Store Connect",
                "PROCESSING": "Apple обрабатывает",
                "VALID": "обработана",
            }.get(state, state)))
            last_state = state
        if state == "VALID":
            return data[0]
        if state in ("FAILED", "INVALID"):
            raise AscError("Apple не приняла сборку %s: processingState = %s. Причина — в письме от "
                           "App Store Connect и в разделе TestFlight → сборка" % (build, state))
        if clock() >= deadline:
            raise AscError("Сборка %s не обработана за %d мин (последнее состояние: %s). Она может "
                           "появиться позже — тогда добавьте её в группу вручную" % (build, timeout // 60, state))
        sleep(interval)


def set_whats_new(api, build_id, text, locale="ru", out=print):
    text = text.strip()
    if len(text) > WHATS_NEW_LIMIT:
        text = text[:WHATS_NEW_LIMIT - 1].rstrip() + "…"
    if not text:
        out("«Что тестировать» не задано — пропускаю")
        return None
    existing = api.get("/v1/builds/%s/betaBuildLocalizations" % build_id).get("data", [])
    target = next((l for l in existing if l.get("attributes", {}).get("locale") == locale), None)
    if target is None and existing:
        target = existing[0]
    if target is not None:
        api.request("PATCH", "/v1/betaBuildLocalizations/%s" % target["id"], body={"data": {
            "type": "betaBuildLocalizations", "id": target["id"], "attributes": {"whatsNew": text}}})
        out("«Что тестировать» обновлено (%s)" % target.get("attributes", {}).get("locale", locale))
        return target["id"]
    created = api.request("POST", "/v1/betaBuildLocalizations", body={"data": {
        "type": "betaBuildLocalizations",
        "attributes": {"locale": locale, "whatsNew": text},
        "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    out("«Что тестировать» добавлено (%s)" % locale)
    return created.get("data", {}).get("id")


def ensure_export_compliance(api, build, out=print):
    if build.get("attributes", {}).get("usesNonExemptEncryption") is None:
        api.request("PATCH", "/v1/builds/%s" % build["id"], body={"data": {
            "type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False}}})
        out("Экспортное соответствие: шифрование не используется")


def find_group(api, app_id, name):
    groups = api.get_all("/v1/betaGroups", **{
        "filter[app]": app_id,
        "fields[betaGroups]": "name,isInternalGroup,publicLink,publicLinkEnabled",
        "limit": "200",
    })
    for g in groups:
        if g.get("attributes", {}).get("name", "").strip().lower() == name.strip().lower():
            return g
    names = ", ".join("«%s»" % g.get("attributes", {}).get("name") for g in groups) or "ни одной"
    raise AscError("Нет группы TestFlight «%s». Есть: %s. Создайте её: docs/TESTFLIGHT.md, шаг 7" % (name, names))


def add_to_group(api, group, build_id, out=print):
    name = group["attributes"].get("name")
    try:
        api.request("POST", "/v1/betaGroups/%s/relationships/builds" % group["id"],
                    body={"data": [{"type": "builds", "id": build_id}]})
    except ApiError as e:
        if e.status != 409:
            raise
        if group["attributes"].get("isInternalGroup"):
            out("::warning::Внутренняя группа «%s» и так получает все сборки" % name)
        else:
            out("::warning::Сборка не добавлена в группу «%s» (возможно, уже там): %s" % (name, e))
        return
    out("Сборка добавлена в группу «%s»" % name)


def external_state(api, build_id):
    detail = api.get("/v1/builds/%s/buildBetaDetail" % build_id).get("data", {})
    return detail.get("attributes", {}).get("externalBuildState")


def submit_for_review(api, build_id, out=print):
    state = external_state(api, build_id)
    out("Состояние для внешнего тестирования: %s" % EXTERNAL_STATE_TEXT.get(state, state))
    if state != "READY_FOR_BETA_SUBMISSION":
        return state
    try:
        api.request("POST", "/v1/betaAppReviewSubmissions", body={"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    except ApiError as e:
        if e.status in (409, 422):
            out("::warning::Сборку не удалось отправить на проверку: %s. Частая причина — не заполнена "
                "«Информация о тестировании» (docs/TESTFLIGHT.md, шаг 7)" % e)
            return state
        raise
    out("Сборка отправлена на проверку Beta App Review (обычно до суток)")
    return "WAITING_FOR_BETA_REVIEW"


def distribute(api, bundle_id, version, build, whats_new="", group_name="", submit=False,
               locale="ru", timeout=3600, interval=60, clock=time.time, sleep=time.sleep, out=print):
    app = find_app(api, bundle_id)
    b = wait_for_build(api, app["id"], version, build, timeout, interval, clock=clock, sleep=sleep, out=out)
    ensure_export_compliance(api, b, out=out)
    set_whats_new(api, b["id"], whats_new, locale=locale, out=out)
    result = {"build_id": b["id"], "group": None, "public_link": None, "state": None}
    if not group_name:
        out("Группа не задана (вход group или переменная TESTFLIGHT_GROUP) — сборка никуда не добавлена")
        return result
    group = find_group(api, app["id"], group_name)
    result["group"] = group["attributes"].get("name")
    add_to_group(api, group, b["id"], out=out)
    if submit and not group["attributes"].get("isInternalGroup"):
        result["state"] = submit_for_review(api, b["id"], out=out)
    if group["attributes"].get("publicLinkEnabled") and group["attributes"].get("publicLink"):
        result["public_link"] = group["attributes"]["publicLink"]
        out("Публичная ссылка: %s" % result["public_link"])
    return result


# ---------------------------------------------------------------- CLI

def append_summary(lines):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


def read_whats_new(args):
    if args.whats_new:
        return args.whats_new
    if args.whats_new_file and os.path.exists(args.whats_new_file):
        with open(args.whats_new_file, encoding="utf-8") as f:
            return f.read()
    return ""


def build_parser():
    p = argparse.ArgumentParser(description="App Store Connect для выпуска «Деберца»")
    sub = p.add_subparsers(dest="command", required=True)

    k = sub.add_parser("write-key", help="записать ASC_KEY_P8 в файл .p8")
    k.add_argument("--dir", default=os.path.join(os.environ.get("RUNNER_TEMP", "."), "asc"))

    c = sub.add_parser("check", help="предпроверка перед сборкой")
    c.add_argument("--bundle-id", required=True)
    c.add_argument("--version")
    c.add_argument("--build")

    d = sub.add_parser("distribute", help="раздача загруженной сборки")
    d.add_argument("--bundle-id", required=True)
    d.add_argument("--version", required=True)
    d.add_argument("--build", required=True)
    d.add_argument("--whats-new")
    d.add_argument("--whats-new-file")
    d.add_argument("--group", default="")
    d.add_argument("--submit", action="store_true", help="отправить на Beta App Review")
    d.add_argument("--locale", default="ru")
    d.add_argument("--timeout", type=int, default=3600, help="ждать обработки, секунд")
    d.add_argument("--interval", type=int, default=60)
    return p


def main(argv=None, env=None, api_factory=None):
    env = os.environ if env is None else env
    args = build_parser().parse_args(argv)
    try:
        if args.command == "write-key":
            path = write_key(env, args.dir)
            print("Ключ записан: %s" % path)
            return 0
        if api_factory is None:
            key_id, issuer, key = credentials_from_env(env)
            api = Api(key_id, issuer, key)
        else:
            api = api_factory()
        if args.command == "check":
            info = check(api, args.bundle_id, args.version, args.build)
            append_summary(["App Store Connect: приложение «%s», последняя сборка — %s"
                            % (info["name"], info["latest_build"] or "нет")])
            return 0
        if args.command == "distribute":
            result = distribute(api, args.bundle_id, args.version, args.build,
                                whats_new=read_whats_new(args), group_name=args.group.strip(),
                                submit=args.submit, locale=args.locale,
                                timeout=args.timeout, interval=args.interval)
            lines = ["### Раздача TestFlight", "",
                     "- Сборка %s (%s) обработана" % (args.build, args.version)]
            if result["group"]:
                lines.append("- Группа: %s" % result["group"])
            if result["state"]:
                lines.append("- Состояние: %s" % EXTERNAL_STATE_TEXT.get(result["state"], result["state"]))
            if result["public_link"]:
                lines.append("- Публичная ссылка: %s" % result["public_link"])
            append_summary(lines)
            return 0
    except AscError as e:
        print("::error::%s" % e)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
