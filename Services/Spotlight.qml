pragma Singleton
import QtQml
import Quickshell

// phiOS — Services/Spotlight (S-43). Just the shared `shown` flag:
// Spotlight/Spotlight.qml is instantiated once PER SCREEN (ADR 077, see
// its own header for why a primary-only instance would defeat the
// feature), so the toggle/open/close IPC handler cannot live inside that
// per-screen file — Quickshell would register the same "spotlight" IPC
// target N times. One IpcHandler lives in shell.qml instead (the one
// non-repeated root), calling the functions here; every per-screen overlay
// just reads root.shown as an external binding.

Singleton {
    id: root
    property bool shown: false
}
