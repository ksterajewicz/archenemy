// archenemy — ekran logowania „w tarczy”: wspólny układ rice'ów yin i yang.
// Cały formularz mieści się w tarczy zaćmienia z tapety rice'a (yin: ciemna
// tarcza na czerni, yang: jasna tarcza na bieli — ta sama geometria);
// reszta ekranu zostaje pustą tapetą. Bez szkła, bez ramek: sama typografia
// i jedna linia pod hasłem. Układ jest wpasowany w tę jedną tapetę, więc
// tło nie idzie za wyborem z Super+W (theme.conf: followWallpaper=0).
// Kolory z theme.conf rice'a: base, ink (tekst główny), soft, muted, faint,
// mark (logo), alarm.
import QtQuick

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font
    // Tarcza na tapetach yin-eclipse i yang-eclipse: środek 65,6 % × 46,4 %, promień 29,5 % wysokości obrazu.
    readonly property real discX: (width - bg.paintedWidth) / 2 + 0.656 * bg.paintedWidth
    readonly property real discY: (height - bg.paintedHeight) / 2 + 0.4637 * bg.paintedHeight
    readonly property real discR: 0.295 * bg.paintedHeight

    Backdrop { id: bg; anchors.fill: parent; base: config.base }

    Greeter { id: greeter; onRejected: { secret.text = ""; shake.restart() } }
    Now { id: now }
    Seat { id: seat; wanted: config.loginScreen; focusTarget: secret }

    Item {
        visible: seat.here
        anchors.fill: parent

        Column {
            id: stage
            x: root.discX - width / 2
            y: root.discY - height / 2 + 6 * root.u
            width: root.discR * 1.3
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: now.time
                color: config.ink
                font.family: root.face
                font.weight: Font.ExtraLight
                font.pixelSize: 132 * root.u
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: now.date
                color: config.soft
                font.family: root.face
                font.pixelSize: 19 * root.u
            }
            Item { width: 1; height: 76 * root.u }
            Choice {
                anchors.horizontalCenter: parent.horizontalCenter
                text: greeter.userLabel
                idleColor: config.muted
                hoverColor: config.ink
                enabledChoice: greeter.userCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 17 * root.u
                onChosen: greeter.nextUser()
            }
            Item { width: 1; height: 18 * root.u }
            Item {
                id: field
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300 * root.u
                height: 40 * root.u
                Secret {
                    id: secret
                    anchors.fill: parent
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    dotColor: config.ink
                    dotSize: 13 * root.u
                    hintColor: config.faint
                    fontFamily: root.face
                    onAccepted: greeter.login(text)
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: greeter.failed ? config.alarm : config.ink
                    opacity: greeter.failed ? 0.95 : (secret.text.length > 0 ? 0.7 : 0.3)
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 10 * root.u; duration: 50 }
                    NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -10 * root.u; duration: 90 }
                    NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 0; duration: 60 }
                }
            }
            Item { width: 1; height: 14 * root.u }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: greeter.failed ? "wrong password" : (greeter.capsLock ? "caps lock is on" : " ")
                color: config.alarm
                font.family: root.face
                font.pixelSize: 14 * root.u
            }
        }

        Row {
            x: 56 * root.u
            y: root.height - height - 48 * root.u
            spacing: 16 * root.u
            Mark {
                anchors.verticalCenter: parent.verticalCenter
                mode: config.logo; glyph: config.distroGlyph
                color: config.mark
                size: 26 * root.u
            }
            Choice {
                anchors.verticalCenter: parent.verticalCenter
                text: greeter.sessionName
                idleColor: config.muted
                hoverColor: config.ink
                enabledChoice: greeter.sessionCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 15 * root.u
                onChosen: greeter.nextSession()
            }
        }

        PowerRow {
            x: root.width - width - 56 * root.u
            y: root.height - height - 52 * root.u
            idleColor: config.muted; hoverColor: config.ink
            face: root.face; size: 15 * root.u
        }
    }
}
