import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Notifications/Toast (S-30, master plan §8.3 surface 3, and the
// closed decision in master-plan §2.3 / architettura §8.2.1: "notifica
// come icona animata con testo scorrevole, dettaglio nel pannello" — an
// animated icon with pager-style scrolling text, full detail lives in the
// sidebar (S-31), not here. Not a stack of toast cards: exactly one shown
// at a time, from Services.Notifications' own queue, so a burst of
// notifications reads as a sequence rather than a pile of overlapping
// boxes — matching the source sentence's singular "un'icona", not "delle
// icone".
//
// One instance per screen (shell.qml's Variants, same pattern as Bar.Bar,
// ADR 077): every monitor shows the same toast, mirroring how the bar
// itself repeats per screen rather than picking one "primary" monitor no
// document has ever named.
//
// Anchored bottom-right, not top where the bar lives: Bar.qml computes its
// own height from tokens with no property another file can read, so
// anchoring a second layer-shell surface directly below it would either
// duplicate that formula or risk overlap — bottom-right sidesteps the
// problem entirely and is itself a conventional corner for a transient
// notification. Flagged here for cheap veto if a screenshot says otherwise.
//
// Category B governs the show/hide transition (§6.5's own table names
// "notifiche e toast" under B): near-instant, no organic easing, via the
// same Behavior-on-opacity idiom every Widgets/ surface already uses.
// The marquee scroll inside is a different thing — continuous motion for
// as long as the toast is visible, not a state transition — read as
// Category A (§6.5: "continuo, leggero", the two named examples being
// kitty's cursor_trail and the agent's processing indicator): linear only,
// per A's own rule that an eased loop reads as a pulse, so no per-widget
// easing mapping is needed the way Category B has one.

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

    // Default dismiss delay when the sender did not request one:
    // NotificationServer reports "no expire timeout requested" as a
    // negative value per the Desktop Notification Specification, not zero
    // — zero itself means "never expire on its own", which this toast still
    // bounds, since an un-glanced-at toast blocking the whole queue behind
    // it would defeat the "reads as a sequence" goal above.
    readonly property int dismissAfter: root.shown && root.notification.expireTimeout > 0
        ? root.notification.expireTimeout : 5000

    anchors { bottom: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    // keyboardFocus defaults to WlrKeyboardFocus.None (confirmed against
    // the real WlrLayershell header) — a toast must never steal focus, and
    // that is already the case with nothing set here.

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
    visible: opacity > 0
    opacity: root.shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }

    Widgets.Panel {
        id: panel
        anchors.fill: parent

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
                        PauseAnimation { duration: 800 }
                        NumberAnimation {
                            to: -(body.implicitWidth - textClip.width)
                            duration: Config.Appearance.motionAPeriod
                            easing.type: Easing.Linear
                        }
                        PauseAnimation { duration: 800 }
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

    Timer {
        id: dismissTimer
        interval: root.dismissAfter
        onTriggered: Services.Notifications.dismissToast()
    }

    onNotificationChanged: {
        if (root.notification !== null) dismissTimer.restart()
        else dismissTimer.stop()
    }
}
