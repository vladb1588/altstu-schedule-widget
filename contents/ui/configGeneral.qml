import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_group1Name: g1name.text
    property alias cfg_group1Id: g1id.text
    property alias cfg_group2Name: g2name.text
    property alias cfg_group2Id: g2id.text
    property alias cfg_refreshMinutes: refresh.value
    property alias cfg_daysAhead: daysAhead.value
    property alias cfg_showWeekend: weekend.checked
    property alias cfg_pythonPath: python.text
    property alias cfg_localDir: localDir.text

    QQC2.TextField {
        id: g1name
        Kirigami.FormData.label: i18n("Group 1 — name:")
        placeholderText: "1ИИС-42"
    }
    QQC2.TextField {
        id: g1id
        Kirigami.FormData.label: i18n("Group 1 — schedule id:")
        placeholderText: "2000020600"
        inputMethodHints: Qt.ImhDigitsOnly
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.TextField {
        id: g2name
        Kirigami.FormData.label: i18n("Group 2 — name:")
        placeholderText: "1ИИС-41"
    }
    QQC2.TextField {
        id: g2id
        Kirigami.FormData.label: i18n("Group 2 — schedule id:")
        placeholderText: "2000020599"
        inputMethodHints: Qt.ImhDigitsOnly
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.SpinBox {
        id: refresh
        Kirigami.FormData.label: i18n("Refresh every, min:")
        from: 5
        to: 720
        stepSize: 5
    }
    QQC2.SpinBox {
        id: daysAhead
        Kirigami.FormData.label: i18n("Days to show:")
        from: 1
        to: 28
    }
    QQC2.CheckBox {
        id: weekend
        text: i18n("Show Saturday / Sunday")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.TextField {
        id: python
        Kirigami.FormData.label: i18n("Python executable:")
        placeholderText: "python3"
    }
    QQC2.TextField {
        id: localDir
        Kirigami.FormData.label: i18n("Local HTML folder:")
        placeholderText: i18n("(optional) reads <id>.html from here instead of the site")
        Layout.fillWidth: true
    }
    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: i18n("id = number in the page URL altstu.ru/m/s/<id>/.  Local folder is a fallback for when the site is unreachable (e.g. behind VPN): save each group's page there as <id>.html.")
    }
}
