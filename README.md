# Kiyan OS (LB1 — Let's Be One)

Kiyan OS is a BlueBuild-derived, bootc-based KDE image. Phase 1 publishes the OCI image to GHCR, builds a hybrid bootable ISO, signs the image and ISO, and publishes the ISO assets as a public GitHub Release. The German VPS pulls and verifies the release over HTTPS; no SSH private key is needed by GitHub Actions.

## Architecture

- Base: `ghcr.io/ublue-os/bazzite:stable` (Bazzite's KDE image; the old `bazzite-kde` name is not used).
- Image updates: switch to `ghcr.io/manmojt/kiyan-os:latest` with `bootc switch`. BlueBuild rechunking is enabled to help reduce repeat downloads; it does not guarantee byte-level delta updates for every change.
- ISO: built with osbuild Bootc Image Builder's Anaconda ISO target. Its runner-local input copy reports `ID=fedora` so BIB selects Fedora's RPM repositories; the install kickstart switches the installed system to the signed, public `ghcr.io/manmojt/kiyan-os:latest` image, whose identity remains `ID=kiyan`. Fedora's signed shim and GRUB EFI packages provide UEFI Secure Boot, plus x86 GRUB BIOS support. CI inspects the El Torito boot entries and the signed UEFI shim before publishing; Secure Boot applies to UEFI only.
- Updates to the VPS: Actions publishes a versioned release. A local systemd timer on the VPS polls the public release, downloads its split ISO assets, verifies the SHA-256 and Cosign Sigstore bundle, then replaces `/home/ubuntu/mac_shared/Kiyan-OS-LB1-x86_64.iso`.

## Signing keys

The Cosign image/ISO keypair is persistent. `cosign.pub` is public and committed. The passwordless `cosign.key` is a signing secret: its local copy has mode `0600`, is excluded by `.gitignore`, and its contents are stored as the GitHub Actions secret `SIGNING_SECRET`. The ISO is published with a Cosign Sigstore bundle and verified against the committed public key on the VPS.

GitHub encrypts Actions secrets at rest, but the workflow can read a secret when it explicitly passes it to an action or command. Anyone with write access to this repository can change a workflow to use repository secrets, so restrict write access and review workflow changes. The SSH key for the VPS is not stored in GitHub or used by this deployment.

The RSA-4096 Kiyan OS root CA is separate from the Cosign key. Its public certificate is shipped at `/usr/share/kiyan/kiyan-os-root-ca.pem`; its private key stays outside this repository under the operator's private local data directory. The certificate alone does not enforce authenticity: Kiyan Store and package clients must verify signatures against it.

## Build and install

The workflow runs on `push` to `main` and `workflow_dispatch`. Pushes that change `recipes/**`, `files/**`, or `cosign.pub` rebuild the image before the ISO; ISO-only, deploy, and documentation changes reuse the existing signed `latest` image. To choose manually, dispatch with `build_image=false`, for example `gh workflow run build-kiyan-os.yml -f build_image=false`; the ISO job verifies the OCI signature before using that image. It uses x86_64 `ubuntu-latest` hosted runners for both image and ISO builds. The only Actions secret required for signing is `SIGNING_SECRET`; the workflow uses its scoped `GITHUB_TOKEN` for GHCR and release publication.

To install the VPS pull timer, run `sudo ./deploy/install-puller.sh` on the VPS. It installs a root-owned polling script and systemd service/timer that runs as `ubuntu`, reads public GitHub release assets, and writes only to `/home/ubuntu/mac_shared/`. The puller never executes downloaded ISO contents.

## Hardware notes

The requested Intel i915 and Intel DSP kernel arguments are included for the target MateBook class of hardware. On other machines they may be ignored or need adjustment. Huawei I2C modules are requested in the initramfs and loaded by a small periodic recovery unit. Package builds validate the Fedora/Bazzite package names and repository availability.

Persian XKB layout is `ir` (the XKB country/layout code), available alongside `us` with Alt+Shift switching. The default system locale remains `en_US.UTF-8`; Vazirmatn is added through BlueBuild's Google Fonts module.

## Phase 4 & 5: Kiyan native suite, Store, and OTA

`recipes/recipe.yml` installs Firefox, LibreOffice headless, and the existing media/archive dependencies, then the `files` module copies the following image paths into place:

| Component | Executables and integration files |
| --- | --- |
| Downloader | `/usr/bin/kiyan-downloader`, `/usr/share/applications/kiyan-downloader.desktop` |
| Converter | `/usr/bin/kiyan-converter`, `/usr/share/applications/kiyan-converter.desktop`, `/usr/share/kio/servicemenus/kiyan-converter.desktop` |
| Extractor | `/usr/bin/kiyan-extractor`, `/usr/share/applications/kiyan-extractor.desktop` |
| Player | `/usr/bin/kiyan-player`, `/usr/share/applications/kiyan-player.desktop` |
| Browser | `/usr/bin/kiyan-browser`, `/usr/bin/kiyan-browser-sync`, `/usr/lib64/firefox/distribution/policies.json`, `/usr/share/kiyan/browser/newtab.html`, and the `kiyan-browser-sync` user service/timer |
| Store | `/usr/bin/kiyan-store`, `/usr/share/applications/kiyan-store.desktop` |
| OTA and deployment switcher | `/usr/bin/kiyan-ota`, `/usr/bin/kiyan-timemachine`, `/usr/share/applications/kiyan-ota.desktop` |

The downloader probes URLs with `yt-dlp` and uses `aria2c` with 32 connections for other downloads. The player uses mpv's Vulkan output, dynamic normalization capped at 9.5 dB (about 3× amplitude), a 10-band EQ, and primary/secondary subtitles. Persian subtitles are copied to a UTF-8 sidecar when CP1256 decoding is needed. The extractor uses `unrar`, `7z`, Python zip/tar support, rejects unsafe zip paths, and repairs CP437-decoded CP1256 names without overwriting existing files. The converter runs locally with ffmpeg, heif-convert, or LibreOffice.

Firefox policies enable its built-in tracking protection and install uBlock Origin. The speed dial labels any feed tiles and shopping offer as sponsored; it does not set, read, or stuff cookies. Sync runs on a 24-hour user timer but does nothing until `smart_shopping_opt_in` is set to `true` in `~/.config/kiyan/browser.json`. The expected HTTPS JSON feed is configurable there and defaults to `https://92.5.113.35/kiyan/v1/tiles.json`; the server must present a certificate valid for that IP address. The response schema is `{"tiles":[{"title":"…","url":"https://…"}],"smart_shopping":{"title":"…","url":"https://…"}}`. A search partner URL can be set with `search_url` in the same file; an empty value uses the browser page's default search destination. No search partner or feed API contract was provided, so these defaults are integration points rather than a claim that a partner service is live.

Kiyan packages are `.kpk` tar archives containing `manifest.json`, detached DER CMS signature `manifest.p7s`, and `payload/`. The signed manifest has a safe `name`, a `files` mapping of relative paths to SHA-256 hashes, and an optional `executables` array naming files to install executable. The installer verifies the signature against `/usr/share/kiyan/kiyan-os-root-ca.pem`, checks hashes and archive paths, asks before installation, and copies files beneath `/var/lib/kiyan/packages/`; it does not execute package scripts. This is a signed payload installer, not a package registry or dependency resolver. Flatpak and Distrobox installs also require user confirmation. Windows installers require confirmation and use an available WinBoat CLI or the user's Proton installation.

OTA upgrades stage a bootc update (or rpm-ostree update fallback) and leave the current deployment available as the rollback point. `kiyan-timemachine` and the rollback action queue the previous deployment as the next boot default; switching takes effect after reboot. OSTree retains the prior deployment rather than making a separate filesystem snapshot, and the platform may prune older deployments.
