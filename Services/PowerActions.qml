pragma Singleton
import Quickshell

// One owner for the six system-power commands so the actual command line
// for e.g. "reboot" is written once, not once per surface — the bar
// popout's "power" section and Launcher/Launcher.qml's "system" action
// kind both call `perform()` here.
//
// "lock" goes through Components/Lock/Lock.qml's IpcHandler, never
// `loginctl lock-session` directly, because unlocking has no IPC path and
// locking-by-IPC is the one already-proven-safe entry point. "logout"
// mirrors hyprland.lua's own Super+M binding exactly, so the two paths to
// the same action never disagree. suspend/hibernate/reboot/shutdown are
// plain `systemctl` verbs.
Singleton {
    id: root

    function lock() {
        // `-p` is required: `qs ipc call` with no instance selector
        // targets the default config, and phi-shell is launched as a
        // named one (`qs -p ~/.config/quickshell/phi`).
        Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", "lock", "lock"])
    }
    function suspend() { Quickshell.execDetached(["systemctl", "suspend"]) }
    function hibernate() { Quickshell.execDetached(["systemctl", "hibernate"]) }
    function logout() {
        // `hyprshutdown` is not installed on this system, so the fallback
        // always runs. This build's Lua config rejects the traditional
        // dispatcher-string form, so the fallback uses the Lua-call form,
        // `hl.dsp.exit()` — matching hyprland.lua.tmpl's own SHIFT+M
        // binding and Hyprland's own bundled example config.
        Quickshell.execDetached(["sh", "-c",
            "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch \"hl.dsp.exit()\""])
    }
    function reboot() { Quickshell.execDetached(["systemctl", "reboot"]) }
    function shutdown() { Quickshell.execDetached(["systemctl", "poweroff"]) }

    // One place every confirming surface (the bar popout's power/status
    // sections, Launcher's system-action confirm view) reads, so they
    // can't disagree about which of the six actions needs a second step.
    function needsConfirm(action) {
        return action === "hibernate" || action === "logout"
            || action === "reboot" || action === "shutdown"
    }

    // The display title for an action id — every surface reads from here,
    // so none can describe the same action differently.
    function title(action) {
        switch (action) {
        case "lock": return "Lock"
        case "suspend": return "Suspend"
        case "hibernate": return "Hibernate"
        case "logout": return "Log out"
        case "reboot": return "Reboot"
        case "shutdown": return "Shut down"
        }
        return action
    }

    function perform(action) {
        switch (action) {
        case "lock": root.lock(); break
        case "suspend": root.suspend(); break
        case "hibernate": root.hibernate(); break
        case "logout": root.logout(); break
        case "reboot": root.reboot(); break
        case "shutdown": root.shutdown(); break
        }
    }
}
