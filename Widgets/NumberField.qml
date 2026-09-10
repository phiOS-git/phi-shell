import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/NumberField (Out-of-plan: settings-overhaul batch C). A
// numeric stepper: −  [value]  + . Used wherever a theme variable needs a
// number — font scale, spacing scale, radii, a motion duration, a wallpaper
// scale — because the user's directive for this round is "avoid sliders for
// theme variables": a slider invites idle dragging of a value that should
// be deliberate, and cannot show an exact figure. A slider stays for the
// two places a continuous sweep is the point (texture intensity, a bezier
// handle).
//
// Controlled: `value` is the caller's. `committed(value)` fires on a
// step-button press or when the field is edited and confirmed (Enter /
// focus-out) — never per keystroke.

Row {
    id: root

    property real value: 0
    property real step: 1
    property real from: -1e9
    property real to: 1e9
    property int decimals: 0
    property string suffix: ""

    signal committed(real value)

    spacing: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width

    function _fmt(v) {
        var s = Number(v).toFixed(root.decimals)
        return root.suffix.length > 0 ? s + root.suffix : s
    }
    function _clamp(v) { return Math.max(root.from, Math.min(root.to, v)) }
    function _apply(v) {
        var c = root._clamp(v)
        root.value = c
        field.text = root._fmt(c)
        root.committed(c)
    }

    onValueChanged: if (!field.keyboardFocus) field.text = root._fmt(root.value)
    Component.onCompleted: field.text = root._fmt(root.value)

    SmallButton {
        anchors.verticalCenter: parent.verticalCenter
        label: "−"
        enabled: root.value - root.step >= root.from - 1e-9
        onClicked: root._apply(root.value - root.step)
    }

    TextField {
        id: field
        anchors.verticalCenter: parent.verticalCenter
        width: WidgetStates.chToPixels(Config.Appearance.space6, root.chWidth)
        horizontalAlignment: Text.AlignHCenter
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        invalid: text.length > 0 && isNaN(parseFloat(text))
        onCommitted: (t) => {
            var n = parseFloat(t)
            if (!isNaN(n)) root._apply(n)
            else field.text = root._fmt(root.value)
        }
    }

    SmallButton {
        anchors.verticalCenter: parent.verticalCenter
        label: "+"
        enabled: root.value + root.step <= root.to + 1e-9
        onClicked: root._apply(root.value + root.step)
    }
}
