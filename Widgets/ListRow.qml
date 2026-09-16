import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/ListRow (S-21). A row inside a list, popover or launcher
// result set. The one place in this widget library that renders the ">"
// glyph: the affordance rule (§8.6) reserves it for the active input point
// only, so no other widget in this directory draws it. Here it marks
// keyboard-navigation position specifically (the resolved "focus" state),
// which is distinct from `active` (a persisted selection, e.g. "this is
// the current tab") — the two can coexist on the same row without
// conflict, since resolve() already gives active/pressed precedence over a
// bare focus state. The row has one leading slot: it shows ">" while
// focused, else the row's own `glyph` if it has one, else nothing — never
// both, so the glyph never appears as ambient decoration.
//
// User bug report, 2026-09-16: a "thin" restyle (rework-issues.md "New
// requests" item 14 — plain text, a highlighter pill, no resting box) was
// built directly into this widget's own DEFAULT look — but ListRow is the
// SHARED row used everywhere (Settings nav, the agent panel's project
// list, the memory-notice picker, …), not just the status bar overlays'
// device lists it was actually reported against, so every one of those
// unrelated surfaces silently changed shape too. "The sections should
// have never change, those are specific elements for a custom panel, not
// simple entries in a list. The devices lists instead can stay as they
// are. All the previous changes were meant for the status bar overlays
// only." `thin` (opt-in, default false) is the fix: false reproduces this
// widget's original panel-button look byte-for-byte (verified against
// commit 4494290, the last one before this ever changed), true is the new
// look — set explicitly only at the call sites that are genuinely a
// status-bar-overlay device list (Widgets/WifiNetworkList.qml, and
// Panels/BarPopout.qml's bluetooth/ethernet/tailscale/firewall/timer/
// stopwatch rows), never as this widget's own default.

