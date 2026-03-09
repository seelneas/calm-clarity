import main

from conftest import auth_headers, signup_and_login


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


def test_google_calendar_sync_lifecycle(client, monkeypatch):
    signup_payload = signup_and_login(client, email="sync@example.com")
    headers = auth_headers(signup_payload["access_token"])

    monkeypatch.setattr(main, "_google_calendar_connected", lambda _: True)

    connect_response = client.post(
        "/integrations/google-calendar/connect",
        headers=headers,
        json={"access_token": "fake-token"},
    )
    assert connect_response.status_code == 200

    status_response = client.get(
        "/integrations/google-calendar/sync/status",
        headers=headers,
    )
    assert status_response.status_code == 200
    status_payload = status_response.json()
    assert status_payload["connected"] is True
    assert status_payload["auto_sync_enabled"] is True

    settings_response = client.put(
        "/integrations/google-calendar/sync/settings",
        headers=headers,
        json={"auto_sync_enabled": True, "sync_interval_minutes": 120},
    )
    assert settings_response.status_code == 200
    assert settings_response.json()["sync_interval_minutes"] == 60

    monkeypatch.setattr(main, "_process_calendar_push_queue", lambda *args, **kwargs: (1, 0))
    monkeypatch.setattr(main, "_calendar_pull_sync", lambda *args, **kwargs: (2, "cursor-iso"))

    sync_response = client.post(
        "/integrations/google-calendar/sync/run",
        headers=headers,
        json={
            "access_token": "fake-token",
            "local_changes": [
                {
                    "action": "create",
                    "client_event_id": "local-1",
                    "summary": "Focus Session",
                    "start_iso": "2026-03-07T10:00:00Z",
                    "end_iso": "2026-03-07T11:00:00Z",
                    "timezone": "UTC",
                }
            ],
        },
    )
    assert sync_response.status_code == 200
    sync_payload = sync_response.json()

    assert sync_payload["pulled_count"] == 2
    assert sync_payload["pushed_count"] == 1
    assert sync_payload["failed_count"] == 0
    assert "events" in sync_payload

    disconnect_response = client.post(
        "/integrations/google-calendar/disconnect",
        headers=headers,
    )
    assert disconnect_response.status_code == 200

    status_after_disconnect = client.get(
        "/integrations/google-calendar/sync/status",
        headers=headers,
    )
    assert status_after_disconnect.status_code == 200
    assert status_after_disconnect.json()["connected"] is False
