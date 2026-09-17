import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// An animated icon with scrolling text; full detail lives in the sidebar,
// not here. Not a stack of toast cards: exactly one shown at a time, from
// Services.Notifications' own queue, so a burst of notifications reads as
// a sequence rather than a pile of overlapping boxes.
//
// One instance per screen (shell.qml's Variants, same pattern as Bar):
// every monitor shows the same toast, mirroring how the bar repeats per
// screen.
//
// Anchored bottom-right, not top where the bar lives: Bar.qml computes
// its own height from tokens with no property another file can read, so
// anchoring a second layer-shell surface directly below it would either
// duplicate that formula or risk overlap — bottom-right sidesteps that.
//
// The show/hide transition is near-instant, no organic easing, via the
// same Behavior-on-opacity idiom every Widgets/ surface uses. The marquee
// scroll inside is a different thing — continuous motion for as long as
// the toast is visible, not a state transition — so it's linear only; an
// eased loop would read as a pulse. The marquee's dwell at each end
// reuses motionAPeriod rather than a second magic-number constant: the
// same period already governs how long the loop takes to cross the text.

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
    // keyboardFocus defaults to WlrKeyboardFocus.None — a toast must
    // never steal focus, and that's already the case with nothing set here.

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
    // PanelWindow has no `opacity` property — a `PanelWindow { opacity:
    // ... }` binding still compiles as a dynamic property rather than
    // failing, so this is easy to miss until something tries to animate
    // it. The fade lives on `fadeRoot` below instead — a plain Item,
    // which does have a real, animatable opacity — and `visible` stays
    // true until that fade-out finishes, so the window doesn't vanish
    // mid-animation the way it would if `visible` just followed
    // `root.shown` directly.
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

            // Clicking the toast opens the notifications overlay, where
            // the actual detail/actions/dismiss controls live — a
            // shortcut to that panel, not new content on the toast
            // itself. A bare click does not also dismiss the toast:
            // Services/Notifications.qml's own centrally-timed expiry
            // still owns that — opening the panel to look at something is
            // not the same gesture as being done with it.
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

    // No local dismiss timer: Services/Notifications.qml bounds every
    // tracked notification's lifetime centrally and calls the real
    // Notification.expire(), which fires `closed` and advances this queue
    // through the same handler regardless of whether a toast was ever
    // showing it.
}
