"""py2app build script — produces a fully standalone Claude Profiles.app.

Usage:
    conda run -n claude-profiles python setup_app.py py2app

The resulting .app bundles Python + all dependencies inside itself.
No Python installation required on the target Mac.
"""
from setuptools import setup

APP = ["menubar/menubar.py"]

CONDA_LIB = "/Users/kemalaraz/miniconda3/envs/claude-profiles/lib"

# All conda-provided dylibs that Python extension modules (.so) depend on
# via @rpath but that are not present in the macOS system dyld cache.
_FRAMEWORKS = [
    "libffi.8.dylib",
    "libexpat.1.dylib",
    "libbz2.dylib",
    "libcrypto.3.dylib",
    "liblzma.5.dylib",
    "libssl.3.dylib",
    "libz.1.dylib",
]

OPTIONS = {
    "argv_emulation": False,
    "semi_standalone": False,   # bundle Python itself — fully standalone
    "site_packages": True,
    "frameworks": [f"{CONDA_LIB}/{lib}" for lib in _FRAMEWORKS],
    "iconfile": "resources/icon.icns",
    "plist": {
        "CFBundleName":           "Claude Profiles",
        "CFBundleDisplayName":    "Claude Profiles",
        "CFBundleIdentifier":     "com.claudeprofiles.menubar",
        "CFBundleVersion":        "0.1.0",
        "CFBundleShortVersionString": "0.1.0",
        "LSUIElement":            True,   # menu bar only — no Dock icon
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "MIT License",
        "NSAppleScriptEnabled":   True,
    },
    "packages": [
        "rumps",
        "objc",
        "Foundation",
        "AppKit",
        "claude_profiles",
    ],
    "includes": [
        "plistlib",
        "json",
        "threading",
        "subprocess",
        "pathlib",
        "xml.etree.ElementTree",
        "xml.parsers.expat",
    ],
    "excludes": [
        "tkinter",
        "unittest",
        "distutils",
    ],
    # Bundle the CLI scripts alongside the Python app
    "resources": [
        ("bin", ["bin/claude-profiles"]),
        (".",   ["claude_profiles"]),  # puts claude_profiles/ directly under Resources/
    ],
}

setup(
    name="Claude Profiles",
    app=APP,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
