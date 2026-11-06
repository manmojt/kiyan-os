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

The workflow runs on `push` to `main` and `workflow_dispatch`. It uses x86_64 `ubuntu-latest` hosted runners for both image and ISO builds. The only Actions secret required for signing is `SIGNING_SECRET`; the workflow uses its scoped `GITHUB_TOKEN` for GHCR and release publication.

To install the VPS pull timer, run `sudo ./deploy/install-puller.sh` on the VPS. It installs a root-owned polling script and systemd service/timer that runs as `ubuntu`, reads public GitHub release assets, and writes only to `/home/ubuntu/mac_shared/`. The puller never executes downloaded ISO contents.

## Hardware notes

The requested Intel i915 and Intel DSP kernel arguments are included for the target MateBook class of hardware. On other machines they may be ignored or need adjustment. Huawei I2C modules are requested in the initramfs and loaded by a small periodic recovery unit. Package builds validate the Fedora/Bazzite package names and repository availability.

Persian XKB layout is `ir` (the XKB country/layout code), available alongside `us` with Alt+Shift switching. The default system locale remains `en_US.UTF-8`; Vazirmatn is added through BlueBuild's Google Fonts module.
