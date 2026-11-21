// archenemy — ekran logowania SDDM, rice yin, wariant C „tafla”.
// Znak rozpoznawczy yin: tafla matowego szkła (grafit z alfą, biała linia
// 1 px, rozmyta tapeta pod spodem) — tu jako wysoka, wąska płyta po lewej,
// naprzeciw tarczy zaćmienia. Pole hasła w ramce jak pole rofi tego rice'a.
import QtQuick
import QtQuick.Effects
import "components"

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font

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
        id: slab
        visible: primaryScreen
        x: root.width * 0.33 - width / 2
        y: (root.height - height) / 2
        width: 440 * root.u
        height: 620 * root.u

        ShaderEffectSource {
            id: behind
            anchors.fill: parent
            sourceItem: bg
            sourceRect: Qt.rect(slab.x, slab.y, slab.width, slab.height)
            visible: false
        }
        Rectangle {
            id: slabShape
            anchors.fill: parent
            radius: 24 * root.u
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: behind
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            maskEnabled: true
            maskSource: slabShape
        }
        Rectangle {
            anchors.fill: parent
            radius: 24 * root.u
            color: Qt.rgba(18 / 255, 18 / 255, 21 / 255, 0.55)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
        }

        Mark {
            x: (parent.width - width) / 2
            y: 52 * root.u
            mode: config.logo; glyph: config.distroGlyph
            color: config.white
            size: 38 * root.u
        }

        Column {
            y: 132 * root.u
            width: parent.width
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: now.time
                color: config.white
                font.family: root.face
                font.weight: Font.Light
                font.pixelSize: 92 * root.u
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: now.date
                color: config.mist
                font.family: root.face
                font.pixelSize: 17 * root.u
            }
            Item { width: 1; height: 60 * root.u }
            Choice {
                anchors.horizontalCenter: parent.horizontalCenter
                text: greeter.userLabel
                idleColor: config.paper
                hoverColor: config.white
                enabledChoice: greeter.userCount > 1
                opacity: 1
                font.family: root.face
                font.pixelSize: 16 * root.u
                onChosen: greeter.nextUser()
            }
            Item { width: 1; height: 16 * root.u }
            Rectangle {
                id: field
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300 * root.u
                height: 52 * root.u
                radius: 12 * root.u
                color: Qt.rgba(12 / 255, 12 / 255, 14 / 255, 0.60)
                border.width: 1
                border.color: greeter.failed ? config.ember : Qt.rgba(1, 1, 1, secret.text.length > 0 ? 0.6 : 0.35)
                Secret {
                    id: secret
                    anchors.fill: parent
                    anchors.leftMargin: 18 * root.u
                    anchors.rightMargin: 18 * root.u
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    dotColor: config.white
                    dotSize: 13 * root.u
                    hintColor: config.smoke
                    fontFamily: root.face
                    onAccepted: greeter.login(text)
                }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 10 * root.u; duration: 50 }
                    NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -10 * root.u; duration: 90 }
                    NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 0; duration: 60 }
                }
            }
            Item { width: 1; height: 12 * root.u }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: greeter.failed ? "wrong password" : (greeter.capsLock ? "caps lock is on" : " ")
                color: config.ember
                font.family: root.face
                font.pixelSize: 13 * root.u
            }
        }

        Choice {
            x: (parent.width - width) / 2
            y: parent.height - 122 * root.u
            text: greeter.sessionName
            idleColor: config.ash
            hoverColor: config.white
            enabledChoice: greeter.sessionCount > 1
            opacity: 1
            font.family: root.face
            font.pixelSize: 14 * root.u
            onChosen: greeter.nextSession()
        }
        Rectangle {
            x: 40 * root.u
            y: parent.height - 84 * root.u
            width: parent.width - 80 * root.u
            height: 1
            color: Qt.rgba(1, 1, 1, 0.10)
        }
        Row {
            x: (parent.width - width) / 2
            y: parent.height - 58 * root.u
            spacing: 30 * root.u
            Choice { text: "suspend"; visible: sddm.canSuspend || config.preview === "1"; idleColor: config.ash; hoverColor: config.white; font.family: root.face; font.pixelSize: 14 * root.u; onChosen: sddm.suspend() }
            Choice { text: "restart"; visible: sddm.canReboot || config.preview === "1"; idleColor: config.ash; hoverColor: config.white; font.family: root.face; font.pixelSize: 14 * root.u; onChosen: sddm.reboot() }
            Choice { text: "shut down"; visible: sddm.canPowerOff || config.preview === "1"; idleColor: config.ash; hoverColor: config.white; font.family: root.face; font.pixelSize: 14 * root.u; onChosen: sddm.powerOff() }
        }
    }
}
