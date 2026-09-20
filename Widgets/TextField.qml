import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// The one text-entry primitive: a bordered box, a placeholder that clears on
// input, a focus ring (the one control state that still shows accent) and an
// `invalid` tint for a field validating free text (a hex colour, a number).
// Controlled, like Widgets/Toggle: `text` is a plain property the caller owns;
// editing emits `edited(text)` continuously and `committed(text)` on Enter or
// focus-out (Qt's TextInput.editingFinished). A caller that repaints the shell
// on every keystroke binds to `committed` only — a half-typed hex should not
// reach Config.ThemeOverrides.

Item {
    id: root

    // `text` is the field's own text, aliased straight to the TextInput so
    // there is no model/view copy to keep in sync and no binding loop between
    // them: the caller seeds it (Component.onCompleted / a reset) and reads it
    // back.
    property alias text: input.text
    property string placeholder: ""
    property bool mono: true
    property bool invalid: false
    // echoMode passthrough for a future secrets field; default is normal.
    property int echoMode: TextInput.Normal
    property alias inputMethodHints: input.inputMethodHints
    property alias horizontalAlignment: input.horizontalAlignment
    property alias readOnly: input.readOnly
    // On by default, since most callers of this widget are either a
    // search/filter field or a short value entry where clearing in one tap is
    // welcome either way; a caller that truly never wants it (a secrets field,
    // say) can turn it off.
    property bool clearable: true

    readonly property bool keyboardFocus: input.activeFocus

    signal edited(string text)
    signal committed(string text)
    // Escape here blurs the field rather than reaching whatever the field sits
    // inside (a panel, a dialog, a list row) — a panel should only close on
    // Escape when nothing inside it is still focused. A caller that wants a
    // second Escape to then close its own surface listens for this and
    // re-focuses its own fallback handler.
    signal escaped()

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real padH: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
    // The shared field/button height, so a TextField and a StyledButton in the
    // same Row match instead of the button towering.
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

    // The clear affordance: a muted "×" that brightens on hover, the same
    // low-key weight Widgets/SmallButton uses for a minor action — clearing a
    // field is common enough to deserve one tap, not a select-all-delete.
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

    // Set for the duration of the explicit blur below, and read by
    // onEditingFinished: Qt's TextInput emits editingFinished on ANY focus
    // loss, not just Enter — so `input.focus = false` here would otherwise
    // also fire root.committed(text), turning Escape into a silent commit of
    // whatever half-typed text is in the field. Escape means cancel not
    // commit.
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
