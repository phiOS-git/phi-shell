pragma Singleton
import Quickshell

// phiOS — Services/PowerActions (docs/TODO.md: "add a power icon to the
// left isle of the status bar, it's overlay should have power options
// (suspend, logout, shutdown, lock, hibernate, reboot) ... add log out,
// lock, suspend, hibernate, reboot, shutdown commands so that they can be
// quickly referenced in the runner bar as well"). One owner for the six
// system-power commands so the actual command line for e.g. "reboot" is
// written once, not once per surface — Panels/BarPopout.qml's "power"
// section and Launcher/Launcher.qml's "system" action kind (sourced from
// `phi query`'s SystemActionsProvider) both call `perform()` here rather
// than each keeping its own copy.
//
// "lock" and "logout" are lifted from Launcher/Launcher.qml verbatim,
// where they already existed before this file did (that comment's own
// reasoning carries over): lock goes through Lock/Lock.qml's IpcHandler,
// never `loginctl lock-session` directly, because unlocking has no IPC
// path (Lock.qml's own header) and locking-by-IPC is the one already-
// proven-safe entry point; logout mirrors hyprland.lua's own Super+M
// binding exactly, so the two paths to the same action never disagree.
// suspend/hibernate/reboot/shutdown are plain `systemctl` verbs — no
// existing binding to match, since none of the four had a keybind or any
// other trigger anywhere in this project before this entry.
Singleton {
    id: root

    function lock() {
        // See Launcher/Launcher.qml's original version of this line for
        // why `-p` is required here: `qs ipc call` with no instance
        // selector targets the DEFAULT config, and phi-shell is launched
        // as a named one (`qs -p ~/.config/quickshell/phi`).
        Quickshell.execDetached(["qs", "-p", Quickshell.configDir, "ipc", "call", "lock", "lock"])
    }
    function suspend() { Quickshell.execDetached(["systemctl", "suspend"]) }
    function hibernate() { Quickshell.execDetached(["systemctl", "hibernate"]) }
    function logout() {
        Quickshell.execDetached(["sh", "-c",
            "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"])
    }
    function reboot() { Quickshell.execDetached(["systemctl", "reboot"]) }
    function shutdown() { Quickshell.execDetached(["systemctl", "poweroff"]) }

    // docs/TODO.md: "Reboot and Shutdown should require confirmation" —
    // one place both surfaces ask the same question, rather than each
    // deciding independently (and potentially disagreeing) which of the
    // six actions is destructive enough to need a second step.
    function needsConfirm(action) { return action === "reboot" || action === "shutdown" }

    // The display title for an action id — Panels/BarPopout.qml's button
    // labels and Launcher/Launcher.qml's confirm-view prompt both read
    // from here, so the two surfaces cannot describe the same action
    // differently.
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
