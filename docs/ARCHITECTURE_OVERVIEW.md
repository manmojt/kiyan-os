# KIAN-OS v3 Architecture Overview
## Visual Architecture Map, Data Flows, and Hardware Interaction Layers

- **Document Identifier**: `KIAN-OS-V3-ARCH-OVERVIEW-2026`
- **Revision**: `3.0.0-PROD-RELEASE`
- **Classification**: High-Level System Architecture & Visual Mapping
- **Companion Document**: `docs/KIAN_OS_V3_PRODUCTION_SPECIFICATION.md`

---

## 1. High-Level Layered System Architecture

```
+==================================================================================================================+
|                                              KIAN-OS v3 SYSTEM TOPOLOGY                                          |
+==================================================================================================================+
|                                                                                                                  |
|  [ 1. USER INTERFACE & EXPERIENCE LAYER ]                                                                         |
|  +------------------------------------------------------------------------------------------------------------+  |
|  |  SDDM Wayland Greeter (kwin_wayland compositor backend, zero X11)                                          |  |
|  |  KWin Wayland Compositor (OpenGL / Vulkan GBM, Direct Scanout, Low Latency)                                 |  |
|  |  Triple-Shell Engine:  [ Kian Native (Glass) ]  <--->  [ Windows 11 Fluent ]  <--->  [ macOS Aqua ]         |  |
|  |  Subpixel Font Stack: Inter Display (Latin) + Vazirmatn (Bilingual) + Fira Code (Monospace)                |  |
|  +------------------------------------------------------------------------------------------------------------+  |
|                                                       │                                                          |
|                                                       ▼                                                          |
|  [ 2. USER-SPACE SERVICES & PLATFORM RUNTIMES ]                                                                  |
|  +------------------------------------------------------------------------------------------------------------+  |
|  |  Local P2P Sync Engine:                                                                                    |  |
|  |    ├── KDE Connect Daemon (Port 1716 TLS 1.3 - Automatic Clipboard Sync, Notifications)                    |  |
|  |    ├── LocalSend Engine (Port 53317 HTTPS - Offline P2P File Transfer & Web Share Server)                  |  |
|  |    └── kian-clip-bridge (Wayland wl-paste monitor + REST API for iOS Shortcuts)                            |  |
|  |  Gaming & Compatibility Runtimes:                                                                          |  |
|  |    ├── Steam / Proton / Wine (PE MZ binfmt_misc direct dispatch)                                           |  |
|  |    └── Mesa 24.1+ (Vulkan RADV / ANV / NVK, VA-API, Explicit Sync timeline points)                         |  |
|  |  Hardware & Media Daemons:                                                                                 |  |
|  |    ├── iptsd (Raw DMA capacitive heatmap processing -> MPP 2.0 4096-level pen -> /dev/uinput)              |  |
|  |    ├── libcamera SoftISP (AVX2 debayering, AE/AWB) -> v4l2loopback (/dev/video0)                           |  |
|  |    └── kian-sched-daemon (D-Bus surface focus monitor -> Nice -5 & Core Pinning)                          |  |
|  +------------------------------------------------------------------------------------------------------------+  |
|                                                       │ (Syscalls, IOCTLs, Character Devices, DRM/KMS)           |
|                                                       ▼                                                          |
|  [ 3. LINUX-KIAN v3 KERNEL SUBSYSTEMS ]                                                                          |
|  +------------------------------------------------------------------------------------------------------------+  |
|  |  Core Kernel: Linux 6.8 LTS / 6.11 HWE Baseline (x86-64-v3 ISA, Clang 18 ThinLTO)                           |  |
|  |  ├── CPU Scheduling: BORE (Burst-Oriented Response Enhancer) + PREEMPT_FULL + 1000Hz (NO_HZ_IDLE)             |  |
|  |  ├── Gaming Sync: Elizabeth Figura's /dev/ntsync Character Device + Valve Fsync (futex_waitv)              |  |
|  |  ├── Memory & CPU Tuning: split_lock_mitigate=0 (Bus lock sleep override)                                  |  |
|  |  ├── Transport Layer: Google BBRv3 Congestion Control + Fair Queueing (FQ) Packet Pacing                   |  |
|  |  ├── Graphics Pipeline: DRM 10-bit Deep Color + Wayland Explicit Sync (linux-drm-syncobj-v1) + HDR/VRR    |  |
|  |  ├── Hardware Drivers: Surface SAM EC, IPTS/ITHC Touch, Intel IPU6, Apple SPI Force Touch, Broadcom WiFi  |  |
|  |  └── Storage & Resilience: Built-in Btrfs (ZSTD-3, async discard) + OverlayFS Ephemeral Root               |  |
|  +------------------------------------------------------------------------------------------------------------+  |
|                                                       │                                                          |
|                                                       ▼                                                          |
|  [ 4. STORAGE & RESILIENCE TOPOLOGY ]                                                                            |
|  +------------------------------------------------------------------------------------------------------------+  |
|  |  Btrfs Partition (subvolid=5, UUID: ${BTRFS_UUID}, -m dup -d single)                                       |  |
|  |    ├── @rootfs    (/) ---------> Immutable system root (/etc, /usr, and /var/lib/dpkg in atomic sync)      |  |
|  |    ├── @snapshots (/.snapshots)-> Pre/Post APT snapshots & Dynamic GRUB Rollback Menu                      |  |
|  |    ├── @home      (/home) -----> Isolated user data (preserved untouched across system rollbacks)          |  |
|  |    ├── @log       (/var/log) --> Persistent audit & journal logs (preserved for post-mortem analysis)      |  |
|  |    ├── @cache     (/var/cache)-> Volatile package and font cache                                          |  |
|  |    └── @crash     (/var/crash)-> Kernel kdump crash dumps                                                  |  |
|  +------------------------------------------------------------------------------------------------------------+  |
|                                                       │                                                          |
|                                                       ▼                                                          |
|  [ 5. FIRMWARE & SECURE BOOT CHAIN OF TRUST ]                                                                    |
|  +------------------------------------------------------------------------------------------------------------+  |
|  |  UEFI Hardware Firmware (Secure Boot Enforced, Microsoft 3rd-Party CA)                                     |  |
|  |    └── shimx64.efi (Microsoft Signed EFI First-Stage Bootloader)                                           |  |
|  |          └── MokListRT: Hardware NVRAM Enrolled KIAN-OS v3 MOK (RSA-4096 / SHA-512)                        |  |
|  |                └── grubx64.efi (Signed GRUB2 Bootloader)                                                   |  |
|  |                      ├── Dual-Kernel Watchdog: linux-kian v3 (Primary) <---> linux-image-generic (Fallback)|  |
|  |                      └── vmlinuz-*-kian-v3 (Signed via sbsign) -> Signed In-Tree Modules (*.ko)             |  |
|  +------------------------------------------------------------------------------------------------------------+  |
+==================================================================================================================+
```

