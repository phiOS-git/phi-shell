import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Highlighter (docs/TODO.md, design system: "highlighter
// effect (similar to the status bar hover effect, but applied to texts,
// not to full button or element background, it should only highlight the
// text, with a transition L to R, the text should change color but
// following the highlight like a mask, it can be used on hoverable texts.
// add also a highlighter-out effect closing L to R to use for triggered
// highlights like the search results. when unhovering it just goes back R
// to L)").
//
// Widgets/Segment.qml's own hover sweep (its `hoverAmount` Rectangle) is
// explicitly documented there as NOT a per-pixel masked text reveal, on
// purpose: Segment can hold a Canvas `iconDelegate` (BatteryIcon,
// WifiIcon, ...), and duplicating + clipping a second copy of an infinite-
// animation Canvas for every hover would double that cost for a micro-
// interaction. That constraint does not apply here — this widget wraps
// plain text only, so a second `Text` layer costs nothing, and a genuine
// masked reveal is exactly what a "highlighter marker" effect needs: two
// identical Text items stacked (rest colour underneath, highlight colour
// on top), the top one clipped to a window that grows/shrinks across the
// text width instead of fading as a flat crossfade.
//
// Passive, like Widgets/StyledText: does not own its own HoverHandler —
// `hovered` is a plain property a parent drives (a ListRow, a search
// result row, anything that already owns a larger hoverable area than
// just this text), the same convention StyledText's own `hovered` already
// follows. `trigger()` is the separate one-shot path for a "triggered"
// highlight that is not tied to hover at all (the TODO's own example: a
// search result) — it plays a quick full reveal and then closes the
// window from its LEFT edge moving right ("closing L to R"), distinct
// from the plain hover-out motion below (the window's RIGHT edge simply
// retreating back where it came from, "goes back R to L").
//
// Model: a revealed window [_revealLeft, _revealRight] (both 0..1,
// fractions of the text's own width) marks which portion of the overlay
// (highlight-coloured) text is visible through the clip. Plain hover only
// ever moves `_revealRight` (0 at rest, 1 hovered) — `_revealLeft` stays
// pinned at 0, so the window always grows from/shrinks back to the left
// edge, which is exactly "L to R" growth and its own reverse. `trigger()`
// additionally sweeps `_revealLeft` 0->1 once the window is already fully
// open, eating the highlight away from the left — the "closing L to R"
// motion the plain hover reverse does not produce on its own.
//
// Motion category B throughout (a discrete, triggered state change —
// hover and a one-shot flash are both exactly what category B is for;
// category C is reserved for exactly two named effects elsewhere in this
// codebase, typing and scramble, and does not fit here).

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

    // Only `_revealRight` gets an ambient Behavior: the plain hover path
    // (onHoveredChanged below) is the only thing that ever drives it
    // outside of trigger()'s own explicit animation steps, and hover never
    // touches `_revealLeft` at all (see this file's header — hover only
    // ever moves the right edge). `_revealLeft` is driven exclusively by
    // flashSequence's own explicit NumberAnimation/PropertyAction steps
    // below, deliberately with NO Behavior of its own — an earlier version
    // of this file reset both edges via plain assignment and relied on two
    // independent same-duration Behaviors happening to stay in lockstep to
    // avoid a visible flicker; this version removes that assumption
    // entirely by giving the close/reset steps explicit, deterministic
    // control instead of hoping two Behaviors race identically.
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
