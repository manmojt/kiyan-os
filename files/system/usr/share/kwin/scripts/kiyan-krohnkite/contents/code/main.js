/* KWin script: deterministic master/stack tiling on window create and desktop change. */
var busy = false;
function eligible(w) {
    return w && w.normalWindow && !w.fullScreen && !w.minimized && !w.skipTaskbar &&
        !w.specialWindow && !w.desktopWindow && !w.dock;
}
function tile() {
    if (busy) return;
    busy = true;
    try {
        var desktop = workspace.currentDesktop;
        var screen = workspace.activeScreen;
        var windows = workspace.stackingOrder.filter(function (w) {
            return eligible(w) && w.output === screen &&
                (w.onAllDesktops || w.desktops.indexOf(desktop) >= 0);
        });
        if (windows.length === 0) return;
        var area = workspace.clientArea(5, screen, desktop);
        if (!area || area.width < 300 || area.height < 200) return;
        var gap = 8;
        if (windows.length === 1) {
            windows[0].frameGeometry = {x: area.x + gap, y: area.y + gap,
                width: area.width - 2 * gap, height: area.height - 2 * gap};
            return;
        }
        var masterWidth = Math.floor(area.width * 0.58);
        var stackWidth = area.width - masterWidth;
        var stackHeight = Math.floor((area.height - gap * (windows.length - 1)) / (windows.length - 1));
        windows.forEach(function(w, i) {
            if (i === 0) w.frameGeometry = {x: area.x + gap, y: area.y + gap,
                width: masterWidth - 2 * gap, height: area.height - 2 * gap};
            else w.frameGeometry = {x: area.x + masterWidth + gap,
                y: area.y + gap + (i - 1) * (stackHeight + gap),
                width: stackWidth - 2 * gap, height: stackHeight};
        });
    } finally { busy = false; }
}
workspace.windowAdded.connect(function(w) { if (eligible(w)) setTimeout(tile, 250); });
workspace.windowRemoved.connect(function() { setTimeout(tile, 250); });
workspace.currentDesktopChanged.connect(function() { setTimeout(tile, 100); });
registerShortcut("Kiyan Dynamic Tiling: Retile", "Retile current desktop", "Meta+Shift+T", tile);