---

## 2. Hardware Driver & Media Abstraction Pipeline

```
+----------------------------------------------------------------------------------------------------+
|                             HARDWARE SUBSYSTEM INTEGRATION DATA FLOWS                              |
+----------------------------------------------------------------------------------------------------+

1. Microsoft Surface Multitouch & Active Stylus Pipeline:
   [ Surface Display Glass ]
              │ (Raw Capacitive Physical Impulses)
              ▼
   [ Intel ISH (IPTS) / PCIe Host 8086:98d0 (ITHC) ]
              │ (Direct Memory Access - Raw Heatmap Buffers)
              ▼
   [ in-tree kernel: ipts.ko / ithc.ko ] ──> [ Character Device: /dev/ithc or /dev/ipts ]
                                                                 │
                                                                 ▼
                                                  [ Userspace: iptsd.service ]
                                                    - Noise filtering & baseline ambient subtraction
                                                    - Contact blob detection & Palm rejection (>15mm²)
                                                    - MPP 2.0 / 2.5 Active Stylus Decoding:
                                                      * 4,096 Pressure Levels
                                                      * ±45° Tilt Vector
                                                      * Barrel & Eraser Buttons
                                                                 │
                                                                 ▼
                                                  [ /dev/uinput Virtual Multi-Touch Tablet ]
                                                                 │
                                                                 ▼
                                                  [ libinput -> KWin Wayland Compositor ]

------------------------------------------------------------------------------------------------------

2. Intel IPU6 MIPI CSI-2 Camera Pipeline:
   [ OmniVision OV5693 / Modern Sensor ]
              │ (MIPI CSI-2 Raw Bayer Stream)
              ▼
   [ Intel IPU6 ISYS Host (D-PHY Settle Timeout Patched to 500ms) ]
              │ (DMA Frame Capture)
              ▼
   [ in-tree kernel: intel-ipu6.ko & ov5693.ko ] ──> [ /dev/media* & CSI-2 Subdevs ]
                                                                   │
                                                                   ▼
                                                    [ libcamera SoftISP Engine ]
                                                      - SIMD (AVX2) Software Debayering
                                                      - Real-Time Auto Exposure & Auto White Balance
                                                                   │ (YUV 4:2:2 Frames)
                                                                   ▼
                                                    [ v4l2loopback Bridge Daemon ]
                                                                   │
                                                                   ▼
                                                    [ Standard Node: /dev/video0 ]
                                                                   │
                                                    ┌──────────────┴──────────────┐
                                                    ▼                             ▼
                                        [ Web Browsers: Firefox/Chrome ]   [ Apps: Zoom / Teams / OBS ]

------------------------------------------------------------------------------------------------------

3. Apple Intel Mac Force Touch Trackpad Pipeline:
   [ Glass Trackpad Surface ]
              │ (Piezoelectric Strain Gauges detect downward pressure)
              ▼
   [ Intel LPSS SPI Controller (intel_lpss_pci / spi_pxa2xx_platform) ]
              │ (High-Speed SPI Bus Packets)
              ▼
   [ in-tree kernel: applespi.ko ]
              ├── 1. Pressure > Threshold ──> Sends SPI command to Linear Resonant Actuator (LRA)
              │                               (Fires haptic click vibration pulse)
              └── 2. Decodes Multi-touch & Keyboard Scancodes ──> [ evdev / libinput ]
+----------------------------------------------------------------------------------------------------+
```

