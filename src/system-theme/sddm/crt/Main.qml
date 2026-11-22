// archenemy — ekran logowania SDDM, rice crt: „linia poleceń”.
// Ekran kineskopu: linie skanowania na całym obrazie, odczyt czasu w lewym
// górnym rogu jak na oscyloskopie i jedna linia statusu na dole — logo,
// login, hasło z kursorem blokowym, sesja, zasilanie. Środek ekranu zostaje
// dla tapety: ostatnio ustawionej przez Super+W (theme.conf.user:
// background), a bez niej krzywych oscyloskopu rice'a.
import QtQuick
import QtQuick.Effects
import "components"

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font
    readonly property real barHeight: 78 * u
    readonly property real edge: 56 * u

    Backdrop {
        id: backdrop
        anchors.fill: parent
        base: config.base
        custom: config.background
    }
    Scanlines {
        anchors.fill: parent
        color: Qt.rgba(0, 8 / 255, 24 / 255, 0.28)
        pitch: Math.max(3, Math.round(3 * root.u))
    }

    Greeter { id: greeter; onRejected: { secret.text = ""; shake.restart() } }
    Now { id: now }
    Seat { id: seat; wanted: config.loginScreen; focusTarget: secret }

    Item {
        visible: seat.here
        anchors.fill: parent

        // Odczyt czasu. Na tapecie użytkownika stoi na ciemnej podkładce.
        Rectangle {
            visible: backdrop.usingCustom
            x: readout.x - 24 * root.u
            y: readout.y - 18 * root.u
            width: readout.width + 48 * root.u
            height: readout.height + 36 * root.u
            radius: 4 * root.u
            color: config.base
            opacity: 0.9
        }
        Column {
            id: readout
            x: root.edge
            y: 52 * root.u
            spacing: 2 * root.u
            Text {
                text: now.date.toUpperCase()
                color: config.blue
                font.family: root.face
                font.pixelSize: 16 * root.u
                font.letterSpacing: 2 * root.u
            }
            Text {
                text: now.time
                color: config.phosphor
                font.family: root.face
                font.weight: Font.Light
                font.pixelSize: 100 * root.u
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: config.glow
                    shadowBlur: 1.0
                    shadowOpacity: 0.65
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 32
                    autoPaddingEnabled: true
                }
            }
        }

        // Komunikat nad linią statusu.
        Text {
            x: root.edge
            y: root.height - root.barHeight - height - 14 * root.u
            text: greeter.failed ? "ACCESS DENIED" : (greeter.capsLock ? "CAPS LOCK IS ON" : "")
            color: config.alarm
            font.family: root.face
            font.pixelSize: 15 * root.u
            font.letterSpacing: 2 * root.u
        }

        // Linia statusu na całą szerokość ekranu.
        Rectangle {
            id: bar
            y: root.height - height
            width: root.width
            height: root.barHeight
            color: Qt.rgba(3 / 255, 21 / 255, 51 / 255, 0.86)
            Rectangle { width: parent.width; height: Math.max(1, Math.round(root.u)); color: config.glow; opacity: 0.85 }

            Row {
                id: prompt
                x: root.edge
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18 * root.u
                transform: Translate { id: promptShift }

                Mark {
                    anchors.verticalCenter: parent.verticalCenter
                    mode: config.logo; glyph: config.distroGlyph
                    color: config.phosphor
                    size: 30 * root.u
                }
                Item { width: 10 * root.u; height: 1 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "login:"; color: config.blue; font.family: root.face; font.pixelSize: 18 * root.u }
                Choice {
                    anchors.verticalCenter: parent.verticalCenter
                    text: greeter.userName
                    idleColor: config.phosphor
                    hoverColor: config.glow
                    enabledChoice: greeter.userCount > 1
                    opacity: 1
                    font.family: root.face
                    font.pixelSize: 18 * root.u
                    onChosen: greeter.nextUser()
                }
                Item { width: 18 * root.u; height: 1 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "password:"; color: greeter.failed ? config.alarm : config.blue; font.family: root.face; font.pixelSize: 18 * root.u }
                Secret {
                    id: secret
                    anchors.verticalCenter: parent.verticalCenter
                    width: 340 * root.u
                    height: 40 * root.u
                    verticalAlignment: TextInput.AlignVCenter
                    dotColor: config.phosphor
                    dotSize: 14 * root.u
                    hint: ""
                    blockCursor: true
                    fontFamily: root.face
                    onAccepted: greeter.login(text)
                }
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: promptShift; property: "x"; to: 10 * root.u; duration: 50 }
                NumberAnimation { target: promptShift; property: "x"; to: -10 * root.u; duration: 90 }
                NumberAnimation { target: promptShift; property: "x"; to: 0; duration: 60 }
            }

            Row {
                x: root.width - width - root.edge
                anchors.verticalCenter: parent.verticalCenter
                spacing: 40 * root.u
                Choice {
                    anchors.verticalCenter: parent.verticalCenter
                    text: greeter.sessionName
                    idleColor: config.blue
                    hoverColor: config.phosphor
                    enabledChoice: greeter.sessionCount > 1
                    opacity: 1
                    font.family: root.face
                    font.pixelSize: 15 * root.u
                    onChosen: greeter.nextSession()
                }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Math.max(1, Math.round(root.u)); height: 22 * root.u; color: config.dim }
                PowerRow {
                    anchors.verticalCenter: parent.verticalCenter
                    idleColor: config.blue; hoverColor: config.phosphor
                    face: root.face; size: 15 * root.u
                }
            }
        }
    }
}
