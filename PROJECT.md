# Project: KIAN-OS v3 Production Specification & Build Automation

## Architecture
KIAN-OS v3 is a clean-slate hybrid operating system based on Ubuntu 24.04 LTS (Noble Numbat) and the custom `linux-kian v3` kernel. It unifies:
1. Mobile-class power efficiency via BORE scheduler, 1000Hz timer, NO_HZ_IDLE, and Wayland foreground surface prioritization.
2. Desktop gaming performance via in-kernel Valve Fsync (futex_waitv), Elizabeth Figura's NTSync driver (/dev/ntsync), PE/COFF MZ binfmt_misc handler, split-lock mitigation disablement, and Wayland explicit sync (linux-drm-syncobj-v1).
3. Broad hardware support for Microsoft Surface (SAM, IPTS/ITHC, Surface Pen), Intel IPU6 cameras (OVTI5693, D-PHY timeout patch, libcamera SoftISP + v4l2loopback), Apple Intel Mac SPI (Force Touch trackpad/keyboard), and Broadcom BCM43xx non-free firmware.
4. Cryptographic immutability and recovery via Btrfs root subvolumes (@rootfs, @snapshots, @home, @log, @cache, @crash), automated pre/post APT and boot snapshots, GRUB rollback menu with ephemeral OverlayFS fallback, 4096-bit RSA MOK Secure Boot signing, and dual-kernel watchdog fallback (linux-kian v3 paired with stock linux-image-generic).
5. 100% pure Wayland user-space with KWin compositor, SDDM Wayland greeter, strict X11 elimination, and Triple-Shell Interface Engine (Kian Native, Windows 11 Fluent, macOS Aqua) featuring zero-reboot switching (<450ms).
6. High-fidelity subpixel font rendering with Inter Display and Vazirmatn font stacks.
7. Calamares graphical installer with automated Btrfs partitioning, pre-install hardware probe, silent `ubuntu-drivers autoinstall` during partition extraction, and live session cleanup.
8. Cross-platform local P2P sync and clipboard synchronization across iOS, Android, macOS, and Windows without internet dependencies.
9. Modular 5-phase automated build pipeline generating a bootable hybrid ISO from clean-slate debootstrap.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Baseline Kernel (Linux 6.8 / 6.11 HWE) | Target Ubuntu Noble LTS kernel tree with dual baseline support | M1, M2 | Survey 1 |
| 2 | BORE CPU Scheduler & Preemption | Burst-Oriented Response Enhancer with PREEMPT_DYNAMIC/FULL | M1, M2 | Survey 1 |
| 3 | 1000Hz Timer & Low Latency | CONFIG_HZ_1000=y and Wayland foreground surface task priority | M1, M2 | Survey 1 |
| 4 | Windows Gaming Runtime (Fsync & NTSync) | Valve futex_waitv & in-kernel /dev/ntsync character device driver | M1, M2 | Survey 1 |
| 5 | PE/COFF MZ binfmt_misc Handler | Direct kernel-level dispatch of Windows binaries to Wine/Proton | M1, M2 | Survey 1 |
| 6 | Split-Lock Mitigation Override | Disable artificial 10ms thread penalties for Windows games | M1, M2 | Survey 1 |
| 7 | Microarchitecture & Compiler Optimization | x86-64-v3 ISA baseline and Clang ThinLTO compilation pipeline | M1, M2 | Survey 1 |
| 8 | Surface SAM & IPTS/ITHC Integration | Surface EC aggregator, multitouch, and active Pen digitizer | M1, M2 | Survey 1 |
| 9 | Intel IPU6 Camera Pipeline | OVTI5693 ACPI sensor, D-PHY settle patch, libcamera SoftISP, v4l2loopback | M1, M2 | Survey 1 |
| 10 | Apple Intel Mac SPI Driver | applespi, intel_lpss_pci, spi_pxa2xx_platform & Force Touch LRA | M1, M2 | Survey 1 |
| 11 | Broadcom BCM43xx Firmware | Embedding non-free Broadcom wireless firmware | M1, M2 | Survey 1 |
| 12 | Google BBRv3 Transport | BBRv3 congestion control with FQ packet pacing | M1, M2 | Survey 1 |
| 13 | DRM/KMS 10-bit Deep Color & HDR/VRR | BT.2020 / DCI-P3 color spaces, FreeSync / G-Sync interfaces | M1, M2 | Survey 1 |
| 14 | Wayland Explicit Sync | linux-drm-syncobj-v1 and DRM timeline points for NVIDIA & AMD RADV | M1, M2 | Survey 1 |
| 15 | Btrfs Read-Only Subvolumes & Layout | Flat layout: @rootfs, @snapshots, @home, @log, @cache, @crash | M1, M4 | Survey 3 |
| 16 | Atomic Boot & Package Snapshots | Snapper integration and custom DPkg APT transaction hooks | M1, M4 | Survey 3 |
| 17 | GRUB Snapshot Rollback & OverlayFS | Dynamic GRUB menu with ephemeral tmpfs overlay fallback | M1, M4 | Survey 3 |
| 18 | Secure Boot MOK Signing Infrastructure | 4096-bit RSA MOK keypair, sbsign, shimx64.efi integration | M1, M4 | Survey 3 |
| 19 | Dual-Kernel Fallback & Watchdog | linux-kian primary + stock generic fallback with bootcounter | M1, M4 | Survey 3 |
| 20 | 100% Pure Wayland Session | SDDM Wayland greeter, kwin_wayland, strict X11 purge | M1, M3 | Survey 2 |
| 21 | Triple-Shell Interface Engine | Zero-reboot switching: Kian Native, Windows 11 Fluent, macOS Aqua | M1, M3 | Survey 2 |
| 22 | Subpixel Font Rendering & Stacks | Fontconfig configuration for Inter Display & Vazirmatn | M1, M3 | Survey 2 |
| 23 | Calamares Graphical Installer | Pre-install probe, Btrfs subvolumes, ubuntu-drivers autoinstall, live cleanup | M1, M3 | Survey 2 |
| 24 | Cross-Platform Local P2P Sync | Dual-engine: KDE Connect clipboard + LocalSend offline transfer | M1, M3 | Survey 2 |
| 25 | Patch Compatibility Matrix & Conflict Fixes | Formal analysis of BORE, NTSync, Fsync, IPTS, IPU6, BBRv3 against 6.8/6.11 | M1, M2 | Survey 1 |
| 26 | Performance & Latency Assessment | Quantitative evaluation of scheduling, timer, and compiler impact | M1, M2 | Survey 1 |
| 27 | Failure Mode & Security Analysis | Btrfs ENOSPC reserve, metadata DUP, MOK trust boundary | M1, M4 | Survey 3 |
| 28 | Modular Automated Build Pipeline | 5-phase scripts: common, kernel, rootfs, desktop, iso, verify | M4 | Survey 3 |
| 29 | E2E Testing & Verification Suite | Syntax validation, linting, configuration parsing, integration test harness | M5 | Track 2 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Production Architecture & Specification | Master technical deliberation document covering R1-R4 (`docs/KIAN_OS_V3_PRODUCTION_SPECIFICATION.md`) | Survey Complete | COMPLETE |
| M2 | Kernel Patch Compatibility & Config Package | Detailed compatibility matrix, patch recipes, and complete `linux-kian v3` `.config` (`kernel/`) | M1 | IN_PROGRESS |
| M3 | User-Space, Triple-Shell & Calamares Recipes | KWin Wayland configs, `kian-shell-switcher`, fontconfig, Calamares module pipeline, and P2P sync configs (`desktop/`, `installer/`) | M1 | IN_PROGRESS |
| M4 | Automated Build Scripts Suite | Production-grade modular build scripts (`01_build_kernel.sh`, `02_bootstrap_rootfs.sh`, `03_customize_desktop.sh`, `04_build_iso.sh`, `05_verify_iso.sh`, `build_all.sh`) and rollback engine (`scripts/`, `build/`) | M2, M3 | PLANNED |
| M5 | E2E Verification, Challenger Stress Test & Forensic Audit | Test runner, static analysis, shell syntax validation, configuration assertions, reviewer reviews, challenger testing, and forensic audit (`tests/`) | M4 | PLANNED |

