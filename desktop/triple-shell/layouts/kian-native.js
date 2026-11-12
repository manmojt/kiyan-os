// ==============================================================================
// KIAN-OS v3 Triple-Shell Layout: Kian Native Glassmorphic Dark Crystal (+ 4K Wallpaper)
// Path: desktop/triple-shell/layouts/kian-native.js
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

var panel = new Panel("org.kde.plasma.panel");
panel.location = "bottom";
panel.height = 56;
panel.floating = true;
panel.alignment = "center";
panel.hiding = "none";

var kickoff = panel.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("icon", "/usr/share/pixmaps/kiyan-icon.png");
kickoff.writeConfig("favoritesPortedToKAstats", true);

var taskmanager = panel.addWidget("org.kde.plasma.icontasks");
taskmanager.currentConfigGroup = ["General"];
taskmanager.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:kian-theme-switcher.desktop",
    "applications:localsend_app.desktop",
    "applications:systemsettings.desktop"
]);
taskmanager.writeConfig("showOnlyCurrentScreen", true);
taskmanager.writeConfig("showOnlyCurrentDesktop", true);

var systray = panel.addWidget("org.kde.plasma.systemtray");
systray.currentConfigGroup = ["General"];
systray.writeConfig("extraItems", [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth"
]);

var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateFormat", "shortDate");
clock.writeConfig("use24hFormat", 2);
