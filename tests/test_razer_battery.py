"""Tests for the notification logic in razer-battery.py.

Covers _maybe_notify() and the state-file helpers used to deduplicate
notifications while the mouse drains below 10%.
"""

import importlib.util
import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "razer-battery.py"


def _load_module(xdg_runtime_dir):
    spec = importlib.util.spec_from_file_location("_razer_battery_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pytest_collection_modifyitems(config, items):
    pass


import pytest


@pytest.fixture
def tmp_state_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    return tmp_path


@pytest.fixture
def razer(tmp_state_dir):
    return _load_module(tmp_state_dir)


@pytest.fixture
def notify(monkeypatch):
    calls = []

    def fake_popen(args, *a, **kw):
        calls.append(args)

        class _Proc:
            def wait(self):
                return 0

        return _Proc()

    monkeypatch.setattr(subprocess, "Popen", fake_popen)
    return calls


@pytest.fixture
def state_path(razer):
    return Path(razer.STATE_FILE)


@pytest.fixture
def prev_level_path(razer):
    return Path(razer.PREV_LEVEL_FILE)


def test_above_threshold_does_not_notify_and_clears_state(razer, notify, state_path):
    state_path.write_text("5")

    razer._maybe_notify("Mouse", 50, charging=False)

    assert notify == []
    assert not state_path.exists()


def test_charging_does_not_notify_and_clears_state(razer, notify, state_path):
    state_path.write_text("5")

    razer._maybe_notify("Mouse", 5, charging=True)

    assert notify == []
    assert not state_path.exists()


def test_first_time_below_threshold_notifies_and_persists(razer, notify, state_path):
    razer._maybe_notify("Mouse", 8, charging=False)

    assert len(notify) == 1
    cmd = notify[0]
    assert cmd[0] == "notify-send"
    assert "-u" in cmd
    assert "critical" in cmd
    assert "Mouse: 8%" in cmd
    assert "Batería baja (8%)" in cmd
    assert state_path.read_text() == "8"


def test_same_level_does_not_re_notify(razer, notify, state_path):
    state_path.write_text("7")

    razer._maybe_notify("Mouse", 7, charging=False)

    assert notify == []
    assert state_path.read_text() == "7"


def test_higher_level_still_below_threshold_does_not_re_notify(razer, notify, state_path):
    state_path.write_text("5")

    razer._maybe_notify("Mouse", 7, charging=False)

    assert notify == []
    assert state_path.read_text() == "5"


def test_lower_level_re_notifies_and_updates_state(razer, notify, state_path):
    state_path.write_text("7")

    razer._maybe_notify("Mouse", 5, charging=False)

    assert len(notify) == 1
    assert state_path.read_text() == "5"


def test_threshold_is_inclusive_at_10(razer, notify, state_path):
    razer._maybe_notify("Mouse", 10, charging=False)

    assert len(notify) == 1
    assert state_path.read_text() == "10"


def test_level_11_does_not_notify(razer, notify, state_path):
    razer._maybe_notify("Mouse", 11, charging=False)

    assert notify == []


def test_clear_missing_state_does_not_raise(razer):
    razer._clear_state()


def test_level_zero_does_not_notify(razer, notify, state_path):
    razer._maybe_notify("Mouse", 0, charging=False)

    assert notify == []
    assert not state_path.exists()


def test_level_zero_does_not_clobber_existing_state(razer, notify, state_path):
    state_path.write_text("7")

    razer._maybe_notify("Mouse", 0, charging=False)

    assert notify == []
    assert state_path.read_text() == "7"


def test_level_negative_does_not_notify(razer, notify, state_path):
    razer._maybe_notify("Mouse", -1, charging=False)

    assert notify == []
    assert not state_path.exists()


def test_detect_charging_first_run_returns_false_and_persists(razer, prev_level_path):
    assert razer._detect_charging(50) is False
    state = json.loads(prev_level_path.read_text())
    assert state["prev"] == 50


def test_detect_charging_level_unchanged_returns_false(razer, prev_level_path):
    razer._detect_charging(50)
    assert razer._detect_charging(50) is False
    state = json.loads(prev_level_path.read_text())
    assert state["prev"] == 50


def test_detect_charging_level_drop_returns_false(razer, prev_level_path):
    razer._detect_charging(50)
    assert razer._detect_charging(45) is False
    state = json.loads(prev_level_path.read_text())
    assert state["prev"] == 45
    assert state["last_rise"] == 0


def test_detect_charging_level_rise_returns_true(razer, prev_level_path):
    razer._detect_charging(50)
    assert razer._detect_charging(55) is True
    state = json.loads(prev_level_path.read_text())
    assert state["prev"] == 55
    assert state["last_rise"] > 0


def test_detect_charging_missing_state_file_returns_false(tmp_state_dir, razer, prev_level_path):
    assert not prev_level_path.exists()
    assert razer._detect_charging(50) is False
    state = json.loads(prev_level_path.read_text())
    assert state["prev"] == 50


def test_detect_charging_corrupt_state_file_returns_false(tmp_state_dir, razer, prev_level_path):
    prev_level_path.write_text("not-json")
    assert razer._detect_charging(50) is False
    state = json.loads(prev_level_path.read_text())
    assert state["prev"] == 50


def test_detect_charging_legacy_plain_int_state_file(tmp_state_dir, razer, prev_level_path):
    prev_level_path.write_text("40")
    assert razer._detect_charging(45) is True
    state = json.loads(prev_level_path.read_text())
    assert state["prev"] == 45


def test_detect_charging_grace_period_keeps_true_on_flat(razer, prev_level_path):
    razer._detect_charging(50)
    assert razer._detect_charging(55) is True
    assert razer._detect_charging(55) is True


def test_detect_charging_grace_period_expires(razer, prev_level_path, monkeypatch):
    base = 1_700_000_000.0
    monkeypatch.setattr(razer.time, "time", lambda: base)
    razer._detect_charging(50)
    monkeypatch.setattr(razer.time, "time", lambda: base + 10)
    assert razer._detect_charging(55) is True
    monkeypatch.setattr(razer.time, "time", lambda: base + razer.CHARGING_GRACE_SECONDS + 20)
    assert razer._detect_charging(55) is False


def test_detect_charging_drop_resets_grace_immediately(razer, prev_level_path, monkeypatch):
    base = 1_700_000_000.0
    monkeypatch.setattr(razer.time, "time", lambda: base)
    razer._detect_charging(50)
    monkeypatch.setattr(razer.time, "time", lambda: base + 10)
    assert razer._detect_charging(55) is True
    monkeypatch.setattr(razer.time, "time", lambda: base + 20)
    assert razer._detect_charging(50) is False