// ==============================================================================
// KIAN-OS v3 Triple-Shell Layout: macOS Aqua
// Path: desktop/triple-shell/layouts/macos-aqua.js
// Description: Dynamic Plasma JavaScript layout for macOS Aqua top bar + dock.
// ==============================================================================

// 1. Remove all existing Plasma panels cleanly
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// 2. Panel 1: Top 28px Frosted Global Menu Bar
var topBar = new Panel("org.kde.plasma.panel");
topBar.location = "top";
topBar.height = 28;
topBar.floating = false;
topBar.hiding = "none";

// 2a. Kian System Menu (Apple-Style Top Left Launcher)
var kianMenu = topBar.addWidget("org.kde.plasma.kickoff");
kianMenu.currentConfigGroup = ["General"];
kianMenu.writeConfig("icon", "start-here-symbolic");
kianMenu.writeConfig("favoritesPortedToKAstats", true);

// 2b. Global DBus Application Menu (macOS AppMenu Registrar)
var appMenu = topBar.addWidget("org.kde.plasma.appmenu");
appMenu.currentConfigGroup = ["General"];
appMenu.writeConfig("compactView", false);

// 2c. Expanding Spacer pushing Status & Clock to Right
var topSpacer = topBar.addWidget("org.kde.plasma.panelspacer");
topSpacer.currentConfigGroup = ["General"];
topSpacer.writeConfig("expanding", true);

// 2d. Status System Tray
var topTray = topBar.addWidget("org.kde.plasma.systemtray");
topTray.currentConfigGroup = ["General"];
topTray.writeConfig("extraItems", [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth"
]);

// 2e. macOS Standard Typography Clock ("EEE MMM d  h:mm a")
var topClock = topBar.addWidget("org.kde.plasma.digitalclock");
topClock.currentConfigGroup = ["Appearance"];
topClock.writeConfig("dateFormat", "custom");
topClock.writeConfig("customDateFormat", "EEE MMM d  h:mm a");
topClock.writeConfig("showSeconds", false);

// 3. Panel 2: Bottom Floating Centered Dock
var dock = new Panel("org.kde.plasma.panel");
dock.location = "bottom";
dock.height = 64;
dock.alignment = "center";
dock.floating = true;
dock.hiding = "dodgewindows";

// 3a. Dock Icon Task Manager (Parabolic Zoom & Launchers)
var dockTasks = dock.addWidget("org.kde.plasma.icontasks");
dockTasks.currentConfigGroup = ["General"];
dockTasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.falkon.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:localsend_app.desktop",
    "applications:systemsettings.desktop"
]);
dockTasks.writeConfig("showOnlyCurrentScreen", true);
dockTasks.writeConfig("showOnlyCurrentDesktop", true);
dockTasks.writeConfig("indicateAudioStreams", true);
dockTasks.writeConfig("fill", false);
dockTasks.writeConfig("iconSpacing", "medium");
