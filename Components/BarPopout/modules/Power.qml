import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// Six plain action rows plus a "Settings…" row that opens the settings panel
// generally (not deep-linked to any one section). Reboot/Shutdown are gated
// behind PowerActions' shared centered confirm dialog, same policy the runner
// bar's own confirm sub-view uses for the identical two actions.

Column {
    id: root

    property real chWidth: 0
    property bool active: false

    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space1
    visible: root.active

    Local.PowerActions { id: powerActions }

    Column {
        width: parent.width
        spacing: root.chWidth * Config.Appearance.space2

        Widgets.SmallButton {
            width: parent.width
            label: Services.PowerActions.title("lock")
            onClicked: powerActions.request("lock")
        }
        Widgets.SmallButton {
            width: parent.width
            label: Services.PowerActions.title("suspend")
            onClicked: powerActions.request("suspend")
        }
        Widgets.SmallButton {
            width: parent.width
            label: Services.PowerActions.title("hibernate")
            onClicked: powerActions.request("hibernate")
        }
        Widgets.SmallButton {
            width: parent.width
            label: Services.PowerActions.title("logout")
            onClicked: powerActions.request("logout")
        }
        Widgets.Separator { width: parent.width; strong: true }
        Widgets.SmallButton {
            width: parent.width
            label: Services.PowerActions.title("reboot")
            onClicked: powerActions.request("reboot")
        }
        Widgets.SmallButton {
            width: parent.width
            label: Services.PowerActions.title("shutdown")
            onClicked: powerActions.request("shutdown")
        }
        Widgets.Separator { width: parent.width; strong: true }
        Widgets.SmallButton {
            width: parent.width
            label: "Settings…"
            onClicked: { Services.SettingsPanel.show(); Services.BarPopout.hide() }
        }
    }
}
