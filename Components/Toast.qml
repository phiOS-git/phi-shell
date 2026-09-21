import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Icon-first toast: a compact avatar expands to reveal the notification text,
// then shrinks back away on dismiss. One shown at a time from
// Services.Notifications' queue. Clicking opens the source and dismisses it;
// the ✕ button or a two-finger swipe dismiss directly. On-screen duration is
// Services.Notifications.toastSeconds (0 = each notification's own timeout).

PanelWindow {
    id: root

    required property ShellScreen screen

    // Captured separately from the live activeToast: the service nulls that
    // out immediately on dismiss, but the out-animation still needs content
    // to render while it plays.
    property var shownNotification: null
    // True for the whole time the card sits at toastWidth with text shown;
    // drives the close button and the marquee.
    property bool expanded: false

    readonly property string appIconPath: root.shownNotification !== null && root.shownNotification.appIcon.length > 0
        ? Quickshell.iconPath(root.shownNotification.appIcon, true) : ""
    readonly property string excerptText: root.shownNotification !== null
        ? (root.shownNotification.appName.length > 0 ? root.shownNotification.appName + " — " : "")
            + (root.shownNotification.summary.length > 0 ? root.shownNotification.summary : root.shownNotification.body)
        : ""

    anchors { bottom: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    // keyboardFocus: defaults to WlrKeyboardFocus.None (never steal focus).

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real toastWidth: chWidth * 32
    readonly property real edgeMargin: chWidth * Config.Appearance.space3
    readonly property real iconSlot: root.chWidth * Config.Appearance.space4
    readonly property real compactWidth: root.iconSlot + Config.Appearance.panelPadding * 2

    margins { bottom: root.edgeMargin; right: root.edgeMargin }

    // Fixed surface size; the card animates inside it, no per-frame resizes.
    implicitWidth: root.toastWidth
    implicitHeight: layout.implicitHeight + Config.Appearance.panelPadding * 2
    visible: root.shownNotification !== null

    // --- swipe-to-dismiss ---------------------------------------------------
    property real swipeX: 0
    readonly property real _swipeRatio: 0.3 // swipe past this fraction of toastWidth dismisses
    readonly property bool _swiping: dragHandler.active || swipeReset.running

    Behavior on swipeX {
        enabled: !root._swiping
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    function _checkSwipe(final) {
        if (Math.abs(root.swipeX) > root.toastWidth * root._swipeRatio) {
            Services.Notifications.dismissToast()
        } else if (final) {
            root.swipeX = 0
        }
    }

    // Settles a touchpad swipe that stopped short of the threshold and
    // stopped generating wheel events, without waiting for a drag release.
    // Explicit stop() first: a non-repeating Timer's `running` can still read
    // true inside its own onTriggered, which would otherwise leave _swiping
    // true and skip the snap-back Behavior below.
    Timer {
        id: swipeReset
        interval: Config.Appearance.motionAPeriod / 4
        onTriggered: { swipeReset.stop(); root._checkSwipe(true) }
    }

    // --- content capture + arrival/dismissal sequencing ---------------------
    Connections {
        target: Services.Notifications
        function onActiveToastChanged() {
            const n = Services.Notifications.activeToast
            if (n !== null) {
                // Covers both "nothing was showing" and "one notification
                // replaced another directly": snap to compact/hidden with the
                // new content, then play the arrival sequence again.
                inSeq.stop()
                outSeq.stop()
                root.shownNotification = n
                root.swipeX = 0
                fadeRoot.opacity = 0
                card.width = root.compactWidth
                body.opacity = 0
                inSeq.start()
            } else {
                inSeq.stop()
                outSeq.start()
            }
        }
    }

    SequentialAnimation {
        id: inSeq
        NumberAnimation {
            target: fadeRoot; property: "opacity"; to: 1
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
        }
        ScriptAction { script: root.expanded = true }
        ParallelAnimation {
            NumberAnimation {
                target: card; property: "width"; to: root.toastWidth
                duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
            }
            NumberAnimation {
                target: body; property: "opacity"; to: 1
                duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
            }
        }
    }

    SequentialAnimation {
        id: outSeq
        ScriptAction { script: root.expanded = false }
        ParallelAnimation {
            NumberAnimation {
                target: card; property: "width"; to: root.compactWidth
                duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
            }
            NumberAnimation {
                target: body; property: "opacity"; to: 0
                duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
            }
        }
        NumberAnimation {
            target: fadeRoot; property: "opacity"; to: 0
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
        }
        // The sequence's own finished, not a child animation's: Qt suppresses
        // a child's finished on natural completion (see Lock/LockTransition.qml).
        onFinished: root.shownNotification = null
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        // Wraps card so its opacity animates without fighting Panel's own
        // internal Behavior on opacity (state-driven, kept intact on card).
        opacity: 0

        Widgets.Panel {
            id: card
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.compactWidth
            clip: true
            hovered: rowHover.hovered
            transform: Translate { x: root.swipeX }

            WheelHandler {
                acceptedDevices: PointerDevice.TouchPad
                orientation: Qt.Horizontal
                onWheel: (e) => {
                    root.swipeX += e.pixelDelta.x !== 0 ? e.pixelDelta.x : e.angleDelta.x / 8
                    swipeReset.restart()
                    root._checkSwipe()
                }
            }
            DragHandler {
                id: dragHandler
                target: null
                yAxis.enabled: false
                onTranslationChanged: root.swipeX = translation.x
                onActiveChanged: if (!active) root._checkSwipe(true)
            }

            // Icon first, text revealed to its right as the card grows. Row
            // sits at Panel's own padded content origin (anchors can only
            // reach a direct parent/sibling, not the Panel root beyond it),
            // which tracks card's left edge as width animates either way.
            Row {
                id: layout
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.chWidth * Config.Appearance.space2

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        const n = root.shownNotification
                        if (!n) return
                        Services.Notifications.openSource(n.appName, n)
                        try { n.dismiss() } catch (e) { n.tracked = false }
                    }
                }

                Item {
                    id: iconSlotItem
                    width: root.iconSlot
                    height: root.iconSlot
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: appIconImage
                        anchors.fill: parent
                        visible: root.appIconPath.length > 0
                        source: root.appIconPath
                        fillMode: Image.PreserveAspectFit
                    }
                    // No icon: fall back to the app name's first letter.
                    Widgets.StyledText {
                        anchors.centerIn: parent
                        visible: !appIconImage.visible
                        kind: "title"
                        text: root.shownNotification !== null && root.shownNotification.appName.length > 0
                            ? root.shownNotification.appName.charAt(0) : ""
                    }
                }

                Item {
                    id: textClip
                    clip: true
                    width: root.toastWidth - root.iconSlot - layout.spacing - Config.Appearance.panelPadding * 2
                        - (closeBtn.visible ? closeBtn.width + layout.spacing : 0)
                    height: body.implicitHeight

                    Widgets.StyledText {
                        id: body
                        text: root.excerptText
                        opacity: 0
                        sizeStep: 1

                        SequentialAnimation on x {
                            running: body.implicitWidth > textClip.width && root.expanded
                            loops: Animation.Infinite
                            PauseAnimation { duration: Config.Appearance.motionAPeriod }
                            NumberAnimation {
                                to: -(body.implicitWidth - textClip.width)
                                duration: Config.Appearance.motionAPeriod
                                easing.type: Easing.Linear
                            }
                            PauseAnimation { duration: Config.Appearance.motionAPeriod }
                            NumberAnimation {
                                to: 0
                                duration: Config.Appearance.motionAPeriod
                                easing.type: Easing.Linear
                            }
                        }
                    }
                }
            }

            Widgets.SmallButton {
                id: closeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "✕"
                visible: root.expanded
                onClicked: Services.Notifications.dismissToast()
            }
        }
    }
}
