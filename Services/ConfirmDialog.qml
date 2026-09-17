pragma Singleton
import Quickshell
import qs.Services as Services

// One owner for the shown/content state of the single shared full-screen
// dialog surface (Components/Dialogs/ConfirmDialog.qml), same one-owner
// shape as Services/AgentPanel.qml, Services/Calendar.qml.
//
// Any caller anywhere in the shell opens it with `open({...})`; the caller
// hands over what to show and a plain JS callback for the confirm action —
// this file never knows what "reboot" or "disable battery saving" means,
// the same separation Services/PowerActions.qml keeps between the action
// and whatever asks for it.
Singleton {
    id: root

    property bool shown: false

    // This dialog and the agent panel/settings panel raise themselves to
    // WlrLayer.Overlay and grab keyboard focus (Services/LayerFocus.qml)
    // while shown — unlike Services/Spotlight.qml, which is meant to layer
    // OVER an already-open panel, this dialog must be the ONLY such
    // surface holding focus, or which of two same-layer windows actually
    // receives a keypress is undefined — dangerous when one of them
    // defaults Enter to a destructive confirm. So opening this closes
    // every other panel rather than coexisting with them.
    onShownChanged: if (root.shown) {
        Services.AgentPanel.hide()
        Services.SettingsPanel.hide()
        Services.BarPopout.hide()
        Services.Calendar.hide()
    }

    property string title: ""
    property string message: ""
    property string confirmLabel: "Confirm"
    property string cancelLabel: "Cancel"

    // Not exposed to consumers outside this file — the dialog reads it
    // only through confirm() below, never directly, so a caller can never
    // be left with a stale reference after hide() clears it.
    property var _onConfirm: null

    // opts: { title, message, confirmLabel, cancelLabel, onConfirm }.
    // confirmLabel/cancelLabel default to "Confirm"/"Cancel" when omitted —
    // most callers (destructive system actions) want the action's own name
    // there instead ("Reboot", "Shut down").
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
    // opens another dialog (chaining a second confirm) must not have its
    // own open() immediately undone by this one's own cleanup running
    // afterwards.
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
