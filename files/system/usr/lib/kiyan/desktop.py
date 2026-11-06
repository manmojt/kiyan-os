#!/usr/bin/python3
"""Shared safe desktop-session helpers for Kiyan OS."""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

HOME = pathlib.Path.home()
STATE = HOME / ".local/state/kiyan"
CONFIG = HOME / ".config"
OWNED = ("kdeglobals", "kwinrc", "plasmarc", "plasma-org.kde.plasma.desktop-appletsrc",
         "kglobalshortcutsrc", "kcminputrc", "dolphinrc",
         ".local/share/kxmlgui6/dolphin/dolphinui.rc")


def have(name):
    return shutil.which(name) is not None


def run(argv, *, check=True, capture=False, timeout=20, input_text=None):
    try:
        return subprocess.run([str(x) for x in argv], check=check, text=True,
                              capture_output=capture, timeout=timeout, input=input_text)
    except FileNotFoundError:
        raise RuntimeError(f"Required command not found: {argv[0]}")
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        raise RuntimeError(f"Command failed ({argv[0]}): {detail or exc.returncode}")


def notify(title, message, icon="dialog-information"):
    if have("kdialog") and (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        run(["kdialog", "--title", title, "--passivepopup", message, "4"], check=False)


def error(title, message):
    if have("kdialog") and (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        run(["kdialog", "--title", title, "--error", message], check=False)
    else:
        print(f"{title}: {message}", file=sys.stderr)


def qdbus(*args, check=False):
    for binary in ("qdbus6", "qdbus"):
        if have(binary):
            return run([binary, *args], check=check, capture=True, timeout=6).stdout
    raise RuntimeError("qdbus6/qdbus is unavailable; run this inside a Plasma session")


def atomic_write(path, data):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def snapshot(label="last-change"):
    """Save owned KDE configs and their absent/present state for one-step undo."""
    root = STATE / "snapshots" / label
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True, mode=0o700)
    manifest = {"version": 1, "files": {}}
    for relative in OWNED:
        source = HOME / ".config" / relative if not relative.startswith(".local/") else HOME / relative
        present = source.is_file()
        manifest["files"][relative] = present
        if present:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    atomic_write(root / "manifest.json", json.dumps(manifest, indent=2).encode())
    return root


def undo_snapshot(label="last-change"):
    root = STATE / "snapshots" / label
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError("No saved Kiyan change is available to undo")
    manifest = json.loads(manifest_path.read_text())
    CONFIG.mkdir(parents=True, exist_ok=True)
    for relative, existed in manifest["files"].items():
        target = HOME / ".config" / relative if not relative.startswith(".local/") else HOME / relative
        if existed:
            atomic_write(target, (root / relative).read_bytes())
        else:
            target.unlink(missing_ok=True)
    return reload_plasma()


def reload_plasma():
    if have("qdbus6") or have("qdbus"):
        qdbus("org.kde.KWin", "/KWin", "org.kde.KWin", "reconfigure")
        qdbus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "refreshCurrentShell")


def apply_plasma_layout(path):
    script = pathlib.Path(path).read_text(encoding="utf-8")
    qdbus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", script, check=True)
