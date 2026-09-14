import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Accordion (Out-of-plan: settings-overhaul batch G). A
// titled disclosure: a header row that toggles an inline body open and
// shut. Used by Settings/sections/Devices.qml for each Chroma integration's
// extra settings (the user's directive: "a setting button that opens extra
// settings with an accordion").
//
// Inline, not a popover — the settings content pane is a clipped Flickable
// (same constraint Widgets/ColorField.qml calls out). The body's height
// animates category B, the one transition category the whole shell shares.
//
// Stateless w.r.t. persistence: `expanded` is plain view state the caller
// can seed or ignore. The seven transverse states exist on the header for
// interface uniformity (§8.6); only default/hover/disabled/loading have a
// defined look for a disclosure header.

Column {
    id: root

    property string title: ""
    property bool expanded: false
    property bool loading: false
    default property alias content: body.data
    // Style pass 2026-09-14: an optional header-trailing action (a "clear"
    // button, say) — the gap this widget's own header comment left open
    // for docs/TODO.md's "sometimes have the arrow icon and sometimes
    // don't" complaint: Panels/tabs/Notifications.qml's own notification-
    // group header needed exactly this and grew a hand-rolled disclosure
    // instead, one more grammar the shell had to reconcile. Empty by
    // default so every existing caller (Devices.qml, Updates.qml) is
    // unaffected.
    property alias trailingAction: trailingSlot.data

    width: parent ? parent.width : 0
    spacing: 0

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real _ch: chMetrics.width
    readonly property real _pad: Config.Appearance.space2 * _ch

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: toggleArea.hovered, pressed: toggleArea.pressed,
        active: root.expanded, keyboardFocus: false,
        loading: root.loading, invalid: false
    })

    Item {
        id: header
        width: parent.width
        height: caret.implicitHeight + root._pad * 2

        // The trailing slot's own footprint, measured so the toggle area
        // below can stop short of it — same non-overlapping-regions shape
        // Panels/tabs/Notifications.qml's own group header already used,
        // so a trailing "clear" doesn't also toggle the disclosure (or vice
        // versa) the way one shared full-width TapHandler would.
        readonly property real _trailingW: trailingSlot.children.length > 0 ? trailingSlot.width : 0

        Item {
            id: toggleArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: header._trailingW > 0 ? header._trailingW + root._ch : 0
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            readonly property bool hovered: hover.hovered || toggleArea.activeFocus
            readonly property bool pressed: tap.pressed

            HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: tap; enabled: root.enabled; onTapped: root.expanded = !root.expanded }
            // Style pass 2026-09-14: a shared, reused widget (Devices'
            // Chroma integrations, Updates' package lists) with no
            // keyboard path to its own only action — see Widgets/
            // StyledButton.qml's identical comment for the general gap
            // this pass found and fixed across every shared widget type.
            activeFocusOnTab: true
            Keys.onReturnPressed: if (root.enabled) root.expanded = !root.expanded
            Keys.onSpacePressed: if (root.enabled) root.expanded = !root.expanded

            Rectangle {
                anchors.fill: parent
                radius: Config.Appearance.radiusSmall
                color: Config.Appearance.textPrimary
                opacity: toggleArea.hovered ? 0.06 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
            }

            StyledText {
                id: caret
                anchors.left: parent.left
                anchors.leftMargin: root._pad
                anchors.verticalCenter: parent.verticalCenter
                mono: true
                kind: "label"
                text: root.expanded ? "▾" : "▸"
            }
            StyledText {
                anchors.left: caret.right
                anchors.leftMargin: root._ch
                anchors.right: parent.right
                anchors.rightMargin: root._pad
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                elide: Text.ElideRight
            }
        }

        Item {
            id: trailingSlot
            anchors.right: parent.right
            anchors.rightMargin: root._pad
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    // Clipped wrapper so the body's own height can be animated without its
    // content spilling while collapsed. Style pass: "accordions don't
    // differentiate the body" (docs/TODO.md) — a hairline rule on the left
    // edge, inset from the header's own caret column, is the one piece of
    // chrome every collapsible surface in this shell can share regardless
    // of what its body actually holds (a settings sub-group, a list of
    // notification cards, …), so a body always reads as "inside" its
    // header rather than just another block of content below it.
    Item {
        width: parent.width
        height: root.expanded ? body.implicitHeight + root._pad : 0
        clip: true
        Behavior on height {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Rectangle {
            x: root._pad
            y: 0
            width: Config.Appearance.borderWidth
            height: parent.height
            color: Config.Appearance.border
        }

        Column {
            id: body
            width: parent.width - root._pad
            x: root._pad
            y: root._pad / 2
            spacing: Config.Appearance.space1 * root._ch
        }
    }
}
