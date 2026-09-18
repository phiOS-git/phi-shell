import QtQml
import qs.Services as Services
import "../../Bar/glyphs.js" as Glyphs

// The power-action glyph/confirm logic shared by the "power" card (six
// full rows) and the "status" card's own compact power-icon row — each
// instantiates this once as a plain child, same reusable-non-singleton
// shape as Services/LayerFocus.qml.
//
// Confirmation: Services/ConfirmDialog.qml's shared centered modal closes
// every other panel (this popout included) the moment it opens, so
// cancelling returns to a closed bar, not a still-open action list.

QtObject {
    id: root

    function glyph(action) {
        switch (action) {
        case "lock": return Glyphs.lock
        case "suspend": return Glyphs.powerSleep
        case "hibernate": return Glyphs.hibernate
        case "logout": return Glyphs.logout
        case "reboot": return Glyphs.restart
        case "shutdown": return Glyphs.power
        }
        return ""
    }

    // Removed: a per-action `tone()` used to recolor each hovered icon
    // (lock/suspend/hibernate → accent/info, logout/reboot → warn,
    // shutdown → error). The status card's power row now shows a plain
    // background wash on hover instead (Status.qml), so the only consumer
    // in this module is gone. The per-action colours themselves live on
    // now as a steady glyph identity in Dialogs/PowerActionsRow.qml's own
    // `_toneFor()`, not as a hover effect.

    function request(action) {
        if (Services.PowerActions.needsConfirm(action)) root.confirmAndPerform(action)
        else { Services.PowerActions.perform(action); Services.BarPopout.hide() }
    }

    function confirmAndPerform(action) {
        Services.ConfirmDialog.open({
            title: Services.PowerActions.title(action),
            message: "This cannot be undone.",
            confirmLabel: Services.PowerActions.title(action),
            onConfirm: () => {
                Services.PowerActions.perform(action)
                Services.BarPopout.hide()
            }
        })
    }
}
