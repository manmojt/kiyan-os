#!/usr/bin/python3
"""Supported Plasma persona settings and reversible desktop defaults."""
ACCENT = "64,224,208"
PERSONAS = {
    "macos": {
        "lookandfeel": "org.kiyan.macos",
        "name": "macOS Mode",
        "kwin": {"org.kde.kdecoration2": {"ButtonsOnLeft": "XIA", "ButtonsOnRight": ""},
                 "Windows": {"FocusPolicy": "ClickToFocus"}},
        "shortcuts": {"org.kde.kglobalaccel": {"Switch One Desktop to the Left": "Meta+Ctrl+Left",
                      "Switch One Desktop to the Right": "Meta+Ctrl+Right"}},
        "notes": "Left-side window buttons; macOS-style key chords are available in System Settings."
    },
    "windows11": {
        "lookandfeel": "org.kiyan.windows11",
        "name": "Windows 11 Mode",
        "kwin": {"Windows": {"ElectricBorderMaximize": "true", "ElectricBorderTiling": "true",
                                "Placement": "Centered"}},
        "shortcuts": {},
        "notes": "Centered taskbar, system tray, KWin edge tiling, and Plasma clipboard history (Meta+V)."
    },
    "linux-pro": {
        "lookandfeel": "org.kiyan.linuxpro",
        "name": "Linux Pro Mode",
        "kwin": {"Windows": {"ElectricBorderMaximize": "true", "ElectricBorderTiling": "true", "Placement": "Smart"},
                 "Plugins": {"kwin4_effect_overviewEnabled": "true", "kiyan-krohnkiteEnabled": "true"}},
        "shortcuts": {},
        "notes": "Minimal top panel with the bundled Kiyan dynamic master/stack tiler enabled."
    }
}
