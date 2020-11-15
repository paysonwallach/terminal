/*
* Copyright (c) 2011-2019 elementary, Inc. (https://elementary.io)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU Lesser General Public
* License version 3, as published by the Free Software Foundation.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU Lesser General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*/

namespace Terminal {
    public class MainWindow : Gtk.ApplicationWindow {
        private Pango.FontDescription term_font;
        private Gtk.Clipboard clipboard;
        private Gtk.Clipboard primary_selection;
        private Terminal.Widgets.Searchbar searchbar;
        private Gtk.Revealer search_revealer;
        private Gtk.Overlay window_geometry_overlay;

        private bool is_fullscreen = false;
        private bool search_is_active = false;

        private const int NORMAL = 0;
        private const int MAXIMIZED = 1;
        private const int FULLSCREEN = 2;

        private int rows = 0;
        private int cols = 0;
        private uint? resize_overlay_callback_id;
        private Gtk.Label resize_overlay;

        private const string HIGH_CONTRAST_BG = "#fff";
        private const string HIGH_CONTRAST_FG = "#333";
        private const string DARK_BG = "rgba(46, 46, 46, 0.95)";
        private const string DARK_FG = "#a5a5a5";
        private const string SOLARIZED_LIGHT_BG = "rgba(253, 246, 227, 0.95)";
        private const string SOLARIZED_LIGHT_FG = "#586e75";

        public bool unsafe_ignored;
        public bool restore_pos { get; construct; default = true; }
        public uint focus_timeout { get; private set; default = 0;}
        public Gtk.Menu menu { get; private set; }
        public Terminal.Application app { get; construct; }
        public SimpleActionGroup actions { get; construct; }
        public TerminalWidget terminal { get; private set; default = null; }

        public const string ACTION_PREFIX = "win.";
        public const string ACTION_FULLSCREEN = "action-fullscreen";
        public const string ACTION_NEW_WINDOW = "action-new-window";
        public const string ACTION_ZOOM_DEFAULT_FONT = "action-zoom-default-font";
        public const string ACTION_ZOOM_IN_FONT = "action-zoom-in-font";
        public const string ACTION_ZOOM_OUT_FONT = "action-zoom-out-font";
        public const string ACTION_COPY = "action-copy";
        public const string ACTION_COPY_LAST_OUTPUT = "action-copy-last-output";
        public const string ACTION_PASTE = "action-paste";
        public const string ACTION_SEARCH = "action-search";
        public const string ACTION_SEARCH_NEXT = "action-search-next";
        public const string ACTION_SEARCH_PREVIOUS = "action-search-previous";
        public const string ACTION_SELECT_ALL = "action-select-all";
        public const string ACTION_OPEN_IN_FILES = "action-open-in-files";
        public const string ACTION_SCROLL_TO_LAST_COMMAND = "action-scroll-to-last-command";
        public const string ACTION_SHOW_SETTINGS = "action-show-settings";
        public const string ACTION_SHOW_INSPECTOR = "action-show-inspcetor";

        private static Gee.MultiMap<string, string> action_accelerators = new Gee.HashMultiMap<string, string> ();

        private const ActionEntry[] ACTION_ENTRIES = {
            { ACTION_FULLSCREEN, action_fullscreen },
            { ACTION_NEW_WINDOW, action_new_window },
            { ACTION_ZOOM_DEFAULT_FONT, action_zoom_default_font },
            { ACTION_ZOOM_IN_FONT, action_zoom_in_font },
            { ACTION_ZOOM_OUT_FONT, action_zoom_out_font },
            { ACTION_COPY, action_copy },
            { ACTION_COPY_LAST_OUTPUT, action_copy_last_output },
            { ACTION_PASTE, action_paste },
            { ACTION_SEARCH, action_search, null, "false" },
            { ACTION_SEARCH_NEXT, action_search_next },
            { ACTION_SEARCH_PREVIOUS, action_search_previous },
            { ACTION_SELECT_ALL, action_select_all },
            { ACTION_OPEN_IN_FILES, action_open_in_files },
            { ACTION_SCROLL_TO_LAST_COMMAND, action_scroll_to_last_command },
            { ACTION_SHOW_SETTINGS, action_show_settings },
            { ACTION_SHOW_INSPECTOR, action_show_inspector }
        };

