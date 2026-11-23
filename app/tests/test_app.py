from app import app


def test_home_shows_environment(monkeypatch):
    monkeypatch.setenv("APP_ENV", "dev")
    resp = app.test_client().get("/")
    assert resp.status_code == 200
    assert b"dev" in resp.data


def test_health_endpoint():
    resp = app.test_client().get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"
