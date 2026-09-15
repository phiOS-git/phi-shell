import QtQuick
import qs.Config as Config

// phiOS — Widgets/StaggerReveal. Out-of-plan: interface rework Phase 1
// (rework.md s4: "all elements should have similar transition (fade and
// minimal slide) for appearing and disappearing. Elements that are nested
// (eg. status bar overlays) should have compound transitions where they
// fade in and the inner elements fade in in order (with minimal delay,
// just a subtle effect that don't slow down the usage).").
//
// Widgets/Reveal is the existing piece for a single block whose visibility
// a binding drives (height 0 <-> content height, one fade). This is the
// different, NESTED case s4 describes: a container that is already
// revealing itself (a Panel/Popover fading in, already using its own
// `Behavior on opacity`, "minimal slide" being whatever that OUTER wrapper
// already does) whose CHILDREN should not all snap in at once the instant
// the container finishes — each direct child fades in a few milliseconds
// after the previous one, in declaration order. s4's own wording for this
// nested case names only the fade ("fade in and the inner elements fade in
// in order"), not a second slide layered on every row — deliberately
// opacity-only here, see `_animate()`'s own comment for the mechanical
// reason a per-child position slide is not safe to add.
//
// Not wired into any real overlay yet — rework.md's calendar/status/
// notifications/etc. overlays are later phases' work (they don't exist as
// real components yet). This file only has to exist and work correctly so
// those phases can drop it in without re-deriving the animation.
//
// Usage — a settings-style column of rows inside an already-fading-in
// Panel (direct children, same convention Widgets/Reveal itself already
// uses — no wrapping Column needed, StaggerReveal IS the column):
//
//   Panel {
//       visible: someOverlay.open
//       // (Panel's own `Behavior on opacity` above is the OUTER fade.)
//
//       StaggerReveal {
//           shown: someOverlay.open
//           anchors.fill: parent
//
//           StyledText { text: "first row" }
//           StyledText { text: "second row" }
//           StyledText { text: "third row" }
//       }
//   }
//
// Every DIRECT child above gets tagged in declaration order and faded in,
// `staggerStep` milliseconds after the previous one. Same category-B
// duration/curve every widget in this shell already uses for its own
// opacity Behavior (Config.Appearance.motionBDuration/motionBCurve) —
// `staggerStep` is the only new number, and it is a per-child DELAY on top
// of that shared animation, not a second timing system: not a design token
// (no colour/font/size/duration literal is hardcoded here), the same
// one-ratio latitude WidgetStates.js's own INACTIVE_OPACITY already takes.

Column {
    id: root

    property bool shown: false
    // rework.md s4's own words: "just a subtle effect that don't slow down
    // the usage" — small enough that a five-row overlay finishes its whole
    // cascade well inside a normal glance, not a perceptible sequential
    // reveal.
    property int staggerStep: 24

    width: parent ? parent.width : 0
    // No `default property alias` needed: Column's own default property
    // already is `data`, so a consumer's directly-declared children land
    // exactly where `root.children` below expects them with no extra
    // indirection.

    // Re-tags and re-plays on every shown toggle, not just the first —
    // an overlay that closes and reopens gets the same cascade again,
    // matching s4's "for appearing and disappearing".
    onShownChanged: root._reveal()
    Component.onCompleted: root._reveal()

    function _reveal() {
        for (var i = 0; i < root.children.length; i++)
            root._animate(root.children[i], i)
    }

    // Lazily attaches one persistent NumberAnimation per child instead of
    // rebuilding it on every toggle — Qt.createQmlObject is the QML-
    // idiomatic way to give an arbitrary, caller-supplied Item (this
    // widget does not own its children's own .qml types, so it cannot
    // declare a `Behavior` on them directly) its own animated property.
    // A creation failure (should not happen for a plain NumberAnimation,
    // but nothing here is worth a hard crash for) just leaves that child
    // static — fails open onto "no stagger", never onto a broken panel.
    //
    // Opacity only, deliberately no position slide: `Column` itself
    // authoritatively assigns every child's `y` on each relayout (that is
    // the whole point of a positioner) — a second, independent animation
    // also driving `y` would fight that assignment instead of cooperating
    // with it, unlike QtQuick's own built-in positioner `add`/`move`
    // transitions (which are for children actually being inserted/removed,
    // not for an existing, statically-declared child toggling visibility —
    // not what `shown` does here). Fading is the one channel free to
    // animate without that conflict.
    function _animate(child, index) {
        if (child._staggerAnim === undefined) {
            try {
                child._staggerAnim = Qt.createQmlObject(
                    'import QtQuick; NumberAnimation { property: "opacity" }',
                    child, "StaggerReveal")
                child.opacity = root.shown ? 1 : 0
            } catch (e) {
                child._staggerAnim = null
            }
        }
        if (!child._staggerAnim)
            return

        var anim = child._staggerAnim
        anim.target = child
        anim.duration = Config.Appearance.motionBDuration
        anim.easing.type = Easing.Bezier
        anim.easing.bezierCurve = Config.Appearance.motionBCurve
        anim.delay = root.shown ? index * root.staggerStep : 0
        anim.to = root.shown ? 1 : 0
        anim.restart()
    }
}
