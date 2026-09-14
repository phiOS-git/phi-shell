import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/Calendar.qml (OOP-04, shell restyle). The user's
// directive: the calendar is not a sidebar tab any more — "it's not a side
// panel, rather a small panel appearing below the bar in the corner",
// opened by clicking the bar clock. PLACEHOLDER content by instruction;
// the real month/agenda view and any CalDAV backend are a separate job
// (architettura §8.8 is still open, no backlog step builds one).
//
// Single instance (shell.qml, screens[0]) — a focused toggled surface, not
// a per-monitor ambient one, same as Panels/Sidebar and Settings.
// Anchored top-right, just below the bar: the top margin is the bar's real
// height, published by Bar/Bar.qml through Services/BarMetrics (OOP-20 —
// this file used to keep its own `fontSize1 + space2·ch·2` guess).

PanelWindow {
    id: root

    readonly property bool shown: Services.Calendar.shown

    anchors { top: true; right: true; left: true; bottom: true }
    // docs/TODO.md: "the status bar overlays ... are still lower that they
    // should be" — same bug, same fix, as Panels/BarPopout.qml's own
    // `exclusiveZone` comment explains in full (including the primary
    // evidence for the mechanism and the falsifiable cases to watch for):
    // `0` (not `-1`) let the bar's own reservation already shift this
    // window's top-anchored origin down before the `anchors.topMargin`
    // below (bar height + gap) added the SAME height again on top of that.
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0

    // Style pass 2026-09-14: no Escape handling existed — click-outside
    // was the only way to close this panel, unlike its sibling small
    // corner surfaces (QuickNote already has it).
    Services.LayerFocus { target: root }

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    Timer {
        id: clockTimer
        property var now: new Date()
        interval: 1000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: now = new Date()
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        // Click anywhere outside the small panel closes it.
        MouseArea {
            anchors.fill: parent
            onClicked: Services.Calendar.hide()
        }

        Item {
            id: cardWrap
            anchors.top: parent.top
            anchors.right: parent.right
            // features-change (item 1): the same minimal gap the docks keep.
            anchors.topMargin: Services.BarMetrics.height + Config.Appearance.panelGap
            anchors.rightMargin: Config.Appearance.panelGap
            width: root.chWidth * 34
            height: panel.height

            // Swallow clicks on the card (border included).
            MouseArea { anchors.fill: parent }

            Widgets.Panel {
            id: panel
            width: parent.width
            radius: Config.Appearance.panelRadius
            height: bodyCol.implicitHeight + padding * 2

            focus: root.shown
            Keys.onEscapePressed: Services.Calendar.hide()

            Column {
                id: bodyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: root.chWidth * Config.Appearance.space2

                Widgets.StyledText {
                    kind: "title"
                    sizeStep: 3
                    text: Qt.formatDateTime(clockTimer.now, "dddd d MMMM yyyy")
                }

                // Follow-up (user, 2026-09-11): "the calendar overlay...
                // should have time animating like a flip clock" — six
                // Widgets.FlipDigit cells (H H : m m : s s), each flipping
                // independently only when the character it shows actually
                // changes; the colons are plain static text, they never
                // change so there's nothing to animate.
                //
                // docs/TODO.md follow-up (2026-09-14): "the ':' not
                // vertically aligned, also remove the borders" — both from
                // the same cause. `showCard: true` (the default) pads each
                // FlipDigit cell above and below its glyph for the card
                // frame/seam (Widgets/FlipDigit.qml's own `_padding`); the
                // plain colon Text has no such padding. A QtQuick Row
                // top-aligns children at y:0, so the taller, padded digit
                // cells sat visibly lower than the un-padded colon glyph.
                // `showCard: false` drops the frame, the seam and the
                // padding, leaving every cell the same height as a plain
                // Text at this font/size — the same colon glyph the digits
                // already reuse internally — so the row aligns without it.
                Row {
                    readonly property string hh: Qt.formatDateTime(clockTimer.now, "HH")
                    readonly property string mm: Qt.formatDateTime(clockTimer.now, "mm")
                    readonly property string ss: Qt.formatDateTime(clockTimer.now, "ss")

                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.hh.charAt(0) }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.hh.charAt(1) }
                    Widgets.StyledText { mono: true; sizeStep: 4; text: ":" }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.mm.charAt(0) }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.mm.charAt(1) }
                    Widgets.StyledText { mono: true; sizeStep: 4; text: ":" }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.ss.charAt(0) }
                    Widgets.FlipDigit { sizeStep: 4; showCard: false; value: parent.ss.charAt(1) }
                }
                Widgets.Separator { width: parent.width }
                Widgets.StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    kind: "label"
                    text: "Calendar and agenda view — placeholder. A month grid and "
                        + "event list land in a later pass (architettura §8.8)."
                }
            }
            } // Widgets.Panel
        } // cardWrap
    }
}
