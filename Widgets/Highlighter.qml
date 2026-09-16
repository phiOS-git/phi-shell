import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// A "highlighter marker" text effect: a genuine masked reveal, distinct
// from Widgets/Segment.qml's own hover sweep (a plain Rectangle wash —
// Segment can hold a Canvas `iconDelegate`, and duplicating + clipping a
// second copy of an infinite-animation Canvas for every hover would double
// that cost). This widget wraps plain text only, so a second `Text` layer
// costs nothing: two identical Text items stacked (rest colour underneath,
// highlight colour on top), the top one clipped to a window that
// grows/shrinks across the text width instead of fading as a flat
// crossfade.
//
// Passive, like Widgets/StyledText: does not own its own HoverHandler —
// `hovered` is a plain property a parent drives (a ListRow, a search
// result row, anything that already owns a larger hoverable area than
// just this text). `trigger()` is the separate one-shot path for a
// highlight not tied to hover at all (e.g. a search result arriving) — it
// plays a quick full reveal and then closes the window from its LEFT edge
// moving right, distinct from the plain hover-out motion (the window's
// RIGHT edge simply retreating back where it came from).
//
// Model: a revealed window [_revealLeft, _revealRight] (both 0..1,
// fractions of the text's own width) marks which portion of the overlay
// (highlight-coloured) text is visible through the clip. Plain hover only
// ever moves `_revealRight` (0 at rest, 1 hovered) — `_revealLeft` stays
// pinned at 0, so the window always grows from/shrinks back to the left
// edge. `trigger()` additionally sweeps `_revealLeft` 0->1 once the window
// is already fully open, eating the highlight away from the left — motion
// the plain hover reverse does not produce on its own.
//
// Motion category B throughout: hover and a one-shot flash are both
// discrete, triggered state changes.

Item {
    id: root

    property string text: ""
    property string kind: "value" // "label" | "value" | "title" — same meaning as StyledText
    property string tone: ""
    property bool invalid: false
    property int sizeStep: 2
    property bool mono: false

    // Driven by a parent that owns the actual pointer/hover detection —
    // see this file's header. Toggling this plays the plain hover-in/out
    // motion; call trigger() instead for the one-shot "triggered highlight"
    // motion.
    property bool hovered: false

    readonly property color restColor: WidgetStates.contentColor(Config.Appearance, root.kind, root.tone, root.invalid)
    property color highlightColor: Config.Appearance.accent

    signal triggerFinished()

    implicitWidth: baseText.implicitWidth
    implicitHeight: baseText.implicitHeight

    readonly property real _textWidth: baseText.implicitWidth

    property real _revealLeft: 0
    property real _revealRight: 0

    // Only `_revealRight` gets an ambient Behavior: hover never touches
    // `_revealLeft` at all (see this file's header — hover only ever moves
    // the right edge). `_revealLeft` is driven exclusively by
    // flashSequence's own explicit NumberAnimation/PropertyAction steps
    // below, deliberately with NO Behavior of its own — two independent
    // same-duration Behaviors racing to reset both edges risks a visible
    // flicker if they don't land in the same frame; explicit,
    // deterministic PropertyAction steps avoid that entirely.
    Behavior on _revealRight {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    onHoveredChanged: {
        // A trigger() in flight owns the window until it finishes — do
        // not fight it with a hover-driven change arriving mid-flash.
        if (flashSequence.running) return
        root._revealLeft = 0
        root._revealRight = root.hovered ? 1 : 0
    }

    // The one-shot "triggered highlight... closing L to R" path. Opens the
    // window fully (same duration/curve as a hover-in, so it reads as the
    // same family of motion), holds briefly, then closes it by sweeping
    // `_revealLeft` up to meet `_revealRight`, then snaps both back to
    // their rest values in the same instant (PropertyAction, which sets a
    // value without going through any Behavior on that property) so the
    // reset itself is never visible — never touches `hovered`, so this
    // composes correctly with an element that is ALSO hoverable.
    function trigger() {
        flashSequence.restart()
    }

    function _openWindow() { root._revealRight = 1 }

    SequentialAnimation {
        id: flashSequence
        ScriptAction { script: root._openWindow() }
        PauseAnimation { duration: Config.Appearance.motionBDuration }
        NumberAnimation {
            target: root; property: "_revealLeft"
            from: 0; to: 1
            duration: Config.Appearance.motionBDuration
            easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve
        }
        PropertyAction { target: root; property: "_revealLeft"; value: 0 }
        PropertyAction { target: root; property: "_revealRight"; value: root.hovered ? 1 : 0 }
        ScriptAction { script: root.triggerFinished() }
    }

    Text {
        id: baseText
        text: root.text
        color: root.restColor
        font.family: root.mono ? Config.Appearance.fontMono : Config.Appearance.fontUi
        font.pixelSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
        font.weight: root.kind === "title" ? Font.DemiBold : Font.Normal
    }

    Item {
        id: clipWindow
        x: root._textWidth * root._revealLeft
        width: Math.max(0, root._textWidth * (root._revealRight - root._revealLeft))
        height: baseText.implicitHeight
        clip: true

        Text {
            // Anchored so it lines up with baseText regardless of
            // clipWindow's own x offset — only the visible SLICE moves,
            // not the glyphs themselves, which is what makes this read as
            // a mask sweeping across static text rather than the text
            // itself sliding.
            x: -clipWindow.x
            text: root.text
            color: root.highlightColor
            // Set individually, not `font: baseText.font` — every other
            // font-matching pair in this codebase (Widgets/StyledText,
            // Widgets/FlipDigit) sets the three sub-properties explicitly
            // rather than assigning the whole grouped `font` value from
            // another item, so this stays consistent with an established,
            // working pattern instead of a version-dependent assumption.
            font.family: root.mono ? Config.Appearance.fontMono : Config.Appearance.fontUi
            font.pixelSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
            font.weight: root.kind === "title" ? Font.DemiBold : Font.Normal
        }
    }
}
