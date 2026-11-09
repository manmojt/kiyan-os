// ==============================================================================
// KIAN-OS v3 Triple-Shell Layout: Kian Native (Glassmorphic Dark Crystal)
// Path: desktop/triple-shell/layouts/kian-native.js
// Description: Dynamic Plasma JavaScript layout for Kian Native glassmorphic UI.
// ==============================================================================

// 1. Remove all existing Plasma panels cleanly
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// 2. Instantiate Kian Native Floating Bottom Dock-Panel
var panel = new Panel("org.kde.plasma.panel");
panel.location = "bottom";
panel.height = 56;
panel.floating = true;
panel.alignment = "center";
panel.hiding = "none";

// 3. Application Launcher (Kickoff with Kian Glass Emblem)
var kickoff = panel.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "kian-emblem");
kickoff.writeConfig("favoritesPortedToKAstats", true);

// 4. Active Task Manager (Glass Cards with Neon Glow)
var taskmanager = panel.addWidget("org.kde.plasma.taskmanager");
taskmanager.currentConfigGroup = ["General"];
taskmanager.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:localsend_app.desktop"
]);
taskmanager.writeConfig("showOnlyCurrentScreen", true);
taskmanager.writeConfig("showOnlyCurrentDesktop", true);
taskmanager.writeConfig("wheelEnabled", true);

// 5. System Tray & Status Island
var systray = panel.addWidget("org.kde.plasma.systemtray");
systray.currentConfigGroup = ["General"];
systray.writeConfig("extraItems", [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth"
]);

// 6. Minimalist Digital Clock
var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "shortDate");
clock.writeConfig("use24hFormat", 2);
