# Kiyan OS v4 Appearance Layouts (GPLv2)
# Unlocks authentic Windows 11 Centered Taskbar + Start Menu + Right Window Controls

import gi
import zorin_appearance.Layouts.layout as layout
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gio, GLib


class Windows11CenteredShell(layout.Layout, Gtk.Box):

    __metaclass__ = layout.LayoutBox

    environment = 'zorin:GNOME'

    def __init__(self):
        Gtk.Box.__init__(self)

        self.enabled_extensions = [
            'zorin-menu@zorinos.com',
            'zorin-taskbar@zorinos.com',
            'zorin-desktop-icons@zorinos.com',
            'zorin-tiling-shell@zorinos.com',
            'blur-my-shell@aunetx',
        ]
        self.disabled_extensions = [
            'add-to-desktop@tommimon.github.com',
            'apps-menu@gnome-shell-extensions.gcampax.github.com',
            'places-menu@gnome-shell-extensions.gcampax.github.com',
            'zorin-dash@zorinos.com',
            'zorin-hide-activities-move-clock@zorinos.com',
            'fullscreen-to-empty-workspace@aiono.dev',
        ]
        panel_pos = (
            '{"0":['
            '{"element":"leftBox","visible":true,"position":"centered"},'
            '{"element":"activitiesButton","visible":false,"position":"stackedTL"},'
            '{"element":"taskbar","visible":true,"position":"centered"},'
            '{"element":"centerBox","visible":false,"position":"stackedBR"},'
            '{"element":"rightBox","visible":true,"position":"stackedBR"},'
            '{"element":"systemMenu","visible":true,"position":"stackedBR"},'
            '{"element":"dateMenu","visible":true,"position":"stackedBR"},'
            '{"element":"desktopButton","visible":true,"position":"stackedBR"}'
            ']}'
        )
        self.settings = [
            ('org.gnome.desktop.wm.preferences', 'button-layout',
             GLib.Variant('s', 'appmenu:minimize,maximize,close')),
            ('org.gnome.desktop.interface', 'enable-hot-corners',
             GLib.Variant('b', False)),
            ('org.gnome.desktop.interface', 'zorin-display-overview-on-startup',
             GLib.Variant('b', False)),
            ('org.gnome.shell.extensions.zorin-menu', 'layout',
             GLib.Variant('s', 'ALL')),
            ('org.gnome.shell.extensions.zorin-taskbar', 'panel-element-positions',
             GLib.Variant('s', panel_pos)),
            ('org.gnome.shell.extensions.zorin-taskbar', 'panel-element-positions-monitors-sync',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-taskbar', 'panel-margin',
             GLib.Variant('i', 4)),
            ('org.gnome.shell.extensions.zorin-taskbar', 'global-border-radius',
             GLib.Variant('i', 3)),
            ('org.gnome.shell.extensions.zorin-taskbar', 'intellihide',
             GLib.Variant('b', False)),
            ('org.gnome.shell.extensions.zorin-taskbar', 'show-favorites',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-taskbar', 'show-running-apps',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-taskbar', 'show-window-previews',
             GLib.Variant('b', True)),
            ('org.gnome.nautilus.preferences', 'click-policy',
             GLib.Variant('s', 'double')),
        ]

        preview = Gtk.DrawingArea()
        preview.connect('draw', self.draw_layout_preview)
        preview.set_size_request(layout.LAYOUT_PREVIEW_WIDTH,
                                 layout.LAYOUT_PREVIEW_HEIGHT)
        self.pack_start(preview, True, False, 0)

    def draw_layout_preview(self, widget, cr):
        style_context = widget.get_style_context()
        color = style_context.get_color(Gtk.StateFlags.NORMAL)
        cr.set_source_rgba(*color)

        w = layout.LAYOUT_PREVIEW_WIDTH
        h = layout.LAYOUT_PREVIEW_HEIGHT

        # Screen Outline
        cr.set_line_width(2)
        cr.rectangle(1, 1, w - 2, h - 2)
        cr.stroke()

        # Centered Windows 11 Popup Start Menu
        mw, mh = 86, 76
        mx, my = round((w - mw) / 2), h - mh - 20
        cr.rectangle(mx, my, mw, mh)
        cr.stroke()
        for r in range(3):
            for c in range(4):
                cr.rectangle(mx + 12 + c * 17, my + 14 + r * 17, 7, 7)
                cr.fill()

        # Bottom Floating Taskbar with Centered Icons
        cr.rectangle(5, h - 15, w - 10, 11)
        cr.stroke()
        start_x = round(w / 2) - 24
        for idx in range(5):
            cr.rectangle(start_x + idx * 10, h - 12, 5, 5)
            cr.fill()
        cr.rectangle(w - 34, h - 11, 24, 3)
        cr.fill()
