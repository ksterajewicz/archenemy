// archenemy — na którym monitorze stoi formularz logowania.
//
// SDDM 0.21 tworzy osobne okno (i osobną kopię Main.qml) dla każdego
// monitora (GreeterApp.cpp, addViewForScreen); klawiaturę oddaje tylko oknu
// monitora głównego. Każda kopia motywu ma jeden obiekt Seat i pokazuje
// formularz wtedy, gdy `here` jest prawdą.
//
// `wanted` to nazwa złącza wybranego monitora (theme.conf.user, klucz
// loginScreen; pusta = monitor główny). Nazwy złączy nie są stałe: ten sam
// ekran bywa eDP-1 albo eDP-2, a serwer X nazywa HDMI-A-1 jako HDMI-1.
// Dlatego dopasowanie idzie od najdokładniejszego do najluźniejszego i
// każdy stopień wygrywa tylko przy DOKŁADNIE jednym trafieniu:
//   1. ta sama nazwa,
//   2. ten sam typ złącza i numer (HDMI-A-1 = HDMI-1),
//   3. ten sam typ złącza (eDP-2 = eDP-1),
//   4. ta sama klasa: ekran wbudowany (eDP, LVDS, DSI) albo zewnętrzny,
//   5. monitor główny.
// Wynik jest zawsze nazwą z listy PODŁĄCZONYCH monitorów, więc wybrany,
// ale odpięty monitor kończy na monitorze głównym — nigdy na pustym ekranie.
// Wszystkie okna liczą to samo z tych samych danych: formularz jest na
// dokładnie jednym. Po odpięciu monitora lista się zmienia i wynik liczy
// się od nowa.
//
// Wyjście awaryjne: monitor z formularzem bywa podłączony, ale niewidoczny
// (laptop w stacji dokującej z zamkniętą klapą — serwer X dalej widzi jego
// ekran). Dlatego każdy monitor BEZ formularza pokazuje krótką podpowiedź,
// a kliknięcie na nim przenosi formularz właśnie tam: zapis do
// config.loginScreen (QQmlPropertyMap wspólny dla wszystkich okien
// greetera) przelicza wynik we wszystkich oknach naraz. Zmiana żyje do
// końca tego ekranu logowania; trwały wybór to Super+A → [g].
import QtQuick
import QtQuick.Window

Item {
    id: seat
    anchors.fill: parent

    property string wanted: ""
    property string hintFont: config.font
    // Element, który ma dostać klawiaturę (pole hasła).
    property Item focusTarget: null

    readonly property var screens: Qt.application.screens
    readonly property string own: Screen.name
    readonly property string target: pick(wanted, screens)
    readonly property bool here: decide(target, own, screens)
    readonly property bool windowActive: Window.active

    function names(list) {
        var out = []
        if (!list)
            return out
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].name)
                out.push(String(list[i].name))
        }
        return out
    }

    // Typ złącza: litery z początku nazwy ("HDMI-A-1" → "HDMI", "eDP-1" → "EDP").
    function kind(name) {
        var m = /^[A-Za-z]+/.exec(name)
        return m ? m[0].toUpperCase() : ""
    }

    // Typ + ostatni numer ("HDMI-A-1" i "HDMI-1" → "HDMI-1").
    function shortName(name) {
        var m = /(\d+)\s*$/.exec(name)
        return kind(name) + "-" + (m ? m[1] : "")
    }

    function builtIn(name) {
        var k = kind(name)
        return k === "EDP" || k === "LVDS" || k === "DSI"
    }

    // Jedyny element listy spełniający warunek albo "".
    function only(list, test) {
        var hit = ""
        var count = 0
        for (var i = 0; i < list.length; i++) {
            if (test(list[i])) {
                hit = list[i]
                count++
            }
        }
        return count === 1 ? hit : ""
    }

    function pick(want, list) {
        var all = names(list)
        if (all.length === 0)
            return ""
        var primary = all[0]   // Qt trzyma monitor główny na początku listy
        want = String(want || "").trim()
        if (want === "" || kind(want) === "")
            return primary
        var upper = want.toUpperCase()
        return only(all, function (n) { return n.toUpperCase() === upper })
            || only(all, function (n) { return shortName(n) === shortName(want) })
            || only(all, function (n) { return kind(n) === kind(want) })
            || only(all, function (n) { return builtIn(n) === builtIn(want) })
            || primary
    }

    function decide(chosen, mine, list) {
        var all = names(list)
        // Brak listy albo okna spoza listy: zdanie SDDM o monitorze głównym.
        if (chosen === "" || mine === "" || all.indexOf(mine) < 0)
            return primaryScreen
        return mine === chosen
    }

    // Klawiatura: okno z formularzem prosi o fokus i ponawia, dopóki go nie
    // ma (SDDM aktywuje okno monitora głównego już po wczytaniu motywu).
    function claim() {
        if (!here)
            return
        var w = Window.window
        if (w && !w.active)
            w.requestActivate()
        if (focusTarget)
            focusTarget.forceActiveFocus()
    }

    onHereChanged: claim()
    onWindowActiveChanged: claim()
    Component.onCompleted: claim()

    Timer {
        interval: 300
        repeat: true
        running: seat.here && !seat.windowActive
        onTriggered: seat.claim()
    }

    MouseArea {
        anchors.fill: parent
        enabled: !seat.here && seat.own !== ""
        onClicked: config.loginScreen = seat.own
    }
    Text {
        visible: !seat.here && seat.own !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 44 * parent.height / 1080
        text: "click to log in on this screen"
        color: "#E8E8E8"
        style: Text.Outline
        styleColor: "#161616"
        opacity: 0.8
        font.family: seat.hintFont
        font.pixelSize: Math.max(11, 15 * parent.height / 1080)
    }
}
