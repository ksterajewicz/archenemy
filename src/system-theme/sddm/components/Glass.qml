// archenemy — tafla matowego szkła: rozmyty wycinek tła pod spodem, barwa
// i cienka krawędź. Element musi leżeć w tym samym układzie współrzędnych
// co `source` (zwykle oba są dziećmi korzenia motywu) — wycinek tła bierze
// się z jego x, y, szerokości i wysokości.
import QtQuick
import QtQuick.Effects

Item {
    id: glass
    property Item source
    property real radius: 14
    property color tint: Qt.rgba(1, 1, 1, 0.4)
    property color edge: Qt.rgba(1, 1, 1, 0.2)
    property real edgeWidth: 1

    ShaderEffectSource {
        id: behind
        anchors.fill: parent
        sourceItem: glass.source
        sourceRect: Qt.rect(glass.x, glass.y, glass.width, glass.height)
        visible: false
    }
    Rectangle {
        id: shape
        anchors.fill: parent
        radius: glass.radius
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
        maskSource: shape
    }
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: glass.tint
        border.width: glass.edgeWidth
        border.color: glass.edge
    }
}
