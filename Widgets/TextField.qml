import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/TextField (Out-of-plan: settings-overhaul batch A). The
// one text-entry primitive. Before this, three sections each inlined their
// own bare TextInput + placeholder + focus-border Rectangle
// (Settings/sections/Theme.qml, Keybindings.qml, Devices.qml), every copy
// noting "no text-entry widget exists in this library yet". This is that
// widget: a bordered box, a placeholder that clears on input, a focus ring
// (the one control state that still shows accent, §8.6 / OOP-02), and an
// `invalid` tint for a field validating free text (a hex colour, a number).
//
// Controlled, like Pill: `text` is a plain property the caller owns;
// editing emits `edited(text)` continuously and `committed(text)` on Enter
// or focus-out (Qt's TextInput.editingFinished). A caller that repaints the
// shell on every keystroke binds to `committed` only — a half-typed hex
// should not reach Config.ThemeOverrides.

Item {
    id: root

    // `text` is the field's own text, aliased straight to the TextInput so
    // there is no model/view copy to keep in sync and no binding loop
    // between them: the caller seeds it (Component.onCompleted / a reset)
    // and reads it back, the same imperative shape Settings/sections/
    // Theme.qml's inlined field already used.
    property alias text: input.text
    property string placeholder: ""
    property bool mono: true
    property bool invalid: false
    // echoMode passthrough for a future secrets field; default is normal.
    property int echoMode: TextInput.Normal
    property alias inputMethodHints: input.inputMethodHints
    property alias horizontalAlignment: input.horizontalAlignment
    property alias readOnly: input.readOnly

    readonly property bool keyboardFocus: input.activeFocus

    signal edited(string text)
    signal committed(string text)

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real padH: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
    readonly property real padV: WidgetStates.chToPixels(Config.Appearance.space1, chWidth) * 0.75

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: false, pressed: false,
        active: false, keyboardFocus: root.keyboardFocus,
        loading: false, invalid: root.invalid
    })

    implicitWidth: WidgetStates.chToPixels(Config.Appearance.space6, chWidth) * 3
    implicitHeight: input.implicitHeight + padV * 2
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: "transparent"
        border.width: Config.Appearance.borderWidth
        border.color: root.invalid ? Config.Appearance.error
            : (root.keyboardFocus ? Config.Appearance.focusRing : Config.Appearance.border)

        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }
    }

    StyledText {
        anchors.left: parent.left
        anchors.leftMargin: root.padH
        anchors.right: parent.right
        anchors.rightMargin: root.padH
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text.length === 0 && root.placeholder.length > 0
        kind: "label"
        mono: root.mono
        sizeStep: 1
        elide: Text.ElideRight
        text: root.placeholder
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: root.padH
        anchors.rightMargin: root.padH
        verticalAlignment: Text.AlignVCenter
        clip: true
        activeFocusOnTab: true
        echoMode: root.echoMode
        font.family: root.mono ? Config.Appearance.fontMono : Config.Appearance.fontUi
        font.pixelSize: Config.Appearance.fontSize1
        color: root.invalid ? Config.Appearance.error : Config.Appearance.textPrimary
        selectionColor: Config.Appearance.selectionBackground
        selectedTextColor: Config.Appearance.selectionText
        onTextEdited: root.edited(text)
        onEditingFinished: root.committed(text)
    }

    function forceEditFocus() { input.forceActiveFocus() }
}
