// archenemy — ekran logowania SDDM, rice tron, wariant C „dysk”.
// Świecący pierścień ze środkiem w punkcie zbiegu siatki (na horyzoncie):
// w środku godzina i kropki hasła, pod pierścieniem użytkownik. Łuk na
// pierścieniu rośnie z każdym wpisanym znakiem.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "components"

Item {
    id: root
    readonly property real u: height / 1080
    readonly property string face: config.font
    readonly property real horizon: (height - bg.paintedHeight) / 2 + 0.4217 * bg.paintedHeight
    readonly property real ringR: 236 * u
    readonly property color lineColor: greeter.failed ? config.alarm : config.cyan

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

        Item {
            id: disc
            x: root.width / 2 - width / 2
            y: root.horizon - height / 2
            width: 2 * root.ringR + 40 * root.u
            height: width
            transform: Translate { id: discShift }

            // Tło dysku: przyciemnia siatkę i poświatę horyzontu pod tekstem.
            Rectangle {
                anchors.centerIn: parent
                width: 2 * root.ringR
                height: width
                radius: width / 2
                color: Qt.rgba(2 / 255, 10 / 255, 15 / 255, 0.78)
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.lineColor
                    shadowBlur: 1.0
                    shadowOpacity: 0.8
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    blurMax: 32
                }
                // Pierścień zewnętrzny.
                ShapePath {
                    strokeColor: root.lineColor
                    strokeWidth: Math.max(1.5, 3 * root.u)
                    fillColor: "transparent"
                    PathAngleArc { centerX: disc.width / 2; centerY: disc.height / 2; radiusX: root.ringR; radiusY: root.ringR; startAngle: 0; sweepAngle: 360 }
                }
                // Cienki pierścień wewnętrzny.
                ShapePath {
                    strokeColor: Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.45)
                    strokeWidth: 1
                    fillColor: "transparent"
                    PathAngleArc { centerX: disc.width / 2; centerY: disc.height / 2; radiusX: root.ringR - 18 * root.u; radiusY: root.ringR - 18 * root.u; startAngle: 0; sweepAngle: 360 }
                }
                // Łuk postępu: 12° na znak hasła, od godziny dwunastej.
                ShapePath {
                    strokeColor: config.bright
                    strokeWidth: Math.max(3, 7 * root.u)
                    capStyle: ShapePath.FlatCap
                    fillColor: "transparent"
                    PathAngleArc { centerX: disc.width / 2; centerY: disc.height / 2; radiusX: root.ringR - 9 * root.u; radiusY: root.ringR - 9 * root.u; startAngle: -90; sweepAngle: Math.min(360, secret.text.length * 12) }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 - 132 * root.u
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
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
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: now.date
                    color: config.text
                    opacity: 0.85
                    font.family: root.face
                    font.pixelSize: 16 * root.u
                }
                Item { width: 1; height: 34 * root.u }
                Secret {
                    id: secret
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 300 * root.u
                    height: 36 * root.u
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    dotColor: config.text
                    dotSize: 13 * root.u
                    hintColor: config.dim
                    fontFamily: root.face
                    onAccepted: greeter.login(text)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: greeter.failed ? "access denied" : (greeter.capsLock ? "caps lock is on" : " ")
                    color: config.alarm
                    font.family: root.face
                    font.pixelSize: 13 * root.u
                }
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: discShift; property: "x"; to: 10 * root.u; duration: 50 }
                NumberAnimation { target: discShift; property: "x"; to: -10 * root.u; duration: 90 }
                NumberAnimation { target: discShift; property: "x"; to: 0; duration: 60 }
            }
        }

        Choice {
            x: (root.width - width) / 2
            y: disc.y + disc.height + 18 * root.u
            text: greeter.userName
            idleColor: config.ink
            hoverColor: config.bright
            enabledChoice: greeter.userCount > 1
            opacity: 1
            font.family: root.face
            font.pixelSize: 18 * root.u
            onChosen: greeter.nextUser()
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
