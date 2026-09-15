import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Dialogs/PowerMenu. docs/TODO.md: "when pressing SUPER+L instead
// of locking immediatly, evoke an overlay menu with options (lock,
// suspend, hibernate, shutdown, reboot)." Services/PowerMenu.qml owns the
// shown/double-tap state (see that file's header for the full mechanism
// and why it's not the same failure mode as the abandoned Spotlight
// bare-SUPER double-tap attempt) — this file is presentation only.
//
// Layer-shell/scrim/fade plumbing copied verbatim from Dialogs/
// ConfirmDialog.qml, same as Dialogs/BatteryAlert.qml before it.
//
// Restyled 2026-09-15 (references/lock-options-reference.webp,
// user-provided: "I would like to have the lock options like this") from
// a titled card containing a vertical Widgets.ListRow list to a bare
// horizontal Dialogs/PowerActionsRow pill row directly on the scrim,
// "Lock" marked with the accent fill as the default action — matching the
// reference image itself, which shows exactly that. Added "logout" (this
// menu never had it before, though Services/PowerActions.qml always
// could) since the reference includes it and Lock/Lock.qml's own new
// power row (added the same day, same request's second half: "add the
// power options in the lockscreen as well to use them without
// unlocking") uses the identical action set minus "lock" itself.
// Reboot/shutdown still go through the existing Services.ConfirmDialog
// "this cannot be undone" step (Services/PowerActions.needsConfirm()) —
// PowerActionsRow's own `chosen` signal only decides whether to interpose
// that step, the mechanism itself is untouched.
PanelWindow {
    id: root

    readonly property bool shown: Services.PowerMenu.shown

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    Services.LayerFocus { target: root }

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
        // Style pass 2026-09-14: same reasoning as Dialogs/ConfirmDialog's
        // own strong scrim — a menu of session-ending actions (including
        // shutdown/reboot) is the same weight of full-attention blocking
        // surface, and this and ConfirmDialog should not visibly disagree
        // about how urgent that class of decision reads.
        strong: true
    }
    // Style pass 2026-09-15 (reported directly, comparing against
    // references/lock-options-reference.webp: "dim is too soft"). This
    // overlay sits on top of the REAL, likely bright desktop — windows,
    // terminals, whatever was on screen — not a pre-muted photo the way
    // the reference's own backdrop is, so `strong` alone (80% black, this
    // shell's own darkest existing token) still let more of it show than
    // the reference's mood calls for. A second identical layer compounds
    // it (two 80%-opaque blacks stack to ~96% transmittance) using the
    // same existing token twice rather than inventing a new one-off
    // opacity value. No blur effect is available here (would need an
    // unverified Qt graphical-effects module this codebase has never
    // taken a dependency on) — this is the lever design tokens allow.
    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
        strong: true
    }

    function _confirmAndPerform(action) {
        Services.ConfirmDialog.open({
            title: Services.PowerActions.title(action),
            message: "This cannot be undone.",
            confirmLabel: Services.PowerActions.title(action),
            onConfirm: () => Services.PowerActions.perform(action)
        })
        Services.PowerMenu.hide()
    }
    function _choose(action) {
        if (Services.PowerActions.needsConfirm(action)) root._confirmAndPerform(action)
        else { Services.PowerActions.perform(action); Services.PowerMenu.hide() }
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Services.PowerMenu.hide()
        }

        // Swallow clicks on the row itself so tapping a pill doesn't also
        // hit this Item's own click-outside-closes MouseArea above.
        Item {
            anchors.centerIn: parent
            width: pills.implicitWidth
            height: pills.implicitHeight

            MouseArea { anchors.fill: parent }

            focus: root.shown
            Keys.onEscapePressed: Services.PowerMenu.hide()

            PowerActionsRow {
                id: pills
                actions: ["lock", "logout", "suspend", "hibernate", "reboot", "shutdown"]
                highlightedAction: "lock"
                onChosen: (action) => root._choose(action)
            }
        }
    }
}
