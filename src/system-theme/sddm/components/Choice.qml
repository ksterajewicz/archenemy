// archenemy — klikalna pozycja tekstowa (sesja, użytkownik, zasilanie).
import QtQuick

Text {
    id: choice
    property color idleColor: "#808080"
    property color hoverColor: "white"
    property bool enabledChoice: true
    signal chosen()

    color: area.containsMouse && enabledChoice ? hoverColor : idleColor
    opacity: enabledChoice ? 1.0 : 0.4
    Behavior on color { ColorAnimation { duration: 150 } }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: choice.enabledChoice ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (choice.enabledChoice) choice.chosen()
    }
}
