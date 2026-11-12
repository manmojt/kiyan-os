# Kiyan OS v4 Appearance Layouts (GPLv2)
# Unlocks authentic macOS Sequoia Dock + Top Bar + Fullscreen-to-New-Space + Frosted Shell Glass
# inside native Zorin Appearance without any paid upgrade wall!

import gi
import zorin_appearance.Layouts.layout as layout
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gio, GLib


class MacOSSequoiaShell(layout.Layout, Gtk.Box):

    __metaclass__ = layout.LayoutBox

    environment = 'zorin:GNOME'

    def __init__(self):
        Gtk.Box.__init__(self)

        self.enabled_extensions = [
            'zorin-dash@zorinos.com',
            'zorin-hide-activities-move-clock@zorinos.com',
            'zorin-magic-lamp-effect@zorinos.com',
            'zorin-desktop-icons@zorinos.com',
            'zorin-tiling-shell@zorinos.com',
            'blur-my-shell@aunetx',
            'fullscreen-to-empty-workspace@aiono.dev',
        ]
        self.disabled_extensions = [
            'add-to-desktop@tommimon.github.com',
            'apps-menu@gnome-shell-extensions.gcampax.github.com',
            'places-menu@gnome-shell-extensions.gcampax.github.com',
            'zorin-menu@zorinos.com',
            'zorin-taskbar@zorinos.com',
        ]
        self.settings = [
            ('org.gnome.desktop.wm.preferences', 'button-layout',
             GLib.Variant('s', 'close,minimize,maximize:appmenu')),
            ('org.gnome.desktop.interface', 'enable-hot-corners',
             GLib.Variant('b', True)),
            ('org.gnome.desktop.interface', 'zorin-display-overview-on-startup',
             GLib.Variant('b', False)),
            ('org.gnome.shell.extensions.zorin-dash', 'dock-position',
             GLib.Variant('s', 'BOTTOM')),
            ('org.gnome.shell.extensions.zorin-dash', 'extend-height',
             GLib.Variant('b', False)),
            ('org.gnome.shell.extensions.zorin-dash', 'always-center-icons',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-dash', 'dock-fixed',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-dash', 'intellihide',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-dash', 'autohide-in-fullscreen',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-dash', 'dash-max-icon-size',
             GLib.Variant('i', 48)),
            ('org.gnome.shell.extensions.zorin-dash', 'show-show-apps-button',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-dash', 'show-apps-at-top',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-dash', 'show-trash',
             GLib.Variant('b', True)),
            ('org.gnome.shell.extensions.zorin-dash', 'transparency-mode',
             GLib.Variant('s', 'FIXED')),
            ('org.gnome.shell.extensions.zorin-dash', 'background-opacity',
             GLib.Variant('d', 0.45)),
            ('org.gnome.shell.extensions.zorin-dash', 'click-action',
             GLib.Variant('s', 'minimize-or-previews')),
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

        # Top macOS Menu Bar
        cr.set_line_width(2)
        cr.move_to(2, 11)
        cr.line_to(w - 2, 11)
        cr.stroke()

        # Top left logo & menus
        cr.rectangle(6, 4, 5, 4)
        cr.fill()
        cr.rectangle(16, 5, 14, 2)
        cr.fill()
        cr.rectangle(34, 5, 12, 2)
        cr.fill()

        # Top right indicators & clock
        cr.rectangle(w - 44, 5, 38, 2)
        cr.fill()

        # Centered Window Preview with Left Traffic Lights
        win_w, win_h = 124, 78
        wx, wy = round((w - win_w) / 2), round((h - win_h) / 2) - 4
        cr.set_line_width(2)
        cr.rectangle(wx, wy, win_w, win_h)
        cr.stroke()
        cr.move_to(wx, wy + 12)
        cr.line_to(wx + win_w, wy + 12)
        cr.stroke()
        for idx in range(3):
            cr.rectangle(wx + 5 + idx * 6, wy + 4, 3, 3)
            cr.fill()

        # Bottom Floating macOS Dock
        dock_w, dock_h = 96, 14
        dx, dy = round((w - dock_w) / 2), h - dock_h - 5
        cr.set_line_width(2)
        cr.rectangle(dx, dy, dock_w, dock_h)
        cr.stroke()
        for idx in range(6):
            cr.rectangle(dx + 8 + idx * 14, dy + 4, 6, 6)
            cr.fill()