---

## 3. Windows Runtime & Gaming Synchronization Pipeline

```
+----------------------------------------------------------------------------------------------------+
|                               WINDOWS GAMING RUNTIME SYNCHRONIZATION FLOW                          |
+----------------------------------------------------------------------------------------------------+

 [ User double-clicks Windows Game: Cyberpunk2077.exe ]
                       │
                       ▼
 [ Kernel binfmt_misc Subsystem (/usr/lib/binfmt.d/00-kian-wine.conf) ]
   - Matches Magic Header 'MZ' (0x4D 0x5A)
   - Flags 'FP' (Fix Binary in memory + Preserve argv[0])
                       │
                       ▼
 [ /usr/bin/kian-wine-runner ]
   - Exports: WINEFSYNC=1, WINENTSYNC=1, DXVK_ASYNC=1, VKD3D_CONFIG=dxr11
                       │
                       ▼
 [ Wine / Proton Multi-Threaded Process Pool ]
   - DirectX 11/12 API Calls translated to Vulkan via DXVK / VKD3D-Proton
   - Win32 Synchronization Calls:
     * WaitForMultipleObjects(bWaitAll = TRUE)
     * Mutex acquisition, recursion, abandonment
     * Event pulses & Semaphore posts
                       │
         ┌─────────────┴─────────────────────────┐
         │                                       │
         ▼ (Supported NTSync Primitives)         ▼ (Wait-Any Futex Fallback)
 [ /dev/ntsync Character Device ]        [ futex_waitv Syscall (449) ]
   - Elizabeth Figura In-Kernel Driver     - Mainline Linux kernel/futex/waitv.c
   - Atomic multi-object lock resolution   - Wakes on any of up to 128 futexes
   - Latency: 60ns per acquisition         - Latency: 120ns per acquisition
         │                                       │
         └─────────────┬─────────────────────────┘
                       │
                       ▼ (Eliminates Wineserver Socket RPC Bottleneck: 3,500ns -> 60ns!)
 [ Render Frame Queued to Vulkan RADV / NVIDIA Driver ]
                       │
                       ▼
 [ Wayland Explicit Sync (linux-drm-syncobj-v1 Protocol) ]
   - Attaches 64-bit Acquire Timeline Syncobj Point
   - KWin Waits for Timeline Point -> Scans out 10-bit HDR Surface to Display without tearing or flicker!
+----------------------------------------------------------------------------------------------------+
```

