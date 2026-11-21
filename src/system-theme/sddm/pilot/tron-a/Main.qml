// archenemy — ekran logowania SDDM, rice tron, wariant A „horyzont”.
// Godzina stoi na linii horyzontu siatki z tapety tron-grid; pod horyzontem,
// już na siatce, jedno pole: użytkownik i hasło w cienkiej cyjanowej ramce.
import QtQuick
import QtQuick.Effects
import "components"

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font
    // Linia horyzontu tapety tron-grid: 42,2 % wysokości obrazu.
    readonly property real horizon: (height - bg.paintedHeight) / 2 + 0.4217 * bg.paintedHeight

    Rectangle { anchors.fill: parent; color: config.base }
    Image {
        id: bg
        anchors.fill: parent
        source: root.width / Math.max(1, root.height) > 1.69 ? "background-169.png" : "background-1610.png"
        fillMode: Image.PreserveAspectCrop
    }

    Greeter { id: greeter; onRejected: { secret.text = ""; shake.restart() } }
    Now { id: now }

    Item {
        visible: primaryScreen
        anchors.fill: parent

        Text {
            id: clock
            x: (root.width - width) / 2
            y: root.horizon - height + 22 * root.u
            text: now.time
            color: config.cyan
            font.family: root.face
            font.weight: Font.Light
            font.pixelSize: 156 * root.u
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: config.cyan
                shadowBlur: 1.0
                shadowOpacity: 0.75
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 40
                autoPaddingEnabled: true
            }
        }
        Text {
            x: (root.width - width) / 2
            y: root.horizon + 34 * root.u
            text: now.date
            color: config.text
            opacity: 0.85
            font.family: root.face
            font.pixelSize: 19 * root.u
        }

        Rectangle {
            id: field
            x: (root.width - width) / 2
            y: root.horizon + 118 * root.u
            width: 460 * root.u
            height: 58 * root.u
            radius: 6 * root.u
            color: Qt.rgba(2 / 255, 10 / 255, 15 / 255, 0.62)
            border.width: Math.max(1, Math.round(2 * root.u))
            border.color: greeter.failed ? config.alarm : config.cyan
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: greeter.failed ? config.alarm : config.cyan
                shadowBlur: 0.8
                shadowOpacity: 0.55
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 24
                autoPaddingEnabled: true
            }

            Choice {
                id: who
                x: 20 * root.u
                anchors.verticalCenter: parent.verticalCenter
                text: greeter.userName
                idleColor: config.ink
                hoverColor: config.bright
                enabledChoice: greeter.userCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 17 * root.u
                onChosen: greeter.nextUser()
            }
            Rectangle {
                id: divider
                x: who.x + who.width + 18 * root.u
                y: 14 * root.u
                width: 1
                height: parent.height - 28 * root.u
                color: config.cyan
                opacity: 0.4
            }
            Secret {
                id: secret
                x: divider.x + 18 * root.u
                width: parent.width - x - 20 * root.u
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                dotColor: config.text
                dotSize: 13 * root.u
                hintColor: config.dim
                fontFamily: root.face
                onAccepted: greeter.login(text)
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: fieldShift; property: "x"; to: 10 * root.u; duration: 50 }
                NumberAnimation { target: fieldShift; property: "x"; to: -10 * root.u; duration: 90 }
                NumberAnimation { target: fieldShift; property: "x"; to: 0; duration: 60 }
            }
            transform: Translate { id: fieldShift }
        }
        Text {
            x: (root.width - width) / 2
            y: field.y + field.height + 16 * root.u
            text: greeter.failed ? "access denied" : (greeter.capsLock ? "caps lock is on" : " ")
            color: config.alarm
            font.family: root.face
            font.pixelSize: 14 * root.u
        }

        Row {
            x: 56 * root.u
            y: root.height - height - 48 * root.u
            spacing: 16 * root.u
            Mark {
                anchors.verticalCenter: parent.verticalCenter
                mode: config.logo; glyph: config.distroGlyph
                color: config.cyan
                size: 26 * root.u
            }
            Choice {
                anchors.verticalCenter: parent.verticalCenter
                text: greeter.sessionName
                idleColor: config.ink
                hoverColor: config.bright
                enabledChoice: greeter.sessionCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 15 * root.u
                onChosen: greeter.nextSession()
            }
        }
        Row {
            x: root.width - width - 56 * root.u
            y: root.height - height - 52 * root.u
            spacing: 36 * root.u
            Choice { text: "suspend"; visible: sddm.canSuspend || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.suspend() }
            Choice { text: "restart"; visible: sddm.canReboot || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.reboot() }
            Choice { text: "shut down"; visible: sddm.canPowerOff || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.powerOff() }
        }
    }
}
