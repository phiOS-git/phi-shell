import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Panels/QuickNote. Requested: "add a quick note: when clicking the
// bottom right corner a quick floating editor window appears... Positioning
// the mouse in the corner should have show a small transition (inspired by
// macos corner note)." Services/ QuickNote.qml owns the text/persistence; this
// file is presentation a small always-present corner tab that grows on hover
// (the "small transition"), and expands into a full editor on click. Anchored
// bottom-right with content-sized implicitWidth/implicitHeight not a
// full-screen transparent surface — copied directly from
// Notifications/Toast.qml, the only other small, non-blocking corner surface
// in this repo. That choice matters specifically: a full-screen transparent
// PanelWindow would intercept pointer input across the WHOLE screen, breaking
// click- through to every window underneath. Sizing the window itself to just
// the corner tab (or the editor, once open) avoids that by construction — no
// click-outside-to-close handler is needed either, since clicking anywhere
// outside this small window never reaches it at all. exclusiveZone: 0 (Toast's
// own choice, not -1): this is an ambient on-demand utility, not a blocking
// modal — it reserves no space and does not dim/cover anything else, so it
// sits outside the still-open "dim coverage split" TODO entirely. Single
// instance on screens[0], not per-screen: same reasoning as every other
// focused/toggled (not ambient-per-monitor) surface in this repo — one note,
// not one per monitor. Flagged for cheap veto, the same standing caveat every
// prior single-vs-per-screen call in this repo carries.
PanelWindow {
    id: root

    readonly property bool shown: Services.QuickNote.shown

    anchors { bottom: true; right: true }
    exclusiveZone: 0
    color: "transparent"

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    // No margin, deliberately: the TODO names "positioning the mouse in the
    // corner" as the trigger, the same macOS hot-corner gesture that flings
    // the pointer to the true screen edge — an inset tab would sit in a gap
    // the gesture overshoots, and never register as hovered at all.

    readonly property real editorWidth: chWidth * 42
    readonly property real editorHeight: chWidth * 26

    // Gated on cardFade.visible (== shown || still fading out), not root.shown directly: shrinking the window the instant `shown` goes false would clip cardFade's own fade-out mid-animation, since the window's geometry and the card's opacity would then be animating in opposite directions at once.
    // Keeping the window editor-sized until the fade has actually finished avoids that.
    implicitWidth: cardFade.visible ? root.editorWidth : tab.width
    implicitHeight: cardFade.visible ? root.editorHeight : tab.height

    Behavior on implicitWidth {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    // Only take real keyboard focus while the editor is actually open the
    // corner tab, like Toast, must never steal focus from whatever the user is
    // doing. Reactive, unlike Services/LayerFocus.qml's one-shot
    // Component.onCompleted shape — this window is a single, permanently-
    // alive instance whose focus need toggles over its lifetime, not a surface
    // created fresh each time it's shown. Also seeds the editor's text on
    // every open — imperatively, not a one-way `text:` binding (QML would
    // silently break the first time the user types). Merged into this one
    // handler rather than a second onShownChanged — QML does not support
    // declaring the same signal handler twice on one object.
    onShownChanged: {
        if (root.WlrLayershell)
            root.WlrLayershell.keyboardFocus = root.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        if (root.shown) {
            editor.text = Services.QuickNote.text
            editor.forceActiveFocus()
        }
    }

    // The corner "tab" — always present, scales up on hover, tap toggles the
    // editor open/closed.
    Item {
        id: tab
        readonly property real restSize: root.chWidth * 1.6
        readonly property real hoverSize: root.chWidth * 3.2
        // No root.shown branch: `tab` is already invisible whenever shown is
        // true (see `visible`), so that branch never reads.
        width: hoverHandler.hovered ? hoverSize : restSize
        height: hoverHandler.hovered ? hoverSize : restSize
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        visible: !root.shown

        Behavior on width {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on height {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Rectangle {
            anchors.fill: parent
            radius: Config.Appearance.radiusBase
            color: Config.Appearance.accent
            opacity: hoverHandler.hovered ? 0.9 : 0.55

            Behavior on opacity {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }

        HoverHandler { id: hoverHandler; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Services.QuickNote.toggle() }
    }

    // The editor itself — a Widgets.Panel matching every other card surface in this repo.
    // Fade lives on this wrapper Item, not on the Panel directly: Widgets/Panel.qml's own root already binds its own `opacity` internally) assigning `opacity:`/`visible:` on the Panel instance itself would silently replace that binding rather than compose with it.
    // Same fadeRoot-wraps-the-Panel shape as Dialogs/ConfirmDialog.qml and Dialogs/BatteryAlert.qml, and the same `shown || opacity > 0` visibility — fade-OUT actually renders instead of the Panel vanishing the instant `shown` flips false.
    Item {
        id: cardFade
        anchors.fill: parent
        opacity: root.shown ? 1 : 0
        visible: root.shown || cardFade.opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        Widgets.Panel {
            id: card
            anchors.fill: parent
            // Match the status bar's own background instead of the generic
            // "shaded" surface1 — the inner `textPanel` keeps the default and
            // now reads as a genuinely distinct inner section against it.
            bgColorOverride: Config.Appearance.colorMain
            focus: root.shown
            Keys.onEscapePressed: Services.QuickNote.hide()

            Column {
                anchors.fill: parent
                spacing: root.chWidth * Config.Appearance.space2

                Item {
                    id: header
                    width: parent.width
                    height: Math.max(titleText.implicitHeight, closeBtn.height)

                    Widgets.StyledText {
                        id: titleText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "title"
                        sizeStep: 2
                        text: "Quick note"
                    }
                    Widgets.StyledButton {
                        id: closeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Close"
                        Keys.onEscapePressed: Services.QuickNote.hide()
                        onClicked: Services.QuickNote.hide()
                    }
                }

                Widgets.Panel {
                    id: textPanel
                    width: parent.width
                    // Widgets.Panel's own padding is applied INTERNALLY —
                    // nothing extra to subtract beyond the header and the one
                    // Column spacing gap between them.
                    height: parent.height - header.height - parent.spacing

                    Flickable {
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: editor.implicitHeight
                        clip: true

                        TextEdit {
                            id: editor
                            width: parent.width
                            wrapMode: TextEdit.Wrap
                            font.family: Config.Appearance.fontUi
                            font.pixelSize: Config.Appearance.fontSize1
                            color: Config.Appearance.textPrimary
                            selectByMouse: true
                            persistentSelection: true
                            Keys.onEscapePressed: Services.QuickNote.hide()
                            onTextChanged: Services.QuickNote.setText(text)
                        }
                    }
                }
            }
        }
    }
}
