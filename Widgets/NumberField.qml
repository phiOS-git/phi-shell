import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// A numeric stepper: − [value] + . Used wherever a theme variable needs a
// number — font scale, spacing scale, radii, a motion duration, a wallpaper
// scale — rather than a slider: a slider invites idle dragging of a value that
// should be deliberate, and cannot show an exact figure. A slider stays for
// the two places a continuous sweep is the point (texture intensity, a bezier
// handle). Controlled: `value` is the caller's. `committed(value)` fires on a
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

    // A flat fixed width overflows for a long suffix like " days"
    // (Notifications.qml's retention field: "365 days" is 8 characters with
    // inset padding eating into the same space). Measures the widest value
    // this field can actually show (from/to, at the real decimals/suffix)
    // instead of guessing a fixed width, so a long suffix gets more room
    // rather than overflowing it.
    TextMetrics {
        id: widestMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: {
            var a = root._fmt(root.from)
            var b = root._fmt(root.to)
            return a.length >= b.length ? a : b
        }
    }
    readonly property real _minFieldWidth: WidgetStates.chToPixels(Config.Appearance.space6, chWidth)
    readonly property real _fieldWidth: Math.max(root._minFieldWidth,
        widestMetrics.width + WidgetStates.chToPixels(Config.Appearance.space2, chWidth))

    function _fmt(v) {
        var s = Number(v).toFixed(root.decimals)
        return root.suffix.length > 0 ? s + root.suffix : s
    }
    function _clamp(v) { return Math.max(root.from, Math.min(root.to, v)) }
    // Rounds `value` itself to `decimals`, not just the displayed text
    // otherwise a typed "5.7" into a `decimals: 0` field (or float drift from
    // repeatedly stepping by a fractional `step`) leaves the field showing "6"
    // while `value`, and the `committed` it emits, are still 5.7 underneath. A
    // caller wrapping its own `Math.round(v)` around the committed value stays
    // a harmless no-op once this rounds at the source.
    function _round(v) {
        var mult = Math.pow(10, root.decimals)
        return Math.round(v * mult) / mult
    }
    function _apply(v) {
        var c = root._round(root._clamp(v))
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
        width: root._fieldWidth
        horizontalAlignment: Text.AlignHCenter
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        invalid: text.length > 0 && isNaN(parseFloat(text))
        // Narrow (space6·ch) and never meant to sit empty — a clear button
        // here would just crowd the digits for no real gain over overtyping.
        clearable: false
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
