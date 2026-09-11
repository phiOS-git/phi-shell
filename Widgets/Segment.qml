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
// OOP-02/OOP-03 (shell restyle): the button's label/icon track the
// resolved state's fg, so an inverted active segment reads as inverted,
// not as invisible same-on-same. Two bar-specific knobs: `ambient:
// "isle"` switches the text to the mono font and (OOP-21) drops the
// resting fill and border entirely — a bar button is a bare
// opposite-coloured glyph on the wallpaper, boxed only when selected;
// `squared` forces a roughly square footprint for the workspace and btop
// buttons. A panel Segment keeps its 1px contrast border and resting
// background.

Item {
    id: root

    property string glyph: ""
    property string label: ""
    // docs/TODO.md: "Apply SVG animations to icon when changing within
    // states" (status-bar rework). `glyph` is a plain font-symbol
    // character — it cannot express a custom animated icon. A caller that
    // needs one sets `iconDelegate` instead (and leaves `glyph` empty):
    // Bar/modules/Brightness.qml's sun/moon eclipse icon is the first
    // consumer. See the `customIcon` Loader below for how it's sized and
    // positioned; every existing glyph/label-only consumer is unaffected
    // since this defaults to null.
    property Component iconDelegate: null
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

    // OOP-22 (item 4): screen x of this button's RIGHT edge — the bar
    // popout aligns its own right edge to this so it hangs directly under
    // the button rather than in the corner. Guarded: mapToItem(null) can
    // throw before the item is in a scene; callers treat 0 as "fall back
    // to a corner position". (Replaced OOP-17's centerX(), now unused.)
    function rightX() {
        try {
            return root.mapToItem(null, root.width, 0).x
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
    // R3: the status bar reads much tighter than a panel button — half a
    // rhythm unit of vertical inset on an isle Segment, a full one on a
    // panel Segment (the same half-step latitude the runner takes for its
    // own hpad).
    readonly property real paddingV: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
        * (root.ambient === "isle" ? 0.5 : 1)

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
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
        Behavior on border.color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    // Follow-up (user, 2026-09-11): "change the hover effect, instead of
    // changing the button borders and background, 'highlight' the text...
    // Do that with a transition (quick)." Isle-only (the status bar) — a
    // panel Segment (a settings row, a sidebar tab) keeps its existing
    // flat hover fill untouched, same scoping decision as `labelFirst`
    // above. Direction changed to bottom-to-top per a second follow-up
    // (user, 2026-09-12) — was left-to-right (width growth, anchored
    // left) originally, now height growth anchored to the bottom.
    //
    // `_sweepOn` covers BOTH "hover" and "active" (not just hover) —
    // second follow-up (user, 2026-09-12): clicking a hovered button
    // flickered, because the sweep (already at full coverage from the
    // hover) was shrinking back out at the exact moment the OLD active
    // case's own `bg` was independently fading in via the base Rectangle
    // below — two different rectangles, two different current values,
    // neither at full coverage for a moment in the middle of that
    // crossfade. Since hover and (non-accent) active render pixel-
    // identical already (WidgetStates.js's isle `hover`/`active` cases
    // share the same colorOpposite/colorMain pair — confirmed with the
    // user this identical-strength look is intentional), the fix is to
    // have them share the SAME rectangle/mechanism instead of two: a
    // hover-then-click now has nothing to visually settle, because the
    // sweep was already fully in and just stays there. Excludes
    // `accentWhenActive`'s active state (PhiAgent) — that path already
    // renders via its own accent colours on the base Rectangle below,
    // untouched, so it must not also get a colorOpposite sweep on top.
    //
    // Driven off `resolvedState`, not the raw `hovered` flag: resolve()
    // already picks exactly one state by precedence (active/pressed beats
    // focus beats hover), so a button that is BOTH keyboard-focused and
    // mouse-hovered shows its focus ring, not a hover sweep fighting it
    // for the same space — the same precedence `stateColors` itself
    // already respects.
    //
    // Deliberately NOT a per-pixel masked reveal of the icon/label
    // content (i.e. not a duplicate icon/text layer clipped to the sweep
    // extent, the way SunMoonIcon/BatteryIcon/GpuIcon's own fills work):
    // several of this bar's icons are procedural Canvas drawings, and
    // rendering every `iconDelegate` a second time just to clip it would
    // double each icon's Canvas and its running animations (a real cost —
    // BatteryIcon's charge pulse, WifiIcon's search pulse etc. are all
    // infinite loops) for a hover/active micro-interaction. Instead: this
    // Rectangle alone sweeps for the BACKGROUND, and the foreground
    // colour (`contentColor`, which every icon/label already reads) just
    // fades to the inverted pair on the same timer via the Behaviors
    // those already have — `StyledText`/`StyledIcon` both already carry
    // `Behavior on color`, so the label fades smoothly; a custom Canvas
    // `iconDelegate` has no such Behavior on its own `iconColor` (that
    // property is fed by a binding at the call site, not an imperative
    // assignment — the same binding-vs-Behavior gap this session hit and
    // documented repeatedly elsewhere, e.g. Brightness.qml's header), so
    // those icons snap colour instead of fading.
    readonly property bool _sweepOn: root.ambient === "isle"
        && (root.resolvedState === "hover"
            || (root.resolvedState === "active" && !root.accentWhenActive))
    property real hoverAmount: 0
    Behavior on hoverAmount {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
    onResolvedStateChanged: root.hoverAmount = root._sweepOn ? 1 : 0
    Component.onCompleted: root.hoverAmount = root._sweepOn ? 1 : 0

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.ambient === "isle" ? parent.height * root.hoverAmount : 0
        radius: Config.Appearance.radiusBase
        color: Config.Appearance.colorOpposite
        visible: root.ambient === "isle" && height > 0.5
    }

    // Follow-up (user, 2026-09-11): "invert the order, text before icon" —
    // scoped to `ambient: "isle"` (the status bar) only, not every Segment
    // in the app (a panel Segment elsewhere — a settings row, a sidebar
    // tab — keeps icon-then-label; nothing there was asked to change).
    readonly property bool labelFirst: root.ambient === "isle"

    Item {
        // A plain Item, not a Row: Qt's own Row docs say a child "should
        // not... horizontally anchor itself using left, right,
        // horizontalCenter, fill or centerIn", and icon/text below anchor
        // horizontally to each other. Explicit rounded x/y instead of
        // `anchors.centerIn: parent` — follow-up (user, 2026-09-11): a
        // workspace digit read "1px low-right" of true centre. `centerIn`
        // computes `(parent - child) / 2`, which is fractional whenever
        // that difference is odd; Math.round pins it to a whole pixel
        // instead of leaving the sub-pixel remainder for the renderer to
        // resolve however it does. Applies to every Segment, not just
        // workspaces — the same rounding gap exists wherever content and
        // button box sizes differ by an odd number of pixels.
        id: layout
        readonly property bool _iconShown: iconGlyph.visible || customIcon.active
        implicitWidth: (iconGlyph.visible ? iconGlyph.implicitWidth : (customIcon.active ? customIcon.implicitWidth : 0))
            + (_iconShown && labelText.visible ? root.gap : 0)
            + (labelText.visible ? labelText.implicitWidth : 0)
        implicitHeight: Math.max(iconGlyph.visible ? iconGlyph.implicitHeight : (customIcon.active ? customIcon.implicitHeight : 0), labelText.visible ? labelText.implicitHeight : 0)
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
            anchors.left: root.labelFirst && labelText.visible ? labelText.right : parent.left
            anchors.leftMargin: root.labelFirst && labelText.visible ? root.gap : 0
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
            anchors.left: root.labelFirst && labelText.visible ? labelText.right : parent.left
            anchors.leftMargin: root.labelFirst && labelText.visible ? root.gap : 0
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
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.activated()
    }

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
