// archenemy — tło ekranu logowania.
//
// Domyślnie tapeta rice'a z katalogu motywu: background-169.png dla ekranów
// 16:9 i szerszych, background-1610.png dla wyższych (`builtin: false` =
// rice nie ma stałej tapety i rysuje tło zastępcze sam, pod spodem albo
// nad tym elementem — patrz `showingImage`). Gdy `custom` jest
// niepuste (theme.conf.user, klucz background — kopia tapety ostatnio
// ustawionej przez Super+W, wgrana do katalogu motywu), tłem jest ten plik.
// Plik, którego Qt nie umie wczytać (uszkodzony, format bez wtyczki), nie
// zostawia pustego ekranu: tło wraca do tapety rice'a. `dim` przyciemnia
// wyłącznie cudzą tapetę kolorem `base`, żeby tekst rice'a został czytelny.
import QtQuick

Item {
    id: backdrop
    property color base: "black"
    property string custom: ""
    property real dim: 0
    property bool builtin: true

    readonly property bool usingCustom: custom !== "" && !customFailed
    // Czy na ekranie jest jakikolwiek obraz (tapeta użytkownika albo rice'a).
    readonly property bool showingImage: usingCustom || builtin
    readonly property real paintedWidth: image.paintedWidth
    readonly property real paintedHeight: image.paintedHeight
    property bool customFailed: false

    onCustomChanged: customFailed = false

    Rectangle { anchors.fill: parent; color: backdrop.base }

    Image {
        id: image
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        // Duża tapeta nie zajmuje pamięci ponad rozmiar ekranu.
        sourceSize.width: Math.max(1, backdrop.width)
        sourceSize.height: Math.max(1, backdrop.height)
        visible: backdrop.showingImage
        source: backdrop.usingCustom
            ? Qt.resolvedUrl("../" + backdrop.custom)
            : (backdrop.builtin
               ? Qt.resolvedUrl(backdrop.width / Math.max(1, backdrop.height) > 1.69
                                ? "../background-169.png" : "../background-1610.png")
               : "")
        onStatusChanged: {
            if (status === Image.Error && backdrop.usingCustom)
                backdrop.customFailed = true
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: backdrop.usingCustom && backdrop.dim > 0
        color: backdrop.base
        opacity: Math.min(1, Math.max(0, backdrop.dim))
    }
}
