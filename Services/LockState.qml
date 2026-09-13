pragma Singleton
import Quickshell

// phiOS — Services/LockState.qml (docs/TODO.md: "add in and out transition
// for the status bar, to be triggered on start, lock and unlock"). A
// minimal, write-from-one-place broadcast of whether the session is
// locked, so Bar/Bar.qml — a separate top-level surface with no way to
// reach into Lock/Lock.qml's own WlSessionLock instance directly — can
// react to locking and unlocking. Lock/Lock.qml is the only writer;
// WlSessionLock is the real service surface here, and Lock/Lock.qml's own
// header already carries the narrow exception for touching it — this file
// is the read side of that state, not a second place allowed to touch
// WlSessionLock itself.
//
// `locked` goes true the instant Lock/Lock.qml starts locking
// (lockIpc.lock(), the same moment its own `root.locked` does) and goes
// false only once its conceal fade finishes on a successful unlock — not
// at the earlier instant PAM returns Success, which is `root.authenticated`
// turning true, a level Lock/Lock.qml deliberately does not expose here.
// Matching the fade's own finish keeps a bar reveal timed to when the
// desktop actually becomes visible again, not to when authentication
// merely succeeded while the lock surface was still fading out on top of it.
Singleton {
    property bool locked: false
}
