// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*
* Copyright (c) 2011-2017 elementary LLC. (https://elementary.io)
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

public class Terminal.Application : Gtk.Application {
    public static GLib.Settings saved_state;
    public static GLib.Settings settings;
    public static GLib.Settings settings_sys;

    private GLib.List <MainWindow> windows;

    public static string? working_directory = null;
    [CCode (array_length = false, array_null_terminated = true)]
    private static string[]? command_e = null;
    private static string? command_x = null;

    private static bool option_version = false;

    // option_new_window will be true if the new-window flag was given.
    private static bool option_new_window = false;

    public int minimum_width;
    public int minimum_height;

    static construct {
        saved_state = new GLib.Settings ("io.elementary.terminal.saved-state");
        settings = new GLib.Settings ("io.elementary.terminal.settings");
        settings_sys = new GLib.Settings ("org.gnome.desktop.interface");
    }

    construct {
        flags |= ApplicationFlags.HANDLES_COMMAND_LINE;
        flags |= ApplicationFlags.SEND_ENVIRONMENT;
        application_id = "io.elementary.terminal";  /* Ensures only one instance runs */

        Intl.setlocale (LocaleCategory.ALL, "");
    }

    public Application () {
        Granite.Services.Logger.initialize ("PantheonTerminal");
        Granite.Services.Logger.DisplayLevel = Granite.Services.LogLevel.DEBUG;

        windows = new GLib.List <MainWindow> ();
    }

    public void new_window () {
        var window = get_last_window ();

        if (window == null) {
            new MainWindow (this);
        }
    }

    public override int command_line (ApplicationCommandLine command_line) {
        // keep the application running until we are done with this commandline
        hold ();
        int res = _command_line (command_line);
        release ();
        return res;
    }

    public override void window_added (Gtk.Window window) {
        windows.append (window as MainWindow);
        base.window_added (window);
    }

    public override void window_removed (Gtk.Window window) {
        windows.remove (window as MainWindow);
        base.window_removed (window);
    }

    public override bool dbus_register (DBusConnection connection, string object_path) throws Error {
        base.dbus_register (connection, object_path);

        var dbus = new DBus ();
        connection.register_object (object_path, dbus);

        dbus.finished_process.connect ((id, process, exit_status) => {
            foreach (var window in windows) {
                var terminal = window.terminal;
                if (terminal.terminal_id == id) {

                    if (!terminal.is_init_complete ()) {
                        terminal.set_init_complete ();
                    } else {

                        if ((window.get_window ().get_state () & Gdk.WindowState.FOCUSED) == 0) {
                            var notification = new Notification (_("Task finished"));
                            notification.set_body (process);
                            notification.set_icon (new ThemedIcon ("utilities-terminal"));
                            send_notification (null, notification);
                        }
                    }

                }
            }
        });

        return true;
    }

    private static OptionContext get_options_context () {
        var context = new OptionContext (null);
        context.add_main_entries (ENTRIES, "pantheon-terminal");
        context.add_group (Gtk.get_option_group (true));

        // Disable automatic help to prevent default `exit(0)` behaviour.
        context.set_help_enabled (false);

        return context;
    }

    private int _command_line (ApplicationCommandLine command_line) {
        var context = get_options_context ();

        string[] args = command_line.get_arguments ();
        string commandline = "";
        string[] arg_opt = {};
        string[] arg_cmd = {};
        bool build_cmdline = false;

        /* Everything after "--" or "-x" or "--commandline=" is to be treated as a single command to be executed
         * (maybe with its own options) so it is not passed to the parser.  It will be passed as is to a new tab/shell.
         */
        foreach (unowned string s in args) {
            if (build_cmdline) {
                arg_cmd += s;
            } else {
                if (s == "--" || s == "-x" || s.has_prefix ("--commandline=")) {
                    if (s.has_prefix ("--commandline=") && s.length > 14) {
                        arg_cmd += s.substring (14);
                    }

                    build_cmdline = true;
                } else {
                    arg_opt += s;
                }
            }
        }

        commandline = string.joinv (" ", arg_cmd);

        try {
            unowned string[] tmp = arg_opt;
            context.parse (ref tmp);
        } catch (Error e) {
            stdout.printf ("pantheon-terminal: ERROR: " + e.message + "\n");
            return 0;
        }

        if (working_directory == null) {
            /* Try to get pwd from commandline (may still be null) */
            working_directory = command_line.getenv ("PWD");
        }

        if (command_e != null) {
            run_commands (command_e, working_directory);
        } else if (commandline.length > 0) {
            run_command_line (commandline, working_directory);
        } else if (command_x != null) {
            const string WARNING = "Usage: --commandline=[COMMANDLINE] without spaces around '='\r\n\r\n";
            start_terminal_with_working_directory (working_directory);
            get_last_window ().terminal.feed (WARNING.data);
        } else if (option_version) {
            command_line.print ("%s %s", Config.PROJECT_NAME, Config.VERSION + "\n\n");
        } else {
            start_terminal_with_working_directory (working_directory);
        }

        // Do not save the value until the next instance of
        // Pantheon Terminal is started
        command_e = null;
        command_x = null;
        option_new_window = false;
        working_directory = null;

        return 0;
    }

    private void run_commands (string[] commands, string? working_directory = null) {
        MainWindow? window;
        window = get_last_window ();

        if (window == null || option_new_window) {
            window = new MainWindow (this);
        }

        foreach (string command in commands) {
            new MainWindow.with_working_directory (this, working_directory);
        }
    }

    private void run_command_line (string command_line, string? working_directory = null) {
        new MainWindow.with_working_directory (this, working_directory);
    }

    private void start_terminal_with_working_directory (string? working_directory) {
        new MainWindow.with_working_directory (this, working_directory);
    }

    private MainWindow? get_last_window () {
        uint length = windows.length ();

        return length > 0 ? windows.nth_data (length - 1) : null;
    }

    private const OptionEntry[] ENTRIES = {
        { "version", 'v', 0, OptionArg.NONE, ref option_version, N_("Show version"), null },
        /* -e flag is used for running single string commands. May be more than one -e flag in cmdline */
        { "execute", 'e', 0, OptionArg.STRING_ARRAY, ref command_e, N_("Run a program in terminal"), "COMMAND" },

        /* -x flag is removed before OptionContext parser applied but is included here so that it appears in response
         *  to  the --help flag */
        { "commandline", 'x', 0, OptionArg.STRING, ref command_x,
          N_("Run remainder of line as a command in terminal. Can also use '--' as flag"), "COMMAND_LINE" },

        /* -n flag forces a new window, instead of a new tab */
        { "new-window", 'n', 0, OptionArg.NONE, ref option_new_window, N_("Open a new terminal window"), null },

        { "working-directory", 'w', 0, OptionArg.FILENAME, ref working_directory,
          N_("Set shell working directory"), "DIR" },

        { null }
    };

    public static int main (string[] args) {

        // Handle help directly in main, because we want output to go to the
        // calling terminal, not one of our own windows.
        foreach (unowned string s in args) {
            if (s == "-h" || s == "--help") {
                var context = get_options_context ();

                // sets the program name in the usage statement
                Environment.set_prgname (args[0]);

                var help = context.get_help (true, null);
                stdout.printf (help);
                return 0;
            }
        }

        var app = new Terminal.Application ();
        return app.run (args);
    }
}
