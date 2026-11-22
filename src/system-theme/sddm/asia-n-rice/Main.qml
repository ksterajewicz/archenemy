// archenemy — ekran logowania SDDM, rice asia-n-rice: „zwój”.
// Wysoka, wąska tafla po lewej jak wiszący zwój: godzina ułożona pionowo
// (godziny nad minutami), data, użytkownik, hasło w zaokrąglonym polu,
// zasilanie na dole tafli. Różowa linia biegnie wzdłuż jej krawędzi. Logo
// i sesja w lewym dolnym rogu. Tło: tapeta ostatnio ustawiona przez Super+W
// (theme.conf.user: background). Rice nie ma stałej tapety w repo, więc bez
// niej tłem jest rysowane tutaj pasiaste słońce rice'a na łupkowym niebie.
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
        builtin: false
    }

    // Tło zastępcze: niebo, słońce z poziomymi przerwami, linia wzgórz.
    Item {
        id: sky
        visible: !backdrop.showingImage
        anchors.fill: parent
        // Niebo w jednym kolorze: przerwy w słońcu mają ten sam kolor, więc
        // poza tarczą ich nie widać.
        Rectangle { anchors.fill: parent; color: config.base }
        Item {
            id: sun
            readonly property real d: root.height * 0.56
            x: root.width * 0.68 - d / 2
            y: root.height * 0.47 - d / 2
            width: d
            height: d
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: config.blush }
                    GradientStop { position: 1.0; color: config.rose }
                }
            }
            // Przerwy rosną ku dołowi tarczy.
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    x: -2
                    width: sun.width + 4
                    height: sun.d * (0.014 + 0.007 * index)
                    y: sun.d * (0.585 + 0.082 * index)
                    color: config.base
                }
            }
        }
        Rectangle {
            y: root.height * 0.80
            width: root.width
            height: root.height * 0.20
            color: config.night
        }
    }

    Greeter { id: greeter; onRejected: { secret.text = ""; shake.restart() } }
    Now { id: now }
    Seat { id: seat; wanted: config.loginScreen; focusTarget: secret }

    Item {
        visible: seat.here
        anchors.fill: parent

        Glass {
            id: scroll
            source: backdrop.showingImage ? backdrop : sky
            x: 150 * root.u
            y: 84 * root.u
            width: 330 * root.u
            height: root.height - 2 * y - 70 * root.u
            radius: 14 * root.u
            tint: Qt.rgba(42 / 255, 52 / 255, 68 / 255, 0.78)
            edge: Qt.rgba(180 / 255, 118 / 255, 135 / 255, 0.55)
            edgeWidth: Math.max(1, Math.round(2 * root.u))
            transform: Translate { id: scrollShift }
        }
        Item {
            x: scroll.x
            y: scroll.y
            width: scroll.width
            height: scroll.height
            transform: Translate { x: scrollShift.x }

            Column {
                y: 52 * root.u
                width: parent.width
                spacing: 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: now.time.substring(0, 2)
                    color: config.blush
                    font.family: root.face
                    font.weight: Font.Light
                    font.pixelSize: 150 * root.u
                    height: 150 * root.u
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: now.time.substring(3, 5)
                    color: config.rose
                    font.family: root.face
                    font.weight: Font.Light
                    font.pixelSize: 150 * root.u
                    height: 150 * root.u
                    verticalAlignment: Text.AlignVCenter
                }
                Item { width: 1; height: 20 * root.u }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: now.date
                    color: config.text
                    opacity: 0.8
                    font.family: root.face
                    font.pixelSize: 16 * root.u
                }
                Item { width: 1; height: 40 * root.u }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 44 * root.u; height: Math.max(1, Math.round(2 * root.u)); color: config.rose }
                Item { width: 1; height: 40 * root.u }

                Choice {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: greeter.userLabel
                    idleColor: config.text
                    hoverColor: config.blush
                    enabledChoice: greeter.userCount > 1
                    opacity: 1
                    font.family: root.face
                    font.pixelSize: 17 * root.u
                    onChosen: greeter.nextUser()
                }
                Item { width: 1; height: 18 * root.u }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 64 * root.u
                    height: 50 * root.u
                    radius: 14 * root.u
                    color: Qt.rgba(30 / 255, 38 / 255, 50 / 255, 0.7)
                    border.width: Math.max(1, Math.round(2 * root.u))
                    border.color: greeter.failed ? config.alarm : Qt.rgba(180 / 255, 118 / 255, 135 / 255, secret.text.length > 0 ? 0.95 : 0.55)
                    Secret {
                        id: secret
                        anchors.fill: parent
                        anchors.leftMargin: 16 * root.u
                        anchors.rightMargin: 16 * root.u
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        dotColor: config.text
                        dotSize: 13 * root.u
                        hintColor: config.muted
                        fontFamily: root.face
                        onAccepted: greeter.login(text)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 40 * root.u
                    verticalAlignment: Text.AlignVCenter
                    text: greeter.failed ? "wrong password" : (greeter.capsLock ? "caps lock is on" : " ")
                    color: config.alarm
                    font.family: root.face
                    font.pixelSize: 14 * root.u
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - height - 36 * root.u
                spacing: 12 * root.u
                Repeater {
                    model: [
                        { label: "suspend",   can: sddm.canSuspend },
                        { label: "restart",   can: sddm.canReboot },
                        { label: "shut down", can: sddm.canPowerOff }
                    ]
                    Choice {
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: modelData.can || config.preview === "1"
                        text: modelData.label
                        idleColor: config.muted
                        hoverColor: config.blush
                        font.family: root.face
                        font.pixelSize: 15 * root.u
                        onChosen: {
                            if (modelData.label === "suspend") sddm.suspend()
                            else if (modelData.label === "restart") sddm.reboot()
                            else sddm.powerOff()
                        }
                    }
                }
            }
        }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: scrollShift; property: "x"; to: 10 * root.u; duration: 50 }
            NumberAnimation { target: scrollShift; property: "x"; to: -10 * root.u; duration: 90 }
            NumberAnimation { target: scrollShift; property: "x"; to: 0; duration: 60 }
        }

        // Logo i sesja: lewy dolny róg, pod zwojem.
        Row {
            x: 56 * root.u
            y: root.height - height - 44 * root.u
            spacing: 16 * root.u
            Mark {
                anchors.verticalCenter: parent.verticalCenter
                mode: config.logo; glyph: config.distroGlyph
                color: config.rose
                size: 28 * root.u
            }
            Choice {
                anchors.verticalCenter: parent.verticalCenter
                text: greeter.sessionName
                idleColor: config.text
                hoverColor: config.blush
                enabledChoice: greeter.sessionCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 15 * root.u
                onChosen: greeter.nextSession()
            }
        }
    }
}
