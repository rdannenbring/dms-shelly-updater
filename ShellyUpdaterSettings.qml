import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "shellyUpdater"

    readonly property string defaultTerminal: Quickshell.env("TERMINAL") || "kitty"

    // Which settings tab is active (see the DankTabBar near the bottom).
    property int currentTab: 0

    // Track dependent settings so sub-options can show/hide reactively.
    property bool tooltipEnabled: false
    property bool aurEnabled: true
    property bool notifyEnabled: false
    property bool detectEnabled: true
    property bool limitEnabled: false
    property bool aiEnabled: false
    property bool failuresNotifyEnabled: true
    function refreshDependents() {
        tooltipEnabled = loadValue("showTooltip", false);
        aurEnabled = loadValue("enableAur", true);
        notifyEnabled = loadValue("notifyOnUpdates", false);
        detectEnabled = loadValue("detectFailedUpdates", true);
        limitEnabled = loadValue("limitBuildResources", false);
        aiEnabled = loadValue("aiEnabled", false);
        failuresNotifyEnabled = loadValue("notifyOnFailures", true);
    }
    Component.onCompleted: Qt.callLater(refreshDependents)
    onSettingChanged: refreshDependents()
    // pluginService (and plugin data) can be assigned AFTER Component.onCompleted
    // when the settings panel is reopened. The base PluginSettings reloads each
    // child widget's value on these signals — but not our dependent flags, so
    // without this the sub-settings stay hidden until the toggle is flipped
    // (their loadValue() returned the default at onCompleted time). Separate
    // Connections objects stack with the base's inline handlers rather than
    // replacing them.
    Connections {
        target: root
        function onPluginServiceChanged() { root.refreshDependents(); }
    }
    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.refreshDependents();
        }
    }

    // ---- Reusable helpers ----------------------------------------------
    component SectionHeader: Column {
        property string title: ""
        property string subtitle: ""
        width: parent.width
        spacing: Theme.spacingXS
        Rectangle { width: parent.width; height: 1; color: Theme.outline; opacity: 0.3 }
        StyledText {
            text: title
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }
        StyledText {
            width: parent.width
            text: subtitle
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            visible: subtitle !== ""
        }
    }

    // Monospace command box with a copy-to-clipboard button.
    component CopyableCommand: Rectangle {
        id: cc
        property string command: ""
        property string copyText: command
        property bool multiline: false
        property bool copied: false

        width: parent.width
        height: cmdText.implicitHeight + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHighest

        Timer { id: copyResetTimer; interval: 1500; onTriggered: cc.copied = false }

        StyledText {
            id: cmdText
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.right: copyBtn.left
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            text: cc.command
            font.family: "monospace"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.primary
            wrapMode: cc.multiline ? Text.WrapAnywhere : Text.NoWrap
            elide: cc.multiline ? Text.ElideNone : Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        DankActionButton {
            id: copyBtn
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: 28
            iconName: cc.copied ? "check" : "content_copy"
            iconSize: 16
            iconColor: cc.copied ? Theme.primary : Theme.surfaceVariantText
            tooltipText: cc.copied ? "Copied!" : "Copy to clipboard"
            onClicked: {
                Quickshell.execDetached(["dms", "cl", "copy", cc.copyText]);
                cc.copied = true;
                copyResetTimer.restart();
            }
        }
    }

    // Slider with an inline "reset to default" button shown when the value has
    // been changed away from its default.
    component SliderWithReset: Column {
        id: sr
        required property string settingKey
        required property string label
        property string description: ""
        property int defaultValue: 0
        property int value: defaultValue
        property int minimum: 0
        property int maximum: 100
        property string unit: ""
        property bool isInitialized: false

        width: parent.width
        spacing: Theme.spacingS

        function findSettings() {
            var item = parent;
            while (item) {
                if (item.saveValue !== undefined && item.loadValue !== undefined)
                    return item;
                item = item.parent;
            }
            return null;
        }
        function loadValue() {
            var s = findSettings();
            if (s && s.pluginService) {
                value = s.loadValue(settingKey, defaultValue);
                isInitialized = true;
            }
        }
        onValueChanged: {
            if (!isInitialized)
                return;
            var s = findSettings();
            if (s)
                s.saveValue(settingKey, value);
        }
        Component.onCompleted: Qt.callLater(loadValue)

        Row {
            width: parent.width
            spacing: Theme.spacingS
            StyledText {
                width: parent.width - resetBtn.width - Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: sr.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }
            DankActionButton {
                id: resetBtn
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 26
                iconName: "restart_alt"
                iconSize: 16
                iconColor: Theme.surfaceVariantText
                tooltipText: "Reset to default (" + sr.defaultValue + (sr.unit ? " " + sr.unit : "") + ")"
                visible: sr.value !== sr.defaultValue
                // DankSlider reassigns its own `value` on drag, which breaks the
                // `value: sr.value` binding — so push the default into the slider
                // directly, then update our own value (which persists it).
                onClicked: {
                    dankSlider.value = sr.defaultValue;
                    sr.value = sr.defaultValue;
                }
            }
        }
        StyledText {
            width: parent.width
            text: sr.description
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            visible: sr.description !== ""
        }
        DankSlider {
            id: dankSlider
            width: parent.width
            value: sr.value
            minimum: sr.minimum
            maximum: sr.maximum
            unit: sr.unit
            wheelEnabled: false
            onSliderValueChanged: newValue => sr.value = newValue
        }
    }

    // Icon field: free-text Material Symbol name + live preview + quick picks.
    component IconSetting: Column {
        id: iconRoot
        required property string settingKey
        required property string label
        property string description: ""
        property string defaultValue: ""
        property var suggestions: []
        property string value: defaultValue
        property bool isInitialized: false

        width: parent.width
        spacing: Theme.spacingS

        function findSettings() {
            var item = parent;
            while (item) {
                if (item.saveValue !== undefined && item.loadValue !== undefined)
                    return item;
                item = item.parent;
            }
            return null;
        }
        function loadValue() {
            var s = findSettings();
            if (s && s.pluginService) {
                value = s.loadValue(settingKey, defaultValue);
                field.text = value;
                isInitialized = true;
            }
        }
        function commit(v) {
            value = v;
            field.text = v;
            var s = findSettings();
            if (s) s.saveValue(settingKey, v);
        }
        Component.onCompleted: Qt.callLater(loadValue)

        StyledText {
            text: iconRoot.label
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }
        StyledText {
            width: parent.width
            text: iconRoot.description
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            visible: iconRoot.description !== ""
        }
        Row {
            width: parent.width
            spacing: Theme.spacingM
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40
                radius: Theme.cornerRadius
                color: Theme.secondaryHover
                DankIcon {
                    anchors.centerIn: parent
                    name: iconRoot.value || "help"
                    size: Theme.iconSize
                    color: Theme.primary
                }
            }
            DankTextField {
                id: field
                width: parent.width - 40 - Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: iconRoot.defaultValue
                onEditingFinished: iconRoot.commit(text)
                onActiveFocusChanged: { if (!activeFocus) iconRoot.commit(text); }
            }
        }
        Flow {
            width: parent.width
            spacing: Theme.spacingXS
            visible: iconRoot.suggestions.length > 0
            Repeater {
                model: iconRoot.suggestions
                Rectangle {
                    required property var modelData
                    width: 36; height: 36
                    radius: Theme.cornerRadius
                    color: pickHover.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh
                    border.width: iconRoot.value === modelData ? 2 : 0
                    border.color: Theme.primary
                    DankIcon {
                        anchors.centerIn: parent
                        name: modelData
                        size: Theme.iconSize - 2
                        color: Theme.surfaceText
                    }
                    MouseArea {
                        id: pickHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: iconRoot.commit(modelData)
                    }
                }
            }
        }
    }

    // ====================================================================
    StyledText {
        width: parent.width
        text: "Shelly Updater"
        font.pixelSize: Theme.fontSizeLarge + 2
        font.weight: Font.Bold
        color: Theme.surfaceText
    }
    StyledText {
        width: parent.width
        text: "A DankBar widget that checks and applies system updates through the Shelly (ALPM) CLI."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ---- Tab bar --------------------------------------------------------
    Item {
        width: parent.width
        height: 45 + Theme.spacingM

        DankTabBar {
            id: settingsTabBar
            width: Math.min(parent.width, 720)
            height: 45
            anchors.horizontalCenter: parent.horizontalCenter
            currentIndex: root.currentTab
            model: [
                { text: "Setup", icon: "download" },
                { text: "Checks", icon: "update" },
                { text: "Notify", icon: "notifications" },
                { text: "Sources", icon: "inventory_2" },
                { text: "Look", icon: "palette" },
                { text: "Actions", icon: "ads_click" },
                { text: "Updates", icon: "terminal" },
                { text: "AI", icon: "neurology" }
            ]

            Component.onCompleted: Qt.callLater(updateIndicator)

            onTabClicked: index => {
                root.currentTab = index;
                currentIndex = index;
            }
        }
    }

    // ==== Tab 0: Setup ===================================================
    Column {
        visible: root.currentTab === 0
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader {
            title: "Prerequisites"
            subtitle: "This widget requires the Shelly CLI. If the pill shows an error, install Shelly first."
        }
        Rectangle {
            width: parent.width
            height: prereqCol.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.15)
            border.width: 1
            border.color: Theme.outlineLight
            Column {
                id: prereqCol
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingS

                StyledText { text: "Install Shelly (official repo):"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText }
                CopyableCommand { command: "sudo pacman -S shelly" }
                StyledText { text: "…or via an AUR helper:"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                CopyableCommand { command: "yay -S shelly" }
                CopyableCommand { command: "paru -S shelly" }

                Rectangle { width: parent.width; height: 1; color: Theme.outline; opacity: 0.2 }

                StyledText {
                    width: parent.width
                    text: "Running updates without password prompts"
                    font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    width: parent.width
                    text: "Applying updates needs root. To skip the password prompt in the terminal, add a passwordless sudoers rule for Shelly (review carefully — this grants root package management without a password):"
                    font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; wrapMode: Text.WordWrap
                }
                CopyableCommand {
                    multiline: true
                    command: "echo \"$USER ALL=(root) NOPASSWD: /usr/bin/shelly\" | \\\n  sudo tee /etc/sudoers.d/shelly-nopasswd\nsudo chmod 440 /etc/sudoers.d/shelly-nopasswd"
                }
                StyledText {
                    width: parent.width
                    text: "Then run  shelly fix-permissions  once so Shelly's cache and directories are owned correctly."
                    font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ==== Tab 1: Checks ==================================================
    Column {
        visible: root.currentTab === 1
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader {
            title: "Automatic Checks"
            subtitle: "Control how and when the widget checks for available updates."
        }
        ToggleSetting {
            settingKey: "autoCheck"
            label: "Check automatically"
            description: "Periodically check for available updates in the background."
            defaultValue: true
        }
        SelectionSetting {
            settingKey: "checkFrequency"
            label: "Check frequency"
            description: "How often to check when automatic checks are enabled."
            defaultValue: "60"
            options: [
                { label: "Every 15 minutes", value: "15" },
                { label: "Every 30 minutes", value: "30" },
                { label: "Every hour", value: "60" },
                { label: "Every 4 hours", value: "240" },
                { label: "Once a day", value: "1440" }
            ]
        }
        ToggleSetting {
            settingKey: "checkAtStartup"
            label: "Check at startup"
            description: "Run a check as soon as the widget loads."
            defaultValue: true
        }
        ToggleSetting {
            settingKey: "confirmations"
            label: "Confirmation prompts"
            description: "Ask for confirmation in the terminal before applying updates. When off, updates run with --no-confirm."
            defaultValue: true
        }
        ToggleSetting {
            settingKey: "alwaysConfirmKernel"
            label: "Always confirm kernel updates"
            description: "Force the confirmation prompt whenever an upgrade includes a kernel package (linux, linux-lts, linux-zen, …), even if the confirmation prompts above are turned off. Lets you review or decline kernel updates before they apply."
            defaultValue: false
        }
    }

    // ==== Tab 2: Notify =================================================
    Column {
        visible: root.currentTab === 2
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader {
            title: "Notifications"
            subtitle: "Send a desktop notification when a background check finds new updates. De-duplicated across monitors, and only re-fires when the set of updates changes."
        }
        ToggleSetting {
            settingKey: "notifyOnUpdates"
            label: "Notify when updates are found"
            description: "Requires notify-send (libnotify) and a running notification daemon."
            defaultValue: false
        }
        SliderWithReset {
            visible: root.notifyEnabled
            height: visible ? implicitHeight : 0
            settingKey: "notifyThreshold"
            label: "Minimum updates to notify"
            description: "Only notify when at least this many updates are available."
            defaultValue: 1
            minimum: 1
            maximum: 25
            unit: ""
        }

        SectionHeader {
            title: "Failures"
            subtitle: "Failed updates can slip by silently — the terminal closes and the run may even report success (e.g. an AUR build cancelled because its PKGBUILD changed)."
        }
        ToggleSetting {
            settingKey: "notifyOnFailures"
            label: "Notify when an update fails"
            description: "Send a notification when packages from an update run didn't apply. The notification carries a \"View details\" action (and \"Explain with AI\" when AI analysis is configured in the AI tab)."
            defaultValue: true
        }
        ToggleSetting {
            visible: root.failuresNotifyEnabled
            height: visible ? implicitHeight : 0
            settingKey: "notifyFailuresRepeat"
            label: "Keep reminding until resolved"
            description: "Re-send the failure notification on each background check while failures remain unresolved (a package is resolved when it updates successfully, is uninstalled, is held, or you dismiss it). Off by default — this can be noisy depending on your check frequency."
            defaultValue: false
        }
    }

    // ==== Tab 3: Sources ================================================
    Column {
        visible: root.currentTab === 3
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader {
            title: "Sources"
            subtitle: "Pacman (official repositories) is always included. Toggle the extra sources you use."
        }
        ToggleSetting { settingKey: "enableAur"; label: "AUR"; description: "Include Arch User Repository packages."; defaultValue: true }
        ToggleSetting {
            visible: root.aurEnabled
            height: visible ? implicitHeight : 0
            settingKey: "excludeDevelAur"
            label: "Exclude devel / -git packages"
            description: "Ignore AUR packages that only track upstream commits (reported as 'latest-commit', e.g. *-git). Leaves just real version releases, so the count matches a paru-style view."
            defaultValue: false
        }
        ToggleSetting { settingKey: "enableFlatpak"; label: "Flatpak"; description: "Include Flatpak applications."; defaultValue: true }
        ToggleSetting { settingKey: "enableAppimage"; label: "AppImage"; description: "Include AppImages managed by Shelly."; defaultValue: false }
    }

    // ==== Tab 4: Look (Appearance / Detailed View / Tooltip) ============
    Column {
        visible: root.currentTab === 4
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader { title: "Appearance" }
        IconSetting {
            settingKey: "iconDefault"
            label: "Icon — up to date"
            description: "Material Symbol shown when there are no updates. Browse names at fonts.google.com/icons."
            defaultValue: "check_circle"
            suggestions: ["check_circle", "task_alt", "verified", "shield", "done_all", "package_2"]
        }
        IconSetting {
            settingKey: "iconUpdates"
            label: "Icon — updates available"
            description: "Material Symbol shown when updates are available."
            defaultValue: "system_update_alt"
            suggestions: ["system_update_alt", "download", "file_download", "cloud_download", "upgrade", "new_releases"]
        }
        IconSetting {
            settingKey: "iconFailures"
            label: "Icon — last update failed"
            description: "Material Symbol shown when packages from the last update run didn't apply. A distinct glyph (not just a color) so it stays visible with bar themes that mute icon colors."
            defaultValue: "release_alert"
            suggestions: ["release_alert", "warning", "running_with_errors", "sync_problem", "report", "priority_high"]
        }
        ToggleSetting {
            settingKey: "showCount"
            label: "Show update count"
            description: "Display the number of available updates next to the icon."
            defaultValue: true
        }
        SelectionSetting {
            settingKey: "countPositionH"
            label: "Count position (horizontal bar)"
            description: "Where the count sits relative to the icon on a top/bottom bar."
            defaultValue: "right"
            options: [ { label: "Left of icon", value: "left" }, { label: "Right of icon", value: "right" } ]
        }
        SelectionSetting {
            settingKey: "countPositionV"
            label: "Count position (vertical bar)"
            description: "Where the count sits relative to the icon on a left/right bar."
            defaultValue: "bottom"
            options: [ { label: "Above icon", value: "top" }, { label: "Below icon", value: "bottom" } ]
        }

        SectionHeader {
            title: "Detailed View"
            subtitle: "The list shown when left-clicking the widget (long descriptions are truncated with an ellipsis)."
        }
        SliderWithReset {
            settingKey: "detailRows"
            label: "Rows to show"
            description: "Number of update rows visible before the list scrolls."
            defaultValue: 6
            minimum: 3
            maximum: 15
            unit: "rows"
        }

        SectionHeader { title: "Tooltip" }
        ToggleSetting {
            settingKey: "showTooltip"
            label: "Show tooltip on hover"
            description: "Show the total and per-source update counts when hovering the pill."
            defaultValue: false
        }
        ToggleSetting {
            visible: root.tooltipEnabled
            height: visible ? implicitHeight : 0
            settingKey: "tooltipShowPackages"
            label: "Include package names"
            description: "Also list the individual package names in the tooltip."
            defaultValue: false
        }
        SliderWithReset {
            visible: root.tooltipEnabled
            height: visible ? implicitHeight : 0
            settingKey: "tooltipDelay"
            label: "Show delay"
            description: "Delay before the tooltip appears after hovering."
            defaultValue: 500
            minimum: 0
            maximum: 2000
            unit: "ms"
        }
        ToggleSetting {
            visible: root.tooltipEnabled
            height: visible ? implicitHeight : 0
            settingKey: "tooltipFade"
            label: "Fade in"
            description: "Fade the tooltip in when it appears instead of showing instantly."
            defaultValue: true
        }
    }

    // ==== Tab 5: Actions (Menu / Click Actions) =========================
    Column {
        visible: root.currentTab === 5
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader { title: "Menu" }
        ToggleSetting {
            settingKey: "showOpenShellyMenuItem"
            label: "Show \"Open Shelly UI\""
            description: "Include an entry in the menu to launch the Shelly graphical interface (shelly-ui)."
            defaultValue: true
        }

        SectionHeader {
            title: "Click Actions"
            subtitle: "Choose what each mouse button does when clicking the pill."
        }
        SelectionSetting {
            settingKey: "leftClickAction"
            label: "Left click"
            defaultValue: "updates"
            options: [
                { label: "Open updates view", value: "updates" },
                { label: "Open menu", value: "menu" },
                { label: "Open Shelly UI", value: "ui" },
                { label: "Do nothing", value: "none" }
            ]
        }
        SelectionSetting {
            settingKey: "middleClickAction"
            label: "Middle click"
            defaultValue: "none"
            options: [
                { label: "Do nothing", value: "none" },
                { label: "Open updates view", value: "updates" },
                { label: "Open menu", value: "menu" },
                { label: "Open Shelly UI", value: "ui" }
            ]
        }
        SelectionSetting {
            settingKey: "rightClickAction"
            label: "Right click"
            defaultValue: "menu"
            options: [
                { label: "Open menu", value: "menu" },
                { label: "Open updates view", value: "updates" },
                { label: "Open Shelly UI", value: "ui" },
                { label: "Do nothing", value: "none" }
            ]
        }
    }

    // ==== Tab 6: Updates (Terminal / Performance) =======================
    Column {
        visible: root.currentTab === 6
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader { title: "Terminal" }
        StringSetting {
            settingKey: "terminal"
            label: "Terminal application"
            description: "Terminal used to run updates (e.g. ghostty, kitty, alacritty, foot). '-e' is appended automatically. Defaults to your $TERMINAL."
            placeholder: defaultTerminal
            defaultValue: defaultTerminal
        }
        ToggleSetting {
            settingKey: "closeTerminalOnDone"
            label: "Close terminal when finished"
            description: "Automatically close the terminal window once an update completes, instead of keeping it open with a \"Press Enter to close\" prompt. Note: this also closes it on failure, so any errors won't stay on screen."
            defaultValue: false
        }
        ToggleSetting {
            settingKey: "surviveRestart"
            label: "Keep terminal alive across DMS restarts"
            description: "Launch the update terminal in its own systemd scope so it survives a DMS crash or restart (the update keeps running in its own window). Opens the update in a standalone window rather than a tab of your existing terminal. Requires systemd (uses systemd-run)."
            defaultValue: true
        }
        ToggleSetting {
            settingKey: "detectFailedUpdates"
            label: "Detect failed updates"
            description: "After an update, flag any package that still shows a pending update (it didn't apply) with a red \"failed\" marker in the updates view, plus a \"View log\" button. This records the update session with 'script' to keep a log — turn off to run updates without that wrapper."
            defaultValue: true
        }
        SliderWithReset {
            visible: root.detectEnabled
            height: visible ? implicitHeight : 0
            settingKey: "failureHistoryDays"
            label: "Keep failed-update history for"
            description: "Failed updates are saved and shown in the Update History view (marked in red), then pruned after this many days. This is the plugin's own log — successful updates come from the system package log (/var/log/pacman.log) and are never pruned by this setting. Max 180 days."
            defaultValue: 30
            minimum: 1
            maximum: 180
            unit: "days"
        }

        SectionHeader {
            title: "Performance"
            subtitle: "Large AUR builds can compile in parallel across every core and make the desktop unresponsive while an update runs. These options throttle the build."
        }
        ToggleSetting {
            settingKey: "limitBuildResources"
            label: "Limit resource usage during updates"
            description: "Apply the settings below when running updates so heavy builds don't peg the CPU. Off by default — updates run at full speed."
            defaultValue: false
        }
        ToggleSetting {
            visible: root.limitEnabled
            height: visible ? implicitHeight : 0
            settingKey: "lowerPriority"
            label: "Run at lower priority"
            description: "Run the update with nice (low CPU priority) and ionice (idle I/O), so compiles yield to your desktop. The build still uses all cores when nothing else needs them, so it's nearly free when the system is idle — this is the most effective option for keeping the UI responsive."
            defaultValue: true
        }
        SelectionSetting {
            visible: root.limitEnabled
            height: visible ? implicitHeight : 0
            settingKey: "maxBuildJobs"
            label: "Max parallel build jobs"
            description: "Cap how many compile jobs run at once by setting MAKEFLAGS / CARGO_BUILD_JOBS / CMAKE_BUILD_PARALLEL_LEVEL for the build. \"Automatic\" leaves it to makepkg (usually all cores). Note: a package that hard-codes its own job count (or uses ninja, which has no jobs variable) may ignore this — the priority option above always applies."
            defaultValue: "0"
            options: [
                { label: "Automatic (all cores)", value: "0" },
                { label: "2 jobs", value: "2" },
                { label: "4 jobs", value: "4" },
                { label: "6 jobs", value: "6" },
                { label: "8 jobs", value: "8" },
                { label: "12 jobs", value: "12" },
                { label: "16 jobs", value: "16" }
            ]
        }
    }

    // ==== Tab 7: AI (failure analysis) ==================================
    Column {
        visible: root.currentTab === 7
        width: parent.width
        spacing: Theme.spacingM

        SectionHeader {
            title: "AI Failure Analysis"
            subtitle: "When an update fails, ask an AI to read the captured log and suggest fixes — via a command-line tool YOU configure. The plugin never talks to an AI service directly and never stores API keys; a subscription-based CLI (like Claude Code) works without paying for API credits."
        }
        ToggleSetting {
            settingKey: "aiEnabled"
            label: "Enable AI suggestions"
            description: "Adds a \"Suggest fix with AI\" button to the failure-detail view and an \"Explain with AI\" action to failure notifications."
            defaultValue: false
        }
        StringSetting {
            visible: root.aiEnabled
            height: visible ? implicitHeight : 0
            settingKey: "aiCommand"
            label: "AI command"
            description: "A shell command that reads a prompt on standard input and prints a plain-text answer on standard output. Runs with your desktop session's environment, so tools on your normal PATH work."
            placeholder: "claude -p"
            defaultValue: ""
        }
        Rectangle {
            visible: root.aiEnabled
            width: parent.width
            height: visible ? aiExamplesCol.implicitHeight + Theme.spacingL * 2 : 0
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.15)
            border.width: 1
            border.color: Theme.outlineLight
            Column {
                id: aiExamplesCol
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingS

                StyledText { text: "Examples:"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText }
                StyledText { text: "Claude Code (uses your Claude subscription):"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                CopyableCommand { command: "claude -p" }
                StyledText { text: "OpenCode (uses whatever provider it's configured with):"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                CopyableCommand { command: "opencode run" }
                StyledText { text: "A local model via Ollama (fully offline):"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                CopyableCommand { command: "ollama run llama3.2" }
                StyledText { text: "Gemini CLI:"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                CopyableCommand { command: "gemini -p" }
            }
        }
        StyledText {
            visible: root.aiEnabled
            width: parent.width
            text: "Privacy note: the prompt sent to the command contains the failed package's name, versions, the failure reason, and the saved tail of the update log (which can include hostnames and package lists). Nothing is sent automatically — analysis only runs when you click the button or the notification action."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        SectionHeader {
            visible: root.aiEnabled
            title: "Prompt"
            subtitle: "The exact prompt sent to your AI command. Placeholders are filled in per failure: {package}, {source}, {oldVersion}, {newVersion}, {reason}, {log}, and {environment} (auto-detected distro, kernel, architecture and Shelly version). Clearing the text restores the default."
        }
        Column {
            id: promptEditor
            visible: root.aiEnabled
            width: parent.width
            height: visible ? implicitHeight : 0
            spacing: Theme.spacingS

            // KEEP IN SYNC with aiPromptDefault in ShellyUpdater.qml.
            readonly property string defaultTemplate: [
                "You are helping diagnose a failed package update on a Linux system.",
                "The update was run through the Shelly package manager (wraps pacman/AUR/Flatpak/AppImage).",
                "",
                "System environment:",
                "{environment}",
                "",
                "Package: {package} (source: {source})",
                "Attempted: {oldVersion} -> {newVersion}",
                "Failure reason (updater's classification): {reason}",
                "",
                "Tail of the captured update log:",
                "{log}",
                "",
                "Briefly explain what went wrong, then give concrete numbered fix steps the user can run.",
                "Put each runnable shell command on its own line, prefixed with \"$ \" (dollar + space) and nothing else on that line, so it can be copied and run directly.",
                "Prefer non-interactive command forms so they run inline without prompts (the app runs \"$ \" commands with no terminal, so a command that waits for input just fails).",
                "If a command truly needs a terminal — it asks for a sudo password, or a confirmation/review the user must see (e.g. an AUR PKGBUILD review, or a pacman/yay install confirmation) — prefix it with \"$! \" (dollar + bang + space) instead of \"$ \", so the app opens a terminal for it.",
                "End with a short \"Verify:\" step — a \"$ \"-prefixed command whose output shows whether the fix worked — so the result can be checked afterwards.",
                "Plain text only — no markdown syntax. Keep it under 200 words."
            ].join("\n")
            property bool isInitialized: false

            function findSettings() {
                var item = parent;
                while (item) {
                    if (item.saveValue !== undefined && item.loadValue !== undefined)
                        return item;
                    item = item.parent;
                }
                return null;
            }
            function loadTemplate() {
                var s = findSettings();
                if (s && s.pluginService) {
                    var saved = s.loadValue("aiPromptTemplate", "");
                    promptArea.text = saved !== "" ? saved : defaultTemplate;
                    isInitialized = true;
                }
            }
            // Store "" when the text matches the default (or is blank) so the
            // widget keeps tracking future default improvements.
            function commit() {
                if (!isInitialized)
                    return;
                var s = findSettings();
                if (!s)
                    return;
                var t = promptArea.text;
                var v = (t.trim() === "" || t.trim() === defaultTemplate.trim()) ? "" : t;
                s.saveValue("aiPromptTemplate", v);
                if (t.trim() === "")
                    promptArea.text = defaultTemplate;
            }
            Component.onCompleted: Qt.callLater(loadTemplate)

            Row {
                width: parent.width
                spacing: Theme.spacingS
                StyledText {
                    width: parent.width - promptResetBtn.width - Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: promptArea.text.trim() !== promptEditor.defaultTemplate.trim() ? "Custom prompt" : "Default prompt"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
                DankActionButton {
                    id: promptResetBtn
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: 26
                    iconName: "restart_alt"
                    iconSize: 16
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "Reset to the default prompt"
                    visible: promptArea.text.trim() !== promptEditor.defaultTemplate.trim()
                    onClicked: {
                        promptArea.text = promptEditor.defaultTemplate;
                        promptEditor.commit();
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: 240
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHighest
                border.width: promptArea.activeFocus ? 2 : 1
                border.color: promptArea.activeFocus ? Theme.primary : Theme.outlineLight

                Flickable {
                    id: promptFlick
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    clip: true
                    contentWidth: width
                    contentHeight: promptArea.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    TextArea.flickable: TextArea {
                        id: promptArea
                        width: promptFlick.width
                        wrapMode: TextArea.Wrap
                        textFormat: TextEdit.PlainText
                        font.family: "monospace"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.surface
                        background: null
                        // Persist on focus loss, not per keystroke — saveValue
                        // broadcasts plugin state to every widget instance.
                        onActiveFocusChanged: {
                            if (!activeFocus)
                                promptEditor.commit();
                        }
                    }
                }
            }
        }
    }
}
