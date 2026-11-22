// archenemy — ekran logowania SDDM, rice white-blue: „kapsuła”.
// Jasny rice: godzina w kolorze niebieskim u góry na środku, a logowanie
// to jedna pozioma kapsuła matowego szkła na dole — użytkownik, pole
// hasła, sesja. Logo w lewym dolnym rogu, zasilanie w prawym. Środek ekranu
// zostaje dla tapety: ostatnio ustawionej przez Super+W (theme.conf.user:
// background), a bez niej sześciokątów rice'a.
import QtQuick
import "components"

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font

    Backdrop {
        id: backdrop
        anchors.fill: parent
        base: config.base
        custom: config.background
    }

    Greeter { id: greeter; onRejected: { secret.text = ""; shake.restart() } }
    Now { id: now }
    Seat { id: seat; wanted: config.loginScreen; focusTarget: secret }

    Item {
        visible: seat.here
        anchors.fill: parent

        // Godzina. Na tapecie użytkownika (może być ciemna) stoi na szkle.
        Glass {
            visible: backdrop.usingCustom
            source: backdrop
            x: clock.x - 36 * root.u
            y: clock.y - 14 * root.u
            width: clock.width + 72 * root.u
            height: clock.height + 34 * root.u
            radius: 14 * root.u
            tint: Qt.rgba(1, 1, 1, 0.88)
            edge: Qt.rgba(1 / 255, 72 / 255, 237 / 255, 0.35)
        }
        Column {
            id: clock
            x: (root.width - width) / 2
            y: 70 * root.u
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: now.time
                color: config.blue
                font.family: root.face
                font.weight: Font.Light
                font.pixelSize: 128 * root.u
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: now.date
                color: config.ink
                opacity: 0.7
                font.family: root.face
                font.pixelSize: 18 * root.u
            }
        }

        // Kapsuła logowania.
        Glass {
            id: capsule
            source: backdrop
            x: (root.width - width) / 2
            y: root.height - height - 150 * root.u
            width: 820 * root.u
            height: 76 * root.u
            radius: 14 * root.u
            tint: Qt.rgba(1, 1, 1, backdrop.usingCustom ? 0.88 : 0.62)
            edge: greeter.failed ? config.alarm : Qt.rgba(1 / 255, 72 / 255, 237 / 255, secret.text.length > 0 ? 0.9 : 0.55)
            edgeWidth: Math.max(1, Math.round(2 * root.u))
            transform: Translate { id: capsuleShift }
        }
        Item {
            x: capsule.x
            y: capsule.y
            width: capsule.width
            height: capsule.height
            transform: Translate { x: capsuleShift.x }

            Choice {
                id: who
                x: 32 * root.u
                anchors.verticalCenter: parent.verticalCenter
                text: greeter.userLabel
                idleColor: config.ink
                hoverColor: config.blue
                enabledChoice: greeter.canSwitchUser
                opacity: 1
                font.family: root.face
                font.pixelSize: 18 * root.u
                onChosen: greeter.nextUser()
            }
            Rectangle {
                id: split
                x: who.x + who.width + 28 * root.u
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, Math.round(root.u))
                height: 30 * root.u
                color: config.blue
                opacity: 0.35
            }
            Secret {
                id: secret
                x: split.x + 28 * root.u
                width: session.x - x - 28 * root.u
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                dotColor: config.ink
                dotSize: 14 * root.u
                hintColor: config.muted
                fontFamily: root.face
                hint: greeter.needsName ? "user name" : "password"
                plain: greeter.needsName
                onAccepted: greeter.submit(text)
                onSwitchUser: greeter.nextUser()
                onSwitchSession: greeter.nextSession()
            }
            Choice {
                id: session
                x: parent.width - width - 32 * root.u
                anchors.verticalCenter: parent.verticalCenter
                text: greeter.sessionName
                idleColor: config.muted
                hoverColor: config.blue
                enabledChoice: greeter.sessionCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 15 * root.u
                onChosen: greeter.nextSession()
            }
        }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: capsuleShift; property: "x"; to: 10 * root.u; duration: 50 }
            NumberAnimation { target: capsuleShift; property: "x"; to: -10 * root.u; duration: 90 }
            NumberAnimation { target: capsuleShift; property: "x"; to: 0; duration: 60 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: capsule.y + capsule.height + 14 * root.u
            text: greeter.failed ? "wrong password" : (greeter.capsLock ? "caps lock is on" : " ")
            color: config.alarm
            font.family: root.face
            font.pixelSize: 14 * root.u
        }

        // Rogi: na tapecie użytkownika na szkle, na białej tapecie rice'a bez.
        Glass {
            visible: backdrop.usingCustom
            source: backdrop
            x: mark.x - 18 * root.u; y: mark.y - 14 * root.u
            width: mark.width + 36 * root.u; height: mark.height + 28 * root.u
            radius: 14 * root.u
            tint: Qt.rgba(1, 1, 1, 0.88)
            edge: Qt.rgba(1 / 255, 72 / 255, 237 / 255, 0.25)
        }
        Mark {
            id: mark
            x: 60 * root.u
            y: root.height - height - 56 * root.u
            mode: config.logo; glyph: config.distroGlyph
            color: config.blue
            size: 32 * root.u
        }
        Glass {
            visible: backdrop.usingCustom
            source: backdrop
            x: power.x - 22 * root.u; y: power.y - 14 * root.u
            width: power.width + 44 * root.u; height: power.height + 28 * root.u
            radius: 14 * root.u
            tint: Qt.rgba(1, 1, 1, 0.88)
            edge: Qt.rgba(1 / 255, 72 / 255, 237 / 255, 0.25)
        }
        PowerRow {
            id: power
            x: root.width - width - 64 * root.u
            y: root.height - height - 62 * root.u
            idleColor: config.muted; hoverColor: config.blue
            face: root.face; size: 15 * root.u
        }
    }
}