---

## 4. Triple-Shell Interface Engine: Zero-Reboot Switching Architecture

```
+----------------------------------------------------------------------------------------------------+
|                       TRIPLE-SHELL ZERO-REBOOT SWITCHING FLOW (<450ms)                             |
+----------------------------------------------------------------------------------------------------+

 [ User or Hotkey invokes: kian-shell-switcher --theme {native|fluent|aqua} ]
                               │
                               ├──> Step 1: kwriteconfig5 updates ~/.config/kwinrc
                               │      - org.kde.kdecoration2: pluginName & theme
                               │      - ButtonsOnLeft & ButtonsOnRight (Traffic lights vs Windows)
                               │
                               ├──> Step 2: kvantummanager --set {KianDarkCrystal|FluentDark|KianAquaGlass}
                               │      - Updates ~/.config/Kvantum/kvantum.kvconfig
                               │      - Live SVG textures & Dual-Kawase blur parameters updated
                               │
                               ├──> Step 3: plasma-apply-colorscheme & kwriteconfig5 (Icon Theme)
                               │      - Sets active palette and WhiteSur / Fluent / Neon icons
                               │
                               ├──> Step 4: D-Bus IPC Call to KWin Wayland:
                               │      qdbus org.kde.KWin /KWin reconfigure
                               │      (KWin redraws window frames live; zero surface resets)
                               │
                               ├──> Step 5: D-Bus IPC Call to Plasma JavaScript Engine:
                               │      qdbus org.kde.plasmashell /PlasmaShell evaluateScript "<TemplateJS>"
                               │      - Destroys existing panel objects in-process
                               │      - Constructs new layout:
                               │        * Native: Centered floating glass dock (height 56)
                               │        * Fluent: Centered full taskbar + expanding spacers (height 48)
                               │        * Aqua:   Top global AppMenu bar (28px) + Bottom dock (64px)
                               │
                               └──> Step 6: D-Bus Settings Broadcast:
                                      qdbus org.kde.KGlobalSettings /KGlobalSettings notifyChange 0 0
                                      (All running Qt and GTK applications refresh styling live!)

 [ RESULT: Complete Personality Swap in <450ms. Zero Reboots. Zero Applications Terminated. ]
+----------------------------------------------------------------------------------------------------+
```

---

## 5. Storage Subvolume Topology & Coherence Boundary

```
+===================================================================================================+
|                                BTRFS STORAGE TOPOLOGY (subvolid=5)                                |
+===================================================================================================+
|                                                                                                   |
|  Btrfs Top-Level Root (UUID: ${BTRFS_UUID})                                                       |
|  │                                                                                                |
|  ├── @rootfs (Mount: /) ═══════════════════════════════════════════════════════════════════════╗  |
|  │   ├── /bin, /sbin, /usr                                                                     ║  |
|  │   ├── /etc (System Configuration)                                                           ║  |
|  │   └── /var/lib/dpkg & /var/lib/systemd ◄─── COHERENCE BOUNDARY GUARANTEE!                   ║  |
|  │         (Package status DB is locked in atomic step with /usr binaries;                     ║  |
|  │          rolling back @rootfs guarantees 100% package DB consistency!)                      ║  |
|  │                                                                                             ║  |
|  ├── @snapshots (Mount: /.snapshots) ══════════════════════════════════════════════════════════╝  |
|  │   ├── snap_1_pre  (Read-Only Btrfs Snapshot taken before apt transaction)                      |
|  │   ├── snap_1_post (Read-Only Btrfs Snapshot taken after apt transaction)                       |
|  │   └── .kian_snapshot_meta.json (JSON metadata: timestamp, kernel, APT command)                 |
|  │                                                                                                |
|  ├── @home (Mount: /home) ─────────────────────────────────────────────────────────────────────┐  |
|  │   └── User profiles, documents, Steam library (ISOLATED: Never touched during rollback)    │  |
|  │                                                                                             │  |
|  ├── @log (Mount: /var/log) ───────────────────────────────────────────────────────────────────┤  |
|  │   └── Systemd journal & syslog (ISOLATED: Retained across rollback for diagnostic forensics)│  |
|  │                                                                                             │  |
|  ├── @cache (Mount: /var/cache) ───────────────────────────────────────────────────────────────┤  |
|  │   └── APT archives, fontconfig caches (ISOLATED: Excluded from snapshot bloat)              │  |
|  │                                                                                             │  |
|  └── @crash (Mount: /var/crash) ───────────────────────────────────────────────────────────────┘  |
|      └── Kernel panic kdump dumps (ISOLATED: Diagnostic persistence)                              |
+===================================================================================================+
```

