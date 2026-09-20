import QtQuick
import Quickshell
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// `processing` is bound to Services/Agent.qml (the one client point)
// true while an A1 turn is in flight, false otherwise.
// Segment's `active` state (full bg/fg inversion to accent) is used
// here, not `tone` (a text-colour-only semantic highlight) — this is the
// one bar module that needs the stronger, Tier-1 accent treatment.
// Label, not glyph: U+03A6 (Φ, uppercase) renders through the general UI
// text font via StyledText, not the icon-only symbol font via StyledIcon.
// A slow, continuous opacity breathe. Applied to this wrapper Item, not
// to the Segment directly: Segment already owns its own internal
// `opacity` binding (WidgetStates.opacityFor, for its disabled/loading
// fade) — an external "Animation on opacity" targeting that same property
// would permanently sever that binding the moment it first runs. Runs
// only while `processing` is true, so it costs nothing when idle.

Item {
    id: root

    required property ShellScreen screen
    property bool processing: Services.Agent.processing

    implicitWidth: segment.implicitWidth
    implicitHeight: segment.implicitHeight

    // Clicking the segment toggles the AI agent panel through
    // Services/AgentPanel.qml, the one owner of that surface's shown
    // state — same path as the Super+P bind and the Settings button.
    // `active` still tracks `processing` only: a panel-open state is
    // deliberately NOT reflected here (the panel being on screen is its
    // own feedback). Handler on the inner Segment, not the wrapper Item
    // the wrapper exists only to host the opacity breathe (see the note
    // above on why an external opacity animation on Segment would sever
    // its internal binding).
    Widgets.Segment {
        id: segment
        anchors.fill: parent
        label: "Φ"
        // Segment defaults every bar button's text to sizeStep 0
        // correct for a multi-character label, but a lone glyph character
        // reads visually lighter than this bar's Canvas-drawn icons at
        // that same nominal size. One step up brings its apparent weight
        // closer to its neighbours without hardcoding a size (`sizeStep`
        // is itself the design-token-driven scale, just a different rung).
        sizeStep: 1
        // Also active (not just processing) when the panel itself is
        // open, so a segment whose panel is genuinely open — but not
        // mid-turn — still shows a state.
        active: root.processing || Services.AgentPanel.shown
        // The agent's processing state is Tier-1 accent, not the B&W
        // inversion every other selected control gets. This flag is the
        // one exception to that rule.
        accentWhenActive: true
        // The Φ mark sits in the LEFT isle (leftmost element, ahead of
        // the workspace list).
        ambient: "isle"
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
