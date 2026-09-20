import QtQuick
import qs.Config as Config

// Widgets/Reveal is the piece for a single block whose visibility a binding drives.
// This is the NESTED case: a container that is already revealing itself whose CHILDREN should not all snap in at once the instant the container finishes each direct child fades in a few milliseconds after the previous one in declaration order.
// Deliberately opacity-only, no slide — see `_animate()`'s own comment for the mechanical reason a per-child position slide is not safe to add.
// Usage — a settings-style column of rows inside an already-fading-in Panel: Panel { visible: someOverlay.open // StaggerReveal { shown: someOverlay.open anchors.fill: parent StyledText { text: "first row" } StyledText { text: "second row" } StyledText { text: "third row" } } } Every DIRECT child gets tagged in declaration order and faded in `staggerStep` milliseconds after the previous one.
// Same category-B duration/curve every widget in this shell already uses for its own opacity Behavior `staggerStep` is the only new number, and it is a per-child DELAY on top of that shared animation, not a second timing system.

Column {
    id: root

    property bool shown: false
    // Small enough that a five-row overlay finishes its whole cascade well inside a normal glance, not a perceptible sequential reveal.
    property int staggerStep: 24

    width: parent ? parent.width : 0
    // No `default property alias` needed: Column's own default property already is `data`, — consumer's directly-declared children land exactly where `root.children` expects them with no extra indirection.

    // Re-tags and re-plays on every shown toggle, not just the first — an overlay that closes and reopens gets the same cascade again, on both appearing and disappearing.
    onShownChanged: root._reveal()
    Component.onCompleted: root._reveal()

    function _reveal() {
        for (var i = 0; i < root.children.length; i++)
            root._animate(root.children[i], i)
    }

    // A plain QML/QtQuick Item is not dynamically extensible the way a bare JS object is — assigning an undeclared property name onto a QObject-derived instance is a hard error, not a silent add, — per-child animation objects live in THIS widget's own `_anims` rather than attached to the child itself.
    // `Qt.createQmlObject`'s second argument is `root` not `child` — nothing about owning the animation requires the child to be its QML parent.
    property var _anims: []

    // Lazily creates one persistent SequentialAnimation per child index instead of rebuilding it on every toggle — Qt.createQmlObject is the QML-idiomatic way to give an arbitrary, caller-supplied Item an animated property.
    // A creation failure just leaves that child static — fails open onto "no stagger", never onto a broken panel.
    // Opacity only, deliberately no position slide: `Column` itself authoritatively assigns every child's `y` on each relayout — a second, independent animation driving `y` would fight that assignment instead of cooperating with it, unlike QtQuick's own built-in positioner `add`/`move` transitions.
    // Fading is the one channel free to animate without that conflict.
    function _animate(child, index) {
        if (root._anims[index] === undefined) {
            try {
                // Plain `NumberAnimation`/`PropertyAnimation` has no `delay` property in QtQuick.
                // A `PauseAnimation` ahead of the real `NumberAnimation` inside a `SequentialAnimation` is QtQuick's actual mechanism for "wait, then animate" `animations` is `SequentialAnimation`'s default list property, — two children are reachable by index with no need for `id`s inside the dynamically-created string.
                var seq = Qt.createQmlObject(
                    'import QtQuick; SequentialAnimation { PauseAnimation {}; NumberAnimation { property: "opacity" } }',
                    root, "StaggerReveal")
                root._anims[index] = seq
                child.opacity = root.shown ? 1 : 0
            } catch (e) {
                root._anims[index] = null
            }
        }
        var seq = root._anims[index]
        if (!seq)
            return

        var pause = seq.animations[0]
        var anim = seq.animations[1]
        pause.duration = root.shown ? index * root.staggerStep : 0
        anim.target = child
        anim.duration = Config.Appearance.motionBDuration
        anim.easing.type = Easing.Bezier
        anim.easing.bezierCurve = Config.Appearance.motionBCurve
        anim.to = root.shown ? 1 : 0
        seq.restart()
    }
}
