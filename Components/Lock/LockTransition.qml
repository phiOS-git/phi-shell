import QtQuick
import qs.Config as Config

// Single owner of lock/unlock animation. Lock.qml handles layout, this file
// handles movement only (envelope, cascade, low-power snap, concealFinished event).
// concealFinished fires once per conceal — the only trigger that clears `locked`.
//
// reveal (locking): ceremonial. Envelope takes long category-C time; elements
// cascade in on category-B, staggered. conceal (unlocking): fast vanish. Elements
// leave in reverse order on category-B, envelope closes on category-B.
//
// Per-element rise is Translate, not y-animation: the centred Column owns y.
// Translate appends to existing transforms (password panel's error shake).
//
// staggerStep is delay per child, not a second timing system. Scales with mono
// ch (caller-provided chWidth), not hardcoded.

Item {
    id: root

    default property alias content: contentSlot.data

    // Elements to cascade, in reveal order. Each gets category-B fade and rise;
    // conceal plays in reverse.
    property var targets: []
    // Surface mono-cell width in pixels — rise length derived, no hardcoded size.
    property real chWidth: 0
    // False in low power mode: reveal/conceal become an instant snap.
    property bool animated: true
    // True once reveal completes. Lock.qml's safety timer detects unrealized reveal.
    property bool revealed: false

    // Emitted exactly once when conceal's animation (or low-power instant snap)
    // finishes. Lock.qml's only trigger to clear `locked`.
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
        // Completion on SEQUENCE not child fade: Qt suppresses child's `finished`
        // on natural completion. Sequence's `finished` fires exactly on natural
        // end, never on stop(), so it's the reliable hook for "conceal fully closed".
        onFinished: root.concealFinished()
    }

    // --- per-element cascade -------------------------------------------
    // Persistent {anim, translate} per index, created once, reused. Creation
    // failure leaves element static — fails open, never breaks lock screen.
    property var _anims: []

    function _ensureTarget(child, index) {
        if (root._anims[index] !== undefined) return root._anims[index]
        try {
            var translate = Qt.createQmlObject(
                'import QtQuick; Translate { }', child, "LockTransition")
            // Append, never replace: password panel's error shake already uses
            // Translate; second compose additively.
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
            // Fails open: element snaps instead of stranding invisible.
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

    // Jump to finished state without animation (low-power and safety net).
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

    // Locking: envelope opens while elements cascade in.
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

    // Unlocking: elements leave in reverse order, then envelope closes.
    function conceal() {
        revealEnvelope.stop()
        concealEnvelope.stop()
        if (!root.animated) {
            root.snap(false)
            // Still emit completion — Lock.qml unlock depends on it.
            // Deferred so it lands after current handlers.
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