import main

from conftest import auth_headers, signup_and_login


def _issue_step_up_token(client, access_token: str, password: str = "strong-password-123") -> str:
    response = client.post(
        "/admin/re-auth",
        headers=auth_headers(access_token),
        json={"password": password},
    )
    assert response.status_code == 200
    return response.json()["step_up_token"]


def test_auth_signup_login_refresh_flow(client):
    signup_payload = signup_and_login(client, email="flow@example.com")
    access_token = signup_payload["access_token"]

    login_response = client.post(
        "/login",
        json={
            "email": "flow@example.com",
            "password": "strong-password-123",
        },
    )
    assert login_response.status_code == 200
    login_json = login_response.json()
    assert login_json["token_type"] == "bearer"

    refresh_response = client.post(
        "/refresh",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert refresh_response.status_code == 200
    refreshed = refresh_response.json()
    assert refreshed["token_type"] == "bearer"
    assert refreshed["access_token"]


def test_observability_endpoints_return_expected_shapes(client):
    signup_payload = signup_and_login(client)
    headers = auth_headers(signup_payload["access_token"])

    dashboard_response = client.get("/admin/observability/dashboard", headers=headers)
    assert dashboard_response.status_code == 200
    dashboard = dashboard_response.json()
    assert "service_status" in dashboard
    assert "traffic" in dashboard
    assert "signals" in dashboard
    assert isinstance(dashboard["traffic"]["top_paths"], list)

    alerts_response = client.get("/admin/observability/alerts", headers=headers)
    assert alerts_response.status_code == 200
    alerts = alerts_response.json()
    assert alerts["overall_status"] in {"ok", "warn", "fail"}
    assert isinstance(alerts["alerts"], list)

    metrics_response = client.get("/admin/observability/metrics", headers=headers)
    assert metrics_response.status_code == 200
    assert "calm_clarity_http_requests_total" in metrics_response.text


def test_ai_analyze_entry_returns_complete_payload(client):
    signup_payload = signup_and_login(client, email="ai@example.com")
    headers = auth_headers(signup_payload["access_token"])

    response = client.post(
        "/ai/analyze-entry",
        headers=headers,
        json={
            "transcript": "I felt tired in the morning but better after a walk.",
            "summary": "Energy improved after activity",
            "mood": "neutral",
            "mood_confidence": 0.72,
            "tags": ["energy", "walk"],
        },
    )
    assert response.status_code == 200
    payload = response.json()

    assert payload["ai_summary"]
    assert isinstance(payload["ai_action_items"], list)
    assert payload["ai_mood_explanation"]
    assert payload["ai_followup_prompt"]
    assert isinstance(payload["safety_flag"], bool)
    assert isinstance(payload["crisis_resources"], list)


def test_admin_audit_logs_capture_security_events(client):
    admin_signup = signup_and_login(client, email="admin@example.com")
    admin_headers = auth_headers(admin_signup["access_token"])

    member_signup = signup_and_login(client, email="member@example.com")
    member_id = int(member_signup["user"]["id"])

    role_response = client.patch(
        f"/admin/users/{member_id}/role",
        headers={
            **admin_headers,
            "X-Admin-Reauth": _issue_step_up_token(client, admin_signup["access_token"]),
        },
        json={"role": "admin"},
    )
    assert role_response.status_code == 200

    suspend_response = client.post(
        f"/admin/users/{member_id}/suspend",
        headers={
            **admin_headers,
            "X-Admin-Reauth": _issue_step_up_token(client, admin_signup["access_token"]),
        },
    )
    assert suspend_response.status_code == 200

    reactivate_response = client.post(
        f"/admin/users/{member_id}/reactivate",
        headers={
            **admin_headers,
            "X-Admin-Reauth": _issue_step_up_token(client, admin_signup["access_token"]),
        },
    )
    assert reactivate_response.status_code == 200

    delete_response = client.delete(
        f"/admin/users/{member_id}",
        headers={
            **admin_headers,
            "X-Admin-Reauth": _issue_step_up_token(client, admin_signup["access_token"]),
        },
    )
    assert delete_response.status_code == 200

    logs_response = client.get("/admin/audit-logs?limit=200", headers=admin_headers)
    assert logs_response.status_code == 200
    logs_payload = logs_response.json()

    event_types = {item["event_type"] for item in logs_payload["logs"]}
    assert "role_changed" in event_types
    assert "user_suspended" in event_types
    assert "user_reactivated" in event_types
    assert "user_deleted" in event_types


def test_admin_reauth_required_for_sensitive_mutations(client):
    admin_signup = signup_and_login(client, email="admin@example.com")
    admin_headers = auth_headers(admin_signup["access_token"])

    member_signup = signup_and_login(client, email="member2@example.com")
    member_id = int(member_signup["user"]["id"])

    no_reauth = client.post(
        f"/admin/users/{member_id}/suspend",
        headers=admin_headers,
    )
    assert no_reauth.status_code == 403
    assert "re-auth required" in no_reauth.json()["detail"].lower()

    with_reauth = client.post(
        f"/admin/users/{member_id}/suspend",
        headers={
            **admin_headers,
            "X-Admin-Reauth": _issue_step_up_token(client, admin_signup["access_token"]),
        },
    )
    assert with_reauth.status_code == 200


def test_admin_mfa_recovery_codes_flow(client):
    admin_signup = signup_and_login(client, email="admin@example.com")
    admin_headers = auth_headers(admin_signup["access_token"])

    setup = client.get("/admin/mfa/setup", headers=admin_headers)
    assert setup.status_code == 200
    secret = setup.json()["secret"]
    code = main._totp_code(secret, int(main.time.time() // 30))

    enable = client.post(
        "/admin/mfa/enable",
        headers={
            **admin_headers,
            "X-Admin-TOTP": code,
            "X-Admin-Reauth": _issue_step_up_token(client, admin_signup["access_token"]),
        },
        json={"code": code},
    )
    assert enable.status_code == 200

    reauth_with_totp = client.post(
        "/admin/re-auth",
        headers={**admin_headers, "X-Admin-TOTP": code},
        json={"password": "strong-password-123", "mfa_code": code},
    )
    assert reauth_with_totp.status_code == 200
    reauth_token = reauth_with_totp.json()["step_up_token"]

    regenerate = client.post(
        "/admin/mfa/recovery-codes/regenerate",
        headers={
            **admin_headers,
            "X-Admin-TOTP": code,
            "X-Admin-Reauth": reauth_token,
        },
    )
    assert regenerate.status_code == 200
    payload = regenerate.json()
    assert payload["total_codes"] >= 4
    recovery_code = payload["codes"][0]

    status_response = client.get(
        "/admin/mfa/recovery-codes/status",
        headers={**admin_headers, "X-Admin-TOTP": code},
    )
    assert status_response.status_code == 200
    assert status_response.json()["remaining_codes"] >= 1

    reauth_with_recovery = client.post(
        "/admin/re-auth",
        headers={**admin_headers, "X-Admin-Recovery-Code": recovery_code},
        json={"password": "strong-password-123", "recovery_code": recovery_code},
    )
    assert reauth_with_recovery.status_code == 200


def test_user_session_inventory_and_revoke(client):
    signup_payload = signup_and_login(client, email="sessions@example.com")
    access_token = signup_payload["access_token"]

    inventory = client.get(
        "/sessions/active",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert inventory.status_code == 200
    data = inventory.json()
    assert data["total_sessions"] >= 1
    first_session_id = int(data["sessions"][0]["session_id"])

    revoke_one = client.delete(
        f"/sessions/active/{first_session_id}",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert revoke_one.status_code == 200

    inventory_after = client.get(
        "/sessions/active",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert inventory_after.status_code == 200
    matching = [
        item for item in inventory_after.json()["sessions"]
        if int(item["session_id"]) == first_session_id
    ]
    assert matching
    assert matching[0]["revoked_at"] is not None


def test_change_password_forces_global_logout(client):
    signup_payload = signup_and_login(client, email="pwdchange@example.com")
    access_token = signup_payload["access_token"]

    change = client.post(
        "/change-password",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "current_password": "strong-password-123",
            "new_password": "new-strong-password-1",
        },
    )
    assert change.status_code == 200

    old_token_reuse = client.get(
        "/sessions/active",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert old_token_reuse.status_code == 401

    old_login = client.post(
        "/login",
        json={
            "email": "pwdchange@example.com",
            "password": "strong-password-123",
        },
    )
    assert old_login.status_code == 401

    new_login = client.post(
        "/login",
        json={
            "email": "pwdchange@example.com",
            "password": "new-strong-password-1",
        },
    )
    assert new_login.status_code == 200


def test_admin_can_view_and_revoke_user_sessions(client):
    admin_signup = signup_and_login(client, email="admin@example.com")
    admin_headers = auth_headers(admin_signup["access_token"])

    member_signup = signup_and_login(client, email="member-sessions@example.com")
    member_id = int(member_signup["user"]["id"])

    listed = client.get(
        f"/admin/users/{member_id}/sessions",
        headers=admin_headers,
    )
    assert listed.status_code == 200
    assert listed.json()["total_sessions"] >= 1

    revoke_all = client.post(
        f"/admin/users/{member_id}/sessions/revoke-all",
        headers={
            **admin_headers,
            "X-Admin-Reauth": _issue_step_up_token(client, admin_signup["access_token"]),
        },
    )
    assert revoke_all.status_code == 200

    listed_after = client.get(
        f"/admin/users/{member_id}/sessions",
        headers=admin_headers,
    )
    assert listed_after.status_code == 200
    assert listed_after.json()["active_sessions"] == 0
