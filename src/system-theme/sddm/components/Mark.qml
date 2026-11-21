// archenemy — logo systemu na ekranie logowania.
// mode "archenemy": znak Æ rysowany jako ścieżka (ta sama geometria co
// assets/logo/archenemy-ae.svg, viewBox 256) — bez pliku graficznego, więc
// bez qt6-svg i w dowolnym kolorze. Każda inna wartość: glif dystrybucji
// z fontu Nerd Font, podany w theme.conf.user przez instalator (ten sam
// wybór co logo paska: Super+A → system logo).
import QtQuick
import QtQuick.Shapes

Item {
    id: mark
    property string mode: "distro"
    property string glyph: ""
    property color color: "white"
    property real size: 32
    property string glyphFont: "Symbols Nerd Font Mono"

    width: size
    height: size

    Shape {
        visible: mark.mode === "archenemy"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: mark.color
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            scale: Qt.size(mark.size / 256, mark.size / 256)
            PathSvg { path: "M16 232 L112 24 H240 V60 H152 V112 H224 V148 H152 V196 H240 V232 H112 V184 H70 L48 232 Z M80 148 H112 V76 Z" }
        }
    }

    Text {
        visible: mark.mode !== "archenemy"
        anchors.centerIn: parent
        text: mark.glyph
        color: mark.color
        font.family: mark.glyphFont
        font.pixelSize: mark.size
    }
}
