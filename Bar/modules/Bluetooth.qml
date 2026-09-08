import QtQuick
import Quickshell
import qs.Services as Services
import qs.Widgets as Widgets

// phiOS — Bar/modules/Bluetooth.qml (S-23, master plan §8.4: razer's
// "bluetooth (icona solo se connesso)"). "Solo se connesso" is read
// literally, distinct from Network/Wifi's "icona stato" (a state icon
// always present, on or off): with nothing connected this Segment has both
// an empty glyph and an empty label, so it collapses to a zero-size,
// effectively invisible element rather than showing an explicit "off" the
// way Network/Wifi do — those two modules represent a service that is
// SUPPOSED to be always-on (Tailscale, Wi-Fi), where "off" is itself
// informative; a bluetooth device being unpaired-right-now is the ordinary
// case, not an anomaly worth a permanent glyph.
//
// Capability-gated on `bluetooth` (Bar.qml, ADR 074) — real detected
// hardware, not host identity. Flagged for the screenshot to settle, not
// guessed here: master plan §5 lists Bluetooth as installed on `zotac` too
// (`phios-procedura-base-2.md`), while §8.4's own bar inventory table
// lists this segment for `razer` only. If `zotac`'s real capability probe
// reports `bluetooth: true`, this segment will appear there as well —
// that would be the capability system doing exactly what ADR 074 asks
// (driven by capability, not by which host this is), and it is §8.4's
// table, not this code, that would need revisiting.

Widgets.Segment {
    id: root

    required property ShellScreen screen

    property bool detailsShown: false

    readonly property bool anyConnected: Services.BluetoothBridge.anyConnected

    label: root.anyConnected
        ? (root.detailsShown ? Services.BluetoothBridge.firstConnectedName : "●")
        : ""

    onActivated: { if (root.anyConnected) root.detailsShown = !root.detailsShown }
}
