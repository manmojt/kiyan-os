// ==============================================================================
// KIAN-OS v3 Triple-Shell Layout: Windows 11 Fluent
// Path: desktop/triple-shell/layouts/windows-fluent.js
// Description: Dynamic Plasma JavaScript layout for Windows 11 Fluent UI.
// ==============================================================================

// 1. Remove all existing Plasma panels cleanly
var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

// 2. Instantiate Windows 11 Full-Width Bottom Taskbar
var taskbar = new Panel("org.kde.plasma.panel");
taskbar.location = "bottom";
taskbar.height = 48;
taskbar.floating = false;
taskbar.alignment = "center";
taskbar.hiding = "none";

// 3. Left Expanding Spacer (Pushes Start Menu & Tasks to Center)
var leftSpacer = taskbar.addWidget("org.kde.plasma.panelspacer");
leftSpacer.currentConfigGroup = ["General"];
leftSpacer.writeConfig("expanding", true);

// 4. Centered Start Menu (Kickoff with Windows/Fluent Symbolic Icon)
var startMenu = taskbar.addWidget("org.kde.plasma.kickoff");
startMenu.currentConfigGroup = ["General"];
startMenu.writeConfig("icon", "start-here-symbolic");
startMenu.writeConfig("favoritesPortedToKAstats", true);

// 5. Centered Icon Tasks (Windows 11 Icon-Only Taskbar)
var taskManager = taskbar.addWidget("org.kde.plasma.icontasks");
taskManager.currentConfigGroup = ["General"];
taskManager.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:localsend_app.desktop",
    "applications:systemsettings.desktop"
]);
taskManager.writeConfig("showOnlyCurrentScreen", true);
taskManager.writeConfig("showOnlyCurrentDesktop", true);
taskManager.writeConfig("indicateAudioStreams", true);

// 6. Right Expanding Spacer (Balances Center Alignment)
var rightSpacer = taskbar.addWidget("org.kde.plasma.panelspacer");
rightSpacer.currentConfigGroup = ["General"];
rightSpacer.writeConfig("expanding", true);

// 7. System Tray (Notification Center & System Icons)
var systray = taskbar.addWidget("org.kde.plasma.systemtray");
systray.currentConfigGroup = ["General"];
systray.writeConfig("extraItems", [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.battery",
    "org.kde.plasma.notifications"
]);

// 8. Digital Clock with Date (Windows 11 Style)
var clock = taskbar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "shortDate");
clock.writeConfig("showSeconds", false);
