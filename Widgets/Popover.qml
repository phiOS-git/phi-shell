import QtQuick
import qs.Config as Config

// A Panel raised to the popover z-layer with its own show/hide fade. This
// widget only knows how to be a floating surface — content caps and layout are
// the caller's concern (Widgets/Segment), not this file's.
//
// `shown` deliberately owns `opacity` outright rather than combining with
// Panel's own state-driven fade: a popover has two different "invisible"
// concepts (structurally disabled/loading vs. not currently shown), and colour
// already carries the first one — content inside still recolours via each
// row's own state, this container's presence is the one thing worth a
// dedicated animation channel.

Panel {
    id: root

    property bool shown: false

    // Panel already declares `Behavior on opacity`; it keeps animating this
    // override the same way it animates Panel's own default binding, so it is
    // not repeated here.
    z: Config.Appearance.zPopover
    visible: opacity > 0
    opacity: shown ? 1 : 0
}
