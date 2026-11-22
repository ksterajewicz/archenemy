// archenemy — wspólna logika ekranu logowania SDDM (bez wyglądu).
// Motyw każdego rice'a ma własny Main.qml (układ i styl) i jeden obiekt
// Greeter: lista użytkowników i sesji, wybór, logowanie, wynik logowania.
// Obiekty sddm, userModel, sessionModel i keyboard daje greeter SDDM
// (GreeterApp.cpp, SDDM 0.21).
import QtQuick

Item {
    id: greeter
    visible: false

    property int userIndex: 0
    property int sessionIndex: 0
    property bool failed: false
    property bool busy: false

    readonly property int userCount: users.count
    readonly property int sessionCount: sessions.count
    // SDDM pokazuje na liście tylko konta z zakresu UID i z dozwoloną powłoką
    // (UserModel.cpp). Gdy lista jest pusta (konto sieciowe, UID spoza
    // zakresu), nazwę wpisuje się ręcznie — bez tego nie dałoby się zalogować.
    property string typedUser: ""
    readonly property bool listed: users.count > 0
    readonly property bool needsName: !listed && typedUser === ""
    readonly property bool canSwitchUser: listed ? users.count > 1 : typedUser !== ""
    readonly property string userName: listed ? entryText(users, userIndex, "name") : typedUser
    readonly property string userLabel: {
        if (!listed)
            return typedUser
        var real = entryText(users, userIndex, "realName")
        return real !== "" ? real : userName
    }
    readonly property string sessionName: entryText(sessions, sessionIndex, "name")
    readonly property bool capsLock: keyboard.capsLock

    signal rejected()

    function entryText(repeater, index, field) {
        // repeater.count w wyrażeniu = ponowne wyliczenie po wczytaniu modelu.
        if (repeater.count <= 0 || index < 0 || index >= repeater.count)
            return ""
        var item = repeater.itemAt(index)
        return item ? item[field] : ""
    }

    function login(password) {
        if (busy || userName === "")
            return
        failed = false
        busy = true
        sddm.login(userName, password, sessionIndex)
    }

    // Enter w polu: przy pustej liście użytkowników pierwszy Enter przyjmuje
    // nazwę, kolejny loguje hasłem.
    function submit(text) {
        if (needsName) {
            var name = String(text).trim()
            if (name !== "")
                typedUser = name
            return
        }
        login(text)
    }

    function nextUser() {
        if (!listed) {
            // Wpisana nazwa wraca do edycji.
            typedUser = ""
            failed = false
            return
        }
        if (users.count > 1)
            userIndex = (userIndex + 1) % users.count
    }

    function nextSession() {
        if (sessions.count > 1)
            sessionIndex = (sessionIndex + 1) % sessions.count
    }

    Repeater {
        id: users
        model: userModel
        Item {
            property string name: model.name
            property string realName: model.realName
        }
    }

    Repeater {
        id: sessions
        model: sessionModel
        Item { property string name: model.name }
    }

    Component.onCompleted: {
        // Ostatnio używany użytkownik i sesja (SDDM pamięta je w state.conf).
        if (userModel.lastIndex >= 0 && userModel.lastIndex < users.count)
            userIndex = userModel.lastIndex
        if (sessionModel.lastIndex >= 0 && sessionModel.lastIndex < sessions.count)
            sessionIndex = sessionModel.lastIndex
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            greeter.busy = false
            greeter.failed = true
            greeter.rejected()
        }
        function onLoginSucceeded() {
            greeter.busy = false
        }
    }
}