## Code Layout
```
~/teamwork_projects/kian_os_v3/
├── docs/
│   ├── KIAN_OS_V3_PRODUCTION_SPECIFICATION.md   # Comprehensive production specification (R1-R4)
│   └── ARCHITECTURE_OVERVIEW.md                  # High-level subsystem design
├── kernel/
│   ├── PATCH_COMPATIBILITY_MATRIX.md             # Formal compatibility & conflict resolution matrix
│   ├── config-6.8-kian-v3                        # Complete production kernel .config (62+ explicit symbols)
│   └── patches/                                  # Canonical patch definitions & conflict resolutions
│       ├── 0001-sched-bore-noble.patch
│       ├── 0002-drivers-misc-ntsync.patch
│       ├── 0003-drivers-media-ipu6-dphy-settle.patch
│       ├── 0004-drivers-media-ov5693-acpi-hid.patch
│       └── 0005-net-ipv4-tcp-bbrv3.patch
├── desktop/
│   ├── sddm/
│   │   └── sddm.conf.d/wayland.conf              # Pure Wayland SDDM greeter configuration
│   ├── triple-shell/
│   │   ├── kian-shell-switcher                   # Zero-reboot shell switcher CLI/DBus script
│   │   ├── layouts/                              # Plasma panel & look-and-feel templates
│   │   │   ├── kian-native.js
│   │   │   ├── windows-fluent.js
│   │   │   └── macos-aqua.js
│   │   └── kvantum/
│   │       └── KianGlass/KianGlass.kvconfig      # Glassmorphic dark crystal theme
│   ├── fonts/
│   │   └── 50-kian-subpixel-typography.conf      # Inter Display + Vazirmatn fontconfig
│   └── sync/
│       ├── localsend.service                     # Offline P2P transfer daemon
│       └── kdeconnect-clipboard.service          # Offline clipboard sync daemon
├── installer/
│   └── calamares/
│       ├── settings.conf                         # Calamares module sequence
│       ├── modules/
│       │   ├── partition.conf                    # Btrfs automated subvolume layout
│       │   ├── unpackfs.conf
│       │   └── packages.conf
│       └── hooks/
│           ├── pre-install-probe.sh              # Hardware detection hook
│           └── post-install-drivers-and-clean.sh # ubuntu-drivers autoinstall & live artifact purge
├── scripts/
│   ├── kian-rollback                             # Btrfs rollback CLI engine
│   ├── btrfs-apt-hook                            # Pre/Post APT atomic snapshot hook
│   ├── 41_kian_snapshots                         # Dynamic GRUB snapshot menu generator
│   └── kian-boot-success.service                 # Dual-kernel watchdog bootcounter service
├── build/
│   ├── common.sh                                 # Shared variables, logging, dependency validation
│   ├── 01_build_kernel.sh                        # Kernel source fetch, patch application, and bindeb-pkg
│   ├── 02_bootstrap_rootfs.sh                    # Clean-slate Ubuntu 24.04 LTS Noble debootstrap
│   ├── 03_customize_desktop.sh                   # Desktop, SDDM, Triple-Shell, fonts, installer staging
│   ├── 04_build_iso.sh                           # Live squashfs compression, EFI/BIOS hybrid xorriso ISO
│   ├── 05_verify_iso.sh                          # ISO integrity check, bootloader inspection, checksums
│   └── build_all.sh                              # Master end-to-end automation pipeline
└── tests/
    ├── run_all_tests.sh                          # E2E test suite runner
    ├── test_shell_syntax.sh                      # bash -n validation of all scripts
    ├── test_kernel_config.sh                     # CONFIG_* symbol verification
    ├── test_calamares_configs.sh                 # Calamares syntax & module check
    ├── test_fontconfig.sh                        # XML validity of fontconfig
    └── test_btrfs_rollback_logic.sh              # Mock test of rollback & GRUB menu generator
```

