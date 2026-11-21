// archenemy — pole hasła bez własnej ramki: same kropki i kursor.
// Ramkę, linię albo tło rysuje układ danego rice'a wokół tego elementu.
import QtQuick

TextInput {
    id: secret
    property color dotColor: "white"
    property real dotSize: 14
    property string hint: "password"
    property color hintColor: "#808080"
    property string fontFamily: "monospace"

    echoMode: TextInput.Password
    passwordCharacter: "●"
    color: dotColor
    font.family: fontFamily
    font.pixelSize: dotSize
    font.letterSpacing: dotSize * 0.45
    selectByMouse: false
    clip: true
    focus: true
    // Kursor w środku napisu podpowiedzi wygląda jak błąd: przy pustym polu
    // z podpowiedzią fokus pokazuje sama podpowiedź.
    cursorVisible: activeFocus && (text.length > 0 || hint === "")
    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

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
