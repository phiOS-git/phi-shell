pragma Singleton
import Quickshell

// A minimal, write-from-one-place broadcast of whether the session is locked,
// so Components/Bar/Bar.qml — a separate top-level surface with no way to
// reach into Components/Lock/Lock.qml's own WlSessionLock instance directly —
// can react to locking and unlocking. Lock.qml is the only writer; this file
// is the read side, not a second place allowed to touch WlSessionLock itself.
//
// `locked` goes true the instant Lock.qml starts locking, and goes false only
// once its conceal fade finishes on a successful unlock — not at the earlier
// instant PAM returns Success (`root.authenticated` turning true, a level
// Lock.qml deliberately doesn't expose here). Matching the fade's own finish
// keeps a bar reveal timed to when the desktop actually becomes visible again,
// not to when authentication merely succeeded while the lock surface was still
// fading out on top of it.
Singleton {
    property bool locked: false
}