        public MainWindow (Terminal.Application app) {
            Object (
                app: app
            );
        }

        public MainWindow.with_coords (Terminal.Application app, int x, int y,
                                        bool ensure_tab) {
            Object (
                app: app,
                restore_pos: false
            );

            move (x, y);
        }

        public MainWindow.with_working_directory (Terminal.Application app, string? location,
                                                  bool create_new_tab = false) {
            Object (
                app: app
            );
        }

        static construct {
            action_accelerators[ACTION_FULLSCREEN] = "F11";
            action_accelerators[ACTION_NEW_WINDOW] = "<Control><Shift>n";
            action_accelerators[ACTION_ZOOM_DEFAULT_FONT] = "<Control>0";
            action_accelerators[ACTION_ZOOM_DEFAULT_FONT] = "<Control>KP_0";
            action_accelerators[ACTION_ZOOM_IN_FONT] = "<Control>plus";
            action_accelerators[ACTION_ZOOM_IN_FONT] = "<Control>equal";
            action_accelerators[ACTION_ZOOM_IN_FONT] = "<Control>KP_Add";
            action_accelerators[ACTION_ZOOM_OUT_FONT] = "<Control>minus";
            action_accelerators[ACTION_ZOOM_OUT_FONT] = "<Control>KP_Subtract";
            action_accelerators[ACTION_COPY] = "<Control><Shift>c";
            action_accelerators[ACTION_COPY_LAST_OUTPUT] = "<Alt>c";
            action_accelerators[ACTION_PASTE] = "<Control><Shift>v";
            action_accelerators[ACTION_SEARCH] = "<Control><Shift>f";
            action_accelerators[ACTION_SELECT_ALL] = "<Control><Shift>a";
            action_accelerators[ACTION_OPEN_IN_FILES] = "<Control><Shift>e";
            action_accelerators[ACTION_SCROLL_TO_LAST_COMMAND] = "<Alt>Up";
            action_accelerators[ACTION_SHOW_INSPECTOR] = "<Control><Shift>d";
            action_accelerators[ACTION_SHOW_SETTINGS] = "<Contorl><Shift><p>";
        }

