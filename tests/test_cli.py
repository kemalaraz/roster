"""Integration tests for the CLI commands (no subprocess — test functions directly)."""
import json
import pytest
from io import StringIO
from pathlib import Path
from unittest.mock import patch, MagicMock

from claude_profiles.manager import ProfileManager
from claude_profiles.desktop import DesktopManager
from claude_profiles.code import CodeManager
from claude_profiles import cli as cli_module


# ── Fixtures ───────────────────────────────────────────────────────────────────

@pytest.fixture()
def pm(tmp_path, monkeypatch):
    monkeypatch.setattr("claude_profiles.profile.PROFILES_DIR", tmp_path)
    monkeypatch.setattr("claude_profiles.manager.PROFILES_DIR", tmp_path)
    monkeypatch.setattr("claude_profiles.manager.PROFILES_CONFIG", tmp_path / "profiles.json")
    return ProfileManager()


@pytest.fixture()
def dm():
    return DesktopManager()


@pytest.fixture()
def cm(tmp_path, monkeypatch):
    monkeypatch.setattr("claude_profiles.code._BIN_DIR", tmp_path / "bin")
    return CodeManager()


# ── cmd_list ───────────────────────────────────────────────────────────────────

class TestCmdList:
    def test_empty_message(self, pm, capsys):
        with patch("claude_profiles.desktop.DesktopManager.update_available", return_value=None):
            cli_module.cmd_list(pm=pm)
        out = capsys.readouterr().out
        assert "No profiles" in out

    def test_lists_created_profile(self, pm, capsys):
        pm.create("work", display_name="Work")
        with patch("claude_profiles.desktop.DesktopManager.update_available", return_value=None):
            cli_module.cmd_list(pm=pm)
        out = capsys.readouterr().out
        assert "work" in out

    def test_shows_update_warning(self, pm, capsys):
        pm.create("work")
        with patch("claude_profiles.desktop.DesktopManager.update_available",
                   return_value=("1.0", "1.1")):
            cli_module.cmd_list(pm=pm)
        out = capsys.readouterr().out
        assert "1.0" in out
        assert "1.1" in out


# ── cmd_create ─────────────────────────────────────────────────────────────────

class TestCmdCreate:
    def _args(self, name, display_name=None, color="#0066CC", emoji="👤"):
        a = MagicMock()
        a.name = name
        a.display_name = display_name
        a.color = color
        a.emoji = emoji
        return a

    def test_create_prints_success(self, pm, capsys):
        cli_module.cmd_create(pm=pm, args=self._args("work"))
        out = capsys.readouterr().out
        assert "Created" in out or "work" in out

    def test_create_adds_to_manager(self, pm):
        cli_module.cmd_create(pm=pm, args=self._args("work"))
        assert pm.get("work") is not None

    def test_create_duplicate_exits(self, pm):
        pm.create("work")
        with pytest.raises(SystemExit):
            cli_module.cmd_create(pm=pm, args=self._args("work"))


# ── cmd_delete ─────────────────────────────────────────────────────────────────

class TestCmdDelete:
    def _args(self, name, force=True):
        a = MagicMock()
        a.name = name
        a.force = force
        return a

    def test_delete_removes_profile(self, pm):
        pm.create("work")
        cli_module.cmd_delete(pm=pm, args=self._args("work", force=True))
        assert pm.get("work") is None

    def test_delete_missing_exits(self, pm):
        with pytest.raises(SystemExit):
            cli_module.cmd_delete(pm=pm, args=self._args("nonexistent", force=True))


# ── _warn_if_update_pending ────────────────────────────────────────────────────

class TestUpdateWarning:
    def test_no_warning_when_synced(self, capsys):
        dm = MagicMock()
        dm.update_available.return_value = None
        cli_module._warn_if_update_pending(dm)
        assert capsys.readouterr().out == ""

    def test_warning_shows_versions(self, capsys):
        dm = MagicMock()
        dm.update_available.return_value = ("1.0", "1.1")
        cli_module._warn_if_update_pending(dm)
        out = capsys.readouterr().out
        assert "1.0" in out
        assert "1.1" in out
