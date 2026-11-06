// Kiyan Windows 11 persona: centered floating taskbar with system tray.
panels().forEach(function (panel) { panel.remove(); });
var taskbar = new Panel();
taskbar.location = "bottom";
taskbar.height = 48;
taskbar.floating = true;
taskbar.alignment = "center";
taskbar.addWidget("org.kde.plasma.kickoff");
taskbar.addWidget("org.kde.plasma.taskmanager");
taskbar.addWidget("org.kde.plasma.systemtray");
taskbar.addWidget("org.kde.plasma.digitalclock");
