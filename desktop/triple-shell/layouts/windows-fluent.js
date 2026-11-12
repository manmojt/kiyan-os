// ==============================================================================
// KIAN-OS v3 Triple-Shell Layout: Windows 11 Fluent (+ 4K Crystal Wallpaper)
// Path: desktop/triple-shell/layouts/windows-fluent.js
// ==============================================================================

var allDesktops = desktops();
for (var d = 0; d < allDesktops.length; d++) {
    var desk = allDesktops[d];
    desk.wallpaperPlugin = "org.kde.image";
    desk.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desk.writeConfig("Image", "file:///usr/share/wallpapers/KiyanCrystal4K/contents/images/3840x2160.jpg");
    desk.writeConfig("FillMode", 2);
}

var existingPanels = panels();
for (var i = 0; i < existingPanels.length; i++) {
    existingPanels[i].remove();
}

var taskbar = new Panel;
taskbar.location = "bottom";
taskbar.height = 48;
taskbar.alignment = "center";
taskbar.hiding = "none";
try { taskbar.floating = false; } catch (e) {}

var leftSpacer = taskbar.addWidget("org.kde.plasma.panelspacer");
leftSpacer.currentConfigGroup = ["General"];
leftSpacer.writeConfig("expanding", true);

var startMenu = taskbar.addWidget("org.kde.plasma.kickoff");
startMenu.currentConfigGroup = ["General"];
startMenu.writeConfig("icon", "/usr/share/pixmaps/kiyan-icon.png");
startMenu.writeConfig("favoritesPortedToKAstats", true);

var taskManager = taskbar.addWidget("org.kde.plasma.icontasks");
taskManager.currentConfigGroup = ["General"];
taskManager.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:kian-theme-switcher.desktop",
    "applications:localsend_app.desktop",
    "applications:systemsettings.desktop"
]);
taskManager.writeConfig("showOnlyCurrentScreen", true);
taskManager.writeConfig("showOnlyCurrentDesktop", true);
taskManager.writeConfig("indicateAudioStreams", true);

var rightSpacer = taskbar.addWidget("org.kde.plasma.panelspacer");
rightSpacer.currentConfigGroup = ["General"];
rightSpacer.writeConfig("expanding", true);

var systray = taskbar.addWidget("org.kde.plasma.systemtray");

var clock = taskbar.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "shortDate");
clock.writeConfig("showSeconds", false);
