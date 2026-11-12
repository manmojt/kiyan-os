/* === KIAN-OS v3 Calamares Installation Slideshow (API v2) === */

import QtQuick 2.5
import calamares.slideshow 1.0

Presentation
{
    id: presentation

    titleColor: "#3daee9"
    textColor: "#1e222a"

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 6000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        title: "Kian-OS v3 (Noble Edition)"
        centeredText: "Powered by MOK-Signed linux-kian 6.8.12-kian-v3 Superkernel\nBORE 1000Hz Scheduler • Native Windows NTSync • TCP BBRv3"
    }

    Slide {
        title: "Pure KDE Plasma Wayland & Native GPU KMS"
        centeredText: "Zero-tearing Wayland compositor with full Intel, AMD, and NVIDIA KMS firmware,\nnative EDID monitor auto-detection, and subpixel typography."
    }

    Slide {
        title: "Resilient Btrfs Zstd-3 & Dual-Kernel Watchdog"
        centeredText: "Atomic Btrfs subvolumes (@rootfs, @home, @snapshots) with automatic APT snapshots\nand hardware-grade GRUB failover protection."
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
    }
}