        construct {
            actions = new SimpleActionGroup ();
            actions.add_action_entries (ACTION_ENTRIES, this);
            insert_action_group ("win", actions);

            icon_name = "utilities-terminal";

            set_application (app);

            get_style_context ().add_class ("rounded");

            foreach (var action in action_accelerators.get_keys ()) {
                var accels_array = action_accelerators[action].to_array ();
                accels_array += null;

                app.set_accels_for_action (ACTION_PREFIX + action, accels_array);
            }

            /* Make GTK+ CSD not steal F10 from the terminal */
            var gtk_settings = Gtk.Settings.get_default ();
            gtk_settings.gtk_menu_bar_accel = null;

            set_visual (Gdk.Screen.get_default ().get_rgba_visual ());

            title = TerminalWidget.DEFAULT_LABEL;
            restore_saved_state (restore_pos);

            clipboard = Gtk.Clipboard.get (Gdk.Atom.intern ("CLIPBOARD", false));
            update_context_menu ();
            clipboard.owner_change.connect (update_context_menu);

            primary_selection = Gtk.Clipboard.get (Gdk.Atom.intern ("PRIMARY", false));

            var copy_menuitem = new Gtk.MenuItem ();
            copy_menuitem.set_action_name (ACTION_PREFIX + ACTION_COPY);
            copy_menuitem.add (new Granite.AccelLabel.from_action_name (_("Copy"), copy_menuitem.action_name));

            var copy_last_output_menuitem = new Gtk.MenuItem ();
            copy_last_output_menuitem.set_action_name (ACTION_PREFIX + ACTION_COPY_LAST_OUTPUT);
            copy_last_output_menuitem.add (
                new Granite.AccelLabel.from_action_name (_("Copy Last Output"), copy_last_output_menuitem.action_name)
            );

            var paste_menuitem = new Gtk.MenuItem ();
            paste_menuitem.set_action_name (ACTION_PREFIX + ACTION_PASTE);
            paste_menuitem.add (new Granite.AccelLabel.from_action_name (_("Paste"), paste_menuitem.action_name));

            var select_all_menuitem = new Gtk.MenuItem ();
            select_all_menuitem.set_action_name (ACTION_PREFIX + ACTION_SELECT_ALL);
            select_all_menuitem.add (
                new Granite.AccelLabel.from_action_name (_("Select All"), select_all_menuitem.action_name)
            );

            var search_menuitem = new Gtk.MenuItem ();
            search_menuitem.set_action_name (ACTION_PREFIX + ACTION_SEARCH);
            search_menuitem.add (new Granite.AccelLabel.from_action_name (_("Find…"), search_menuitem.action_name));

            var show_in_file_browser_menuitem = new Gtk.MenuItem ();
            show_in_file_browser_menuitem.set_action_name (ACTION_PREFIX + ACTION_OPEN_IN_FILES);
            show_in_file_browser_menuitem.add (
                new Granite.AccelLabel.from_action_name (
                    _("Show in File Browser"),
                    show_in_file_browser_menuitem.action_name
                )
            );

            var show_inspector_submenu_item = new Gtk.MenuItem ();
            show_inspector_submenu_item.set_action_name (ACTION_PREFIX + ACTION_SHOW_INSPECTOR);
            show_inspector_submenu_item.add (new Granite.AccelLabel.from_action_name ("Show Inspector", show_inspector_submenu_item.action_name));

            var show_settings_menuitem = new Gtk.MenuItem ();
            show_settings_menuitem.set_action_name (ACTION_PREFIX + ACTION_SHOW_SETTINGS);
            show_settings_menuitem.add (new Granite.AccelLabel.from_action_name ("Settings", show_settings_menuitem.action_name));

            var reset_size_submenu_item = new Gtk.MenuItem ();
            var reset_size_submenu_item_label = new Gtk.Label ("Reset size");

            reset_size_submenu_item_label.set_hexpand (true);
            reset_size_submenu_item_label.set_halign (Gtk.Align.START);
            reset_size_submenu_item.add (reset_size_submenu_item_label);
            reset_size_submenu_item.activate.connect (() => {
                var char_width = (int) terminal.get_char_width ();
                var char_height = (int) terminal.get_char_height ();
                int border_width, border_height;

                get_border_dimensions (char_width, char_height, out border_width, out border_height);
                resize (80 * char_width + border_width, 25 * char_height + border_height);
                // terminal.set_size (80, 25);
            });

            var submenu = new Gtk.Menu ();
            submenu.append (show_inspector_submenu_item);
            submenu.append (reset_size_submenu_item);

            var advanced_submenu_menuitem = new Gtk.MenuItem ();
            advanced_submenu_menuitem.set_label ("Advanced");
            advanced_submenu_menuitem.set_submenu (submenu);

            menu = new Gtk.Menu ();

            menu.append (copy_menuitem);
            menu.append (copy_last_output_menuitem);
            menu.append (paste_menuitem);
            menu.append (select_all_menuitem);
            menu.append (new Gtk.SeparatorMenuItem ());
            menu.append (search_menuitem);
            menu.append (show_in_file_browser_menuitem);
            menu.append (new Gtk.SeparatorMenuItem ());
            menu.append (advanced_submenu_menuitem);
            menu.append (show_settings_menuitem);
            menu.insert_action_group ("win", actions);

            menu.popped_up.connect (() => {
                update_copy_output_sensitive ();
            });

            setup_ui ();
            show_all ();

            search_revealer.set_reveal_child (false);

            update_font ();
            Application.settings_sys.changed["monospace-font-name"].connect (update_font);
            Application.settings.changed["font"].connect (update_font);

            set_size_request (app.minimum_width, app.minimum_height);

            configure_event.connect (on_window_state_change);
            destroy.connect (on_destroy);
            focus_in_event.connect (() => {
                if (focus_timeout == 0) {
                    focus_timeout = Timeout.add (20, () => {
                        focus_timeout = 0;
                        return Source.REMOVE;
                    });
                }

                return false;
            });
        }

