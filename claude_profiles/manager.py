from __future__ import annotations
import json
import shutil
from pathlib import Path
from typing import List, Optional

from .profile import Profile, PROFILES_DIR

PROFILES_CONFIG = PROFILES_DIR / "profiles.json"


class ProfileManager:
    def __init__(self):
        PROFILES_DIR.mkdir(parents=True, exist_ok=True)
        self._profiles: List[Profile] = []
        self._load()

    # ──────────────────────────────────────────────────────────────
    # persistence
    # ──────────────────────────────────────────────────────────────

    def _load(self):
        if PROFILES_CONFIG.exists():
            data = json.loads(PROFILES_CONFIG.read_text())
            self._profiles = [Profile.from_dict(p) for p in data.get("profiles", [])]

    def _save(self):
        PROFILES_CONFIG.write_text(
            json.dumps({"profiles": [p.to_dict() for p in self._profiles]}, indent=2)
        )

    def reload(self):
        self._load()

    # ──────────────────────────────────────────────────────────────
    # CRUD
    # ──────────────────────────────────────────────────────────────

    def list(self) -> List[Profile]:
        return list(self._profiles)

    def get(self, name: str) -> Optional[Profile]:
        name_lower = name.lower()
        for p in self._profiles:
            if p.name == name or p.slug == name_lower:
                return p
        return None

    def create(
        self,
        name: str,
        display_name: str = None,
        color: str = "#0066CC",
        emoji: str = "👤",
    ) -> Profile:
        if self.get(name):
            raise ValueError(f"Profile '{name}' already exists")
        if not name.replace("-", "").replace("_", "").isalnum():
            raise ValueError("Profile name must be alphanumeric (hyphens/underscores allowed)")

        profile = Profile(
            name=name,
            display_name=display_name or name.capitalize(),
            color=color,
            emoji=emoji,
        )
        profile.profile_dir.mkdir(parents=True, exist_ok=True)
        profile.code_config_dir.mkdir(parents=True, exist_ok=True)

        self._profiles.append(profile)
        self._save()
        return profile

    def update(self, name: str, **kwargs) -> Profile:
        profile = self.get(name)
        if not profile:
            raise KeyError(f"Profile '{name}' not found")
        for k, v in kwargs.items():
            if hasattr(profile, k):
                object.__setattr__(profile, k, v)
        self._save()
        return profile

    def delete(self, name: str, keep_data: bool = False) -> bool:
        profile = self.get(name)
        if not profile:
            return False

        if profile.app_path.exists():
            shutil.rmtree(profile.app_path)

        if not keep_data and profile.profile_dir.exists():
            shutil.rmtree(profile.profile_dir)

        self._profiles = [p for p in self._profiles if p.name != profile.name]
        self._save()
        return True
