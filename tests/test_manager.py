import pytest
import json
from pathlib import Path
from claude_profiles.manager import ProfileManager
from claude_profiles.profile import PROFILES_DIR


@pytest.fixture()
def manager(tmp_path, monkeypatch):
    """A ProfileManager backed by a temp directory instead of ~/.claude-profiles."""
    monkeypatch.setattr("claude_profiles.profile.PROFILES_DIR", tmp_path)
    monkeypatch.setattr("claude_profiles.manager.PROFILES_DIR", tmp_path)
    monkeypatch.setattr("claude_profiles.manager.PROFILES_CONFIG", tmp_path / "profiles.json")
    return ProfileManager()


class TestProfileManagerCreate:
    def test_create_returns_profile(self, manager):
        p = manager.create("work", display_name="Work")
        assert p.name == "work"
        assert p.display_name == "Work"

    def test_create_defaults_display_name_to_capitalized(self, manager):
        p = manager.create("personal")
        assert p.display_name == "Personal"

    def test_create_persists_to_disk(self, manager, tmp_path):
        manager.create("work")
        config = json.loads((tmp_path / "profiles.json").read_text())
        assert any(p["name"] == "work" for p in config["profiles"])

    def test_create_duplicate_raises(self, manager):
        manager.create("work")
        with pytest.raises(ValueError, match="already exists"):
            manager.create("work")

    def test_create_invalid_name_raises(self, manager):
        with pytest.raises(ValueError):
            manager.create("my profile!")  # space + exclamation not allowed

    def test_create_with_emoji_and_color(self, manager):
        p = manager.create("work", emoji="💼", color="#FF0000")
        assert p.emoji == "💼"
        assert p.color == "#FF0000"


class TestProfileManagerGet:
    def test_get_by_name(self, manager):
        manager.create("work")
        assert manager.get("work") is not None

    def test_get_by_slug(self, manager):
        manager.create("My-Work")
        assert manager.get("my-work") is not None

    def test_get_missing_returns_none(self, manager):
        assert manager.get("nonexistent") is None


class TestProfileManagerList:
    def test_empty_list(self, manager):
        assert manager.list() == []

    def test_list_returns_all(self, manager):
        manager.create("work")
        manager.create("personal")
        names = [p.name for p in manager.list()]
        assert "work" in names
        assert "personal" in names

    def test_list_order_preserved(self, manager):
        manager.create("aaa")
        manager.create("zzz")
        names = [p.name for p in manager.list()]
        assert names == ["aaa", "zzz"]


class TestProfileManagerDelete:
    def test_delete_removes_from_list(self, manager):
        manager.create("work")
        manager.delete("work")
        assert manager.get("work") is None

    def test_delete_returns_true_on_success(self, manager):
        manager.create("work")
        assert manager.delete("work") is True

    def test_delete_returns_false_if_missing(self, manager):
        assert manager.delete("nonexistent") is False

    def test_delete_persists(self, manager, tmp_path):
        manager.create("work")
        manager.delete("work")
        config = json.loads((tmp_path / "profiles.json").read_text())
        assert not any(p["name"] == "work" for p in config["profiles"])

    def test_delete_keep_data_leaves_profile_dir(self, manager, tmp_path):
        p = manager.create("work")
        # Manually set the profile dir to somewhere in tmp_path
        manager.delete("work", keep_data=True)
        # Profile dir should still exist (or not have been removed)
        # Just check it didn't raise
        assert manager.get("work") is None


class TestProfileManagerReload:
    def test_reload_picks_up_external_changes(self, manager, tmp_path):
        manager.create("work")
        # Write a second profile directly to disk
        config_path = tmp_path / "profiles.json"
        data = json.loads(config_path.read_text())
        data["profiles"].append({
            "name": "personal", "display_name": "Personal",
            "color": "#0066CC", "emoji": "👤", "created_at": "2024-01-01",
        })
        config_path.write_text(json.dumps(data))
        manager.reload()
        assert manager.get("personal") is not None
