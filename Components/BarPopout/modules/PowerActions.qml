import QtQml
import qs.Config as Config
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

    // The per-action semantic tone painted as the HOVER background of each
    // button in this module's power rows (shutdown error-red, logout/reboot
    // warn-amber, suspend info-blue, lock/hibernate accent), and the paired
    // *Text token the glyph flips to while hovered so it stays readable on
    // the fill — the status card's compact row (Status.qml) reads these
    // directly. Dialogs/PowerActionsRow.qml carries the same two maps for
    // the PowerMenu/Lock pills; they are duplicated exactly as the glyph
    // map above is, because the BarPopout and Dialogs trees cannot import
    // each other. Rule 6: every entry is a design token, never a literal
    // colour.
    function toneFor(action) {
        switch (action) {
        case "lock": return Config.Appearance.accent
        case "suspend": return Config.Appearance.info
        case "hibernate": return Config.Appearance.accent
        case "logout": return Config.Appearance.warn
        case "reboot": return Config.Appearance.warn
        case "shutdown": return Config.Appearance.error
        }
        return Config.Appearance.textMuted
    }

    function toneTextFor(action) {
        switch (action) {
        case "lock": return Config.Appearance.accentText
        case "suspend": return Config.Appearance.infoText
        case "hibernate": return Config.Appearance.accentText
        case "logout": return Config.Appearance.warnText
        case "reboot": return Config.Appearance.warnText
        case "shutdown": return Config.Appearance.errorText
        }
        return Config.Appearance.textMuted
    }

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
