import QtQuick
import Quickshell
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Bar/modules/PhiAgent.qml (S-23, master plan §6.6 Role B / §8.4:
// "Segmento dedicato in barra su zotac e razer"). Placeholder, no backend
// yet, exactly as the AGENT card names it: `processing` has nothing real
// driving it until the agent surface lands (docs/phios-agente.md, M6+) —
// this file is the honest, inert shape that surface will eventually set,
// not a fake trigger invented to make the segment look alive now.
//
// §6.6 Role B: "Tier 1 (accento) solo durante l'elaborazione, altrimenti
// neutro" is Segment's `active` state (full bg/fg inversion to accent,
// Widgets/WidgetStates.js `surfaceColors()`'s "active" case), NOT `tone`
// (Tier 2, a text-colour-only semantic highlight) — Tier 1 and Tier 2 are
// different roles in §6.2, and this is the one bar module in this step
// that needs the former.
//
// Label, not glyph: same font-symbol-coverage reasoning as every other new
// module this step (see Volume.qml's note) — U+03A6 (Φ, uppercase, per
// §6.6's own codepoint rule) renders through the general UI text font via
// StyledText, not the icon-only symbol font via StyledIcon.
//
// Motion category A ("feedback di tracciamento... indicatore di
// elaborazione dell'agente" — §6.5 names this exact segment as category
// A's own worked example): continuous, light — a slow opacity breathe,
// tokens.common.sh's PHI_MOTION_A_PERIOD/EASING (1600ms, linear). Applied
// to this wrapper Item, not to the Segment directly: Segment already owns
// its own internal `opacity` binding (WidgetStates.opacityFor, for its
// disabled/loading fade) — an external "Animation on opacity" targeting
// that same property would permanently sever that binding the moment it
// first runs, a real QML footgun, not a hypothetical one. Runs only while
// `processing` is true, so it costs nothing today: `processing` is
// hardcoded false, making this animation dead code until a real trigger
// exists, deliberately, not a bug — the alternative (leaving the motion
// unwritten) would ship a segment that stays permanently silent even once
// wired, since nothing else in this file would then know to animate it.

Item {
    id: root

    required property ShellScreen screen
    property bool processing: false

    implicitWidth: segment.implicitWidth
    implicitHeight: segment.implicitHeight

    Widgets.Segment {
        id: segment
        anchors.fill: parent
        label: "Φ"
        active: root.processing
    }

    SequentialAnimation on opacity {
        running: root.processing
        loops: Animation.Infinite
        NumberAnimation {
            from: 1.0; to: 0.6
            duration: Config.Appearance.motionAPeriod / 2
            easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
        }
        NumberAnimation {
            from: 0.6; to: 1.0
            duration: Config.Appearance.motionAPeriod / 2
            easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
        }
    }
}
