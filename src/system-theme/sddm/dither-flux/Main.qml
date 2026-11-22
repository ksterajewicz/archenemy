// archenemy — ekran logowania SDDM, rice dither-flux: „karta rastrowa”.
// Jedna kwadratowa karta z cienką krawędzią na środku ekranu, a w jej
// nagłówku raster Bayera — materiał tego rice'a. W karcie godzina, data,
// użytkownik i hasło w prostokątnym polu; logo i sesja w lewym dolnym rogu,
// zasilanie w prawym. Tło: tapeta ostatnio ustawiona przez Super+W
// (theme.conf.user: background). Rice nie ma stałej tapety w repo (jego
// tapety powstają na maszynie), więc bez niej tłem jest raster rysowany tutaj.
import QtQuick
import "components"

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font
    readonly property real line: Math.max(1, Math.round(u))

    Backdrop {
        id: backdrop
        anchors.fill: parent
        base: config.base
        custom: config.background
        builtin: false
    }
    Dither {
        visible: !backdrop.showingImage
        anchors.fill: parent
        from: config.base
        to: config.shade
        cell: Math.max(4, Math.round(6 * root.u))
        vertical: true
        low: 0.05
        high: 0.8
    }

    Greeter { id: greeter; onRejected: { secret.text = ""; shake.restart() } }
    Now { id: now }
    Seat { id: seat; wanted: config.loginScreen; focusTarget: secret }

    Item {
        visible: seat.here
        anchors.fill: parent

        Rectangle {
            id: card
            x: (root.width - width) / 2
            y: (root.height - height) / 2 - 20 * root.u
            width: 540 * root.u
            height: content.height
            color: Qt.rgba(15 / 255, 26 / 255, 36 / 255, 0.93)
            border.width: root.line
            border.color: config.ink
            transform: Translate { id: cardShift }

            Column {
                id: content
                width: parent.width
                spacing: 0

                // Nagłówek: raster gęstniejący w prawo, data po lewej.
                Item {
                    width: parent.width
                    height: 58 * root.u
                    // Raster zaczyna się za datą, żeby nie wchodził pod tekst.
                    Dither {
                        x: parent.width * 0.46; y: root.line
                        width: parent.width - x - root.line
                        height: parent.height - root.line
                        from: config.base
                        to: config.ink
                        cell: Math.max(3, Math.round(4 * root.u))
                        low: 0
                        high: 0.95
                    }
                    Text {
                        x: 28 * root.u
                        anchors.verticalCenter: parent.verticalCenter
                        text: now.date
                        color: config.paper
                        font.family: root.face
                        font.pixelSize: 16 * root.u
                    }
                    Rectangle { y: parent.height - root.line; width: parent.width; height: root.line; color: config.ink }
                }

                Item { width: 1; height: 26 * root.u }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: now.time
                    color: config.paper
                    font.family: root.face
                    font.weight: Font.Light
                    font.pixelSize: 124 * root.u
                }
                Item { width: 1; height: 22 * root.u }

                Choice {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: greeter.userLabel
                    idleColor: config.ink
                    hoverColor: config.paper
                    enabledChoice: greeter.canSwitchUser
                    opacity: 1
                    font.family: root.face
                    font.pixelSize: 17 * root.u
                    onChosen: greeter.nextUser()
                }
                Item { width: 1; height: 16 * root.u }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 96 * root.u
                    height: 50 * root.u
                    color: Qt.rgba(15 / 255, 26 / 255, 36 / 255, 0.6)
                    border.width: root.line
                    border.color: greeter.failed ? config.alarm : (secret.text.length > 0 ? config.paper : config.ink)
                    Secret {
                        id: secret
                        anchors.fill: parent
                        anchors.leftMargin: 16 * root.u
                        anchors.rightMargin: 16 * root.u
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        dotColor: config.paper
                        dotSize: 13 * root.u
                        hintColor: config.shade
                        fontFamily: root.face
                        hint: greeter.needsName ? "user name" : "password"
                        plain: greeter.needsName
                        onAccepted: greeter.submit(text)
                        onSwitchUser: greeter.nextUser()
                        onSwitchSession: greeter.nextSession()
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 44 * root.u
                    verticalAlignment: Text.AlignVCenter
                    text: greeter.failed ? "wrong password" : (greeter.capsLock ? "caps lock is on" : " ")
                    color: config.alarm
                    font.family: root.face
                    font.pixelSize: 14 * root.u
                }
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: cardShift; property: "x"; to: 10 * root.u; duration: 50 }
                NumberAnimation { target: cardShift; property: "x"; to: -10 * root.u; duration: 90 }
                NumberAnimation { target: cardShift; property: "x"; to: 0; duration: 60 }
            }
        }

        // Dolne rogi stoją na własnych podkładkach: tapeta bywa jasnym rastrem.
        Rectangle {
            x: corner.x - 18 * root.u; y: corner.y - 12 * root.u
            width: corner.width + 36 * root.u; height: corner.height + 24 * root.u
            color: Qt.rgba(15 / 255, 26 / 255, 36 / 255, 0.93)
            border.width: root.line; border.color: config.shade
        }
        Row {
            id: corner
            x: 60 * root.u
            y: root.height - height - 56 * root.u
            spacing: 16 * root.u
            Mark {
                anchors.verticalCenter: parent.verticalCenter
                mode: config.logo; glyph: config.distroGlyph
                color: config.paper
                size: 26 * root.u
            }
            Choice {
                anchors.verticalCenter: parent.verticalCenter
                text: greeter.sessionName
                idleColor: config.ink
                hoverColor: config.paper
                enabledChoice: greeter.sessionCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 15 * root.u
                onChosen: greeter.nextSession()
            }
        }
        Rectangle {
            x: power.x - 18 * root.u; y: power.y - 12 * root.u
            width: power.width + 36 * root.u; height: power.height + 24 * root.u
            color: Qt.rgba(15 / 255, 26 / 255, 36 / 255, 0.93)
            border.width: root.line; border.color: config.shade
        }
        PowerRow {
            id: power
            x: root.width - width - 60 * root.u
            y: root.height - height - 60 * root.u
            idleColor: config.ink; hoverColor: config.paper
            face: root.face; size: 15 * root.u
        }
    }
}
