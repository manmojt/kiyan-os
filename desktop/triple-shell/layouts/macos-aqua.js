// ==============================================================================
// KIAN-OS v3 Triple-Shell Layout: macOS Aqua (Default Shell + 4K Crystal Wallpaper)
// Path: desktop/triple-shell/layouts/macos-aqua.js
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

// Panel 1: Top 28px Frosted Global Menu Bar
var topBar = new Panel("org.kde.plasma.panel");
topBar.location = "top";
topBar.height = 28;
topBar.floating = false;
topBar.hiding = "none";

var kianMenu = topBar.addWidget("org.kde.plasma.kickoff");
kianMenu.currentConfigGroup = ["General"];
kianMenu.writeConfig("icon", "/usr/share/pixmaps/kiyan-icon.png");
kianMenu.writeConfig("favoritesPortedToKAstats", true);

var appMenu = topBar.addWidget("org.kde.plasma.appmenu");
appMenu.currentConfigGroup = ["General"];
appMenu.writeConfig("compactView", false);

var topSpacer = topBar.addWidget("org.kde.plasma.panelspacer");
topSpacer.currentConfigGroup = ["General"];
topSpacer.writeConfig("expanding", true);

var topTray = topBar.addWidget("org.kde.plasma.systemtray");
topTray.currentConfigGroup = ["General"];
topTray.writeConfig("extraItems", [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth"
]);

var topClock = topBar.addWidget("org.kde.plasma.digitalclock");
topClock.currentConfigGroup = ["Appearance"];
topClock.writeConfig("dateFormat", "custom");
topClock.writeConfig("customDateFormat", "EEE MMM d  h:mm a");
topClock.writeConfig("showSeconds", false);

// Panel 2: Bottom Floating Centered macOS Dock
var dock = new Panel("org.kde.plasma.panel");
dock.location = "bottom";
dock.height = 60;
dock.alignment = "center";
dock.floating = true;
dock.hiding = "none";
dock.lengthMode = "fit";

var dockTasks = dock.addWidget("org.kde.plasma.icontasks");
dockTasks.currentConfigGroup = ["General"];
dockTasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:firefox.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:kian-theme-switcher.desktop",
    "applications:localsend_app.desktop",
    "applications:systemsettings.desktop"
]);
dockTasks.writeConfig("showOnlyCurrentScreen", true);
dockTasks.writeConfig("showOnlyCurrentDesktop", true);
dockTasks.writeConfig("indicateAudioStreams", true);
dockTasks.writeConfig("fill", false);
dockTasks.writeConfig("iconSpacing", "medium");