Item {
    id: root

    property string label: ""
    property string value: ""
    property string glyph: ""
    property bool active: false
    property bool loading: false
    property bool invalid: false
    // Out-of-plan: settings-overhaul batch A. A search-match wash, distinct
    // from `active` (a persisted selection): the settings nav highlights an
    // entry whose section matches the query without hiding the others.
    // Additive and default-off — every existing caller is unaffected.
    property bool highlighted: false
    // See this file's own header — opt-in, default false (the original
    // look). True is the status-bar-overlay device-list style.
    property bool thin: false

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed
    readonly property bool keyboardFocus: activeFocus

    signal activated()

    readonly property string resolvedState: WidgetStates.resolve({
        enabled: root.enabled, hovered: root.hovered, pressed: root.pressed,
        active: root.active, keyboardFocus: root.keyboardFocus,
        loading: root.loading, invalid: root.invalid
    })
    // rework-issues.md "New requests" item 14: "a list of texts, with the
    // 'highlight' hover and selection (same effect used in the runner
    // bar)" — the "list" ambient (WidgetStates.js) is the thin-text/
    // highlighter recipe, read only when `thin` is set; every other
    // ambient's `default` case (the plain, no-ambient call below) still
    // paints a full-contrast block behind the row at rest, this widget's
    // original look.
    readonly property var stateColors: root.thin
        ? WidgetStates.surfaceColors(Config.Appearance, resolvedState, "list")
        : WidgetStates.surfaceColors(Config.Appearance, resolvedState)
    // The "hover effect (opacity)" half of the same request, `thin` only:
    // a resting row reads at reduced emphasis, hovering (or being
    // selected/focused/invalid, all of which already carry their own
    // colour cue) brings it to full. The original (non-thin) look never
    // dimmed a resting row this way.
    readonly property real restEmphasis: root.thin
        && (root.resolvedState === "default" || root.resolvedState === "disabled")
        ? 0.7 : 1.0

    // OOP-19: when the row background inverts (the "active"/selected state,
    // surfaceColors() → bg: contrast), the label, value and leading glyph
    // must invert with it or the row reads as invisible same-on-same — the
    // bug the user reported for every ListRow-based selection surface
    // (Settings nav, the agent project list, the memory-notice picker).
    // Segment (OOP-03) and StyledButton already recolour their own content
    // this way; ListRow did not. `labelColor` tracks the resolved fg in
    // every state (which is the ordinary full-contrast ink except when
    // inverted or invalid); `valueColor` keeps the §8.6 affordance split —
    // a value stays low-contrast monochrome at rest — and only follows the
    // inversion when the whole row is selected (`thin` also follows it on
    // keyboard-focus, since that state gets its own highlighter pill there
    // too — the original look has no such pill to match).
    readonly property color labelColor: root.stateColors.fg
    readonly property color valueColor: (root.resolvedState === "active"
            || (root.thin && root.resolvedState === "focus"))
        ? root.stateColors.fg
        : Config.Appearance.textMuted

    // design/tokens.common.sh stores space-N in `ch`, not px — see
    // Panel.qml's identical comment.
    TextMetrics {
        id: chMetrics
        font.family: Config.Appearance.fontMono
        font.pixelSize: Config.Appearance.fontSize1
        text: "0"
    }
    readonly property real chWidth: chMetrics.width
    readonly property real inset: WidgetStates.chToPixels(Config.Appearance.space2, chWidth)
    readonly property real gap: WidgetStates.chToPixels(Config.Appearance.space1, chWidth)
    // The `thin` highlight's own small overshoot past the text it hugs —
    // same proportion Launcher.qml's own result-row highlight uses
    // (`hpad: root.chWidth * 0.6`), not this row's `inset` above.
    readonly property real hpad: root.chWidth * 0.6

    // `thin` rows are noticeably denser: Launcher.qml's own result row
    // (the "runner bar" reference the original report cited) is
    // `chMetrics.height + space1` (1ch total), against this row's
    // original `space2 * 2` (4ch). The original look is unchanged.
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)
        + WidgetStates.chToPixels(root.thin ? Config.Appearance.space1 : Config.Appearance.space2, chWidth)
        * (root.thin ? 1 : 2)
    // rework-status-bar.md Style item 7a, root cause: this widget never
    // reported an `implicitWidth` at all — harmless for every EXISTING
    // caller (Settings nav, the agent panel's lists, every status-bar
    // overlay device list), since every one of them explicitly binds
    // `width:` and never reads this back. Widgets/ContextMenu.qml
    // (Style item 7a's actual caller) is the first consumer that needs
    // it: its own `layout` Column sizes the popup window from
    // `layout.implicitWidth`, which for a Column is the max of its
    // children's own `implicitWidth` — never their assigned `width` — so
    // with this unset every row (and the whole menu) collapsed to zero
    // width, rendering the menu as an unreadable sliver: the actual cause
    // behind "the context menu ... has no option inside" surviving this
    // file's own earlier width/height fix on the popup window itself.
    implicitWidth: (root.thin ? 0 : root.inset)
        + (leading.visible ? leading.implicitWidth + root.gap : 0)
        + labelText.implicitWidth
        + (valueText.visible ? root.gap + valueText.implicitWidth : 0)
        + (root.thin ? 0 : root.inset)
    activeFocusOnTab: true
    opacity: WidgetStates.opacityFor(resolvedState) * root.restEmphasis

    // The original look: a full-row-width filled Rectangle, present at
    // every state (colour alone changes).
    Rectangle {
        visible: !root.thin
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: root.stateColors.bg

        Behavior on color {
            ColorAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    // The `thin` "highlighter effect": a Rectangle sized to the leading
    // glyph + label text ONLY (not the row's full width, and not the
    // trailing `value`) — Launcher.qml's own result-row highlight is the
    // literal reference this shape copies. Shown for active/keyboard-focus
    // only; hover is opacity-only (`restEmphasis` above).
    Rectangle {
        visible: root.thin
        x: (leading.visible ? leading.x : labelText.x) - root.hpad
        width: (labelText.x + labelText.contentWidth) - x + root.hpad
        height: parent.height
        radius: Config.Appearance.radiusSmall
        color: root.stateColors.bg
        opacity: (root.resolvedState === "active" || root.resolvedState === "focus") ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Config.Appearance.radiusBase
        color: Config.Appearance.accent
        opacity: root.highlighted && root.resolvedState !== "active" ? 0.12 : 0
        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }
    }

    StyledIcon {
        id: leading
        // The only glyph in this widget library carrying the "active input
        // point" meaning (§8.6) — shown for the focus state specifically,
        // never for hover/active/pressed, and never anywhere else.
        glyph: root.resolvedState === "focus" ? ">" : root.glyph
        visible: glyph.length > 0
        color: root.labelColor
        anchors.left: parent.left
        anchors.leftMargin: root.thin ? 0 : root.inset
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        id: labelText
        text: root.label
        invalid: root.invalid
        color: root.labelColor
        sizeStep: root.thin ? 0 : 2
        anchors.left: parent.left
        anchors.leftMargin: (root.thin ? 0 : root.inset) + (leading.visible ? leading.implicitWidth + root.gap : 0)
        anchors.right: valueText.visible ? valueText.left : parent.right
        anchors.rightMargin: valueText.visible ? root.gap : (root.thin ? 0 : root.inset)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
    }

    StyledText {
        id: valueText
        text: root.value
        kind: "label"
        sizeStep: root.thin ? 0 : 2
        color: root.valueColor
        visible: root.value.length > 0
        anchors.right: parent.right
        anchors.rightMargin: root.thin ? 0 : root.inset
        anchors.verticalCenter: parent.verticalCenter
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.loading
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        enabled: root.enabled && !root.loading
        onTapped: root.activated()
    }

    // Style pass 2026-09-14: see Widgets/StyledButton.qml's identical
    // comment — a systemic keyboard-activation gap, fixed the same way
    // here.
    Keys.onReturnPressed: if (root.enabled && !root.loading) root.activated()
    Keys.onSpacePressed: if (root.enabled && !root.loading) root.activated()

    Behavior on opacity {
        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
