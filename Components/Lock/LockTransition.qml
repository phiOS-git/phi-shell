import QtQuick
import qs.Config as Config

// The single owner of every lock/unlock animation on the lock surface.
// Lock.qml keeps ALL the layout;
// this file keeps ONLY the movement, — transition can be reworked without touching the content: - the whole-surface envelope - the per-element cascade - the low-power bypass - the completion event Lock.qml's security-critical unlock path listens to: `concealFinished` fires exactly once per conceal.
// It is the only trigger that clears `locked` — nothing in this file ever touches PAM or `root.locked`.
// Why the two directions read so differently: - reveal (locking) is ceremonial: the envelope takes the long category-C time the old plain fade already used (motionCScramble), while the elements cascade in during it on the quick category-B duration/curve, each one `staggerStep` after the previous — the "inner elements appear with different timings" part of the design.
// - conceal (unlocking) is a vanish: elements leave in reverse order on category B, then the envelope closes on category B too.
// Leaving a locked screen should feel quick, not ceremonious.
// The per-element rise is a `transform: Translate`, never a `y` animation: a positioner authoritatively owns `y`, and a second animator fighting it is exactly the conflict Widgets/StaggerReveal.qml documents for why IT stays opacity-only.
// A translate renders the same visual without touching geometry, — rise is safe;
// it is appended to any transform the target already had, never replacing it.
// `staggerStep` is a per-child DELAY on top of the shared category-B animation — the same convention Widgets/StaggerReveal.qml's own `staggerStep` documents, so it is not a new design-token-sized number, and it scales with the mono `ch` of the surface rather than hardcoding a size.

