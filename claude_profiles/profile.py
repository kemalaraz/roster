from __future__ import annotations
from dataclasses import dataclass, field, asdict
from pathlib import Path
from datetime import datetime
from typing import Optional

PROFILES_DIR = Path.home() / ".claude-profiles"
USER_APPS_DIR = Path.home() / "Applications"
CLAUDE_APP_SOURCE = Path("/Applications/Claude.app")

PRESET_COLORS = {
    "blue":   "#0066CC",
    "green":  "#00AA44",
    "orange": "#FF6600",
    "purple": "#7700CC",
    "red":    "#CC0000",
    "teal":   "#00889A",
    "pink":   "#CC0066",
    "yellow": "#B8A000",
}

PRESET_EMOJIS = ["👤", "💼", "🏠", "🎓", "🔬", "🎨", "🚀", "⭐", "🌍", "🔧"]


@dataclass
class Profile:
    name: str
    display_name: str
    color: str = "#0066CC"
    emoji: str = "👤"
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())

    @property
    def slug(self) -> str:
        return self.name.lower().replace(" ", "-").replace("_", "-")

    @property
    def bundle_id(self) -> str:
        return f"com.anthropic.claude.profile.{self.slug}"

    @property
    def app_name(self) -> str:
        return f"Claude ({self.display_name})"

    @property
    def app_path(self) -> Path:
        return USER_APPS_DIR / f"Claude-{self.slug}.app"

    @property
    def profile_dir(self) -> Path:
        return PROFILES_DIR / self.slug

    @property
    def code_config_dir(self) -> Path:
        return self.profile_dir / "claude-code"

    @property
    def is_desktop_installed(self) -> bool:
        return self.app_path.exists()

    @property
    def is_code_initialized(self) -> bool:
        return self.code_config_dir.exists()

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "Profile":
        known = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in data.items() if k in known})
