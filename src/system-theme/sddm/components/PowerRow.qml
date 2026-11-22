// archenemy — uśpienie, restart i wyłączenie jako trzy słowa w rzędzie.
// Pozycja jest widoczna tylko wtedy, gdy SDDM może ją wykonać (albo w
// podglądzie: preview=1 w theme.conf.user).
import QtQuick

Row {
    id: power
    property color idleColor: "#808080"
    property color hoverColor: "white"
    property string face: "monospace"
    property real size: 15
    spacing: size * 2.4

    Choice {
        text: "suspend"; visible: sddm.canSuspend || config.preview === "1"
        idleColor: power.idleColor; hoverColor: power.hoverColor
        font.family: power.face; font.pixelSize: power.size
        onChosen: sddm.suspend()
    }
    Choice {
        text: "restart"; visible: sddm.canReboot || config.preview === "1"
        idleColor: power.idleColor; hoverColor: power.hoverColor
        font.family: power.face; font.pixelSize: power.size
        onChosen: sddm.reboot()
    }
    Choice {
        text: "shut down"; visible: sddm.canPowerOff || config.preview === "1"
        idleColor: power.idleColor; hoverColor: power.hoverColor
        font.family: power.face; font.pixelSize: power.size
        onChosen: sddm.powerOff()
    }
}
