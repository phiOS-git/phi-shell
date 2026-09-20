import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Text-entry primitive: bordered box, clearing placeholder, focus ring,
// invalid tint. Controlled by caller: edited() fires continuously,
// committed() on Enter or focus-out.

Item {
    id: root

    // Text aliased to TextInput; no model/view copy or binding loop.
    property alias text: input.text
    property string placeholder: ""
    property bool mono: true
    property bool invalid: false
    // echoMode passthrough for a future secrets field; default is normal.
    property int echoMode: TextInput.Normal
    property alias inputMethodHints: input.inputMethodHints
    property alias horizontalAlignment: input.horizontalAlignment
    property alias readOnly: input.readOnly
    // On by default; callers can turn off for secrets fields.
    property bool clearable: true

    readonly property bool keyboardFocus: input.activeFocus

    signal edited(string text)
    signal committed(string text)
    // Escape blurs field (not propagated). Panel closes only when nothing
    // inside is focused. Listener can re-focus fallback handler for 2nd Escape.
    signal escaped()

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real padH: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
    // Shared field/button height so they match in a Row.
    readonly property real _controlHeight: WidgetStates.controlHeight(Config.Appearance, chWidth)
    readonly property bool _showClear: root.clearable && input.text.length > 0 && !root.readOnly
    readonly property real _clearSlot: _showClear ? (_controlHeight * 0.8 + padH) : 0

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: false, pressed: false,
        active: false, keyboardFocus: root.keyboardFocus,
        loading: false, invalid: root.invalid
    })

    implicitWidth: WidgetStates.chToPixels(Config.Appearance.space6, chWidth) * 3
    implicitHeight: Math.max(input.implicitHeight, _controlHeight)
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: "transparent"
        border.width: Config.Appearance.borderWidth
        border.color: root.invalid ? Config.Appearance.error
            : (root.keyboardFocus ? Config.Appearance.focusRing : Config.Appearance.border)

        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
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

    // Clear affordance: muted "×" that brightens on hover; common enough for
    // one tap vs select-all-delete.
    Item {
        id: clearBtn
        visible: root._showClear
        anchors.right: parent.right
        anchors.rightMargin: root.padH * 0.5
        anchors.verticalCenter: parent.verticalCenter
        width: root._controlHeight * 0.8
        height: width

        StyledIcon {
            anchors.centerIn: parent
            glyph: "×"
            sizeStep: 1
            color: clearHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted
            Behavior on color {
                ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
        }
        HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                input.text = ""
                root.edited("")
                root.committed("")
                input.forceActiveFocus()
            }
        }
    }

    // Set during blur to prevent editingFinished firing on Escape.
    // Qt emits editingFinished on any focus loss, not just Enter.
    property bool _escaping: false

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: root.padH
        anchors.rightMargin: root.padH + root._clearSlot
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
        onEditingFinished: if (!root._escaping) root.committed(text)
        Keys.onEscapePressed: {
            root._escaping = true
            input.focus = false
            root._escaping = false
            root.escaped()
        }
    }

    function forceEditFocus() { input.forceActiveFocus() }
}
