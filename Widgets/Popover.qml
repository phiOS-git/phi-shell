import QtQuick
import qs.Config as Config

// phiOS — Widgets/Popover (S-21). The level-2 disclosure surface of the
// three-level model (master plan §8.5, style plan §7): a Panel raised to
// the popover z-layer with its own show/hide fade. The "max 5 info rows +
// 2 quick actions" cap (§8.5) is enforced where the content is assembled —
// the Segment type, S-22 — not here: this widget only knows how to be a
// floating surface, not what a bar module puts inside one.
//
// `shown` deliberately owns `opacity` outright rather than combining with
// Panel's own state-driven fade: a popover has two different "invisible"
// concepts (structurally disabled/loading vs. not currently shown), and
// colour already carries the first one — content inside still recolours
// via each row's own state, this container's presence is the one thing
// worth a dedicated animation channel.

Panel {
    id: root

    property bool shown: false

    // Panel already declares `Behavior on opacity`; it keeps animating this
    // override the same way it animates Panel's own default binding, so it
    // is not repeated here.
    z: Config.Appearance.zPopover
    visible: opacity > 0
    opacity: shown ? 1 : 0
}