Item {
    id: root

    default property alias content: contentSlot.data

    // The elements to cascade, in reveal order.
    // Each gets its own category-B opacity fade and a small rise;
    // conceal plays the same list in reverse.
    property var targets: []
    // The surface's mono-cell width in pixels — the rise length is derived from it (0 = no rise at all) so no size is hardcoded.
    property real chWidth: 0
    // False in low power mode: reveal/conceal become an instant snap.
    property bool animated: true
    // True once a reveal has completed.
    // Lock.qml's safety timer reads this to detect a reveal that never ran and snap the screen visible.
    property bool revealed: false

    // Emitted exactly once when a conceal's animation has fully finished.
    // Lock.qml listens to this; it is the single place `locked` is cleared.
    signal concealFinished()

    readonly property real rise: root.chWidth > 0 ? root.chWidth * 0.5 : 0
    readonly property int envelopeDuration: Config.Appearance.motionCScramble
    readonly property int elementDuration: Config.Appearance.motionBDuration
    property int staggerStep: 40

    opacity: 0

    Item {
        id: contentSlot
        anchors.fill: parent
    }

    // --- whole-surface envelope ----------------------------------------
    NumberAnimation {
        id: revealEnvelope
        target: root
        property: "opacity"
        from: 0; to: 1
        duration: root.envelopeDuration
        easing.type: Easing.InOutQuad
        onFinished: root.revealed = true
    }

    SequentialAnimation {
        id: concealEnvelope
        PauseAnimation { id: concealPause }
        NumberAnimation {
            id: concealFade
            target: root
            property: "opacity"
            to: 0
            duration: root.elementDuration
            easing.type: Easing.OutQuad
        }
        // Completion hook on the SEQUENCE, deliberately not on the child fade: when a SequentialAnimation ends naturally it suppresses its current (last) child's `finished` signal, so an `onFinished` on `concealFade` would silently never run and Lock.qml's unlock would never see `concealFinished`.
        // The sequence's `finished` fires exactly on natural completion and never on an external `stop()`, so it is the reliable, no-extra- fire hook for "the conceal has fully closed".
        onFinished: root.concealFinished()
    }

    // --- per-element cascade ------------------------------------------- One persistent { anim, translate } pair per target index, created once and reused on every reveal/conceal — the same lazy Qt.createQmlObject pattern Widgets/StaggerReveal.qml already proves out.
    // A creation failure just leaves that element static — fails open onto "no stagger", never onto a broken lock screen.
    property var _anims: []

    function _ensureTarget(child, index) {
        if (root._anims[index] !== undefined) return root._anims[index]
        try {
            var translate = Qt.createQmlObject(
                'import QtQuick; Translate { }', child, "LockTransition")
            // Append, never replace: the password panel already owns a Translate for its error shake, and a second translate composes additively with it.
            child.transform = (child.transform || []).concat([translate])
            var seq = Qt.createQmlObject(
                'import QtQuick; SequentialAnimation { PauseAnimation {}; ParallelAnimation { NumberAnimation { property: "opacity" } NumberAnimation { property: "y" } } }',
                root, "LockTransition")
            root._anims[index] = { seq: seq, translate: translate }
        } catch (e) {
            root._anims[index] = null
        }
        return root._anims[index]
    }

    function _drive(child, index, toOpacity, toY, delay) {
        var entry = root._ensureTarget(child, index)
        if (!entry) {
            // Fails open: the element snaps to its destination instead of being stranded invisible mid-conceal.
            child.opacity = toOpacity
            return
        }
        var seq = entry.seq
        var pause = seq.animations[0]
        var parallel = seq.animations[1]
        var opAnim = parallel.animations[0]
        var yAnim = parallel.animations[1]

        pause.duration = delay
        opAnim.target = child
        opAnim.duration = root.elementDuration
        opAnim.easing.type = Easing.Bezier
        opAnim.easing.bezierCurve = Config.Appearance.motionBCurve
        opAnim.to = toOpacity
        yAnim.target = entry.translate
        yAnim.duration = root.elementDuration
        yAnim.easing.type = Easing.Bezier
        yAnim.easing.bezierCurve = Config.Appearance.motionBCurve
        yAnim.to = toY
        seq.restart()
    }

    // jump everything to a finished state without animation
    function snap(show) {
        root.opacity = show ? 1 : 0
        var n = root.targets.length
        for (var i = 0; i < n; i++) {
            var t = root.targets[i]
            if (!t) continue
            t.opacity = show ? 1 : 0
            var e = root._anims[i]
            if (e) e.translate.y = 0
        }
        root.revealed = show
    }

    // locking: envelope opens while the elements cascade in
    function reveal() {
        revealEnvelope.stop()
        concealEnvelope.stop()
        var n = root.targets.length
        for (var i = 0; i < n; i++) {
            var t = root.targets[i]
            if (!t) continue
            t.opacity = 0
            var entry = root._ensureTarget(t, i)
            if (entry) entry.translate.y = root.rise
        }
        root.opacity = 0
        if (!root.animated) {
            root.snap(true)
            return
        }
        root.revealed = false
        for (var j = 0; j < n; j++) {
            var tj = root.targets[j]
            if (!tj) continue
            root._drive(tj, j, 1, 0, j * root.staggerStep)
        }
        revealEnvelope.start()
    }

    // unlocking: elements leave in reverse order, then the envelope closes
    function conceal() {
        revealEnvelope.stop()
        concealEnvelope.stop()
        if (!root.animated) {
            root.snap(false)
            // Still emit the completion event — Lock.qml's unlock depends on it — deferred so it lands after any signal handler currently in flight.
            Qt.callLater(function () { root.concealFinished() })
            return
        }
        var n = root.targets.length
        if (n > 0) {
            for (var i = 0; i < n; i++) {
                var t = root.targets[n - 1 - i]
                if (!t) continue
                root._drive(t, n - 1 - i, 0, root.rise, i * root.staggerStep)
            }
            concealPause.duration = (n - 1) * root.staggerStep + root.elementDuration
        } else {
            concealPause.duration = 0
        }
        root.revealed = false
        concealEnvelope.start()
    }
}