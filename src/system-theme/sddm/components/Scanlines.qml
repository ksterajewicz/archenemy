// archenemy — linie skanowania kineskopu: poziome kreski co `pitch`
// pikseli, znak rozpoznawczy rice'a crt. Rysowane raz na płótnie.
import QtQuick

Canvas {
    id: lines
    property color color: Qt.rgba(0, 0, 0, 0.25)
    property real pitch: 3

    onHeightChanged: requestPaint()
    onWidthChanged: requestPaint()
    onColorChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = color
        var step = Math.max(2, Math.round(pitch))
        for (var y = 0; y < height; y += step)
            ctx.fillRect(0, y, width, 1)
    }
}
