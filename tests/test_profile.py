import pytest
from claude_profiles.profile import Profile, PRESET_COLORS


class TestProfile:
    def test_slug_lowercases_and_replaces_spaces(self):
        p = Profile(name="My Work", display_name="My Work")
        assert p.slug == "my-work"

    def test_slug_replaces_underscores(self):
        p = Profile(name="my_work", display_name="My Work")
        assert p.slug == "my-work"

    def test_bundle_id_format(self):
        p = Profile(name="work", display_name="Work")
        assert p.bundle_id == "com.anthropic.claude.profile.work"

    def test_bundle_id_uses_slug(self):
        p = Profile(name="My Work", display_name="My Work")
        assert p.bundle_id == "com.anthropic.claude.profile.my-work"

    def test_app_name(self):
        p = Profile(name="work", display_name="Work")
        assert p.app_name == "Claude (Work)"

    def test_app_path_contains_slug(self):
        p = Profile(name="work", display_name="Work")
        assert "Claude-work.app" in str(p.app_path)

    def test_code_config_dir_under_profile_dir(self):
        p = Profile(name="work", display_name="Work")
        assert p.code_config_dir.parent == p.profile_dir

    def test_to_dict_round_trip(self):
        p = Profile(name="work", display_name="Work", color="#FF0000", emoji="💼")
        d = p.to_dict()
        p2 = Profile.from_dict(d)
        assert p2.name         == p.name
        assert p2.display_name == p.display_name
        assert p2.color        == p.color
        assert p2.emoji        == p.emoji

    def test_from_dict_ignores_unknown_keys(self):
        d = {"name": "work", "display_name": "Work", "color": "#0066CC",
             "emoji": "👤", "created_at": "2024-01-01", "unknown_key": "val"}
        p = Profile.from_dict(d)
        assert p.name == "work"

    def test_is_desktop_installed_false_by_default(self):
        p = Profile(name="nonexistent-xyz", display_name="X")
        assert not p.is_desktop_installed

    def test_is_code_initialized_false_by_default(self):
        p = Profile(name="nonexistent-xyz", display_name="X")
        assert not p.is_code_initialized
