// archenemy — pole hasła bez własnej ramki: same kropki i kursor.
// Ramkę, linię albo tło rysuje układ danego rice'a wokół tego elementu.
// `plain` = pole przyjmuje jawny tekst (nazwa użytkownika, gdy SDDM nie ma
// kogo pokazać na liście); przy zmianie trybu pole się czyści. F2 i F3
// zgłaszają zmianę użytkownika i sesji — da się to zrobić bez myszy.
import QtQuick

TextInput {
    id: secret
    property color dotColor: "white"
    property real dotSize: 14
    property string hint: "password"
    property color hintColor: "#808080"
    property string fontFamily: "monospace"
    property bool plain: false
    signal switchUser()
    signal switchSession()
    // Kursor jak w terminalu: migający prostokąt zamiast kreski.
    property bool blockCursor: false

    echoMode: plain ? TextInput.Normal : TextInput.Password
    onPlainChanged: text = ""
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_F2) {
            secret.switchUser()
            event.accepted = true
        } else if (event.key === Qt.Key_F3) {
            secret.switchSession()
            event.accepted = true
        }
    }
    passwordCharacter: "●"
    color: dotColor
    font.family: fontFamily
    font.pixelSize: plain ? dotSize * 1.25 : dotSize
    font.letterSpacing: plain ? 0 : dotSize * 0.45
    selectByMouse: false
    clip: true
    focus: true
    // Kursor w środku napisu podpowiedzi wygląda jak błąd: przy pustym polu
    // z podpowiedzią fokus pokazuje sama podpowiedź.
    cursorVisible: activeFocus && (text.length > 0 || hint === "")
    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
    cursorDelegate: Rectangle {
        visible: secret.cursorVisible
        width: secret.blockCursor ? secret.dotSize * 0.72 : Math.max(1, Math.round(secret.dotSize / 12))
        height: secret.dotSize * 1.5
        color: secret.dotColor
        SequentialAnimation on opacity {
            running: secret.cursorVisible
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 0 }
            PauseAnimation { duration: 600 }
            NumberAnimation { to: 0; duration: 0 }
            PauseAnimation { duration: 500 }
        }
    }

    Text {
        visible: secret.text.length === 0
        anchors.verticalCenter: parent.verticalCenter
        x: secret.horizontalAlignment === TextInput.AlignHCenter ? (parent.width - width) / 2 : 0
        text: secret.hint
        color: secret.hintColor
        font.family: secret.fontFamily
        font.pixelSize: secret.dotSize * 1.15
        font.italic: true
    }
}
