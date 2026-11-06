// Kiyan Linux Pro persona: compact top panel with global menu, tray and clock.
panels().forEach(function (panel) { panel.remove(); });
var topbar = new Panel();
topbar.location = "top";
topbar.height = 30;
topbar.addWidget("org.kde.plasma.kickoff");
topbar.addWidget("org.kde.plasma.appmenu");
topbar.addWidget("org.kde.plasma.panelspacer");
topbar.addWidget("org.kde.plasma.systemtray");
topbar.addWidget("org.kde.plasma.digitalclock");
