import QtQuick
import qs.Config as Config
import qs.Widgets as Widgets

// phiOS — Panels/tabs/ChatBubble (S-31). One message row for AiChat.qml's
// static mock conversation. A standalone file, not a QML inline component:
// this repository has no precedent anywhere for the "component Name: Type
// {}" inline-component feature, and every reusable visual piece elsewhere
// (Widgets/, Bar/modules/) is its own file referenced through a directory
// import instead — the same, already-proven shape AiChat.qml uses to reach
// this file (`import "." as Local`, the same-directory sibling of Bar.qml's
// own `import "modules" as Modules`).
//
// Referenced by id here (bubbleRoot.text/from), not a bare `text`/`from`
// or `parent.text`/`parent.from`, for two independent reasons: StyledText
// already owns a `text` property of its own, which a bare reference would
// resolve to before ever reaching this file's property of the same name;
// and this content lands inside Panel's contentItem (Widgets/Panel.qml),
// not this component itself, so `parent` from inside the nested StyledText
// is the wrong object entirely — the identical indirection this step found
// and fixed once already in Panels/tabs/Notifications.qml.

Widgets.Panel {
    id: bubbleRoot

    property string from: "you"
    property string text: ""

    width: parent ? parent.width : 0
    height: bubbleText.implicitHeight + padding * 2
    active: bubbleRoot.from === "you"

    Widgets.StyledText {
        id: bubbleText
        width: parent.width
        wrapMode: Text.Wrap
        text: bubbleRoot.text
        color: bubbleRoot.from === "you" ? Config.Appearance.accentText : Config.Appearance.textPrimary
    }
}