## Interface Contracts
### Kernel ↔ Userspace
- Character device: `/dev/ntsync` (mode 0666) provides in-kernel NT sync primitives for Wine/Proton.
- Sysctl: `kernel.sched_bore = 1`, `kernel.split_lock_mitigate = 0`, `net.ipv4.tcp_congestion_control = bbr`.
- binfmt_misc: `/proc/sys/fs/binfmt_misc/register` binds PE/COFF MZ signatures (`MZ` header 0x4D 0x5A) to `/usr/bin/kian-wine-launcher`.
- DRM syncobj: `linux-drm-syncobj-v1` Wayland protocol points to DRM timeline syncobjs.

### Shell Switcher ↔ Plasma & KWin
- DBus: `org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript` loads dynamic layout scripts.
- DBus: `org.kde.KWin /KWin org.kde.KWin.reconfigure` forces immediate live window decoration refresh.
- CLI: `kian-shell-switcher --theme [native|fluent|aqua]` validates input and executes hot-swap in $<450\text{ms}$.

### Installer ↔ Target Disk
- Filesystem: Btrfs formatted with `-m dup -d single`.
- Subvolumes: `@rootfs` (/), `@snapshots` (/.snapshots), `@home` (/home), `@log` (/var/log), `@cache` (/var/cache), `@crash` (/var/crash). `/var/lib/dpkg` stays inside `@rootfs`.
- Driver scan: `chroot ${ROOT} ubuntu-drivers autoinstall` during post-partition extraction.
