// archenemy — ekran logowania SDDM, rice yin, wariant B „kolumna”.
// Tarcza zaćmienia zostaje nietknięta po prawej; po lewej jedna wąska
// kolumna tekstu wyrównana do lewej krawędzi: godzina, data, użytkownik,
// hasło na cienkiej linii. Kompozycja asymetryczna, bez szkła.
import QtQuick
import "components"

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font
    readonly property real margin: 104 * u

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

        Mark {
            x: root.margin
            y: 88 * root.u
            mode: config.logo; glyph: config.distroGlyph
            color: config.white
            size: 34 * root.u
        }

        Column {
            id: column
            x: root.margin
            y: root.height * 0.5 - 150 * root.u
            spacing: 0

            Text {
                // Cyfry JetBrainsMono mają lewy margines w glifie — cofnięcie wyrównuje je optycznie do kolumny.
                x: -9 * root.u
                text: now.time
                color: config.white
                font.family: root.face
                font.weight: Font.Thin
                font.pixelSize: 176 * root.u
            }
            Text {
                text: now.date
                color: config.mist
                font.family: root.face
                font.pixelSize: 21 * root.u
            }
            Item { width: 1; height: 96 * root.u }
            Choice {
                text: greeter.userLabel
                idleColor: config.paper
                hoverColor: config.white
                enabledChoice: greeter.userCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 18 * root.u
                onChosen: greeter.nextUser()
            }
            Item { width: 1; height: 14 * root.u }
            Item {
                id: field
                width: 400 * root.u
                height: 44 * root.u
                Secret {
                    id: secret
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    dotColor: config.white
                    dotSize: 14 * root.u
                    hintColor: config.smoke
                    fontFamily: root.face
                    onAccepted: greeter.login(text)
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: greeter.failed ? config.ember : config.white
                    opacity: greeter.failed ? 0.95 : (secret.text.length > 0 ? 0.75 : 0.3)
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: field; property: "x"; to: 10 * root.u; duration: 50 }
                    NumberAnimation { target: field; property: "x"; to: -10 * root.u; duration: 90 }
                    NumberAnimation { target: field; property: "x"; to: 0; duration: 60 }
                }
            }
            Item { width: 1; height: 14 * root.u }
            Text {
                text: greeter.failed ? "wrong password" : (greeter.capsLock ? "caps lock is on" : " ")
                color: config.ember
                font.family: root.face
                font.pixelSize: 14 * root.u
            }
        }

        Row {
            x: root.margin
            y: root.height - height - 84 * root.u
            spacing: 40 * root.u
            Choice {
                text: greeter.sessionName
                idleColor: config.ash
                hoverColor: config.white
                enabledChoice: greeter.sessionCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 15 * root.u
                onChosen: greeter.nextSession()
            }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 14 * root.u; color: config.slate }
            Choice { text: "suspend"; visible: sddm.canSuspend || config.preview === "1"; idleColor: config.ash; hoverColor: config.white; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.suspend() }
            Choice { text: "restart"; visible: sddm.canReboot || config.preview === "1"; idleColor: config.ash; hoverColor: config.white; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.reboot() }
            Choice { text: "shut down"; visible: sddm.canPowerOff || config.preview === "1"; idleColor: config.ash; hoverColor: config.white; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.powerOff() }
        }
    }
}
