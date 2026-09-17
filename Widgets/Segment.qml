import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// The bar's level-1 clickable unit: mute by default, changing state only
// on a real threshold or discrete event, via `tone`. Opening a level-2
// popover is wired by whatever composes this into the bar; this widget
// only renders itself and signals `activated()` when clicked.
//
// The button's label/icon track the resolved state's fg, so an inverted
// active segment reads as inverted, not as invisible same-on-same. Two
// bar-specific knobs: `ambient: "isle"` switches the text to the mono font
// and drops the resting fill and border entirely — a bar button is a bare
// opposite-coloured glyph on the wallpaper, boxed only when selected;
// `squared` forces a roughly square footprint for the workspace and btop
// buttons. A panel Segment keeps its 1px contrast border and resting
// background.

Item {
    id: root

    property string glyph: ""
    property string label: ""
    // `glyph` is a plain font-symbol character — it cannot express a
    // custom animated icon. A caller that needs one sets `iconDelegate`
    // instead (and leaves `glyph` empty): Bar/modules/Brightness.qml's
    // sun/moon eclipse icon is one consumer. See the `customIcon` Loader
    // below for how it's sized and positioned; every existing glyph/
    // label-only consumer is unaffected since this defaults to null.
    property Component iconDelegate: null
    // The label-side mirror of `iconDelegate` above: a plain font-symbol /
    // label-string cannot express rich label content either. A caller that
    // needs one sets `labelDelegate` instead of (or alongside, when
    // labelFirst) `label`: Bar/modules/Clock.qml renders its HH:MM as four
    // Widgets.FlipDigit cells through this slot. Same interaction as the
    // icon side — the loaded item positions where the StyledText label
    // would, and nothing here pushes values into it beyond its own size.
    property Component labelDelegate: null
    property string tone: "" // "" | "error" | "warn" | "success" | "info" — opt-in
    property bool active: false
    property bool loading: false
    property bool invalid: false

    // Which surface pair this button sits on — "shaded" (default, e.g. the
    // sidebar tab strip) or "isle" (the status bar's opposite-coloured
    // islands). Passed straight through to surfaceColors().
    property string ambient: "shaded"

    // "workspace" (Bar/modules/Workspaces.qml's numbered squares) is a
    // bar-button ambient too — same mono font, tight isle padding and hover
    // sweep as "isle" — it only differs in the colour recipe
    // WidgetStates.surfaceColors() gives it (a resting border, an inverted
    // active fill) and in `contentColor` below (its active state must
    // actually show `stateColors.fg`, not the accent-text override every
    // other isle button's active state uses). Every `root.ambient ===
    // "isle"` check below that is really asking "is this a bar button"
    // reads `root._bar` instead, so a future third bar-button ambient needs
    // one line here, not a hunt through five separate conditionals.
    readonly property bool _bar: root.ambient === "isle" || root.ambient === "workspace"

    // The status bar is mono. A bar-button ambient implies it; a panel
    // Segment stays on the UI font.
    property bool mono: root._bar

    // The workspace and btop buttons are square regardless of how wide
    // their single glyph/digit is.
    property bool squared: false

    // Extra px added on top of the computed implicitWidth below — Segment
    // has no built-in "wider when selected" concept, so a caller that
    // wants one (Workspaces.qml, bound to its own `active`) drives this
    // instead. 0 for every other existing caller, so nothing else changes
    // width.
    property real widthBoost: 0
    Behavior on widthBoost {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }

    // The status bar reads one step smaller than panel body text. A panel
    // Segment keeps the body size.
    property int sizeStep: root._bar ? 0 : 2

    // The Φ agent segment's active (processing) state is accent, not the
    // B&W inversion every other selected control uses — the one
    // deliberate exception, set only by Bar/modules/PhiAgent.qml.
    property bool accentWhenActive: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal activated()

    // Screen x of this button's RIGHT edge — a popout can align its own
    // right edge to this so it hangs directly under the button rather than
    // in the corner. Guarded: mapToItem(null) can throw before the item is
    // in a scene; callers treat 0 as "fall back to a corner position".
    function rightX() {
        try {
            return root.mapToItem(null, root.width, 0).x
        } catch (e) {
            return 0
        }
    }

    // Same idea, the button's LEFT edge — for a button near the screen's
    // left edge, right-edge alignment (rightX() above) would pin a
    // popout's far side there and push almost the whole card off-screen;
    // a left-isle consumer anchors its popout's own left edge to this
    // instead.
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

    // The label/icon colour: invalid wins outright, then a plain
    // (non-accentWhenActive) active segment wins over `tone` too —
    // otherwise a toned button (e.g. battery on a low-charge
    // `warn`/`error`, a notification bell with a pending `info`) would
    // show NO visual change at all on selection: active draws no fill or
    // border of its own (WidgetStates.js's isle "active" case), so tone
    // winning would leave a selected-but-toned button with nothing marking
    // it selected. `accentWhenActive` (PhiAgent) is excluded here — its own
    // accent colours already flow through `stateColors.fg` via the ternary
    // above, this branch would be redundant for it and is skipped so tone
    // still applies there exactly as it always did.
    // `ambient === "workspace"` is excluded from the accent-active
    // override too, for the same reason: the selected workspace uses
    // inverted colours, not accent text, so `stateColors.fg`
    // (WidgetStates.js's "workspace" ambient branch, which resolves to the
    // inverted-fill ink colour on active) has to actually reach the
    // label/icon here.
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
    // The status bar reads much tighter than a panel button — half a
    // rhythm unit of vertical inset on an isle Segment, a full one on a
    // panel Segment.
    readonly property real paddingV: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
        * (root._bar ? 0.5 : 1)

    readonly property real gap: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)

    // Floor the content box against the mono cell height. A glyph-only
    // button (btop) and a text-only button (a workspace digit) measure to
    // different heights otherwise — the symbol font's glyph box is shorter
    // than a text line — so glyph-only bar buttons came out visibly short
    // next to their neighbours. Flooring here makes every Segment in an
    // isle the same height regardless of what it holds.
    readonly property real _contentHeight: Math.max(layout.implicitHeight, chMetrics.height)

    implicitHeight: _contentHeight + paddingV * 2
    // A squared button uses symmetric (vertical) padding and then grows to
    // at least its own height, so a single digit or glyph reads as a
    // square tile rather than a wide pill. `widthBoost` (default 0 for
    // every caller but Workspaces.qml) adds on top.
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

    // Isle-only (the status bar) — a panel Segment (a settings row, a
    // sidebar tab) keeps its existing flat hover fill untouched. Direction:
    // top-to-bottom, height growth anchored to the top.
    //
    // Hover-only, deliberately NOT shared with "active": a shared sweep
    // between the two makes them impossible to tell apart by look alone —
    // un-hovering an active button reads as the highlight wrongly staying
    // applied. Active no longer uses this Rectangle or this Behavior AT
    // ALL (WidgetStates.js gives it `accent`-coloured text/icon instead, no
    // fill) — the two states have zero shared mechanism, so they cannot
    // race or be confused for one another, by construction.
    //
    // Driven off `resolvedState`, not the raw `hovered` flag: resolve()
    // already picks exactly one state by precedence (active/pressed beats
    // focus beats hover), so a button that is BOTH keyboard-focused and
    // mouse-hovered shows its focus ring, not a hover sweep fighting it
    // for the same space — the same precedence `stateColors` itself
    // already respects.
    //
    // Deliberately NOT a per-pixel masked reveal of the icon/label content
    // (i.e. not a duplicate icon/text layer clipped to the sweep extent,
    // the way SunMoonIcon/BatteryIcon/GpuIcon's own fills work): several of
    // this bar's icons are procedural Canvas drawings, and rendering every
    // `iconDelegate` a second time just to clip it would double each
    // icon's Canvas and its running animations (BatteryIcon's charge
    // pulse, WifiIcon's search pulse etc. are all infinite loops) for a
    // hover micro-interaction. Instead: this Rectangle alone sweeps for
    // the BACKGROUND, and the foreground colour (`contentColor`, which
    // every icon/label already reads) fades to the inverted pair on the
    // same timer via the Behaviors those already have — `StyledText`/
    // `StyledIcon` both carry `Behavior on color`, so the label fades
    // smoothly; a custom Canvas `iconDelegate` has no such Behavior on its
    // own `iconColor` (that property is fed by a binding at the call site,
    // not an imperative assignment), so those icons snap colour instead of
    // fading.
    //
    // Not routed through a separate `_sweepOn` property read inside the
    // handler below: `onResolvedStateChanged` and a `_sweepOn` binding
    // would both depend on the same `resolvedState` change, and QML does
    // not guarantee which of two dependents on the same source
    // re-evaluates first. If the handler ran before `_sweepOn`'s own
    // binding caught up, it would read a STALE value — on hover-out
    // (resolvedState "hover"→"default"), a stale-true read would set
    // hoverAmount to 1 right as the mouse left, and the mirror on
    // hover-in would silently do nothing. The condition is inlined
    // directly in the handler instead, so there is nothing else for it to
    // race against.
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
        // Matches the background Rectangle's own corner above, so the
        // sweep's top edge never reads more rounded than the button it
        // sits on.
        radius: Config.Appearance.radiusSmall
        color: Config.Appearance.colorOpposite
        visible: root._bar && height > 0.5
    }

    // Text-before-icon order, scoped to bar buttons (the status bar) only
    // — a panel Segment elsewhere (a settings row, a sidebar tab) keeps
    // icon-then-label.
    readonly property bool labelFirst: root._bar

    Item {
        // A plain Item, not a Row: Qt's own Row docs say a child "should
        // not... horizontally anchor itself using left, right,
        // horizontalCenter, fill or centerIn", and icon/text below anchor
        // horizontally to each other. Explicit rounded x/y instead of
        // `anchors.centerIn: parent`: `centerIn` computes
        // `(parent - child) / 2`, which is fractional whenever that
        // difference is odd; Math.round pins it to a whole pixel instead of
        // leaving the sub-pixel remainder for the renderer to resolve
        // however it does — a real, visible gap wherever content and
        // button box sizes differ by an odd number of pixels.
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

        // The delegate binds its own properties declaratively against the
        // enclosing file's own Segment id (e.g. `color: myIconRoot.
        // contentColor`) rather than this Loader pushing them in via
        // onLoaded — a typo in that binding is then a QML load error, not
        // a silently-ignored no-op.
        Loader {
            id: customIcon
            active: root.iconDelegate !== null
            visible: active
            sourceComponent: root.iconDelegate
            // No explicit implicitWidth/implicitHeight binding: Loader
            // already forwards the loaded item's implicit size on its own
            // (confirmed against Qt's own qquickloader.cpp —
            // setImplicitSize(getImplicitWidth(), getImplicitHeight()) —
            // not assumed). A QML binding here would fight that internal
            // C++ write instead of cooperating with it.
            anchors.left: root.labelFirst && layout._labelShown ? (customLabel.active ? customLabel.right : labelText.right) : parent.left
            anchors.leftMargin: root.labelFirst && layout._labelShown ? root.gap : 0
            anchors.verticalCenter: parent.verticalCenter
        }

        // The label-side mirror of `customIcon` above. A caller that sets
        // `labelDelegate` owns the whole label slot; the delegate binds
        // against the enclosing Segment id too (Clock.qml's FlipDigit cells
        // read `root.sizeStep` / `root.contentColor` out of the file scope).
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
        // TapHandler's default `gesturePolicy`, `DragThreshold`, cancels
        // the tap — `onTapped` never fires — if the pointer moves more
        // than ~10px between press and release, which a finger on a
        // touchscreen crosses far more easily than a mouse does. `pressed`
        // alone already drives the full inverted "active" visual
        // (WidgetStates.resolve: `active || pressed`), so the highlight
        // fires the instant a finger lands and stays lit for the whole
        // gesture, then drops back to no-op on release once the tap
        // cancels — looking like the highlight triggered but not the
        // click. `ReleaseWithinBounds` only cancels if the release itself
        // lands outside this Item, so in-between jitter no longer matters.
        gesturePolicy: TapHandler.ReleaseWithinBounds
        // A separate boundary case `ReleaseWithinBounds` itself introduces:
        // a press that lands, and lifts, right at the Item's edge.
        // `margin` grows the release-bounds tolerance uniformly on all
        // four sides. Reused from `paddingV` rather than a new literal —
        // already this Segment's own token-derived vertical breathing
        // room. Left off `hoverHandler` above deliberately — hover already
        // fires correctly, and BarIsle packs Segments with zero spacing,
        // so widening the HOVER region too would let two adjacent
        // buttons' hover zones overlap at their shared edge. Not gated on
        // `Config.Capabilities.touchscreen`: a more forgiving release
        // tolerance is correct for a mouse too.
        margin: root.paddingV
        onTapped: root.activated()
    }

    // Same keyboard-activation fix as Widgets/StyledButton.qml. Every
    // consumer of this widget (bar buttons, settings tabs, workspace
    // pills, firewall presets, …) inherits this for free.
    Keys.onReturnPressed: if (root.enabled && !root.loading) root.activated()
    Keys.onSpacePressed: if (root.enabled && !root.loading) root.activated()

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
