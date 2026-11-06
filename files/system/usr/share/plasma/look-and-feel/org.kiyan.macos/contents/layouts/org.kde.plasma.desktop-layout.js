// Kiyan macOS persona: floating bottom app dock and top global menu panel.
panels().forEach(function (panel) { panel.remove(); });
var menu = new Panel();
menu.location = "top";
menu.height = 30;
menu.addWidget("org.kde.plasma.appmenu");
menu.addWidget("org.kde.plasma.panelspacer");
menu.addWidget("org.kde.plasma.systemtray");
menu.addWidget("org.kde.plasma.digitalclock");
var dock = new Panel();
dock.location = "bottom";
dock.height = 54;
dock.floating = true;
dock.addWidget("org.kde.plasma.kickoff");
dock.addWidget("org.kde.plasma.taskmanager");
dock.addWidget("org.kde.plasma.showdesktop");
