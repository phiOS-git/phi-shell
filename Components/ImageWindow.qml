import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// One delegate per open image, built on Widgets/FloatingFrame — the shared
// chrome for a shell-owned floating window (padded content area, bottom
// header with title and close, native interactive move). Only the
// image-specific pieces live here: the image itself and double-click
// fullscreen.

Widgets.FloatingFrame {
    id: root

    required property string imageId
    required property string path

    readonly property string filename: {
        const parts = root.path.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : root.path
    }

    // Stable prefix for Hyprland rules — the real xdg-toplevel title, not
    // what the header displays. `headerTitle` below is the short, visible
    // one.
    title: "phios-image — " + root.filename
    headerTitle: root.filename

    // Fixed default: multiple of monospace cell, not a bare pixel. Not sized
    // to image resolution; PreserveAspectFit fits any image into this frame.
    width: root.chWidth * 64
    height: root.chWidth * 44

    Image {
        id: img
        anchors.fill: parent
        source: root.path.length > 0 ? "file://" + root.path : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
    }

    // Double-click toggles fullscreen; scoped to the image content, which
    // FloatingFrame keeps clipped and separate from its own draggable header.
    MouseArea {
        anchors.fill: parent
        onDoubleClicked: root.fullscreen = !root.fullscreen
    }

    // Close button in the header strip.
    onCloseRequested: Services.ImageWindows.close(root.imageId)

    // Compositor close request (native signal). Removes entry from model,
    // which destroys the delegate.
    onClosed: Services.ImageWindows.close(root.imageId)
}
