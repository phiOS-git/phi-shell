pragma Singleton
import Quickshell

// phiOS — Services/ConfirmDialog. docs/TODO.md: "confirmation modals (like
// the one for power options) should be centered in the screen, with a dim
// and block the screen until they are resolved. Also make them a reusable
// component as other task (eg. the battery saving mode, see below) will
// use it." One owner for the shown/content state of the single shared
// full-screen dialog surface (Dialogs/ConfirmDialog.qml), same one-owner
// shape as Services/AgentPanel.qml, Services/Calendar.qml.
//
// Any caller anywhere in the shell opens it with `open({...})`; the caller
// hands over what to show and a plain JS callback for the confirm action —
// this file never knows what "reboot" or "disable battery saving" means,
// same separation Services/PowerActions.qml already keeps between the
// action and whatever asks for it.
Singleton {
    id: root

    property bool shown: false
    property string title: ""
    property string message: ""
    property string confirmLabel: "Confirm"
    property string cancelLabel: "Cancel"

    // Not exposed to consumers outside this file — Dialogs/ConfirmDialog.qml
    // reads it only through confirm() below, never directly, so a caller
    // can never be left with a stale reference after hide() clears it.
    property var _onConfirm: null

    // opts: { title, message, confirmLabel, cancelLabel, onConfirm }.
    // confirmLabel/cancelLabel default to "Confirm"/"Cancel" when omitted —
    // most callers (destructive system actions) want the action's own name
    // there instead ("Reboot", "Shut down"), same as the inline confirm
    // this replaces already did.
    function open(opts) {
        var o = opts || {}
        root.title = o.title || ""
        root.message = o.message || ""
        root.confirmLabel = o.confirmLabel || "Confirm"
        root.cancelLabel = o.cancelLabel || "Cancel"
        root._onConfirm = o.onConfirm || null
        root.shown = true
    }

    // Runs the callback AFTER hiding, not before: a callback that itself
    // opens another dialog (a real, expected case — the battery-saving
    // settings toggle mentioned in the TODO could chain a second confirm)
    // must not have its own open() immediately undone by this one's own
    // cleanup running afterwards.
    function confirm() {
        var cb = root._onConfirm
        root.hide()
        if (cb) cb()
    }

    function cancel() { root.hide() }

    function hide() {
        root.shown = false
        root._onConfirm = null
    }
}