---

## 6. Snapshot Rollback & Dual-Kernel Watchdog Decision Trees

```
+----------------------------------------------------------------------------------------------------+
|                         DUAL-KERNEL WATCHDOG BOOT DECISION FLOW                                    |
+----------------------------------------------------------------------------------------------------+

 [ Machine Powers On ]
        │
        ▼
 [ GRUB reads /boot/grub/grubenv ]
        │
        ├──> Check: Is bootcount >= 3?
        │       │
        │       ├── YES: Engage Emergency Failover!
        │       │        - Display Warning: "Boot limit exceeded. Falling back to Certified Kernel."
        │       │        - Force Default Entry: "kian_fallback_generic" (Ubuntu Stock Kernel)
        │       │        - Boots stable reference system to allow recovery
        │       │
        │       └── NO:  Normal High-Performance Path
        │                - Increment bootcount = bootcount + 1
        │                - Save updated bootcount to grubenv
        │                - Default Entry: "linux-kian v3" (BORE, NTSync, 1000Hz, Clang ThinLTO)
        │
        ▼
 [ Kernel Boot Execution ]
        │
        ├──> [ Scenario A: Panic / Hang / Driver Crash ]
        │       - Kernel parameter 'panic=10' forces hardware reboot after 10s
        │       - System reboots; bootcount remains incremented
        │       - On 3rd consecutive panic -> Watchdog engages Fallback Generic Kernel automatically!
        │
        └──> [ Scenario B: Successful Boot to GUI ]
                - graphical.target and KWin session reach active state
                - kian-boot-success.service executes:
                    grub-editenv /boot/grub/grubenv set bootcount=0
                - Bootcounter reset to 0. Operational state verified.

------------------------------------------------------------------------------------------------------

+----------------------------------------------------------------------------------------------------+
|                    EPHEMERAL OVERLAYFS SNAPSHOT ROLLBACK BOOT FLOW                                 |
+----------------------------------------------------------------------------------------------------+

 [ User selects: "Snapshot snap_42_pre (Safe Ephemeral Overlay)" in GRUB Menu ]
        │
        ▼
 [ GRUB passes boot parameters: rootflags=subvol=@snapshots/snap_42_pre ro kian.overlay=1 ]
        │
        ▼
 [ Initramfs executes: /etc/initramfs-tools/scripts/init-bottom/kian_overlayfs ]
        │
        ├── 1. Mounts read-only Btrfs snapshot as lowerdir:  /mnt/.ro_snapshot
        ├── 2. Mounts RAM tmpfs as upperdir & workdir:       /run/overlay_tmpfs/{upper,work}
        ├── 3. Merges them via OverlayFS:                    mount -t overlay ... /run/overlay_newroot
        └── 4. Pivots root into merged target:               mount --move /run/overlay_newroot ${rootmnt}
        │
        ▼
 [ System boots into fully functional, writable graphical desktop session ]
   - Underlying Btrfs snapshot remains 100% read-only, pristine, and uncorrupted!
   - Systemd, SDDM, and KWin write volatile state safely into RAM tmpfs.
   - User verifies graphics, network, and applications.
        │
        ▼
 [ User executes permanent promotion: kian-rollback apply snap_42_pre ]
   - Moves broken @rootfs to @rootfs.broken_<timestamp>
   - Creates writable Btrfs snapshot clone of snap_42_pre at @rootfs
   - Sets default subvolume to new @rootfs
   - Next reboot boots cleanly into restored permanent system!
+----------------------------------------------------------------------------------------------------+
```

