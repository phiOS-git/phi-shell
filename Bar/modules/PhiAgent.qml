import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/PhiAgent.qml (S-23, master plan §6.6 Role B / §8.4:
// "Segmento dedicato in barra su zotac e razer").
//
// S-75: `processing` is now bound to Services/Agent.qml (the one client
// point, ADR 098) — it is true while an A1 turn is in flight and false
// otherwise. The S-23 text below describes the placeholder this replaced;
// the motion and Role-B reasoning it works out are unchanged and still
// apply, only the trigger is real now.
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
    // S-75: wired to the real client. Role B (accent) + category-A breathe
    // while a turn is in flight, neutral otherwise (§6.6). The placeholder
    // `false` from S-23 is gone — this is now driven by Services/Agent.qml,
    // the one client point.
    property bool processing: Services.Agent.processing

    implicitWidth: segment.implicitWidth
    implicitHeight: segment.implicitHeight

    // Out-of-plan (2026-09-09): clicking the segment toggles the phi agent
    // panel (Panels/AgentPanel.qml) through Services/AgentPanel.qml, the
    // one owner of that surface's shown state — same path as the Super+P
    // bind and the Settings button. `active` still tracks `processing`
    // only: §6.6 reserves Role B accent for "durante l'elaborazione", so a
    // panel-open state is deliberately NOT reflected here (the panel being
    // on screen is its own feedback). Handler on the inner Segment, not the
    // wrapper Item — the wrapper exists only to host the opacity breathe
    // (see the note above on why an external opacity animation on Segment
    // would sever its internal binding).
    Widgets.Segment {
        id: segment
        anchors.fill: parent
        label: "Φ"
        active: root.processing
        // §6.6 Role B is a closed ADR: the agent's processing state is
        // Tier-1 accent, not the B&W inversion OOP-02 gave every other
        // selected control. This flag is the one exception to that rule.
        // (`ambient` is left at its default here and set for the whole bar
        // in OOP-03.)
        accentWhenActive: true
        onActivated: Services.AgentPanel.toggle()
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
