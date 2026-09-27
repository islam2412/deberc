"""Тесты scripts/asc.py на подменённом HTTP. Запуск: python3 -m unittest discover -s scripts/tests -v"""

import io
import json
import os
import stat
import sys
import tempfile
import unittest
import urllib.parse
from contextlib import redirect_stdout

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import asc  # noqa: E402

try:
    import jwt
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    HAVE_JWT = True
except ImportError:  # pragma: no cover
    HAVE_JWT = False


def make_pem():
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                            serialization.NoEncryption()).decode()
    return key, pem


class FakeTransport:
    """Отвечает по таблице {(метод, путь): [ответ, ответ, …]}; последний ответ повторяется."""

    def __init__(self, routes):
        self.routes = {k: list(v) for k, v in routes.items()}
        self.calls = []

    def __call__(self, method, url, headers, data):
        parsed = urllib.parse.urlsplit(url)
        query = dict(urllib.parse.parse_qsl(parsed.query))
        body = json.loads(data) if data else None
        self.calls.append((method, parsed.path, query, body, headers))
        key = (method, parsed.path)
        if key not in self.routes:
            return 404, json.dumps({"errors": [{"title": "not found", "detail": parsed.path}]}).encode()
        queue = self.routes[key]
        status, payload = queue.pop(0) if len(queue) > 1 else queue[0]
        if callable(payload):
            payload = payload(query, body)
        return status, (json.dumps(payload).encode() if payload is not None else b"")

    def called(self, method, path):
        return [c for c in self.calls if c[0] == method and c[1] == path]


class FakeClock:
    def __init__(self):
        self.t = 1_800_000_000.0

    def __call__(self):
        return self.t

    def sleep(self, seconds):
        self.t += seconds


APP = {"type": "apps", "id": "APP1", "attributes": {"name": "Деберц: наши правила", "bundleId": "com.islam2412.deberc"}}


def make_api(routes, clock=None):
    clock = clock or FakeClock()
    transport = FakeTransport(routes)
    api = asc.Api("ABCDEFGHIJ", "69a6de7e-0000-1111-2222-333344445555", "unused",
                  transport=transport, sleep=clock.sleep, clock=clock)
    api.token = lambda: "TOKEN"
    return api, transport, clock


def quiet():
    return redirect_stdout(io.StringIO())