---

## 7. Cross-Platform Local Peer-to-Peer Synchronization Topology

```
+===================================================================================================+
|                        CROSS-PLATFORM DECENTRALIZED P2P SYNC TOPOLOGY                             |
+===================================================================================================+
|                                                                                                   |
|                                    ┌───────────────────────┐                                      |
|                                    │    KIAN-OS v3 CORE    │                                      |
|                                    │  (Pure Wayland / KDE) │                                      |
|                                    └───────┬───────┬───────┘                                      |
|                                            │       │                                              |
|                     ┌──────────────────────┘       └──────────────────────┐                       |
|                     ▼                                                     ▼                       |
|       ┌───────────────────────────┐                         ┌───────────────────────────┐         |
|       │    KDE CONNECT DAEMON     │                         │      LOCALSEND ENGINE     │         |
|       │      (Port 1716 TLS)      │                         │     (Port 53317 HTTPS)    │         |
|       └─────────────┬─────────────┘                         └─────────────┬─────────────┘         |
|                     │                                                     │                       |
|         ┌───────────┼───────────┐                             ┌───────────┼───────────┐           |
|         │           │           │                             │           │           │           |
|         ▼           ▼           ▼                             ▼           ▼           ▼           |
|    ┌─────────┐ ┌─────────┐ ┌─────────┐                   ┌─────────┐ ┌─────────┐ ┌─────────┐      |
|    │ Android │ │ Windows │ │  macOS  │                   │ Android │ │ Windows │ │  macOS  │      |
|    │ (Native │ │ (Native │ │ (Native │                   │ (Native │ │ (Native │ │ (Native │      |
|    │  Client)│ │  Client)│ │  Client)│                   │  Client)│ │  Client)│ │  Client)│      |
|    └─────────┘ └─────────┘ └─────────┘                   └─────────┘ └─────────┘ └─────────┘      |
|         │           │           │                             │           │           │           |
|         └─────┬─────┴─────┬─────┘                             └─────┬─────┴─────┬─────┘           |
|               │           │                                         │           │                 |
|               ▼           ▼                                         ▼           ▼                 |
|       [ Automatic Bidirectional ]                           [ Fast Ad-Hoc Directory & File ]      |
|       [ Clipboard Synchronization ]                         [ Streaming across Subnet ]           |
|                                                                                                   |
|                                 ┌───────────────────────────┐                                     |
|                                 │  ZERO-INSTALL WEB SHARE   │                                     |
|                                 │ (Embedded Micro HTTP Srv) │                                     |
|                                 └─────────────┬─────────────┘                                     |
|                                               │                                                   |
|                         ┌─────────────────────┴─────────────────────┐                             |
|                         ▼                                           ▼                             |
|                  ┌─────────────┐                             ┌─────────────┐                      |
|                  │  Apple iOS  │                             │ Any Browser │                      |
|                  │ (Safari Web │                             │ (Guest WiFi │                      |
|                  │  Interface) │                             │   Client)   │                      |
|                  └─────────────┘                             └─────────────┘                      |
|                         ▲                                                                         |
|                         │ (One-Tap Bidirectional Clipboard Sync via REST API)                     |
|                  ┌──────┴────────────────────┐                                                    |
|                  │    kian-clip-bridge       │                                                    |
|                  │ (http://127.0.0.1:53318)  │                                                    |
|                  │   Apple iOS Shortcuts     │                                                    |
|                  └───────────────────────────┘                                                    |
+===================================================================================================+
```

---

## 8. End-to-End Automated Build Pipeline Architecture

