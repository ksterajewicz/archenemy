// archenemy — ekran logowania SDDM, rice tron, wariant B „pulpit sterowniczy”.
// Cztery narożniki-celowniki obejmują ekran jak wyświetlacz HUD; logowanie
// to trzy wiersze „nazwa  wartość” w lewym dolnym rogu (sesja, użytkownik,
// hasło), godzina w prawym górnym. Środek ekranu zostaje dla siatki.
import QtQuick
import QtQuick.Effects
import "components"

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font
    readonly property real inset: 44 * u
    readonly property real arm: 56 * u
    readonly property real stroke: Math.max(1, Math.round(2 * u))
    readonly property real rowHeight: 40 * u
    readonly property real keyWidth: 132 * u

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
        id: hud
        visible: primaryScreen
        anchors.fill: parent

        // Narożniki: po dwa odcinki na róg, wspólna poświata całej warstwy.
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: config.cyan
                shadowBlur: 0.8
                shadowOpacity: 0.7
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 24
            }
            Repeater {
                model: [ { h: 0, v: 0 }, { h: 1, v: 0 }, { h: 0, v: 1 }, { h: 1, v: 1 } ]
                Item {
                    required property var modelData
                    x: modelData.h ? root.width - root.inset - root.arm : root.inset
                    y: modelData.v ? root.height - root.inset - root.arm : root.inset
                    width: root.arm
                    height: root.arm
                    Rectangle { color: config.cyan; opacity: 0.8; width: root.arm; height: root.stroke; y: modelData.v ? root.arm - root.stroke : 0 }
                    Rectangle { color: config.cyan; opacity: 0.8; width: root.stroke; height: root.arm; x: modelData.h ? root.arm - root.stroke : 0 }
                }
            }
        }

        Mark {
            x: root.inset + 44 * root.u
            y: root.inset + 44 * root.u
            mode: config.logo; glyph: config.distroGlyph
            color: config.cyan
            size: 34 * root.u
        }

        Column {
            x: root.width - width - root.inset - 44 * root.u
            y: root.inset + 26 * root.u
            spacing: 0
            Text {
                anchors.right: parent.right
                text: now.time
                color: config.cyan
                font.family: root.face
                font.weight: Font.Light
                font.pixelSize: 104 * root.u
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: config.cyan
                    shadowBlur: 1.0
                    shadowOpacity: 0.7
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 32
                    autoPaddingEnabled: true
                }
            }
            Text {
                anchors.right: parent.right
                text: now.date
                color: config.text
                opacity: 0.85
                font.family: root.face
                font.pixelSize: 17 * root.u
            }
        }

        // Trzy wiersze logowania nad lewym dolnym narożnikiem.
        Column {
            id: rows
            x: root.inset + 44 * root.u
            y: root.height - height - root.inset - 44 * root.u
            spacing: 0
            transform: Translate { id: rowsShift }

            Rectangle { width: 520 * root.u; height: root.stroke; color: config.cyan; opacity: 0.55 }
            Item { width: 1; height: 18 * root.u }

            Item {
                width: 520 * root.u; height: root.rowHeight
                Text { anchors.verticalCenter: parent.verticalCenter; text: "session"; color: config.dim; font.family: root.face; font.pixelSize: 17 * root.u }
                Choice {
                    x: root.keyWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: greeter.sessionName
                    idleColor: config.ink
                    hoverColor: config.bright
                    enabledChoice: greeter.sessionCount > 1
                    opacity: 1
                    font.family: root.face
                    font.pixelSize: 17 * root.u
                    onChosen: greeter.nextSession()
                }
            }
            Item {
                width: 520 * root.u; height: root.rowHeight
                Text { anchors.verticalCenter: parent.verticalCenter; text: "user"; color: config.dim; font.family: root.face; font.pixelSize: 17 * root.u }
                Choice {
                    x: root.keyWidth
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
            }
            Item {
                width: 520 * root.u; height: root.rowHeight
                Rectangle { x: -16 * root.u; y: 8 * root.u; width: root.stroke; height: parent.height - 16 * root.u; color: greeter.failed ? config.alarm : config.cyan }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "password"; color: greeter.failed ? config.alarm : config.cyan; font.family: root.face; font.pixelSize: 17 * root.u }
                Secret {
                    id: secret
                    x: root.keyWidth
                    width: parent.width - x
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    dotColor: config.text
                    dotSize: 13 * root.u
                    hint: ""
                    hintColor: config.dim
                    fontFamily: root.face
                    onAccepted: greeter.login(text)
                }
            }
            Text {
                x: root.keyWidth
                height: 26 * root.u
                verticalAlignment: Text.AlignBottom
                text: greeter.failed ? "access denied" : (greeter.capsLock ? "caps lock is on" : " ")
                color: config.alarm
                font.family: root.face
                font.pixelSize: 14 * root.u
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: rowsShift; property: "x"; to: 10 * root.u; duration: 50 }
                NumberAnimation { target: rowsShift; property: "x"; to: -10 * root.u; duration: 90 }
                NumberAnimation { target: rowsShift; property: "x"; to: 0; duration: 60 }
            }
        }

        Row {
            x: root.width - width - root.inset - 44 * root.u
            y: root.height - height - root.inset - 44 * root.u
            spacing: 36 * root.u
            Choice { text: "suspend"; visible: sddm.canSuspend || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.suspend() }
            Choice { text: "restart"; visible: sddm.canReboot || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.reboot() }
            Choice { text: "shut down"; visible: sddm.canPowerOff || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.powerOff() }
        }
    }
}
