import json
import plistlib
import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock

from claude_profiles.desktop import DesktopManager, _VERSION_FILE
from claude_profiles.profile import Profile


@pytest.fixture()
def tmp_claude_app(tmp_path):
    """A minimal fake Claude.app for testing plist patching."""
    app = tmp_path / "Claude.app"
    contents = app / "Contents"
    contents.mkdir(parents=True)
    plist = {
        "CFBundleIdentifier": "com.anthropic.claude",
        "CFBundleName": "Claude",
        "CFBundleDisplayName": "Claude",
        "CFBundleShortVersionString": "1.2.3",
    }
    with open(contents / "Info.plist", "wb") as f:
        plistlib.dump(plist, f)
    return app


@pytest.fixture()
def profile(tmp_path):
    p = Profile(name="work", display_name="Work")
    # Redirect app path to tmp_path
    with patch.object(type(p), "app_path", new_callable=lambda: property(
        lambda self: tmp_path / f"Claude-{self.slug}.app"
    )):
        yield p


@pytest.fixture()
def dm(tmp_claude_app, tmp_path, monkeypatch):
    monkeypatch.setattr("claude_profiles.desktop._VERSION_FILE",
                        tmp_path / "claude-version.json")
    return DesktopManager(source=tmp_claude_app)


class TestDesktopManagerVersionTracking:
    def test_source_version_reads_plist(self, dm):
        assert dm.source_version() == "1.2.3"

    def test_source_version_missing_app_returns_none(self, tmp_path):
        dm = DesktopManager(source=tmp_path / "NoApp.app")
        assert dm.source_version() is None

    def test_synced_version_none_before_first_write(self, dm):
        assert dm.synced_version() is None

    def test_write_synced_version_persists(self, dm, tmp_path, monkeypatch):
        monkeypatch.setattr("claude_profiles.desktop._VERSION_FILE",
                            tmp_path / "claude-version.json")
        dm.write_synced_version("1.2.3")
        assert dm.synced_version() == "1.2.3"

    def test_update_available_returns_none_when_synced(self, dm, tmp_path, monkeypatch):
        monkeypatch.setattr("claude_profiles.desktop._VERSION_FILE",
                            tmp_path / "claude-version.json")
        dm.write_synced_version("1.2.3")
        assert dm.update_available() is None

    def test_update_available_returns_tuple_when_stale(self, dm, tmp_path, monkeypatch):
        monkeypatch.setattr("claude_profiles.desktop._VERSION_FILE",
                            tmp_path / "claude-version.json")
        dm.write_synced_version("1.0.0")
        result = dm.update_available()
        assert result == ("1.0.0", "1.2.3")

    def test_version_file_is_valid_json(self, dm, tmp_path, monkeypatch):
        monkeypatch.setattr("claude_profiles.desktop._VERSION_FILE",
                            tmp_path / "claude-version.json")
        dm.write_synced_version("1.2.3")
        data = json.loads((tmp_path / "claude-version.json").read_text())
        assert "synced_version" in data
        assert "last_synced" in data

    def test_synced_version_returns_none_on_corrupt_file(self, tmp_path, monkeypatch):
        vf = tmp_path / "claude-version.json"
        vf.write_text("not json{{{")
        monkeypatch.setattr("claude_profiles.desktop._VERSION_FILE", vf)
        dm = DesktopManager(source=tmp_path / "app")
        assert dm.synced_version() is None


class TestPlistPatching:
    def test_setup_patches_bundle_id(self, tmp_claude_app, tmp_path):
        profile = Profile(name="work", display_name="Work")
        dm = DesktopManager(source=tmp_claude_app)

        dest = tmp_path / "Claude-work.app"
        with patch.object(type(profile), "app_path", property(lambda self: dest)):
            with patch("claude_profiles.desktop._run"):  # skip codesign/xattr
                dm.setup(profile, force=True)

        plist_path = dest / "Contents" / "Info.plist"
        with open(plist_path, "rb") as f:
            plist = plistlib.load(f)

        assert plist["CFBundleIdentifier"]  == "com.anthropic.claude.profile.work"
        assert plist["CFBundleName"]        == "Claude (Work)"
        assert plist["CFBundleDisplayName"] == "Claude (Work)"

    def test_setup_raises_if_source_missing(self, tmp_path):
        profile = Profile(name="work", display_name="Work")
        dm = DesktopManager(source=tmp_path / "NoApp.app")
        with pytest.raises(FileNotFoundError):
            dm.setup(profile)
