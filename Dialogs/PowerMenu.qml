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
// NOT DONE: per-action icons (see docs/VERIFICATION.md for the full
// write-up — that red-flagged note belongs there, not here). The TODO
// asks for icons on every row; only "Shut down" gets one here
// (Glyphs.power, already shipped and in use for the bar's own power
// icon). The other four would need new Nerd Font codepoints this session
// could not verify — Bar/glyphs.js's own history is two separate
// shipped-wrong-codepoint bugs (Steam, the scratchpad console icon), both
// user-reported, both from guessing instead of confirming against
// nerd-fonts' own glyphnames.json. Live lookups this session returned
// contradictory results (a "not found" that flipped to "found" on retry,
// and a claim that this project's own already-shipped `nf-md-*` codepoint
// family doesn't exist in the source file at all) — not something to
// build on. Every row still shows its full text label regardless, so a
// missing icon is a missing glyph, not a missing option.
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
                        onActivated: root._choose("lock")
                    }
                    Widgets.ListRow {
                        width: parent.width
                        label: "Suspend"
                        onActivated: root._choose("suspend")
                    }
                    Widgets.ListRow {
                        width: parent.width
                        label: "Hibernate"
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
                        onActivated: root._choose("reboot")
                    }
                }
            }
        }
    }
}
