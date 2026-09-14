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

    // Style pass 2026-09-14 (docs/TODO.md: "history time setting has a
    // text filed for a number + time measure ... the content does not fit
    // the space and overflows"). Every suffix in this shell before " days"
    // (Notifications.qml's retention field) was 1-3 characters ("%", "px",
    // "K", "×"); this widget's field was a flat space6 (~8ch), just wide
    // enough for the SHORT ones, so "365 days" (8 characters) ran right up
    // against — and, with inset padding eating into that same 8ch, past —
    // the field's own edge. Measures the widest value this field can
    // actually show (from/to, at the real decimals/suffix) instead of
    // guessing a fixed width, so a long suffix simply gets more room
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
