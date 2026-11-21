// archenemy — bieżąca godzina i data dla ekranu logowania (odświeżane co sekundę).
import QtQuick

Item {
    id: now
    visible: false
    property date value: new Date()
    readonly property string time: Qt.formatTime(value, "HH:mm")
    readonly property string date: Qt.formatDate(value, "dddd, d MMMM")
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: now.value = new Date()
    }
}
