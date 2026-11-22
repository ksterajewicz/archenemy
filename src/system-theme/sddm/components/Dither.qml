// archenemy — raster uporządkowany (macierz Bayera 4×4): przejście od
// koloru `from` do `to` z kwadratowych komórek, znak rozpoznawczy rice'a
// dither-flux. Rysowane raz na płótnie; `vertical` = przejście z góry na
// dół, inaczej z lewej do prawej. `cell` to bok komórki w pikselach.
import QtQuick

Canvas {
    id: dither
    property color from: "black"
    property color to: "white"
    property real cell: 6
    property bool vertical: false
    // Zakres progu: 0–1 = pełne przejście; węższy = rzadszy raster.
    property real low: 0
    property real high: 1

    onFromChanged: requestPaint()
    onToChanged: requestPaint()
    onCellChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        var size = Math.max(2, Math.round(cell))
        var cols = Math.ceil(width / size)
        var rows = Math.ceil(height / size)
        var bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
        ctx.fillStyle = from
        ctx.fillRect(0, 0, width, height)
        ctx.fillStyle = to
        for (var row = 0; row < rows; row++) {
            var start = -1
            for (var col = 0; col <= cols; col++) {
                var on = false
                if (col < cols) {
                    var along = vertical ? row / Math.max(1, rows - 1) : col / Math.max(1, cols - 1)
                    var level = low + (high - low) * along
                    on = level > (bayer[(row % 4) * 4 + (col % 4)] + 0.5) / 16
                }
                // Sąsiednie włączone komórki idą jednym prostokątem.
                if (on && start < 0) {
                    start = col
                } else if (!on && start >= 0) {
                    ctx.fillRect(start * size, row * size, (col - start) * size, size)
                    start = -1
                }
            }
        }
    }
}
