import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// The bar's level-1 clickable unit: mute by default, changing state only on a
// real threshold or discrete event, via `tone`. It renders itself and emits
// `activated()`; opening a level-2 popover is the caller's job.
//
// Label and icon track the resolved state's fg, so an inverted active segment
// reads as inverted rather than same-on-same. Two bar-specific knobs:
// `ambient: "isle"` switches to the mono font and drops the resting fill and
// border, so a bar button is a bare glyph on the wallpaper, boxed only when
// selected; `squared` forces a roughly square footprint. A panel Segment keeps
// its 1px border and resting background.

Item {
    id: root

    property string glyph: ""
    property string label: ""
    // `glyph` is a plain font symbol and cannot express a custom animated
    // icon. A caller needing one sets `iconDelegate` instead and leaves
    // `glyph` empty — see the `customIcon` Loader below for sizing.
    property Component iconDelegate: null
    // The label-side mirror of `iconDelegate`: a caller needing rich label
    // content sets `labelDelegate` instead of (or alongside, when labelFirst)
    // `label`. The loaded item positions where the StyledText label would.
    property Component labelDelegate: null
    property string tone: "" // "" | "error" | "warn" | "success" | "info" — opt-in
    property bool active: false
    property bool loading: false
    property bool invalid: false

    // Which surface pair this button sits on — "shaded" (default, e.g. the
    // sidebar tab strip) or "isle" (the status bar's opposite-coloured
    // islands). Passed straight through to surfaceColors().
    property string ambient: "shaded"

    // "workspace" is a bar-button ambient too — same mono font, padding and
    // hover sweep as "isle" — differing only in the colour recipe and in
    // `contentColor` below, whose active state must show `stateColors.fg`
    // rather than the accent-text override other isle buttons use. Conditions
    // that really ask "is this a bar button" read `root._bar`, so a third bar
    // ambient needs one line here rather than a hunt through five
    // conditionals.
    readonly property bool _bar: root.ambient === "isle" || root.ambient === "workspace"

    // The status bar is mono. A bar-button ambient implies it; a panel Segment
    // stays on the UI font.
    property bool mono: root._bar

    // The workspace and btop buttons are square regardless of how wide their
    // single glyph/digit is.
    property bool squared: false

    // Extra px on top of the computed implicitWidth. Segment has no built-in
    // "wider when selected", so a caller that wants one drives this. 0
    // elsewhere.
    property real widthBoost: 0
    Behavior on widthBoost {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    // The status bar reads one step smaller than panel body text. A panel
    // Segment keeps the body size.
    property int sizeStep: root._bar ? 0 : 2

    // The Φ agent segment's active (processing) state is accent, not the B&W
    // inversion every other selected control uses — the one deliberate
    // exception, set only by Bar/modules/PhiAgent.qml.
    property bool accentWhenActive: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal activated()
    // Right-click: a module's quick toggle, never its popout.
    signal secondaryActivated()

    // Screen x of this button's RIGHT edge, so a popout can hang directly
    // under it instead of in the corner. Guarded: mapToItem(null) can throw
    // before the item is in a scene, and callers treat 0 as "fall back to a
    // corner".
    function rightX() {
        try {
            return root.mapToItem(null, root.width, 0).x
        } catch (e) {
            return 0
        }
    }

    // The LEFT edge, same idea. Near the screen's left edge, right-edge
    // alignment would pin a popout's far side there and push most of the card
    // off-screen, so a left-isle consumer anchors to this instead.
    function leftX() {
        try {
            return root.mapToItem(null, 0, 0).x
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

    // Label/icon colour. invalid wins outright, then a plain active segment
    // wins over `tone`: active draws no fill or border of its own, so letting
    // tone win would leave a selected-but-toned button with nothing marking it
    // selected.
    //
    // Two exclusions from the accent-active override: `accentWhenActive`
    // already gets its accent through `stateColors.fg`, and the "workspace"
    // ambient uses inverted colours rather than accent text, so its
    // `stateColors.fg` has to reach the label.
    readonly property color contentColor: root.invalid
        ? Config.Appearance.error
        : ((root.resolvedState === "active" && !root.accentWhenActive && root.ambient !== "workspace")
            ? Config.Appearance.accent
            : (root.tone.length > 0
                ? WidgetStates.contentColor(Config.Appearance, "value", root.tone, false)
                : root.stateColors.fg))

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // WidgetStates.js's chToPixels() comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real paddingH: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    // The status bar reads much tighter than a panel button — half a rhythm
    // unit of vertical inset on an isle Segment, a full one on a panel
    // Segment.
    readonly property real paddingV: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
        * (root._bar ? 0.5 : 1)

    readonly property real gap: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    // Floor the content box against the mono cell height: the symbol font's
    // glyph box is shorter than a text line, so glyph-only buttons came out
    // visibly short beside text ones. Flooring makes every Segment in an isle
    // the same height.
    readonly property real _contentHeight: Math.max(layout.implicitHeight, chMetrics.height)

    implicitHeight: _contentHeight + paddingV * 2
    // A squared button uses symmetric padding then grows to at least its own
    // height, so a single digit or glyph reads as a square tile, not a wide
    // pill.
    implicitWidth: (root.squared
        ? Math.max(implicitHeight, layout.implicitWidth + paddingV * 2)
        : layout.implicitWidth + paddingH * 2) + root.widthBoost
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState)

    Rectangle {
        anchors.fill: parent
        // radiusSmall/borderWidthStrong, the same thin/boxy corner and
        // hairline Widgets/StyledButton uses, instead of the generic
        // radiusBase/borderWidth.
        radius: Config.Appearance.radiusSmall
        color: root.stateColors.bg
        border.width: Config.Appearance.borderWidthStrong
        border.color: root.stateColors.border

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    // Isle-only hover sweep, top-to-bottom, height anchored to the top. A
    // panel Segment keeps its flat hover fill.
    //
    // Hover-only, deliberately not shared with "active": a shared sweep makes
    // the two indistinguishable, and un-hovering an active button reads as the
    // highlight wrongly sticking. Active uses no fill at all, so the two
    // states share no mechanism and cannot race.
    //
    // Driven off `resolvedState`, not raw `hovered`: resolve() already picks
    // one state by precedence, so a button both focused and hovered shows its
    // focus ring instead of two effects fighting for the same space.
    //
    // Deliberately not a masked reveal of the icon/label content: several bar
    // icons are procedural Canvas drawings with infinite animations, and
    // rendering each `iconDelegate` a second time to clip it would double that
    // cost for a hover micro-interaction. Instead this Rectangle sweeps the
    // background while `contentColor` fades via the Behaviors StyledText and
    // StyledIcon already carry. A Canvas `iconDelegate` has no such Behavior,
    // so those icons snap colour rather than fade.
    //
    // The condition is inlined in the handler rather than read from a separate
    // `_sweepOn` property: both would depend on the same `resolvedState`
    // change and QML does not order two dependents of one source, so the
    // handler could read a stale value and set hoverAmount to 1 exactly as the
    // mouse left.
    property real hoverAmount: 0
    Behavior on hoverAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    onResolvedStateChanged: root.hoverAmount =
        (root._bar && root.resolvedState === "hover") ? 1 : 0
    Component.onCompleted: root.hoverAmount =
        (root._bar && root.resolvedState === "hover") ? 1 : 0

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root._bar ? parent.height * root.hoverAmount : 0
        // Matches the background Rectangle's own corner above, so the sweep's
        // top edge never reads more rounded than the button it sits on.
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.colorOpposite
        visible: root._bar && height > 0.5
    }

    // Text-before-icon order, scoped to bar buttons (the status bar) only — a
    // panel Segment elsewhere (a settings row, a sidebar tab) keeps
    // icon-then-label.
    readonly property bool labelFirst: root._bar

    Item {
        // A plain Item, not a Row: Qt's Row docs forbid a child anchoring
        // itself horizontally, and icon and text anchor to each other.
        // Explicit rounded x/y rather than `anchors.centerIn`, which computes
        // (parent - child) / 2 and goes fractional on an odd difference — a
        // real, visible gap. Math.round pins it to a whole pixel.
        id: layout
        readonly property bool _iconShown: iconGlyph.visible || customIcon.active
        readonly property bool _labelShown: labelText.visible || customLabel.active
        readonly property real _labelWidth: customLabel.active
            ? customLabel.implicitWidth
            : (labelText.visible ? labelText.implicitWidth : 0)
        readonly property real _labelHeight: customLabel.active
            ? customLabel.implicitHeight
            : (labelText.visible ? labelText.implicitHeight : 0)
        implicitWidth: (iconGlyph.visible ? iconGlyph.implicitWidth : (customIcon.active ? customIcon.implicitWidth : 0))
            + (_iconShown && _labelShown ? root.gap : 0)
            + _labelWidth
        implicitHeight: Math.max(iconGlyph.visible ? iconGlyph.implicitHeight : (customIcon.active ? customIcon.implicitHeight : 0), _labelHeight)
        width: implicitWidth
        height: implicitHeight
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)

        StyledIcon {
            id: iconGlyph
            visible: root.glyph.length > 0
            glyph: root.glyph
            sizeStep: root.sizeStep
            color: root.contentColor
            anchors.left: root.labelFirst && layout._labelShown ? (customLabel.active ? customLabel.right : labelText.right) : parent.left
            anchors.leftMargin: root.labelFirst && layout._labelShown ? root.gap : 0
            anchors.verticalCenter: parent.verticalCenter
        }

        // The delegate binds its own properties against the enclosing file's
        // Segment id rather than this Loader pushing them in, so a typo is a
        // QML load error rather than a silent no-op.
        Loader {
            id: customIcon
            active: root.iconDelegate !== null
            visible: active
            sourceComponent: root.iconDelegate
            // No explicit implicit size binding: Loader already forwards the
            // loaded item's implicit size itself, and a binding here would
            // fight that internal write.
            anchors.left: root.labelFirst && layout._labelShown ? (customLabel.active ? customLabel.right : labelText.right) : parent.left
            anchors.leftMargin: root.labelFirst && layout._labelShown ? root.gap : 0
            anchors.verticalCenter: parent.verticalCenter
        }

        // The label-side mirror of `customIcon`. A caller setting
        // `labelDelegate` owns the whole label slot and binds against the
        // enclosing Segment id.
        Loader {
            id: customLabel
            active: root.labelDelegate !== null
            visible: active
            sourceComponent: root.labelDelegate
            anchors.left: root.labelFirst
                ? parent.left
                : (layout._iconShown ? (iconGlyph.visible ? iconGlyph.right : customIcon.right) : parent.left)
            anchors.leftMargin: root.labelFirst
                ? 0
                : (layout._iconShown ? root.gap : 0)
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            id: labelText
            visible: root.label.length > 0
            text: root.label
            mono: root.mono
            sizeStep: root.sizeStep
            color: root.contentColor
            anchors.left: root.labelFirst
                ? parent.left
                : (layout._iconShown ? (iconGlyph.visible ? iconGlyph.right : customIcon.right) : parent.left)
            anchors.leftMargin: root.labelFirst
                ? 0
                : (layout._iconShown ? root.gap : 0)
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        // `ReleaseWithinBounds`, not TapHandler's default `DragThreshold`,
        // which cancels the tap if the pointer moves ~10px between press and
        // release — easy for a finger. Since `pressed` alone drives the full
        // inverted active visual, the default made a touch look like the
        // highlight fired but the click did not. `ReleaseWithinBounds` only
        // cancels when the release lands outside the Item.
        gesturePolicy: TapHandler.ReleaseWithinBounds
        // `margin` widens the release-bounds tolerance for a press that lands
        // and lifts right at the edge. Reused from `paddingV` rather than a
        // new literal. Left off `hoverHandler` on purpose: BarIsle packs
        // Segments with zero spacing, so a wider hover region would overlap
        // adjacent buttons. Not gated on touchscreen capability — a forgiving
        // release tolerance is correct for a mouse too.
        margin: root.paddingV
        onTapped: root.activated()
    }

    TapHandler {
        enabled: root.enabled && !root.loading
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        margin: root.paddingV
        onTapped: root.secondaryActivated()
    }

    // Same keyboard-activation fix as Widgets/StyledButton.qml. Every consumer
    // of this widget (bar buttons, settings tabs, workspace pills, firewall
    // presets, …) inherits this for free.
    Keys.onReturnPressed: if (root.enabled && !root.loading) root.activated()
    Keys.onSpacePressed: if (root.enabled && !root.loading) root.activated()

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