        /** Returns true if the code parameter matches the keycode of the keyval parameter for
          * any keyboard group or level (in order to allow for non-QWERTY keyboards) **/
#if VALA_0_42
        protected bool match_keycode (uint keyval, uint code) {
#else
        protected bool match_keycode (int keyval, uint code) {
#endif
            Gdk.KeymapKey [] keys;
            Gdk.Keymap keymap = Gdk.Keymap.get_default ();
            if (keymap.get_entries_for_keyval (keyval, out keys)) {
                foreach (var key in keys) {
                    if (code == key.keycode)
                        return true;
                }
            }

            return false;
        }

        private void setup_ui () {
            var provider = new Gtk.CssProvider ();

            provider.load_from_resource ("io/elementary/terminal/Application.css");
            // Vte.Terminal itself registers its default styling with the APPLICATION priority:
            // https://gitlab.gnome.org/GNOME/vte/blob/0.52.2/src/vtegtk.cc#L374-377
            // To be able to overwrite their styles, we need to use +1.
            Gtk.StyleContext.add_provider_for_screen (
                Gdk.Screen.get_default (),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1
            );

            get_style_context ().add_class ("terminal-window");

            var header = new Gtk.HeaderBar ();
            header.show_close_button = true;
            header.has_subtitle = false;
            header.get_style_context ().add_class ("default-decoration");

            set_titlebar (header);

            window_geometry_overlay = new Gtk.Overlay ();

            searchbar = new Terminal.Widgets.Searchbar (this);
            searchbar.get_style_context ().add_class ("searchbar");

            search_revealer = new Gtk.Revealer ();
            search_revealer.set_transition_type (Gtk.RevealerTransitionType.SLIDE_RIGHT);
            search_revealer.add (searchbar);
            search_revealer.margin = 12;
            search_revealer.hexpand = true;
            search_revealer.halign = Gtk.Align.END;
            search_revealer.valign = Gtk.Align.START;

            get_simple_action (ACTION_COPY).set_enabled (false);
            get_simple_action (ACTION_COPY_LAST_OUTPUT).set_enabled (false);
            get_simple_action (ACTION_SCROLL_TO_LAST_COMMAND).set_enabled (false);

            var searchbar_overlay = new Gtk.Overlay ();

            searchbar_overlay.add_overlay (search_revealer);
            window_geometry_overlay.add (searchbar_overlay);
            add (window_geometry_overlay);

            key_press_event.connect ((e) => {
                if (e.is_modifier == 1) {
                    return false;
                }

                switch (e.keyval) {
                    case Gdk.Key.Escape:
                        if (searchbar.search_entry.has_focus) {
                            search_is_active = !search_is_active;
                            return true;
                        }
                        break;
                    case Gdk.Key.Return:
                        if (search_toolbar.search_entry.has_focus) {
                            if (Gdk.ModifierType.SHIFT_MASK in e.state) {
                                search_toolbar.previous_search ();
                            } else {
                                searchbar.next_search ();
                            }
                            return true;
                        } else {
                            terminal.remember_position ();
                            get_simple_action (ACTION_SCROLL_TO_LAST_COMMAND).set_enabled (true);
                            terminal.remember_command_end_position ();
                            get_simple_action (ACTION_COPY_LAST_OUTPUT).set_enabled (false);
                        }
                        break;

                    case Gdk.Key.@1: //alt+[1-8]
                    case Gdk.Key.@2:
                    case Gdk.Key.@3:
                    case Gdk.Key.@4:
                    case Gdk.Key.@5:
                    case Gdk.Key.@6:
                    case Gdk.Key.@7:
                    case Gdk.Key.@8:
                        if (Gdk.ModifierType.MOD1_MASK in e.state &&
                            Application.settings.get_boolean ("alt-changes-tab")) {
                            var i = e.keyval - 49;
                            if (i > notebook.n_tabs - 1)
                                return false;
                            notebook.current = notebook.get_tab_by_index ((int) i);
                            return true;
                        }
                        break;
                    case Gdk.Key.@9:
                        if (Gdk.ModifierType.MOD1_MASK in e.state &&
                            Application.settings.get_boolean ("alt-changes-tab")) {
                            notebook.current = notebook.get_tab_by_index (notebook.n_tabs - 1);
                            return true;
                        }
                        break;

                    case Gdk.Key.Up:
                    case Gdk.Key.Down:
                        terminal.remember_command_start_position ();
                        break;
                    case Gdk.Key.Menu:
                        /* Popup context menu below cursor position */
                        long col, row;
                        terminal.get_cursor_position (out col, out row);
                        var cell_width = terminal.get_char_width ();
                        var cell_height = terminal.get_char_height ();
                        var rect_window = terminal.get_window ();
                        var vadj_val = terminal.get_vadjustment ().get_value ();

                        Gdk.Rectangle rect = {(int)(col * cell_width),
                                              (int)((row - vadj_val) * cell_height),
                                              (int)cell_width,
                                              (int)cell_height};

                        menu.popup_at_rect (rect_window,
                                            rect,
                                            Gdk.Gravity.SOUTH_WEST,
                                            Gdk.Gravity.NORTH_WEST,
                                            e);
                        menu.select_first (false);
                        break;
                    default:
                        if (!(Gtk.accelerator_get_default_mod_mask () in e.state)) {
                            terminal.remember_command_start_position ();
                        }

                        break;
                }

                /* Use hardware keycodes so the key used
                 * is unaffected by internationalized layout */
                if (Gdk.ModifierType.CONTROL_MASK in e.state &&
                    Application.settings.get_boolean ("natural-copy-paste")) {
                    uint keycode = e.hardware_keycode;
                    if (match_keycode (Gdk.Key.c, keycode)) {
                        if (terminal.get_has_selection ()) {
                            terminal.copy_clipboard ();
                            if (!(Gdk.ModifierType.SHIFT_MASK in e.state)) { /* Shift not pressed */
                                terminal.unselect_all ();
                            }
                            return true;
                        } else { /* Ctrl-c: Command cancelled */
                            terminal.last_key_was_return = true;
                        }
                    } else if (match_keycode (Gdk.Key.v, keycode)) {
                        return handle_paste_event ();
                    }
                }

                if (Gdk.ModifierType.MOD1_MASK in e.state) {
                    uint keycode = e.hardware_keycode;

                    if (e.keyval == Gdk.Key.Up) {
                        return !get_simple_action (ACTION_SCROLL_TO_LAST_COMMAND).enabled;
                    }

                    if (match_keycode (Gdk.Key.c, keycode)) { /* Alt-c */
                        update_copy_output_sensitive ();
                    }
                }

                return false;
            });

            var t = new TerminalWidget (this);
            t.scrollback_lines = Application.settings.get_int ("scrollback-lines");

            /* Make the terminal occupy the whole GUI */
            t.vexpand = true;
            t.hexpand = true;

            t.set_font (term_font);
            t.active_shell ();

            searchbar_overlay.add (t);
            terminal = t;
        }

        private void get_border_dimensions (int char_width, int char_height, out int border_width, out int border_height) {
            Gtk.Requisition minimum_size, natural_size;

            terminal.get_preferred_size (out minimum_size, out natural_size);
            border_width = natural_size.width - (char_width * (int) terminal.get_column_count ());
            border_height = natural_size.height - (char_height * (int) terminal.get_row_count ());
        }

        private bool handle_paste_event () {
            if (searchbar.search_entry.has_focus) {
                return false;
            } else if (clipboard.wait_is_text_available ()) {
                action_paste ();
                return true;
            }

            return false;
        }

        private void restore_saved_state (bool restore_pos = true) {
            var rect = Gdk.Rectangle ();
            Terminal.Application.saved_state.get ("window-size", "(ii)", out rect.width, out rect.height);

            default_width = rect.width;
            default_height = rect.height;

            if (default_width == -1 || default_height == -1) {
                Gdk.Rectangle geometry;
                get_screen ().get_monitor_geometry (get_screen ().get_primary_monitor (), out geometry);

                default_width = geometry.width * 2 / 3;
                default_height = geometry.height * 3 / 4;
            }

            if (restore_pos) {
                Terminal.Application.saved_state.get ("window-position", "(ii)", out rect.x, out rect.y);

                if (rect.x != -1 || rect.y != -1) {
                    move (rect.x, rect.y);
                }
            }

            var window_state = Terminal.Application.saved_state.get_enum ("window-state");
            if (window_state == MainWindow.MAXIMIZED) {
                maximize ();
            } else if (window_state == MainWindow.FULLSCREEN) {
                fullscreen ();
                is_fullscreen = true;
            }
        }

        private void update_context_menu () {
            clipboard.request_targets (update_context_menu_cb);
        }

        private void update_context_menu_cb (Gtk.Clipboard clipboard_, Gdk.Atom[]? atoms) {
            bool can_paste = false;

            if (atoms != null && atoms.length > 0)
                can_paste = Gtk.targets_include_text (atoms) || Gtk.targets_include_uri (atoms);

            get_simple_action (ACTION_PASTE).set_enabled (can_paste);
        }

        private void update_copy_output_sensitive () {
            get_simple_action (ACTION_COPY_LAST_OUTPUT).set_enabled (terminal.has_output ());
        }

        private uint timer_window_state_change = 0;
        private bool on_window_state_change (Gdk.EventConfigure event) {
            // triggered when the size, position or stacking of the window has changed
            // it is delayed 400ms to prevent spamming gsettings
            if (timer_window_state_change > 0)
                GLib.Source.remove (timer_window_state_change);

            timer_window_state_change = GLib.Timeout.add (400, () => {
                timer_window_state_change = 0;
                if (get_window () == null)
                    return false;

                /* Check for fullscreen first: https://github.com/elementary/terminal/issues/377 */
                if ((get_window ().get_state () & Gdk.WindowState.FULLSCREEN) != 0) {
                    Terminal.Application.saved_state.set_enum ("window-state", MainWindow.FULLSCREEN);
                } else if (is_maximized) {
                    Terminal.Application.saved_state.set_enum ("window-state", MainWindow.MAXIMIZED);
                } else {
                    Terminal.Application.saved_state.set_enum ("window-state", MainWindow.NORMAL);

                    var rect = Gdk.Rectangle ();
                    get_size (out rect.width, out rect.height);
                    Terminal.Application.saved_state.set ("window-size", "(ii)", rect.width, rect.height);

                    int root_x, root_y;
                    get_position (out root_x, out root_y);
                    Terminal.Application.saved_state.set ("window-position", "(ii)", root_x, root_y);
                }

                return false;
            });

            if (get_window () == null)
                return false;

            int rows = (int) terminal.get_row_count ();
            int cols = (int) terminal.get_column_count ();

            if (this.rows != rows || this.cols != cols) {
                if (resize_overlay_callback_id != null) {
                    Source.remove (resize_overlay_callback_id);
                    resize_overlay.destroy ();
                }

                this.rows = rows;
                this.cols = cols;

                resize_overlay = new Gtk.Label (@"$rows x $cols");
                resize_overlay_callback_id = Timeout.add (1000, () => { resize_overlay.destroy (); return false; });

                resize_overlay.show_all ();
                window_geometry_overlay.add_overlay (resize_overlay);
            }

            return base.configure_event (event);
        }

        private void update_font () {
            // We have to fetch both values at least once, otherwise
            // GLib.Settings won't notify on their changes
            var app_font_name = Application.settings.get_string ("font");
            var sys_font_name = Application.settings_sys.get_string ("monospace-font-name");

            if (app_font_name != "") {
                term_font = Pango.FontDescription.from_string (app_font_name);
            } else {
                term_font = Pango.FontDescription.from_string (sys_font_name);
            }

            terminal.set_font (term_font);
        }

        private void on_destroy () {
            terminal.term_ps ();
        }

        private void on_get_text (Gtk.Clipboard board, string? intext) {
            /* if unsafe paste alert is enabled, show dialog */
            if (Application.settings.get_boolean ("unsafe-paste-alert") && !unsafe_ignored ) {

                if (intext == null) {
                    return;
                }
                if (!intext.validate ()) {
                    warning ("Dropping invalid UTF-8 paste");
                    return;
                }
                var text = intext.strip ();

                if ((text.index_of ("sudo") > -1) && (text.index_of ("\n") != 0)) {
                    var d = new UnsafePasteDialog (this);
                    if (d.run () == 1) {
                        d.destroy ();
                        return;
                    }
                    d.destroy ();
                }
            }

            terminal.remember_command_start_position ();

            if (board == primary_selection) {
                terminal.paste_primary ();
            } else {
                terminal.paste_clipboard ();
            }
        }

        private void action_copy () {
            if (terminal.uri != null && ! terminal.get_has_selection ())
                clipboard.set_text (terminal.uri,
                                    terminal.uri.length);
            else
                terminal.copy_clipboard ();
        }

        private void action_copy_last_output () {
            string output = terminal.get_last_output ();
            Gtk.Clipboard.get_default (Gdk.Display.get_default ()).set_text (output, output.length);
        }

        private void action_paste () {
            clipboard.request_text (on_get_text);
        }

        private void action_select_all () {
            terminal.select_all ();
        }

        private void action_open_in_files () {
            try {
                string uri = Filename.to_uri (terminal.get_shell_location ());

                try {
                     Gtk.show_uri (null, uri, Gtk.get_current_event_time ());
                } catch (Error e) {
                     warning (e.message);
                }

            } catch (ConvertError e) {
                warning (e.message);
            }
        }

        private void action_scroll_to_last_command () {
            terminal.scroll_to_last_command ();
            /* Repeated presses are ignored */
            get_simple_action (ACTION_SCROLL_TO_LAST_COMMAND).set_enabled (false);
        }

        private void action_new_window () {
            app.new_window ();
        }

        private void action_zoom_in_font () {
            terminal.increment_size ();
        }

        private void action_zoom_out_font () {
            terminal.decrement_size ();
        }

        private void action_zoom_default_font () {
            terminal.set_default_font_size ();
        }

        private void action_search () {
            var search_action = (SimpleAction) actions.lookup_action (ACTION_SEARCH);
            var search_state = search_action.get_state ().get_boolean ();

            search_action.set_state (!search_state);
            search_is_active = !search_is_active;
            search_revealer.set_reveal_child (search_is_active);

            if (search_is_active) {
                action_accelerators[ACTION_SEARCH_NEXT] = "<Control>g";
                action_accelerators[ACTION_SEARCH_NEXT] = "<Control>Down";
                action_accelerators[ACTION_SEARCH_PREVIOUS] = "<Control><Shift>g";
                action_accelerators[ACTION_SEARCH_PREVIOUS] = "<Control>Up";
                searchbar.grab_focus ();
            } else {
                action_accelerators.remove_all (ACTION_SEARCH_NEXT);
                action_accelerators.remove_all (ACTION_SEARCH_PREVIOUS);
                searchbar.clear ();
                terminal.grab_focus ();
            }

            string [] next_accels = new string [] {};
            if (!action_accelerators[ACTION_SEARCH_NEXT].is_empty) {
                next_accels = action_accelerators[ACTION_SEARCH_NEXT].to_array ();
            }

            string [] prev_accels = new string [] {};
            if (!action_accelerators[ACTION_SEARCH_NEXT].is_empty) {
                prev_accels = action_accelerators[ACTION_SEARCH_PREVIOUS].to_array ();
            }

            app.set_accels_for_action (
                ACTION_PREFIX + ACTION_SEARCH_NEXT,
                next_accels
            );
            app.set_accels_for_action (
                ACTION_PREFIX + ACTION_SEARCH_PREVIOUS,
                prev_accels
            );
        }

        private void action_search_next () {
            if (search_is_active) {
                searchbar.next_search ();
            }
        }

        private void action_search_previous () {
            if (search_is_active) {
                searchbar.previous_search ();
            }
        }

        private void action_fullscreen () {
            if (is_fullscreen) {
                unfullscreen ();
                is_fullscreen = false;
            } else {
                fullscreen ();
                is_fullscreen = true;
            }
        }

        private void action_show_inspector () {
            set_interactive_debugging (true);
        }

        private void action_show_settings () {
            var settings_dialog = new SettingsDialog ();

            settings_dialog.zoom_default.connect (() => {
                action_zoom_default_font ();
            });
            settings_dialog.zoom_out.connect (() => {
                action_zoom_out_font ();
            });
            settings_dialog.zoom_in.connect (() => {
                action_zoom_in_font ();
            });

            settings_dialog.show ();
        }

        private uint name_check_timeout_id = 0;
        private void schedule_name_check () {
            if (name_check_timeout_id > 0) {
                Source.remove (name_check_timeout_id);
            }

            name_check_timeout_id = Timeout.add (50, () => {
                name_check_timeout_id = 0;
                return false;
            });
        }

        /** Return enough of @path to distinguish it from @conflict_path **/
        private string disambiguate_label (string path, string conflict_path) {
            string prefix = "";
            string conflict_prefix = "";
            string temp_path = path;
            string temp_conflict_path = conflict_path;
            string basename = Path.get_basename (path);

            if (basename != Path.get_basename (conflict_path)) {
                return basename;
            }

            /* Add parent directories until path and conflict path differ */
            while (prefix == conflict_prefix) {
                var parent_temp_path = get_parent_path_from_path (temp_path);
                var parent_temp_confict_path = get_parent_path_from_path (temp_conflict_path);
                prefix = Path.get_basename (parent_temp_path) + Path.DIR_SEPARATOR_S + prefix;
                conflict_prefix = Path.get_basename (parent_temp_confict_path) + Path.DIR_SEPARATOR_S + conflict_prefix;
                temp_path = parent_temp_path;
                temp_conflict_path = parent_temp_confict_path;
            }

            return (prefix + basename).replace ("//", "/");
        }

        /*** Simplified version of PF.FileUtils function, with fewer checks ***/
        private string get_parent_path_from_path (string path) {
            if (path.length < 2) {
                return Path.DIR_SEPARATOR_S;
            }

            StringBuilder string_builder = new StringBuilder (path);
            if (path.has_suffix (Path.DIR_SEPARATOR_S)) {
                string_builder.erase (string_builder.str.length - 1, -1);
            }

            int last_separator = string_builder.str.last_index_of (Path.DIR_SEPARATOR_S);
            if (last_separator < 0) {
                last_separator = 0;
            }

            string_builder.erase (last_separator, -1);
            return string_builder.str + Path.DIR_SEPARATOR_S;
        }

        public GLib.SimpleAction? get_simple_action (string action) {
            return actions.lookup_action (action) as GLib.SimpleAction;
        }
    }
}