```
+===================================================================================================+
|                           5-PHASE REPRODUCIBLE PRODUCTION BUILD PIPELINE                          |
+===================================================================================================+
|                                                                                                   |
|  [ PHASE 1: BUILD ENVIRONMENT & CRYPTOGRAPHIC AUTHORITY ]                                         |
|    ├── Host Prerequisites: Ubuntu 24.04 LTS x86_64, Clang 18, LLVM, GCC 14, xorriso, debootstrap  |
|    └── generate_kian_mok.sh: Generates 4096-bit RSA MOK Private Key & X.509 Certificate           |
|                                                                                                   |
|                                        │                                                          |
|                                        ▼                                                          |
|  [ PHASE 2: LINUX-KIAN v3 KERNEL ORCHESTRATION & PACKAGING ]                                      |
|    ├── 01_build_kernel.sh: Clones Ubuntu Noble Linux Source (6.8 GA / 6.11 HWE)                   |
|    ├── Applies Patch Stack: BORE, NTSync, BBRv3, IPTS/ITHC, IPU6 D-PHY, Apple SPI                 |
|    ├── Injects Kconfig Matrix: CONFIG_GENERIC_CPU_V3=y, CONFIG_HZ_1000=y, CONFIG_SCHED_BORE=y    |
|    ├── Compiles Debian Packages: make bindeb-pkg LLVM=1 LLVM_IAS=1 LOCALVERSION=-kian-v3          |
|    └── Signs vmlinuz with Kian MOK using sbsign                                                   |
|                                                                                                   |
|                                        │                                                          |
|                                        ▼                                                          |
|  [ PHASE 3: CLEAN-SLATE ROOTFS DEBOOTSTRAP & CHROOT PROVISIONING ]                                |
|    ├── 02_bootstrap_rootfs.sh: debootstrap --arch=amd64 --variant=minbase noble /build/rootfs     |
|    ├── Mounts Virtual Filesystems: /dev, /proc, /sys, /run                                        |
|    ├── Installs Dual Kernels: linux-kian-v3 debs (Primary) + linux-image-generic (Certified)      |
|    └── Installs Desktop Stack: plasma-workspace-wayland, kwin-wayland, sddm, btrfs-progs, pipewire|
|                                                                                                   |
|                                        │                                                          |
|                                        ▼                                                          |
|  [ PHASE 4: DESKTOP CUSTOMIZATION, TRIPLE-SHELL & CALAMARES ]                                     |
|    ├── 03_customize_desktop.sh: Enforces SDDM Pure Wayland Greeter & purges /usr/share/xsessions/ |
|    ├── Deploys Triple-Shell Assets (Native, Fluent, Aqua) & Fontconfig Subpixel XML               |
|    ├── Stages Calamares 3.3.5 Btrfs Subvolume Presets (@rootfs, @snapshots, @home, etc.)         |
|    └── Injects Calamares Hooks: Hardware Pre-Probe, ubuntu-drivers autoinstall, and Live Cleanup |
|                                                                                                   |
|                                        │                                                          |
|                                        ▼                                                          |
|  [ PHASE 5: SQUASHFS COMPRESSION, HYBRID BOOTLOADER & ISO MASTERING ]                             |
|    ├── 04_build_iso.sh: Sanitizes chroot, clears caches, truncates /etc/machine-id                |
|    ├── Compresses Rootfs: mksquashfs /build/rootfs filesystem.squashfs -comp zstd -Xlevel 19      |
|    ├── Assembles Dual Bootloaders: EFI Fat Image (shimx64.efi, grubx64.efi) + BIOS ISOLINUX MBR   |
|    ├── Masters Hybrid ISO via xorriso with GPT and MBR partition tables                           |
|    └── 05_verify_iso.sh: Generates SHA-256 Checksum, inspects partition tables, QEMU Smoke Test   |
|                                                                                                   |
|                                        │                                                          |
|                                        ▼                                                          |
|  [ FINAL PRODUCTION ARTIFACT: dist/kian-os-v3-desktop-amd64.iso (Bootable Universal Hybrid ISO) ] |
+===================================================================================================+
```

---
*End of Visual Architecture Overview for KIAN-OS v3.*
