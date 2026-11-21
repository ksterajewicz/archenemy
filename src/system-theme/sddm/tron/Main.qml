// archenemy — ekran logowania SDDM, rice tron: „pulpit sterowniczy”.
// Cztery narożniki-celowniki obejmują ekran jak wyświetlacz HUD; logowanie
// to trzy wiersze „nazwa  wartość” w lewym dolnym rogu (sesja, użytkownik,
// hasło) z logo systemu obok, godzina w prawym górnym. Środek ekranu
// zostaje dla tapety — tłem jest tapeta ostatnio ustawiona przez Super+W
// (theme.conf.user: background), a bez niej siatka rice'a.
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
    readonly property real logoSize: 46 * u

    Backdrop {
        id: backdrop
        anchors.fill: parent
        base: config.base
        custom: config.background
        dim: Number(config.backgroundDim)
    }

    Greeter { id: greeter; onRejected: { secret.text = ""; shake.restart() } }
    Now { id: now }
    Seat { id: seat; wanted: config.loginScreen; focusTarget: secret }

    Item {
        id: hud
        visible: seat.here
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

        // Na tapecie użytkownika (może być jasna) tekst stoi na ciemnych
        // podkładkach w kolorze tła rice'a; na siatce trona ich nie ma.
        Repeater {
            model: [ rows, clock, power ]
            Rectangle {
                required property var modelData
                readonly property real pad: 22 * root.u
                visible: backdrop.usingCustom
                // Podkładka wierszy obejmuje też logo po ich lewej stronie.
                readonly property real extra: modelData === rows ? root.logoSize + 44 * root.u : 0
                x: modelData.x - extra - pad
                y: modelData.y - pad
                width: modelData.width + extra + 2 * pad
                height: modelData.height + 2 * pad
                color: config.base
                opacity: 0.9
            }
        }

        // Logo systemu: lewy dolny róg, na wysokości wierszy logowania.
        Mark {
            x: root.inset + 44 * root.u
            y: rows.y + rows.height - 26 * root.u - 3 * root.rowHeight / 2 - height / 2
            mode: config.logo; glyph: config.distroGlyph
            color: config.cyan
            size: root.logoSize
        }

        Column {
            id: clock
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
            x: root.inset + 44 * root.u + root.logoSize + 44 * root.u
            width: 520 * root.u
            y: root.height - height - root.inset - 44 * root.u
            spacing: 0
            transform: Translate { id: rowsShift }

            // Linia nad wierszami sięga od logo do końca wierszy.
            Rectangle { x: -(root.logoSize + 44 * root.u); width: rows.width - x; height: root.stroke; color: config.cyan; opacity: 0.55 }
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
            id: power
            x: root.width - width - root.inset - 44 * root.u
            y: root.height - height - root.inset - 44 * root.u
            spacing: 36 * root.u
            Choice { text: "suspend"; visible: sddm.canSuspend || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.suspend() }
            Choice { text: "restart"; visible: sddm.canReboot || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.reboot() }
            Choice { text: "shut down"; visible: sddm.canPowerOff || config.preview === "1"; idleColor: config.ink; hoverColor: config.bright; font.family: root.face; font.pixelSize: 15 * root.u; onChosen: sddm.powerOff() }
        }
    }
}
