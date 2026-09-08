import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string g1id: Plasmoid.configuration.group1Id
    readonly property string g2id: Plasmoid.configuration.group2Id
    readonly property string g1name: Plasmoid.configuration.group1Name
    readonly property string g2name: Plasmoid.configuration.group2Name
    readonly property int refreshMinutes: Plasmoid.configuration.refreshMinutes
    readonly property int daysAhead: Plasmoid.configuration.daysAhead
    readonly property bool showWeekend: Plasmoid.configuration.showWeekend
    readonly property string pythonPath: Plasmoid.configuration.pythonPath
    readonly property string localDir: Plasmoid.configuration.localDir

    property var payload: null
    property string runError: ""
    property bool loading: false
    property double lastUpdatedMs: 0
    property int activeTab: 0
    property int nowTick: 0

    readonly property string scriptPath:
        Qt.resolvedUrl("../scripts/fetch.py").toString().replace(/^file:\/\//, "")

    preferredRepresentation: fullRepresentation

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function refresh() {
        if (root.loading)
            return
        root.loading = true
        root.runError = ""
        var cmd = shq(pythonPath) + " " + shq(scriptPath)
        if (localDir.length > 0)
            cmd += " --localdir " + shq(localDir)
        cmd += " " + shq(g1id) + " " + shq(g2id)
        exec.connectSource(cmd)
    }

    function handleResult(data) {
        root.loading = false
        var out = (data["stdout"] || "").trim()
        var err = (data["stderr"] || "").trim()
        if (!out) {
            root.runError = err || i18n("empty output (exit %1)", data["exit code"])
            return
        }
        try {
            root.payload = JSON.parse(out)
            root.lastUpdatedMs = Date.now()
        } catch (e) {
            root.runError = i18n("bad JSON from parser: %1", String(e))
        }
    }

    // ---- helpers -----------------------------------------------------------
    function groupData(idx) {
        if (!payload || !payload.groups)
            return null
        return payload.groups[idx === 0 ? g1id : g2id] || null
    }

    function visibleDays(g) {
        void nowTick
        if (!g || !g.days)
            return []
        var todayISO = Qt.formatDate(new Date(), "yyyy-MM-dd")
        var out = g.days.filter(function (d) {
            if (d.date && d.date < todayISO)
                return false
            if (!showWeekend) {
                var w = (d.weekday || "").toLowerCase()
                if (w.indexOf("суббот") >= 0 || w.indexOf("воскрес") >= 0)
                    return false
            }
            return true
        })
        return daysAhead > 0 ? out.slice(0, daysAhead) : out
    }

    function dayHeader(day) {
        var s = day.weekday || ""
        if (day.date) {
            var d = new Date(day.date + "T00:00:00")
            s += ", " + Qt.formatDate(d, "d MMMM")
        }
        return s
    }

    function ruWeekdayIndex(name) {
        var w = (name || "").toLowerCase()
        if (w.indexOf("понед") === 0 || w.indexOf("понед") > 0) return 1
        if (w.indexOf("вторн") >= 0) return 2
        if (w.indexOf("сред") >= 0) return 3
        if (w.indexOf("четв") >= 0) return 4
        if (w.indexOf("пятн") >= 0) return 5
        if (w.indexOf("суббо") >= 0) return 6
        if (w.indexOf("воскр") >= 0) return 0
        return -1
    }

    function isToday(day) {
        if (day.date) {
            var d = new Date(day.date + "T00:00:00")
            var n = new Date()
            return d.getFullYear() === n.getFullYear()
                && d.getMonth() === n.getMonth()
                && d.getDate() === n.getDate()
        }
        return ruWeekdayIndex(day.weekday) === new Date().getDay()
    }

    function toMinutes(hhmm) {
        var m = /^(\d{1,2}):(\d{2})/.exec(hhmm || "")
        return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : -1
    }

    function isNow(lesson) {
        var n = new Date()
        var cur = n.getHours() * 60 + n.getMinutes()
        var s = toMinutes(lesson.start)
        var e = toMinutes(lesson.end)
        return s >= 0 && e > s && cur >= s && cur < e
    }

    function updatedText() {
        void nowTick
        if (lastUpdatedMs === 0)
            return loading ? i18n("обновление…") : i18n("нет данных")
        var sec = Math.round((Date.now() - lastUpdatedMs) / 1000)
        if (sec < 60) return i18n("обновлено только что")
        var min = Math.round(sec / 60)
        if (min < 60) return i18n("обновлено %1 мин назад", min)
        return i18n("обновлено %1 ч назад", Math.round(min / 60))
    }

    function metaLine(lesson) {
        var parts = []
        var t = lesson.typeFull || lesson.type
        if (t) parts.push(t)
        if (lesson.subgroup) parts.push(i18n("п/г %1", lesson.subgroup))
        if (lesson.room) parts.push(lesson.room)
        if (lesson.teacher && lesson.teacher !== "—") parts.push(lesson.teacher)
        if (lesson.parity) parts.push(lesson.parity)
        return parts.join("  ·  ")
    }

    // ---- data source -----------------------------------------------------
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            exec.disconnectSource(source)
            root.handleResult(data)
        }
    }

    Component.onCompleted: refresh()

    Timer {
        interval: Math.max(5, root.refreshMinutes) * 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowTick++
    }

    // ---- UI -------------------------------------------------------------
    fullRepresentation: Item {
        id: face
        implicitWidth: Kirigami.Units.gridUnit * 21
        implicitHeight: Kirigami.Units.gridUnit * 26
        Layout.minimumWidth: Kirigami.Units.gridUnit * 15
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12

        readonly property var g: root.groupData(root.activeTab)
        readonly property var days: root.visibleDays(g)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PC3.TabBar {
                    id: tabBar
                    Layout.fillWidth: true
                    currentIndex: root.activeTab
                    onCurrentIndexChanged: root.activeTab = currentIndex

                    PC3.TabButton { text: root.g1name || i18n("Группа 1") }
                    PC3.TabButton { text: root.g2name || i18n("Группа 2") }
                }

                PC3.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.loading
                    onClicked: root.refresh()
                    QQC2.ToolTip.text: i18n("Обновить")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 400
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: (face.g && face.g.weekType) || (face.g && face.g.stale)
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    visible: face.g && face.g.weekType
                    text: i18n("Неделя: %1", face.g ? face.g.weekType : "")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }
                Item { Layout.fillWidth: true }
                PC3.Label {
                    visible: face.g && face.g.stale
                    text: "⚠ " + i18n("кэш")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.neutralTextColor
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: root.runError !== "" || (face.g && face.g.error)
                text: "⚠ " + (root.runError !== "" ? root.runError : (face.g ? face.g.error : ""))
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: dayList
                    model: face.days
                    spacing: Kirigami.Units.largeSpacing
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: ColumnLayout {
                        id: dayItem
                        required property var modelData
                        readonly property bool today: root.isToday(modelData)
                        width: ListView.view ? ListView.view.width : implicitWidth
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.Label {
                                text: root.dayHeader(dayItem.modelData)
                                font.bold: true
                                font.capitalization: Font.Capitalize
                                color: dayItem.today ? Kirigami.Theme.highlightColor
                                                     : Kirigami.Theme.textColor
                            }
                            Rectangle {
                                visible: dayItem.today
                                radius: height / 2
                                color: Kirigami.Theme.highlightColor
                                Layout.preferredHeight: sege.implicitHeight + 2
                                Layout.preferredWidth: sege.implicitWidth + Kirigami.Units.smallSpacing * 2
                                PC3.Label {
                                    id: sege
                                    anchors.centerIn: parent
                                    text: i18n("сегодня")
                                    font: Kirigami.Theme.smallFont
                                    color: Kirigami.Theme.highlightedTextColor
                                }
                            }
                            Item { Layout.fillWidth: true }
                            PC3.Label {
                                visible: dayItem.modelData.week > 0
                                text: i18n("нед. %1", dayItem.modelData.week)
                                font: Kirigami.Theme.smallFont
                                opacity: 0.5
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Kirigami.Theme.textColor
                            opacity: 0.12
                        }

                        Repeater {
                            model: dayItem.modelData.lessons || []

                            delegate: RowLayout {
                                id: lessonRow
                                required property var modelData
                                readonly property bool active:
                                    (root.nowTick, dayItem.today && root.isNow(modelData))
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                ColumnLayout {
                                    spacing: 0
                                    Layout.alignment: Qt.AlignTop
                                    PC3.Label {
                                        text: lessonRow.modelData.start || ""
                                        font.bold: true
                                    }
                                    PC3.Label {
                                        text: lessonRow.modelData.end || ""
                                        opacity: 0.55
                                        font: Kirigami.Theme.smallFont
                                    }
                                }

                                Rectangle {
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 3
                                    radius: 1.5
                                    color: lessonRow.active ? Kirigami.Theme.highlightColor
                                                            : Kirigami.Theme.textColor
                                    opacity: lessonRow.active ? 1.0 : 0.22
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing
                                        PC3.Label {
                                            Layout.fillWidth: true
                                            text: lessonRow.modelData.subject || "—"
                                            wrapMode: Text.WordWrap
                                            font.bold: lessonRow.active
                                        }
                                        Rectangle {
                                            visible: lessonRow.modelData.once || lessonRow.modelData.exam
                                            radius: 3
                                            Layout.alignment: Qt.AlignTop
                                            Layout.preferredHeight: tagLbl.implicitHeight + 2
                                            Layout.preferredWidth: tagLbl.implicitWidth + Kirigami.Units.smallSpacing * 2
                                            color: lessonRow.modelData.exam ? "#d24b7a" : "#3f7fd2"
                                            PC3.Label {
                                                id: tagLbl
                                                anchors.centerIn: parent
                                                text: lessonRow.modelData.exam ? i18n("экз/зач") : i18n("разово")
                                                font: Kirigami.Theme.smallFont
                                                color: "white"
                                            }
                                        }
                                    }
                                    PC3.Label {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: root.metaLine(lessonRow.modelData)
                                        wrapMode: Text.WordWrap
                                        opacity: 0.7
                                        font: Kirigami.Theme.smallFont
                                    }
                                }
                            }
                        }

                        PC3.Label {
                            visible: !(dayItem.modelData.lessons && dayItem.modelData.lessons.length)
                            text: i18n("нет пар")
                            opacity: 0.5
                            font: Kirigami.Theme.smallFont
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                PC3.Label {
                    visible: root.loading
                    text: i18n("обновление…")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
                Item { Layout.fillWidth: true }
                PC3.Label {
                    text: root.updatedText()
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
            }
        }
    }
}
