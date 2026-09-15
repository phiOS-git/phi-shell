import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../Bar/glyphs.js" as Glyphs

// phiOS — Dialogs/PowerMenu. docs/TODO.md: "when pressing SUPER+L instead
// of locking immediatly, evoke an overlay menu with options (lock,
// suspend, hibernate, shutdown, reboot)." Services/PowerMenu.qml owns the
// shown/double-tap state (see that file's header for the full mechanism
// and why it's not the same failure mode as the abandoned Spotlight
// bare-SUPER double-tap attempt) — this file is presentation only.
//
// Layer-shell/scrim/fade plumbing copied verbatim from Dialogs/
// ConfirmDialog.qml, same as Dialogs/BatteryAlert.qml before it. Each
// action row is Widgets.ListRow — already animates its own background on
// hover (WidgetStates.surfaceColors + a Behavior on color), which is the
// "hover animations" the TODO asks for; no bespoke hover mechanism
// invented here. Reboot/shutdown still go through the existing
// Services.ConfirmDialog "this cannot be undone" step (Services/
// PowerActions.needsConfirm()), the exact same shape Panels/
// BarPopout.qml's own power card already uses (`_confirmAndPerform`) —
// copied here rather than duplicated with different wording.
//
// Per-action icons (docs/TODO.md, resolved 2026-09-14): Lock, Suspend,
// Shut down and Reboot each get a real, confirmed `nf-md-*` codepoint
// (Bar/glyphs.js: lock, powerSleep, power, restart) — fetched a fresh
// copy of nerd-fonts' own glyphnames.json directly (not summarised, not
// recalled) and matched by exact icon name, avoiding the guess-then-hope
// mistake Bar/glyphs.js's own history already made twice (Steam, the
// scratchpad console icon). Hibernate (2026-09-15): no glyph named
// "hibernate" exists anywhere in nerd-fonts, so it used to render with no
// icon at all — visibly inconsistent next to four rows that all have one.
// Now uses Glyphs.hibernate, a deliberate substitute (see that file's own
// comment for the reasoning), confirmed against a real screenshot of this
// menu rather than assumed to render.
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

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }
        readonly property real chWidth: chMetrics.width

        Widgets.Panel {
            id: card
            anchors.centerIn: parent
            width: fadeRoot.chWidth * 30
            height: body.implicitHeight + padding * 2

            // Swallow clicks on the card so tapping a row doesn't also
            // hit fadeRoot's click-outside-closes MouseArea underneath.
            MouseArea { anchors.fill: parent }

            focus: root.shown
            Keys.onEscapePressed: Services.PowerMenu.hide()

            Column {
                id: body
                width: parent.width
                spacing: fadeRoot.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    width: parent.width
                    kind: "title"
                    sizeStep: 3
                    text: "Power"
                }

                Column {
                    width: parent.width
                    spacing: fadeRoot.chWidth * Config.Appearance.space1

                    Widgets.ListRow {
                        width: parent.width
                        label: "Lock"
                        glyph: Glyphs.lock
                        onActivated: root._choose("lock")
                    }
                    Widgets.ListRow {
                        width: parent.width
                        label: "Suspend"
                        glyph: Glyphs.powerSleep
                        onActivated: root._choose("suspend")
                    }
                    Widgets.ListRow {
                        width: parent.width
                        label: "Hibernate"
                        glyph: Glyphs.hibernate
                        onActivated: root._choose("hibernate")
                    }
                    Widgets.ListRow {
                        width: parent.width
                        label: "Shut down"
                        glyph: Glyphs.power
                        onActivated: root._choose("shutdown")
                    }
                    Widgets.ListRow {
                        width: parent.width
                        label: "Reboot"
                        glyph: Glyphs.restart
                        onActivated: root._choose("reboot")
                    }
                }
            }
        }
    }
}
