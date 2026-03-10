import main


def _reset_abuse_state() -> None:
    with main._rate_limit_lock:
        main._rate_limit_events.clear()
        main._auth_failure_events.clear()
        main._auth_lockouts.clear()


class _MockCaptchaResponse:
    def __init__(self, status_code: int, payload: dict):
        self.status_code = status_code
        self._payload = payload

    def json(self):
        return self._payload


def _configure_captcha(monkeypatch):
    monkeypatch.setattr(main, "ABUSE_CAPTCHA_ENABLED", True)
    monkeypatch.setattr(main, "ABUSE_CAPTCHA_SECRET_KEY", "test-secret")
    monkeypatch.setattr(main, "AUTH_FAILURES_BEFORE_CAPTCHA", 1)
    monkeypatch.setattr(main, "AUTH_FAILURES_BEFORE_LOCKOUT", 100)
    monkeypatch.setattr(main, "AUTH_FAILURE_WINDOW_SECONDS", 3600)
    _reset_abuse_state()


def test_login_requires_captcha_after_failures_and_accepts_valid_provider_token(client, monkeypatch):
    _configure_captcha(monkeypatch)
    monkeypatch.setattr(main, "ABUSE_CAPTCHA_PROVIDER", "turnstile")

    def _captcha_ok(*args, **kwargs):
        return _MockCaptchaResponse(200, {"success": True})

    monkeypatch.setattr(main.requests, "post", _captcha_ok)

    client.post(
        "/signup",
        json={
            "name": "Captcha User",
            "email": "captcha-success@example.com",
            "password": "strong-password-123",
        },
    )

    first = client.post(
        "/login",
        json={"email": "captcha-success@example.com", "password": "wrong-password"},
    )
    assert first.status_code == 401

    second = client.post(
        "/login",
        json={"email": "captcha-success@example.com", "password": "wrong-password"},
    )
    assert second.status_code == 429
    assert second.json()["detail"] == "Captcha required"

    third = client.post(
        "/login",
        headers={"X-Captcha-Token": "provider-token"},
        json={"email": "captcha-success@example.com", "password": "wrong-password"},
    )
    assert third.status_code == 401


def test_login_blocks_when_turnstile_verification_fails(client, monkeypatch):
    _configure_captcha(monkeypatch)
    monkeypatch.setattr(main, "ABUSE_CAPTCHA_PROVIDER", "turnstile")

    def _captcha_fail(*args, **kwargs):
        return _MockCaptchaResponse(200, {"success": False})

    monkeypatch.setattr(main.requests, "post", _captcha_fail)

    client.post(
        "/signup",
        json={
            "name": "Captcha User",
            "email": "captcha-fail@example.com",
            "password": "strong-password-123",
        },
    )

    first = client.post(
        "/login",
        json={"email": "captcha-fail@example.com", "password": "wrong-password"},
    )
    assert first.status_code == 401

    second = client.post(
        "/login",
        headers={"X-Captcha-Token": "bad-token"},
        json={"email": "captcha-fail@example.com", "password": "wrong-password"},
    )
    assert second.status_code == 429
    assert second.json()["detail"] == "Captcha required"


def test_login_blocks_low_score_recaptcha(client, monkeypatch):
    _configure_captcha(monkeypatch)
    monkeypatch.setattr(main, "ABUSE_CAPTCHA_PROVIDER", "recaptcha")
    monkeypatch.setattr(main, "ABUSE_CAPTCHA_MIN_SCORE", 0.7)

    def _captcha_low_score(*args, **kwargs):
        return _MockCaptchaResponse(200, {"success": True, "score": 0.3, "action": "login"})

    monkeypatch.setattr(main.requests, "post", _captcha_low_score)

    client.post(
        "/signup",
        json={
            "name": "Captcha User",
            "email": "captcha-score@example.com",
            "password": "strong-password-123",
        },
    )

    first = client.post(
        "/login",
        json={"email": "captcha-score@example.com", "password": "wrong-password"},
    )
    assert first.status_code == 401

    second = client.post(
        "/login",
        headers={"X-Captcha-Token": "provider-token"},
        json={"email": "captcha-score@example.com", "password": "wrong-password"},
    )
    assert second.status_code == 429
    assert second.json()["detail"] == "Captcha required"
