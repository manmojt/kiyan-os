#!/usr/bin/env python3
"""Pull and verify the latest public Kiyan OS release without SSH credentials."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


REPOSITORY = "manmojt/kiyan-os"
API_URL = f"https://api.github.com/repos/{REPOSITORY}/releases/latest"
ISO_NAME = "Kiyan-OS-LB1-x86_64.iso"
CHECKSUM_NAME = f"{ISO_NAME}.sha256"
BUNDLE_NAME = f"{ISO_NAME}.sigstore.json"
PART_PATTERN = re.compile(r"^Kiyan-OS-LB1-x86_64\.iso\.part-(\d{3,})$")
TAG_PATTERN = re.compile(r"^kiyan-lb1-\d+-[0-9a-f]{12}$")
ALLOWED_DOWNLOAD_HOSTS = {"github.com", "release-assets.githubusercontent.com"}


def log(message: str) -> None:
    print(f"kiyan-release-pull: {message}", flush=True)


def fetch_json() -> dict | None:
    request = Request(
        API_URL,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "KiyanOS-release-puller/1.0",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as exc:
        if exc.code == 404:
            log("no published release yet; will check again on the next timer run")
            return None
        raise


def validate_assets(release: dict) -> list[dict]:
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease") or not TAG_PATTERN.fullmatch(tag):
        raise ValueError(f"latest release is not a published Kiyan LB1 build: {tag!r}")

    assets = release.get("assets")
    if not isinstance(assets, list):
        raise ValueError("release assets are missing")
    by_name: dict[str, dict] = {}
    for asset in assets:
        name = asset.get("name")
        if not isinstance(name, str) or name in by_name:
            raise ValueError("release contains an invalid or duplicate asset name")
        by_name[name] = asset

    if CHECKSUM_NAME not in by_name or BUNDLE_NAME not in by_name:
        raise ValueError("release is missing the ISO checksum or Cosign signature")

    numbered: list[tuple[int, dict]] = []
    for name, asset in by_name.items():
        match = PART_PATTERN.fullmatch(name)
        if match:
            numbered.append((int(match.group(1)), asset))
        elif name not in {CHECKSUM_NAME, BUNDLE_NAME}:
            raise ValueError(f"unexpected release asset: {name}")

    numbered.sort(key=lambda item: item[0])
    if not numbered or [index for index, _ in numbered] != list(range(len(numbered))):
        raise ValueError("release ISO parts are missing or not consecutively numbered")
    return [by_name[CHECKSUM_NAME], by_name[BUNDLE_NAME], *[asset for _, asset in numbered]]


def download(asset: dict, destination, output=None) -> int:
    url = asset.get("browser_download_url")
    parsed = urlparse(url or "")
    if (
        parsed.scheme != "https"
        or parsed.hostname != "github.com"
        or not parsed.path.startswith(f"/{REPOSITORY}/releases/download/")
    ):
        raise ValueError(f"asset has an unexpected download URL: {url!r}")

    request = Request(url, headers={"User-Agent": "KiyanOS-release-puller/1.0"})
    total = 0
    with urlopen(request, timeout=90) as response:
        final_host = urlparse(response.geturl()).hostname
        if final_host not in ALLOWED_DOWNLOAD_HOSTS:
            raise ValueError(f"asset redirected to an unexpected host: {final_host!r}")
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            if output is None:
                destination.write(block)
            else:
                output.write(block)
            total += len(block)

    declared_size = asset.get("size")
    if isinstance(declared_size, int) and total != declared_size:
        raise ValueError(f"asset size mismatch for {asset.get('name')}: {total} != {declared_size}")
    return total


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    output_dir = Path(os.environ.get("KIYAN_OUTPUT_DIR", "/home/ubuntu/mac_shared"))
    state_dir = Path(os.environ.get("STATE_DIRECTORY", "/var/lib/kiyan-os-pull"))
    state_file = state_dir / "current-release"
    final_iso = output_dir / ISO_NAME
    final_checksum = output_dir / CHECKSUM_NAME
    final_bundle = output_dir / BUNDLE_NAME
    public_key = Path("/etc/kiyan-os/cosign.pub")
    cosign = Path("/home/ubuntu/.local/bin/cosign")

    output_dir.mkdir(parents=True, exist_ok=True)
    state_dir.mkdir(parents=True, exist_ok=True)
    release = fetch_json()
    if release is None:
        return 0

    tag = release.get("tag_name", "")
    assets = validate_assets(release)
    if (
        state_file.exists()
        and state_file.read_text(encoding="utf-8").strip() == tag
        and final_iso.is_file()
        and final_checksum.is_file()
        and final_bundle.is_file()
    ):
        log(f"already installed {tag}")
        return 0
    if not public_key.is_file() or not cosign.is_file():
        raise FileNotFoundError("the pinned Cosign public key or local Cosign binary is missing")

    stage = Path(tempfile.mkdtemp(prefix=".kiyan-release-", dir=output_dir))
    try:
        stage_checksum = stage / CHECKSUM_NAME
        stage_bundle = stage / BUNDLE_NAME
        with stage_checksum.open("wb") as checksum_output:
            download(assets[0], checksum_output)
            checksum_output.flush()
            os.fsync(checksum_output.fileno())
        with stage_bundle.open("wb") as bundle_output:
            download(assets[1], bundle_output)
            bundle_output.flush()
            os.fsync(bundle_output.fileno())

        stage_iso = stage / ISO_NAME
        with stage_iso.open("wb") as combined:
            for part in assets[2:]:
                count = download(part, None, output=combined)
                log(f"downloaded {part['name']} ({count} bytes)")
            combined.flush()
            os.fsync(combined.fileno())

        checksum_text = stage_checksum.read_text(encoding="ascii").strip()
        match = re.fullmatch(r"([0-9a-fA-F]{64})\s+\*?" + re.escape(ISO_NAME), checksum_text)
        if not match:
            raise ValueError("release checksum file has an unexpected format")
        actual_digest = sha256(stage_iso)
        if actual_digest.lower() != match.group(1).lower():
            raise ValueError("reassembled ISO does not match the release SHA-256")

        subprocess.run(
            [
                str(cosign),
                "verify-blob",
                "--bundle",
                str(stage_bundle),
                "--key",
                str(public_key),
                str(stage_iso),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        for path in (stage_iso, stage_checksum, stage_bundle):
            path.chmod(0o644)
        # Publish the supporting files first and replace the ISO last, so the
        # final ISO path is the commit point consumers can check for updates.
        os.replace(stage_checksum, final_checksum)
        os.replace(stage_bundle, final_bundle)
        os.replace(stage_iso, final_iso)

        temporary_state = state_dir / ".current-release.new"
        temporary_state.write_text(tag + "\n", encoding="ascii")
        temporary_state.chmod(0o640)
        os.replace(temporary_state, state_file)
        log(f"installed and verified {tag}; SHA-256 {actual_digest}")
        return 0
    finally:
        shutil.rmtree(stage, ignore_errors=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (HTTPError, URLError, OSError, ValueError, subprocess.CalledProcessError) as exc:
        log(f"failed: {exc}")
        if isinstance(exc, subprocess.CalledProcessError):
            detail = (exc.stderr or exc.stdout or "").strip()
            if detail:
                log(f"verification command output: {detail}")
        raise SystemExit(1)
