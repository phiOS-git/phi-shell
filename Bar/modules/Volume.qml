import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Volume.qml (S-23, master plan §8.4: "volume (icona
// solo su mute)" on both hosts). Icon-vs-text criterion (§8.4): volume is a
// continuous value, so it is TEXT by default ("testo più colore-su-soglia
// per ogni valore continuo") — the percentage — and only the discrete
// mute/unmute event gets the icon-like treatment §8.4 actually asks for,
// done here as a short word plus `tone`, not a StyledIcon glyph: font-symbol
// is an icon-only font (Config/Appearance.qml's own comment) whose real
// glyph coverage has never been exercised by any step so far — S-22's three
// module types never set Segment's `glyph` property either — and this step
// has no way to confirm a specific codepoint renders on real hardware.
// Text is the safe fallback the icon-vs-text criterion itself allows for a
// continuous value; a later step that has actually inspected the font can
// turn this into a real glyph in one line.
//
// The click-to-toggle-mute here stands in for the "2 azioni rapide" a
// level-2 popover would otherwise hold: Widgets/Popover (S-21) has no
// floating-surface counterpart wired anywhere in this shell yet (its
// intended host is a real `Quickshell.PopupWindow` — confirmed to exist in
// 0.3.x by reading src/window/popupwindow.hpp, but never used by any step
// to date), so this step keeps every module's interactivity to what a
// plain Segment click can do rather than being the first to debug that
// mechanism sight-unseen. Brightness's popover integration (C-09) and any
// richer volume detail wait for whichever step first builds that.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    // OOP-03: bar buttons sit on the opposite-coloured islands.
    ambient: "isle"

    readonly property bool muted: Services.AudioBridge.muted
    readonly property int percent: Math.round(Services.AudioBridge.volume * 100)

    label: muted ? "mute" : percent + "%"
    tone: muted ? "warn" : ""

    onActivated: Services.AudioBridge.toggleMute()
}
