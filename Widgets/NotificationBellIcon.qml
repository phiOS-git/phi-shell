import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/NotificationBellIcon (docs/TODO.md, status-bar rework:
// "notifications (DND state as well)"). Same dumb/reusable icon family as
// the rest of Widgets/*Icon — Bar/modules/Notifications.qml owns the
// Services/Notifications.qml reads.
//
// Replaces Bar/modules/Notifications.qml's earlier flash-overlay
// technique outright, not just its symptom: that Rectangle was a CHILD
// added after Widgets/Segment.qml's own internal `layout` Item, which
// renders the glyph — anything appended later paints on top of it, so
// the old flash partially obscured the bell it was meant to highlight
// (found and documented while building Widgets/SunMoonIcon.qml, not
// fixed there since that file wasn't touching Notifications.qml). Moving
// the bell itself behind `iconDelegate` removes the whole overlay
// mechanism: there is nothing left to sit on top of the glyph, because
// the animation IS the glyph moving.
//
// `dnd` crossfades between the bell and bell-slashed glyphs (two Nerd
// Font shapes, same verified-against-glyphnames.json rune each already
// was) plus a small scale pop on the transition — a bare crossfade alone
// is the thing the user explicitly said isn't enough for the brightness
// icon; DND is a genuine binary rune swap with no continuous quantity to
// interpolate the way brightness/volume/battery have, so the pop is what
// keeps it from reading as flat. `hasPending` fades a small badge dot in
// and out (no continuous breathing — this is a static "something is
// waiting" state, not an ongoing process like charging/connecting, so it
// does not belong to category A the way those do; a fourth continuously-
// pulsing bar icon alongside battery/wifi/bluetooth would be noise, not
// polish). `arrived` swings the whole glyph — a short, damped rotation
// oscillation, once per call, category B timing per leg.

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property real dndAmount: 0.0   // 0..1, category-B Behavior at the call site
    property real pendingAmount: 0.0 // 0..1, category-B Behavior at the call site

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
    implicitWidth: Math.max(bellGlyph.implicitWidth, bellOffGlyph.implicitWidth)
    implicitHeight: Math.max(bellGlyph.implicitHeight, bellOffGlyph.implicitHeight)
    width: implicitWidth
    height: implicitHeight

    // Bell PUA codepoints — Nerd Font Material Design Icons, same set
    // Bar/glyphs.js already draws every bar icon from. Duplicated here
    // rather than importing glyphs.js (a Bar/-scoped file; Widgets/ stays
    // independent of it, matching every sibling icon in this family,
    // which take their symbol from the caller instead of reading it
    // themselves).
    readonly property string _bellGlyph: String.fromCodePoint(0xF009A)     // nf-md-bell
    readonly property string _bellOffGlyph: String.fromCodePoint(0xF009B)  // nf-md-bell_off

    Item {
        id: swingPivot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.implicitWidth
        height: root.implicitHeight
        transformOrigin: Item.Top

        Text {
            id: bellGlyph
            text: root._bellGlyph
            font.family: Config.Appearance.fontSymbol
            font.pixelSize: root._fontSize
            color: root.iconColor
            opacity: 1 - root.dndAmount
            anchors.centerIn: parent
        }
        Text {
            id: bellOffGlyph
            text: root._bellOffGlyph
            font.family: Config.Appearance.fontSymbol
            font.pixelSize: root._fontSize
            color: root.iconColor
            opacity: root.dndAmount
            anchors.centerIn: parent
        }

        scale: 1.0
        // No `Behavior on scale` here, deliberately: `dndPop` below
        // already drives `scale` with its own explicit two-step
        // NumberAnimation. A Behavior watches every write to the
        // property it's attached to, including ones an unrelated
        // Animation makes directly — stacking one on top of the other
        // would have them fighting over the same property instead of
        // cooperating.
    }

    // DND toggling gives the pivot a brief pop, on top of the crossfade.
    // Triggered by an exposed function, called once by the caller's own
    // discrete `onDndChanged` — NOT by `onDndAmountChanged` here: dndAmount
    // arrives wrapped in the caller's category-B Behavior, which reassigns
    // it on every animation frame of its ~120ms ramp (same reasoning
    // SunMoonIcon's header gives for why a Behavior-driven property
    // repaints every frame). A restart() on every one of those frames
    // would abort dndPop's two-leg sequence over and over and only ever
    // let it play out after the ramp itself finishes, well behind the
    // crossfade instead of together with it.
    function dndToggled() { dndPop.restart() }
    SequentialAnimation {
        id: dndPop
        NumberAnimation { target: swingPivot; property: "scale"; to: 1.14
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        NumberAnimation { target: swingPivot; property: "scale"; to: 1.0
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    // A short, damped swing — call arrived() once per notification.
    // Overlapping calls restart rather than queue (SF-4's own original
    // reasoning: a burst of notifications should not stack effects).
    function arrived() { swingAnim.restart() }
    SequentialAnimation {
        id: swingAnim
        NumberAnimation { target: swingPivot; property: "rotation"; to: -16
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        NumberAnimation { target: swingPivot; property: "rotation"; to: 11
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        NumberAnimation { target: swingPivot; property: "rotation"; to: -6
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        NumberAnimation { target: swingPivot; property: "rotation"; to: 0
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    Rectangle {
        width: Math.max(2, root._fontSize * 0.22)
        height: width
        radius: width / 2
        color: Config.Appearance.accent
        opacity: root.pendingAmount
        anchors.right: swingPivot.right
        anchors.top: swingPivot.top
        anchors.rightMargin: root._fontSize * 0.05
        anchors.topMargin: root._fontSize * 0.05
    }
}
