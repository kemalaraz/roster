import os
import pytest
from pathlib import Path
from unittest.mock import patch

from claude_profiles.code import CodeManager
from claude_profiles.profile import Profile


@pytest.fixture()
def cm(tmp_path, monkeypatch):
    monkeypatch.setattr("claude_profiles.code._BIN_DIR", tmp_path / "bin")
    monkeypatch.setattr("claude_profiles.code._CLAUDE_BIN", "/usr/local/bin/claude")
    return CodeManager()


@pytest.fixture()
def profile(tmp_path):
    p = Profile(name="work", display_name="Work")
    # Redirect profile dir to tmp_path
    with patch.object(type(p), "profile_dir",
                      new_callable=lambda: property(lambda self: tmp_path / self.slug)):
        with patch.object(type(p), "code_config_dir",
                          new_callable=lambda: property(
                              lambda self: tmp_path / self.slug / "claude-code")):
            yield p


class TestCodeManagerSetup:
    def test_setup_creates_config_dir(self, cm, profile):
        cm.setup(profile)
        assert profile.code_config_dir.exists()

    def test_setup_creates_wrapper_script(self, cm, profile, tmp_path):
        wrapper = cm.setup(profile)
        assert wrapper.exists()

    def test_wrapper_is_executable(self, cm, profile):
        wrapper = cm.setup(profile)
        assert os.access(wrapper, os.X_OK)

    def test_wrapper_sets_claude_config_dir(self, cm, profile):
        wrapper = cm.setup(profile)
        content = wrapper.read_text()
        assert "CLAUDE_CONFIG_DIR" in content
        assert str(profile.code_config_dir) in content

    def test_wrapper_calls_claude_bin(self, cm, profile):
        wrapper = cm.setup(profile)
        content = wrapper.read_text()
        assert "/usr/local/bin/claude" in content

    def test_wrapper_forwards_args(self, cm, profile):
        wrapper = cm.setup(profile)
        content = wrapper.read_text()
        assert '"$@"' in content

    def test_wrapper_name_matches_slug(self, cm, profile, tmp_path):
        wrapper = cm.setup(profile)
        assert wrapper.name == f"claude-{profile.slug}"

    def test_setup_idempotent(self, cm, profile):
        cm.setup(profile)
        cm.setup(profile)  # second call should not raise
        assert profile.code_config_dir.exists()


class TestCodeManagerLaunch:
    def test_launch_sets_env_var(self, cm, profile):
        captured_env = {}

        def fake_execvpe(path, args, env):
            captured_env.update(env)

        with patch("os.execvpe", side_effect=fake_execvpe):
            try:
                cm.launch(profile)
            except TypeError:
                pass  # execvpe is mocked, may not return normally

        assert captured_env.get("CLAUDE_CONFIG_DIR") == str(profile.code_config_dir)

    def test_launch_calls_claude_bin(self, cm, profile):
        captured_args = []

        def fake_execvpe(path, args, env):
            captured_args.extend(args)

        with patch("os.execvpe", side_effect=fake_execvpe):
            try:
                cm.launch(profile)
            except TypeError:
                pass

        assert captured_args[0] == "/usr/local/bin/claude"

    def test_launch_passes_extra_args(self, cm, profile):
        captured_args = []

        def fake_execvpe(path, args, env):
            captured_args.extend(args)

        with patch("os.execvpe", side_effect=fake_execvpe):
            try:
                cm.launch(profile, extra_args=["--version"])
            except TypeError:
                pass

        assert "--version" in captured_args
