import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/Segment (S-21). The bar's level-1 clickable unit
// (three-level disclosure model, master plan §8.5/style plan §7): "muto
// per default, cambia stato solo su soglia o evento discreto" — mute
// unless the bar module that owns this decides a real threshold or
// discrete event has occurred, via `tone`. Opening its level-2 popover is
// wired by whatever composes this into the bar (S-22, the "max 5 rows + 2
// actions" cap belongs there too); this widget only renders itself and
// signals `activated()` when clicked.
//
// OOP-02/OOP-03 (shell restyle): the button now carries a 1px contrast
// border and its label/icon track the resolved state's fg (so an inverted
// active segment reads as inverted, not as invisible same-on-same). Two
// bar-specific knobs: `ambient: "isle"` puts it on the status bar's
// opposite-coloured island grammar and switches its text to the mono
// font; `squared` forces a roughly square footprint for the workspace and
// btop buttons.

Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string tone: "" // "" | "error" | "warn" | "success" | "info" — opt-in, §8.6
    property bool active: false
    property bool loading: false
    property bool invalid: false

    // OOP-02: which surface pair this button sits on — "panel" (default,
    // e.g. the sidebar tab strip) or "isle" (the status bar's opposite-
    // coloured islands). Passed straight through to surfaceColors().
    property string ambient: "panel"

    // OOP-03: the status bar is mono (user directive). "isle" ambient
    // implies it; a panel Segment stays on the UI font.
    property bool mono: root.ambient === "isle"

    // OOP-03: the workspace and btop buttons are square regardless of how
    // wide their single glyph/digit is.
    property bool squared: false

    // OOP-10: the status bar reads one step smaller than panel body text
    // (user R2 feedback: "reduce the font size"). A panel Segment keeps
    // the body size.
    property int sizeStep: root.ambient === "isle" ? 0 : 2

    // OOP-02: keep the §6.6 Role B rule for the Φ agent segment — its
    // active (processing) state is Tier-1 accent, not the B&W inversion
    // every other selected control now uses. The one closed-ADR exception,
    // set only by Bar/modules/PhiAgent.qml.
    property bool accentWhenActive: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal activated()

    // R3 #2: screen x of this button's centre, for a popout that points
    // at it. Guarded — mapToItem(null) can throw before the item is in a
    // scene; callers treat 0 as "fall back to a corner position".
    function centerX() {
        try {
            return root.mapToItem(null, root.width / 2, 0).x
        } catch (e) {
            return 0
        }
    }

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    readonly property var stateColors: (root.accentWhenActive && root.resolvedState === "active")
        ? ({ bg: Config.Appearance.accent, fg: Config.Appearance.accentText, border: Config.Appearance.accent })
        : WidgetStates.surfaceColors(Config.Appearance, root.resolvedState, root.ambient)

    // The label/icon colour: a real threshold tone wins, then invalid, then
    // the resolved state's own fg (so an inverted active segment inverts
    // its text too).
    readonly property color contentColor: root.invalid
        ? Config.Appearance.error
        : (root.tone.length > 0
            ? WidgetStates.contentColor(Config.Appearance, "value", root.tone, false)
            : root.stateColors.fg)

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real paddingH: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    readonly property real paddingV: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    readonly property real gap: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    // OOP-11: floor the content box against the mono cell height. A
    // glyph-only button (btop) and a text-only button (a workspace digit)
    // measure to different heights otherwise — the symbol font's glyph
    // box is shorter than a text line — so glyph-only bar buttons came out
    // visibly short next to their neighbours. Flooring here makes every
    // Segment in an isle the same height regardless of what it holds.
    readonly property real _contentHeight: Math.max(layout.implicitHeight, chMetrics.height)

    implicitHeight: _contentHeight + paddingV * 2
    // A squared button uses symmetric (vertical) padding and then grows to
    // at least its own height, so a single digit or glyph reads as a
    // square tile rather than a wide pill.
    implicitWidth: root.squared
        ? Math.max(implicitHeight, layout.implicitWidth + paddingV * 2)
        : layout.implicitWidth + paddingH * 2
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: root.stateColors.bg
        border.width: Config.Appearance.borderWidth
        border.color: root.stateColors.border

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
        }
    }

    Item {
        // A plain Item, not a Row: Qt's own Row docs say a child "should
        // not... horizontally anchor itself using left, right,
        // horizontalCenter, fill or centerIn", and icon/text below anchor
        // horizontally to each other (icon left-edge, text left-of-icon.right).
        id: layout
        anchors.centerIn: parent
        implicitWidth: (iconGlyph.visible ? iconGlyph.implicitWidth : 0)
            + (iconGlyph.visible && labelText.visible ? root.gap : 0)
            + (labelText.visible ? labelText.implicitWidth : 0)
        implicitHeight: Math.max(iconGlyph.visible ? iconGlyph.implicitHeight : 0, labelText.visible ? labelText.implicitHeight : 0)

        StyledIcon {
            id: iconGlyph
            visible: root.glyph.length > 0
            glyph: root.glyph
            sizeStep: root.sizeStep
            color: root.contentColor
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            id: labelText
            visible: root.label.length > 0
            text: root.label
            mono: root.mono
            sizeStep: root.sizeStep
            color: root.contentColor
            anchors.left: iconGlyph.visible ? iconGlyph.right : parent.left
            anchors.leftMargin: iconGlyph.visible ? root.gap : 0
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.activated()
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Config.Appearance.motionBEasingType }
    }
}