class KeyTests(unittest.TestCase):
    PEM = "-----BEGIN PRIVATE KEY-----\nMIGT\nAAAA\n-----END PRIVATE KEY-----"

    def test_normalize_crlf_and_literal_newlines(self):
        self.assertEqual(asc.normalize_key(self.PEM.replace("\n", "\r\n")), self.PEM + "\n")
        self.assertEqual(asc.normalize_key(self.PEM.replace("\n", "\\n")), self.PEM + "\n")

    def test_normalize_rejects_key_without_markers(self):
        with self.assertRaises(asc.AscError) as ctx:
            asc.normalize_key("MIGTAgEAMBMGByqGSM49")
        self.assertIn("BEGIN PRIVATE KEY", str(ctx.exception))

    def test_write_key_permissions_and_github_env(self):
        with tempfile.TemporaryDirectory() as d:
            env_file = os.path.join(d, "github_env")
            env = {"ASC_KEY_ID": "ABCDEFGHIJ", "ASC_KEY_P8": self.PEM, "GITHUB_ENV": env_file}
            path = asc.write_key(env, os.path.join(d, "keys"))
            self.assertTrue(path.endswith("AuthKey_ABCDEFGHIJ.p8"))
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
            with open(path) as f:
                self.assertEqual(f.read(), self.PEM + "\n")
            with open(env_file) as f:
                self.assertEqual(f.read(), "ASC_KEY_PATH=%s\n" % path)

    def test_write_key_rejects_bad_key_id(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(asc.AscError):
                asc.write_key({"ASC_KEY_ID": "abc", "ASC_KEY_P8": self.PEM}, d)

    def test_credentials_require_uuid_issuer(self):
        with self.assertRaises(asc.AscError):
            asc.credentials_from_env({"ASC_KEY_ID": "ABCDEFGHIJ", "ASC_ISSUER_ID": "nope", "ASC_KEY_P8": self.PEM})
        with self.assertRaises(asc.AscError) as ctx:
            asc.credentials_from_env({})
        self.assertIn("ASC_KEY_ID", str(ctx.exception))

    @unittest.skipUnless(HAVE_JWT, "нужен PyJWT[crypto]")
    def test_token_is_es256_with_apple_claims(self):
        key, pem = make_pem()
        now = 1_800_000_000
        token = asc.make_token("ABCDEFGHIJ", "issuer-uuid", pem, now)
        header = jwt.get_unverified_header(token)
        self.assertEqual(header["alg"], "ES256")
        self.assertEqual(header["kid"], "ABCDEFGHIJ")
        self.assertEqual(header["typ"], "JWT")
        claims = jwt.decode(token, key.public_key(), algorithms=["ES256"], audience="appstoreconnect-v1",
                            options={"verify_exp": False, "verify_iat": False})
        self.assertEqual(claims["iss"], "issuer-uuid")
        self.assertLessEqual(claims["exp"] - claims["iat"], 20 * 60)
        self.assertGreater(claims["exp"], now)

    @unittest.skipUnless(HAVE_JWT, "нужен PyJWT[crypto]")
    def test_api_sends_bearer_and_reuses_token(self):
        _, pem = make_pem()
        clock = FakeClock()
        transport = FakeTransport({("GET", "/v1/apps"): [(200, {"data": [APP]})]})
        api = asc.Api("ABCDEFGHIJ", "69a6de7e-0000-1111-2222-333344445555", pem,
                      transport=transport, sleep=clock.sleep, clock=clock)
        api.get("/v1/apps")
        api.get("/v1/apps")
        first, second = transport.calls[0][4]["Authorization"], transport.calls[1][4]["Authorization"]
        self.assertTrue(first.startswith("Bearer "))
        self.assertEqual(first, second)
        clock.t += 11 * 60
        api.get("/v1/apps")
        self.assertNotEqual(transport.calls[2][4]["Authorization"], first)


class HttpTests(unittest.TestCase):
    def test_retries_on_429_then_succeeds(self):
        api, transport, clock = make_api({("GET", "/v1/apps"): [
            (429, {"errors": [{"title": "rate"}]}), (503, None), (200, {"data": [APP]})]})
        start = clock.t
        self.assertEqual(api.get("/v1/apps")["data"][0]["id"], "APP1")
        self.assertEqual(len(transport.calls), 3)
        self.assertGreater(clock.t, start)

    def test_401_explains_which_secrets(self):
        api, _, _ = make_api({("GET", "/v1/apps"): [(401, {"errors": [{"title": "NOT_AUTHORIZED"}]})]})
        with self.assertRaises(asc.ApiError) as ctx:
            api.get("/v1/apps")
        self.assertEqual(ctx.exception.status, 401)
        self.assertIn("ASC_KEY_P8", str(ctx.exception))

    def test_pagination_follows_next(self):
        page2 = asc.API + "/v1/betaGroups?cursor=abc&limit=1"
        api, transport, _ = make_api({("GET", "/v1/betaGroups"): [
            (200, {"data": [{"id": "G1"}], "links": {"next": page2}}),
            (200, {"data": [{"id": "G2"}], "links": {}})]})
        self.assertEqual([g["id"] for g in api.get_all("/v1/betaGroups", limit="1")], ["G1", "G2"])
        self.assertEqual(transport.calls[1][2].get("cursor"), "abc")


class CheckTests(unittest.TestCase):
    def routes(self, builds):
        return {
            ("GET", "/v1/apps"): [(200, {"data": [APP]})],
            ("GET", "/v1/builds"): [(200, {"data": [{"id": str(i), "attributes": {"version": v}}
                                                    for i, v in enumerate(builds)]})],
        }

    def test_version_key_compares_numerically(self):
        self.assertGreater(asc.version_key("260927.1805"), asc.version_key("260927.905"))
        self.assertGreater(asc.version_key("261001.5"), asc.version_key("260930.2359"))
        self.assertGreater(asc.version_key("10"), asc.version_key("9"))

    def test_check_ok(self):
        api, transport, _ = make_api(self.routes(["260927.905", "101"]))
        with quiet():
            info = asc.check(api, "com.islam2412.deberc", "1.0", "260927.1805")
        self.assertEqual(info["latest_build"], "260927.905")
        self.assertEqual(transport.calls[0][2]["filter[bundleId]"], "com.islam2412.deberc")

    def test_check_rejects_lower_build(self):
        api, _, _ = make_api(self.routes(["260927.1805"]))
        with quiet(), self.assertRaises(asc.AscError) as ctx:
            asc.check(api, "com.islam2412.deberc", "1.0", "260927.905")
        self.assertIn("не больше", str(ctx.exception))

    def test_check_requires_exact_bundle_id(self):
        other = dict(APP, attributes={"name": "x", "bundleId": "com.islam2412.deberc.beta"})
        api, _, _ = make_api({("GET", "/v1/apps"): [(200, {"data": [other]})]})
        with quiet(), self.assertRaises(asc.AscError) as ctx:
            asc.check(api, "com.islam2412.deberc")
        self.assertIn("шаг 3", str(ctx.exception))


class DistributeTests(unittest.TestCase):
    BUILD = {"id": "B1", "type": "builds",
             "attributes": {"version": "260927.1805", "processingState": "VALID", "usesNonExemptEncryption": False}}
    GROUP = {"id": "G1", "type": "betaGroups", "attributes": {
        "name": "Семья и друзья", "isInternalGroup": False,
        "publicLinkEnabled": True, "publicLink": "https://testflight.apple.com/join/ABCDEFGH"}}

    def routes(self, over=None):
        processing = dict(self.BUILD, attributes=dict(self.BUILD["attributes"], processingState="PROCESSING"))
        routes = {
            ("GET", "/v1/apps"): [(200, {"data": [APP]})],
            ("GET", "/v1/builds"): [(200, {"data": []}), (200, {"data": [processing]}), (200, {"data": [self.BUILD]})],
            ("GET", "/v1/builds/B1/betaBuildLocalizations"): [
                (200, {"data": [{"id": "L1", "attributes": {"locale": "ru", "whatsNew": None}}]})],
            ("PATCH", "/v1/betaBuildLocalizations/L1"): [(200, {"data": {"id": "L1"}})],
            ("POST", "/v1/betaBuildLocalizations"): [(201, {"data": {"id": "L2"}})],
            ("GET", "/v1/betaGroups"): [(200, {"data": [self.GROUP], "links": {}})],
            ("POST", "/v1/betaGroups/G1/relationships/builds"): [(204, None)],
            ("GET", "/v1/builds/B1/buildBetaDetail"): [
                (200, {"data": {"attributes": {"externalBuildState": "READY_FOR_BETA_SUBMISSION"}}})],
            ("POST", "/v1/betaAppReviewSubmissions"): [(201, {"data": {"id": "S1"}})],
            ("PATCH", "/v1/builds/B1"): [(200, {"data": {"id": "B1"}})],
        }
        routes.update(over or {})
        return routes

    def run_distribute(self, api, clock, **kw):
        out = io.StringIO()
        params = dict(whats_new="Новые соперники", group_name="семья и друзья", submit=True,
                      timeout=3600, interval=60)
        params.update(kw)
        with redirect_stdout(out):
            result = asc.distribute(api, "com.islam2412.deberc", "1.0", "260927.1805",
                                    clock=clock, sleep=clock.sleep, **params)
        return result, out.getvalue()

    def test_full_flow(self):
        api, t, clock = make_api(self.routes())
        result, log = self.run_distribute(api, clock)
        polls = t.called("GET", "/v1/builds")
        self.assertEqual(len(polls), 3)
        self.assertEqual(polls[0][2]["filter[version]"], "260927.1805")
        self.assertEqual(polls[0][2]["filter[preReleaseVersion.version]"], "1.0")
        patch = t.called("PATCH", "/v1/betaBuildLocalizations/L1")[0][3]
        self.assertEqual(patch["data"]["attributes"]["whatsNew"], "Новые соперники")
        add = t.called("POST", "/v1/betaGroups/G1/relationships/builds")[0][3]
        self.assertEqual(add, {"data": [{"type": "builds", "id": "B1"}]})
        submission = t.called("POST", "/v1/betaAppReviewSubmissions")[0][3]
        self.assertEqual(submission["data"]["relationships"]["build"]["data"]["id"], "B1")
        self.assertFalse(t.called("PATCH", "/v1/builds/B1"))  # шифрование уже указано
        self.assertEqual(result["public_link"], "https://testflight.apple.com/join/ABCDEFGH")
        self.assertEqual(result["state"], "WAITING_FOR_BETA_REVIEW")
        self.assertIn("Публичная ссылка", log)

    def test_creates_localization_and_sets_compliance(self):
        unknown = dict(self.BUILD, attributes=dict(self.BUILD["attributes"], usesNonExemptEncryption=None))
        api, t, clock = make_api(self.routes({
            ("GET", "/v1/builds"): [(200, {"data": [unknown]})],
            ("GET", "/v1/builds/B1/betaBuildLocalizations"): [(200, {"data": []})],
        }))
        self.run_distribute(api, clock, group_name="", whats_new="x" * 5000)
        created = t.called("POST", "/v1/betaBuildLocalizations")[0][3]["data"]
        self.assertEqual(created["attributes"]["locale"], "ru")
        self.assertEqual(len(created["attributes"]["whatsNew"]), asc.WHATS_NEW_LIMIT)
        self.assertEqual(created["relationships"]["build"]["data"]["id"], "B1")
        compliance = t.called("PATCH", "/v1/builds/B1")[0][3]
        self.assertIs(compliance["data"]["attributes"]["usesNonExemptEncryption"], False)
        self.assertFalse(t.called("GET", "/v1/betaGroups"))

    def test_processing_failed(self):
        failed = dict(self.BUILD, attributes=dict(self.BUILD["attributes"], processingState="INVALID"))
        api, _, clock = make_api(self.routes({("GET", "/v1/builds"): [(200, {"data": [failed]})]}))
        with self.assertRaises(asc.AscError) as ctx:
            self.run_distribute(api, clock)
        self.assertIn("INVALID", str(ctx.exception))

    def test_timeout_while_processing(self):
        api, t, clock = make_api(self.routes({("GET", "/v1/builds"): [(200, {"data": []})]}))
        with self.assertRaises(asc.AscError) as ctx:
            self.run_distribute(api, clock, timeout=600, interval=60)
        self.assertIn("10 мин", str(ctx.exception))
        self.assertLessEqual(len(t.called("GET", "/v1/builds")), 12)

    def test_unknown_group_lists_existing(self):
        api, _, clock = make_api(self.routes())
        with self.assertRaises(asc.AscError) as ctx:
            self.run_distribute(api, clock, group_name="Друзья")
        self.assertIn("«Семья и друзья»", str(ctx.exception))

    def test_submission_conflict_is_warning(self):
        api, _, clock = make_api(self.routes({("POST", "/v1/betaAppReviewSubmissions"): [
            (409, {"errors": [{"title": "ENTITY_ERROR", "detail": "Missing beta app review details"}]})]}))
        result, log = self.run_distribute(api, clock)
        self.assertIn("::warning::", log)
        self.assertEqual(result["state"], "READY_FOR_BETA_SUBMISSION")

    def test_no_submit_when_already_testing(self):
        api, t, clock = make_api(self.routes({("GET", "/v1/builds/B1/buildBetaDetail"): [
            (200, {"data": {"attributes": {"externalBuildState": "IN_BETA_TESTING"}}})]}))
        result, _ = self.run_distribute(api, clock)
        self.assertFalse(t.called("POST", "/v1/betaAppReviewSubmissions"))
        self.assertEqual(result["state"], "IN_BETA_TESTING")

    def test_internal_group_is_not_submitted(self):
        internal = dict(self.GROUP, attributes=dict(self.GROUP["attributes"], isInternalGroup=True,
                                                    publicLinkEnabled=False))
        api, t, clock = make_api(self.routes({("GET", "/v1/betaGroups"): [(200, {"data": [internal]})]}))
        result, _ = self.run_distribute(api, clock)
        self.assertFalse(t.called("GET", "/v1/builds/B1/buildBetaDetail"))
        self.assertIsNone(result["public_link"])


class CliTests(unittest.TestCase):
    def test_distribute_cli_writes_summary(self):
        api, _, clock = make_api(DistributeTests().routes())
        api.sleep = clock.sleep
        with tempfile.TemporaryDirectory() as d:
            summary = os.path.join(d, "summary.md")
            whats_new = os.path.join(d, "whats_new.txt")
            with open(whats_new, "w", encoding="utf-8") as f:
                f.write("Что нового\n")
            old = os.environ.get("GITHUB_STEP_SUMMARY")
            os.environ["GITHUB_STEP_SUMMARY"] = summary
            try:
                orig_wait = asc.wait_for_build
                asc.wait_for_build = lambda api, *a, **k: orig_wait(api, *a, **dict(k, clock=clock, sleep=clock.sleep))
                with quiet():
                    rc = asc.main(["distribute", "--bundle-id", "com.islam2412.deberc", "--version", "1.0",
                                   "--build", "260927.1805", "--whats-new-file", whats_new,
                                   "--group", "Семья и друзья", "--submit"], env={}, api_factory=lambda: api)
            finally:
                asc.wait_for_build = orig_wait
                if old is None:
                    os.environ.pop("GITHUB_STEP_SUMMARY", None)
                else:
                    os.environ["GITHUB_STEP_SUMMARY"] = old
            self.assertEqual(rc, 0)
            with open(summary, encoding="utf-8") as f:
                text = f.read()
            self.assertIn("testflight.apple.com/join/ABCDEFGH", text)

    def test_cli_error_is_annotation(self):
        api, _, _ = make_api({("GET", "/v1/apps"): [(200, {"data": []})]})
        out = io.StringIO()
        with redirect_stdout(out):
            rc = asc.main(["check", "--bundle-id", "com.example.none"], env={}, api_factory=lambda: api)
        self.assertEqual(rc, 1)
        self.assertTrue(out.getvalue().startswith("::error::"))

    def test_write_key_cli(self):
        with tempfile.TemporaryDirectory() as d:
            env = {"ASC_KEY_ID": "ABCDEFGHIJ", "ASC_KEY_P8": KeyTests.PEM}
            with quiet():
                rc = asc.main(["write-key", "--dir", d], env=env)
            self.assertEqual(rc, 0)
            self.assertTrue(os.path.exists(os.path.join(d, "AuthKey_ABCDEFGHIJ.p8")))


if __name__ == "__main__":
    unittest.main()
