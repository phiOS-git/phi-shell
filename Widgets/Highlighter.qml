import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Masked highlighter-marker reveal for plain text: two identical Text
// layers stacked (rest colour under, highlight colour over), the top one
// clipped to a window that grows across the text width.
// Distinct from Widgets/Segment.qml's hover sweep, which is a flat
// Rectangle wash — Segment can hold a Canvas iconDelegate, and clipping a
// second copy of an infinite-animation Canvas per hover would double that
// cost. Text-only here, so the second layer is free.
// Passive, like Widgets/StyledText: owns no HoverHandler. `hovered` is
// driven by whichever parent already owns the larger hoverable area.
// The revealed window is [_revealLeft, _revealRight], both 0..1 fractions
// of the text width. Hover moves only `_revealRight` (0 at rest, 1
// hovered), so the window always grows from and retreats to the left edge.
// `trigger()` is the one-shot path, untied to hover: it opens fully, then
// sweeps `_revealLeft` 0->1 to eat the highlight away from the left
// motion the plain hover reverse does not produce.
// Motion category B: hover and one-shot flash are both discrete.
// TODO: no caller migrated to it yet. Intended for the tag/status
// highlight effects in docs/reworks/new-features.md.

Item {
    id: root

    property string text: ""
    property string kind: "value" // "label" | "value" | "title" — same meaning as StyledText
    property string tone: ""
    property bool invalid: false
    property int sizeStep: 2
    property bool mono: false

    // Driven by a parent that owns the actual pointer/hover detection
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
    // flicker if they don't land in the same frame; explicit
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
            // clipWindow's own x offset — only the visible SLICE moves
            // not the glyphs themselves, which is what makes this read as
            // a mask sweeping across static text rather than the text
            // itself sliding.
            x: -clipWindow.x
            text: root.text
            color: root.highlightColor
            // Set individually, not `font: baseText.font` — every other
            // font-matching pair in this codebase (Widgets/StyledText
            // Widgets/FlipDigit) sets the three sub-properties explicitly
            // rather than assigning the whole grouped `font` value from
            // another item, so this stays consistent with an established
            // working pattern instead of a version-dependent assumption.
            font.family: root.mono ? Config.Appearance.fontMono : Config.Appearance.fontUi
            font.pixelSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
            font.weight: root.kind === "title" ? Font.DemiBold : Font.Normal
        }
    }
}
