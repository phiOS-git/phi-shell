import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Separator (S-21). A hairline divider, coloured from
// design tokens and sized from the new border-width token (see this
// repository's Appearance.qml and phios-dotfiles/design/tokens.common.sh —
// no §6.3 token covered stroke width before this step, a real gap this
// widget surfaced rather than a deferred decision).
//
// The seven transverse states (§8.6) are present here for interface
// uniformity with every other widget in this directory, but only three
// have a defined look for a plain divider: default, disabled and loading
// fade together via the shared opacity precedence, and invalid tints the
// line to the error colour. hover/pressed/active/keyboardFocus have no
// meaning for a line nothing can click or focus, and are not wired to any
// visual effect — a genuinely honest "not applicable", not a silently
// faked one.

Item {
    id: root

    property bool vertical: false
    property bool strong: false
    property bool loading: false
    property bool invalid: false
    // Present for the seven-state contract; no visual effect here (see
    // file comment above).
    property bool hovered: false
    property bool pressed: false
    property bool active: false
    property bool keyboardFocus: false

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: false, pressed: false,
        active: false, keyboardFocus: false,
        loading: root.loading, invalid: root.invalid
    })

    implicitWidth: vertical ? Config.Appearance.borderWidth : 0
    implicitHeight: vertical ? 0 : Config.Appearance.borderWidth
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        color: root.invalid ? Config.Appearance.error
             : (root.strong ? Config.Appearance.borderStrong : Config.Appearance.border)
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
}
