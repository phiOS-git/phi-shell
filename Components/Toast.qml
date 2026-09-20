import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// Animated icon with scrolling text; one per screen. One notification shown
// at a time from Services.Notifications queue. Bottom-right to avoid bar-height
// formula duplication. Fade: instant easing. Marquee: linear motion (eased
// loop would read as pulse); dwell reuses motionAPeriod constant.

PanelWindow {
    id: root

    required property ShellScreen screen

    readonly property var notification: Services.Notifications.activeToast
    readonly property bool shown: root.notification !== null
    readonly property string appIconPath: root.shown && root.notification.appIcon.length > 0
        ? Quickshell.iconPath(root.notification.appIcon, true) : ""
    readonly property string excerptText: root.shown
        ? (root.notification.appName.length > 0 ? root.notification.appName + " — " : "")
            + (root.notification.summary.length > 0 ? root.notification.summary : root.notification.body)
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

    margins { bottom: root.edgeMargin; right: root.edgeMargin }

    implicitWidth: root.toastWidth
    implicitHeight: layout.implicitHeight + panel.padding * 2
    // PanelWindow has no opacity property; fade on fadeRoot (Item) instead.
    // Visible stays true until fade-out finishes to avoid mid-animation vanish.
    visible: root.shown || fadeRoot.opacity > 0

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Widgets.Panel {
            id: panel
            anchors.fill: parent
            hovered: toastHover.hovered

            // Click opens notifications panel (detail/actions/dismiss);
            // does not dismiss toast (Services/Notifications owns expiry).
            HoverHandler { id: toastHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Services.BarPopout.openNotifications() }

            Row {
                id: layout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.chWidth * Config.Appearance.space2

                Image {
                    id: appIconImage
                    visible: root.appIconPath.length > 0
                    source: root.appIconPath
                    width: root.chWidth * Config.Appearance.space4
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                    fillMode: Image.PreserveAspectFit
                }

                Item {
                    id: textClip
                    clip: true
                    width: root.toastWidth - (root.chWidth * Config.Appearance.space3 * 2)
                        - (appIconImage.visible ? appIconImage.width + layout.spacing : 0)
                    height: body.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Widgets.StyledText {
                        id: body
                        text: root.excerptText
                        sizeStep: 1

                        SequentialAnimation on x {
                            running: body.implicitWidth > textClip.width && root.shown
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
        }
    }

    // No local dismiss; Services/Notifications bounds lifetime centrally.
}
