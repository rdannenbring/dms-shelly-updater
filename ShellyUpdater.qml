import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string pluginName: "shellyUpdater"

    // Effective settings source. The control-center widget is a separate plugin
    // instance whose pluginService is often not wired, so the base
    // loadPluginData() leaves pluginData empty and every setting falls back to
    // its default (e.g. the "Suggest fix with AI" button stays hidden because
    // aiEnabled reads false). When pluginData is empty we read the on-disk
    // plugin_settings.json directly (values there are plain, not double-encoded).
    property var _pdFallback: ({})
    readonly property var _pd: (pluginData && Object.keys(pluginData).length > 0) ? pluginData : _pdFallback
    readonly property string _pluginSettingsPath: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config"))
        + "/DankMaterialShell/plugin_settings.json"
    function _ensureSettings() {
        if (pluginData && Object.keys(pluginData).length > 0)
            return; // base already loaded them
        pluginSettingsProc.running = true;
    }
    Process {
        id: pluginSettingsProc
        command: ["cat", root._pluginSettingsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var all = JSON.parse(text || "{}");
                    // Index by the known plugin name, NOT root.pluginId — the
                    // control-center instance can carry a different/blank pluginId.
                    if (all && all[root.pluginName])
                        root._pdFallback = all[root.pluginName];
                } catch (e) {}
            }
        }
        stderr: StdioCollector { onStreamFinished: {} }
    }

    // ---- Settings (bound to pluginData so they react to changes) ----
    readonly property bool autoCheck: _pd.autoCheck !== undefined ? _pd.autoCheck : true
    readonly property int checkFrequency: parseInt(_pd.checkFrequency || "60") // minutes
    readonly property bool checkAtStartup: _pd.checkAtStartup !== undefined ? _pd.checkAtStartup : true
    readonly property bool confirmations: _pd.confirmations !== undefined ? _pd.confirmations : true
    readonly property bool enableAur: _pd.enableAur !== undefined ? _pd.enableAur : true
    readonly property bool enableFlatpak: _pd.enableFlatpak !== undefined ? _pd.enableFlatpak : true
    readonly property bool enableAppimage: _pd.enableAppimage !== undefined ? _pd.enableAppimage : false
    readonly property bool excludeDevelAur: _pd.excludeDevelAur !== undefined ? _pd.excludeDevelAur : false
    readonly property bool alwaysConfirmKernel: _pd.alwaysConfirmKernel !== undefined ? _pd.alwaysConfirmKernel : false
    readonly property string iconDefault: _pd.iconDefault || "check_circle"
    readonly property string iconUpdates: _pd.iconUpdates || "system_update_alt"
    // Failures get their own GLYPH, not just a color — bar theming can render
    // icon colors nearly indistinguishable, so shape carries the signal.
    readonly property string iconFailures: _pd.iconFailures || "release_alert"
    readonly property bool showCount: _pd.showCount !== undefined ? _pd.showCount : true
    readonly property string countPositionH: _pd.countPositionH || "right" // left | right
    readonly property string countPositionV: _pd.countPositionV || "bottom" // top | bottom
    readonly property bool showTooltip: _pd.showTooltip !== undefined ? _pd.showTooltip : false
    readonly property bool tooltipShowPackages: _pd.tooltipShowPackages !== undefined ? _pd.tooltipShowPackages : false
    readonly property int tooltipDelay: parseInt(_pd.tooltipDelay !== undefined ? _pd.tooltipDelay : 500) // ms
    readonly property bool tooltipFade: _pd.tooltipFade !== undefined ? _pd.tooltipFade : true
    readonly property int detailRows: parseInt(_pd.detailRows !== undefined ? _pd.detailRows : 6)
    readonly property bool showOpenShellyMenuItem: _pd.showOpenShellyMenuItem !== undefined ? _pd.showOpenShellyMenuItem : true
    readonly property bool notifyOnUpdates: _pd.notifyOnUpdates !== undefined ? _pd.notifyOnUpdates : false
    readonly property int notifyThreshold: parseInt(_pd.notifyThreshold !== undefined ? _pd.notifyThreshold : 1)
    readonly property bool notifyOnFailures: _pd.notifyOnFailures !== undefined ? _pd.notifyOnFailures : true
    // Re-fire the failure notification on later background checks while failures
    // remain unresolved (a persistent reminder; can be noisy → default off).
    readonly property bool notifyFailuresRepeat: _pd.notifyFailuresRepeat !== undefined ? _pd.notifyFailuresRepeat : false
    readonly property string leftClickAction: _pd.leftClickAction || "updates" // updates | menu | ui | none
    readonly property string middleClickAction: _pd.middleClickAction || "none"
    readonly property string rightClickAction: _pd.rightClickAction || "menu"
    readonly property string terminal: _pd.terminal || Quickshell.env("TERMINAL") || "kitty"
    readonly property bool closeTerminalOnDone: _pd.closeTerminalOnDone !== undefined ? _pd.closeTerminalOnDone : false
    readonly property bool surviveRestart: _pd.surviveRestart !== undefined ? _pd.surviveRestart : true
    readonly property bool detectFailedUpdates: _pd.detectFailedUpdates !== undefined ? _pd.detectFailedUpdates : true
    // Retention for the self-kept failed-update log (days). Capped by the
    // settings slider; clamped defensively here too.
    readonly property int failureHistoryDays: Math.max(1, Math.min(180, parseInt(_pd.failureHistoryDays !== undefined ? _pd.failureHistoryDays : 30)))
    // Second retention bound (OR'd with the day limit): cap the stored failure
    // history by approximate size so a run that aborts and flags many packages
    // (each keeping a log excerpt) can't balloon the state file.
    readonly property int failureHistoryMaxMB: Math.max(1, Math.min(50, parseInt(_pd.failureHistoryMaxMB !== undefined ? _pd.failureHistoryMaxMB : 10)))
    // Resource limits so big (AUR) builds don't peg the machine and make the
    // desktop unresponsive. Off by default (no change to how updates run).
    readonly property bool limitBuildResources: _pd.limitBuildResources !== undefined ? _pd.limitBuildResources : false
    readonly property bool lowerPriority: _pd.lowerPriority !== undefined ? _pd.lowerPriority : true
    readonly property int maxBuildJobs: parseInt(_pd.maxBuildJobs !== undefined ? _pd.maxBuildJobs : 0) // 0 = unlimited
    // AI failure analysis: a user-configured shell command that reads a prompt
    // on stdin and prints a plain-text answer (e.g. "claude -p", "ollama run
    // llama3.2"). A CLI keeps API keys out of the plugin's plain-JSON state and
    // lets subscription accounts work without API credits.
    readonly property bool aiEnabled: _pd.aiEnabled !== undefined ? _pd.aiEnabled : false
    readonly property string aiCommand: (_pd.aiCommand || "").trim()
    readonly property bool aiReady: aiEnabled && aiCommand !== ""
    // User-editable prompt template ({placeholders} filled per failure). An
    // empty/unset setting means the built-in default below. KEEP IN SYNC with
    // the copy in ShellyUpdaterSettings.qml (settings can't read this file).
    readonly property string aiPromptDefault: [
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
    readonly property string aiPromptTemplate: (_pd.aiPromptTemplate || "").trim() !== "" ? _pd.aiPromptTemplate : aiPromptDefault

    // ---- Live state ----
    property var pacmanUpdates: []
    property var aurUpdates: []
    property var flatpakUpdates: []
    property var appimageUpdates: []
    property bool isChecking: false
    property bool isUpgrading: false
    property bool hasError: false
    property string errorMessage: ""

    // Installed Shelly major version (0 = not yet detected). This plugin targets
    // the Shelly v3+ CLI grammar; on an older shelly every call breaks, so we
    // detect the version once and surface it clearly instead of failing silently.
    property int shellyMajor: 0
    property string shellyVersionRaw: ""
    readonly property bool shellyUnsupported: shellyMajor > 0 && shellyMajor < 3

    // Arch Linux news (Shelly v3 `news`). newsItems is the latest snapshot;
    // newsSeen maps acknowledged links → true (tracked locally so a background
    // poll can't consume the unread badge the way `shelly news` does). newsInit
    // guards the first-run seed that marks all currently-known news read.
    property var newsItems: []
    property var newsSeen: ({})
    property bool newsInit: false
    property bool newsExpanded: false
    readonly property int newsUnreadCount: {
        var c = 0;
        for (var i = 0; i < newsItems.length; i++)
            if (!newsSeen[newsItems[i].link]) c++;
        return c;
    }

    // VCS/devel AUR packages (`-git`, etc.) report "latest-commit" as their new
    // version — upstream commits, not real releases. Optionally exclude them.
    function _isDevelAur(u) {
        return u.newVersion === "latest-commit" || /-(git|svn|hg|bzr|cvs|nightly)$/.test(u.name || "");
    }

    // Category label + rank for the "type" sort (pacman → aur → devel → flatpak
    // → appimage). Devel is an AUR sub-category, matching the row chips.
    function _typeLabel(u) {
        if (u.source === "aur" && root._isDevelAur(u))
            return "devel";
        return u.source || "";
    }
    function _typeRank(u) {
        if (u.source === "pacman") return 0;
        if (u.source === "aur") return root._isDevelAur(u) ? 2 : 1;
        if (u.source === "flatpak") return 3;
        if (u.source === "appimage") return 4;
        return 5;
    }
    readonly property var aurUpdatesEffective: excludeDevelAur ? aurUpdates.filter(u => !root._isDevelAur(u)) : aurUpdates

    // Held/ignored packages (shelly ignore list) — pinned by the user so they
    // stay out of the actionable count and list. pacman/AUR only.
    property var ignoredPackages: []
    function _isHeld(nameOrItem) {
        var n = (typeof nameOrItem === "string") ? nameOrItem : ((nameOrItem && nameOrItem.name) || "");
        return root.ignoredPackages.indexOf(n) !== -1;
    }
    // "Shown" = what the user still needs to act on (held items filtered out).
    readonly property var pacmanUpdatesShown: pacmanUpdates.filter(u => !root._isHeld(u))
    readonly property var aurUpdatesShown: aurUpdatesEffective.filter(u => !root._isHeld(u))

    // Kernel image + headers (linux, linux-lts, linux-zen, …). Deliberately NOT
    // linux-firmware / linux-api-headers — those aren't reboot-critical kernels.
    function _isKernel(nameOrItem) {
        var n = (typeof nameOrItem === "string") ? nameOrItem : ((nameOrItem && nameOrItem.name) || "");
        return /^linux(-(lts|zen|hardened|rt|rt-lts|clang|xanmod|cachyos|surface|libre))?[0-9]*(-headers)?$/.test(n);
    }
    readonly property bool hasKernelUpdate: pacmanUpdatesShown.some(u => root._isKernel(u))

    readonly property int updateCount: pacmanUpdatesShown.length
        + (enableAur ? aurUpdatesShown.length : 0)
        + (enableFlatpak ? flatpakUpdates.length : 0)
        + (enableAppimage ? appimageUpdates.length : 0)

    // Every actionable update, in display order (used by the list, tooltip, and
    // update-notification signature).
    function allShownItems() {
        return root.pacmanUpdatesShown
            .concat(root.enableAur ? root.aurUpdatesShown : [])
            .concat(root.enableFlatpak ? root.flatpakUpdates : [])
            .concat(root.enableAppimage ? root.appimageUpdates : []);
    }

    // Case-insensitive substring match used by the updates & history text
    // filters. Matches against name, description, source and either version
    // (records from both views share name/oldVersion/newVersion).
    function _matchesFilter(item, query) {
        if (!query)
            return true;
        var q = query.toLowerCase().trim();
        if (q === "")
            return true;
        var hay = [item.name, item.description, item.source, item.oldVersion, item.newVersion];
        for (var i = 0; i < hay.length; i++) {
            if (hay[i] && String(hay[i]).toLowerCase().indexOf(q) !== -1)
                return true;
        }
        return false;
    }

    // Last successful check + a slow tick so "checked Nm ago" stays current.
    property double lastChecked: 0
    property int _clock: 0

    // Popout is shared; popoutMode selects which view renders.
    property string popoutMode: "updates" // updates | menu | detail | held | history | faildetail
    property bool popoutOpen: false

    // ---- Package-detail view state ----
    // Clicking a row in the updates view opens an extended-info panel for that
    // package. pacman/AUR details are fetched live; flatpak/appimage fall back
    // to the info already carried on the row (no clean per-package query).
    property var detailItem: null   // the clicked row's normalized record
    property var detailData: null   // { title, source, description, fields:[{label,value,mono}] }
    property bool detailLoading: false
    property string detailError: ""

    // ---- Failed-update tracking ----
    // After an upgrade, any package we tried to update that STILL shows an
    // available update didn't apply. We flag those (only when the run reported
    // a non-zero exit, so a clean run never false-flags) and keep the captured
    // session log so the user can see why. Broadcast so every monitor agrees.
    property var attemptedUpdate: []          // names submitted to the last upgrade
    property var failedPackages: []           // names that failed in the LAST run
    // Persistent "unresolved failures" — the latest failure per package that is
    // STILL pending (in the actionable list), not user-dismissed, and not marked
    // resolved (succeeded in a later run). This drives all the failure visuals so
    // a failure stays surfaced until it's actually dealt with, instead of only
    // reflecting the most recent run. Auto-resolves when a package updates
    // successfully / is uninstalled / is held (all leave allShownItems).
    readonly property var unresolvedFailures: {
        var shown = {};
        var items = root.allShownItems();
        for (var s = 0; s < items.length; s++)
            shown[items[s].name] = true;
        var seen = {};
        var out = [];
        for (var i = 0; i < root.failureHistory.length; i++) {
            var f = root.failureHistory[i];
            if (seen[f.name])
                continue; // only the latest failure record per package governs
            seen[f.name] = true;
            if (f.dismissed || f.resolved)
                continue;
            if (!root._isActionableFailure(f.reason))
                continue; // advisory (batch abort) — the package is just still pending
            if (shown[f.name])
                out.push(f);
        }
        return out;
    }
    readonly property bool hasFailures: unresolvedFailures.length > 0
    readonly property int failureCount: unresolvedFailures.length
    // Summary of the most recent upgrade run: { when, attempted, successful,
    // failed }. Persisted + broadcast; shown on the "Update History" menu item.
    // successful = attempted − failed (the names we submitted that then applied).
    property var lastRunSummary: null
    function lastRunSummaryText() {
        var s = root.lastRunSummary;
        if (!s || !s.attempted)
            return "";
        var bad = s.failed + (s.failed === 1 ? " failure" : " failures");
        return "Last update: " + s.successful + " successful, " + bad;
    }
    property bool _awaitingUpgradeResult: false
    property int _lastUpgradeExit: 0
    property string _lastLogText: ""          // captured session output of last run
    function _isFailed(nameOrItem) {
        var n = (typeof nameOrItem === "string") ? nameOrItem : ((nameOrItem && nameOrItem.name) || "");
        return root.unresolvedFailures.some(function (f) { return f.name === n; });
    }
    // A failure that can only be cleared by an interactive re-run (the user must
    // see and accept a prompt) — currently a changed PKGBUILD, which Shelly
    // refuses to build under --no-confirm. Drives the "run interactive update"
    // buttons in the failure detail and the updates list.
    function _reasonNeedsInteractive(reason) {
        return reason === root.reasonPkgbuildDiff;
    }
    function _needsInteractive(nameOrItem) {
        var n = (typeof nameOrItem === "string") ? nameOrItem : ((nameOrItem && nameOrItem.name) || "");
        return root.unresolvedFailures.some(function (f) {
            return f.name === n && root._reasonNeedsInteractive(f.reason);
        });
    }
    // Only SPECIFIC, diagnosable causes are actionable per-package failures that
    // deserve the persistent red "failed" flag: a build error, a changed PKGBUILD,
    // or a dependency conflict. A generic "Transaction failed" / "Update failed" /
    // "Did not apply" means an Update All aborted and the package simply didn't
    // apply — it's still pending (already shown in the list), so it's advisory,
    // not a failure. Advisory records still live in the history; they just don't
    // flag packages or inflate the count/banner/notifications.
    function _isActionableFailure(reason) {
        return reason === "Build failed"
            || reason === root.reasonPkgbuildDiff
            || reason === root.reasonDepConflict;
    }

    // Durable, self-kept log of failed updates. pacman.log only records
    // SUCCESSFUL transactions, so failures leave no trace there — we persist our
    // own list (pruned to failureHistoryDays) and merge it into the history view.
    // Entries: {when, name, source, oldVersion, newVersion, reason}. `when` is
    // stored in pacman.log's stamp format so both sort/format the same way.
    property var failureHistory: []

    // Current local time as "YYYY-MM-DDTHH:MM:SS±ZZZZ" (matches pacman.log).
    function _nowStamp() {
        var d = new Date();
        function p(n) { return (n < 10 ? "0" : "") + n; }
        var off = -d.getTimezoneOffset();        // minutes east of UTC
        var s = off >= 0 ? "+" : "-";
        var a = Math.abs(off);
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
            + "T" + p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
            + s + p(Math.floor(a / 60)) + p(a % 60);
    }
    // Parse either stamp format to epoch ms. JS Date rejects a colon-less TZ
    // offset ("-0400"), so splice a colon in before parsing.
    function _stampToEpoch(s) {
        var fixed = String(s).replace(/([+\-]\d{2})(\d{2})$/, "$1:$2");
        var t = Date.parse(fixed);
        return isNaN(t) ? 0 : t;
    }
    function _pruneFailureHistory(list) {
        // Bound 1 — age: drop entries older than the day limit.
        var cutoff = Date.now() - root.failureHistoryDays * 86400000;
        var kept = (list || []).filter(function (e) { return root._stampToEpoch(e.when) >= cutoff; });
        // Bound 2 — size (OR'd with age): entries are newest-first, so accumulate
        // from the front and drop the oldest once the serialized history would
        // exceed the megabyte budget. Always keep at least the newest entry.
        var maxBytes = root.failureHistoryMaxMB * 1048576;
        if (maxBytes > 0 && kept.length > 1) {
            var total = 0;
            var out = [];
            for (var i = 0; i < kept.length; i++) {
                var sz = JSON.stringify(kept[i]).length + 1; // +1 ≈ array separator
                if (out.length > 0 && total + sz > maxBytes)
                    break;
                total += sz;
                out.push(kept[i]);
            }
            kept = out;
        }
        return kept;
    }
    function loadFailureHistory() {
        if (!(pluginService && pluginService.loadPluginState))
            return;
        var raw = pluginService.loadPluginState(pluginId, "failureHistory", "[]");
        try {
            root.failureHistory = _pruneFailureHistory(JSON.parse(raw));
        } catch (e) {
            root.failureHistory = [];
        }
        _mergeAiSidecar();
    }
    // Restore everything persisted in plugin state (failure history, failed
    // flags, last-run summary). The control-center widget is a SEPARATE plugin
    // instance whose pluginService is often not wired for state reads — so when
    // pluginService is unavailable we fall back to reading the on-disk state
    // file directly via a Process (the same approach loadHistory uses for
    // pacman.log). Without this the CC history shows no failures.
    readonly property string _statePath: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state"))
        + "/DankMaterialShell/plugins/shellyUpdater_state.json"
    // Per-entry patches are stored in a small append-only JSONL sidecar (one
    // {name,when, ai?/resolved?/dismissed?} record per line) rather than the main
    // state, so they persist even when written from the control-center instance
    // (which has no pluginService to savePluginState with). Both instances write
    // it via sh/printf and merge it into failureHistory on load. Fields are
    // applied last-wins per (name,when), independently of each other, so an AI
    // answer and a later dismiss on the same failure both stick.
    readonly property string _aiSidecarPath: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state"))
        + "/DankMaterialShell/plugins/shellyUpdater_ai.jsonl"
    function _mergeAiSidecar() {
        aiSidecarReadProc.running = true;
    }
    // Append one patch record for a failure entry (CC-safe: sh/printf, value as
    // argv so no shell escaping). patch = { ai?, resolved?, dismissed? }.
    function _writeFailurePatch(name, when, patch) {
        var rec = JSON.stringify(Object.assign({ name: name, when: when }, patch));
        aiSidecarWriteProc.command = ["sh", "-c", "printf '%s\\n' \"$1\" >> \"$2\"", "shelly-ai", rec, root._aiSidecarPath];
        aiSidecarWriteProc.running = true;
    }
    Process {
        id: aiSidecarReadProc
        command: ["cat", root._aiSidecarPath]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (text || "").split("\n");
                // Accumulate patches per (namewhen), later fields win.
                var patches = {};
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i].trim();
                    if (!ln) continue;
                    var o;
                    try { o = JSON.parse(ln); } catch (e) { continue; }
                    if (!o || o.name === undefined) continue;
                    var k = o.name + "" + o.when;
                    if (!patches[k]) patches[k] = {};
                    if (o.ai !== undefined) patches[k].ai = o.ai;
                    if (o.resolved !== undefined) patches[k].resolved = o.resolved;
                    if (o.dismissed !== undefined) patches[k].dismissed = o.dismissed;
                    if (o.aiChat !== undefined) patches[k].aiChat = o.aiChat;
                }
                var list = root.failureHistory.slice();
                var changed = false;
                for (var j = 0; j < list.length; j++) {
                    var p = patches[list[j].name + "" + list[j].when];
                    if (!p) continue;
                    var upd = null;
                    ["ai", "resolved", "dismissed"].forEach(function (fld) {
                        if (p[fld] !== undefined && list[j][fld] !== p[fld]) {
                            if (!upd) upd = JSON.parse(JSON.stringify(list[j]));
                            upd[fld] = p[fld];
                        }
                    });
                    // aiChat is an array → compare by value to avoid churn.
                    if (p.aiChat !== undefined && JSON.stringify(list[j].aiChat) !== JSON.stringify(p.aiChat)) {
                        if (!upd) upd = JSON.parse(JSON.stringify(list[j]));
                        upd.aiChat = p.aiChat;
                    }
                    if (upd) { list[j] = upd; changed = true; }
                }
                if (changed)
                    root.failureHistory = list;
            }
        }
        stderr: StdioCollector { onStreamFinished: {} }
    }
    Process { id: aiSidecarWriteProc }
    // Latest failureHistory entry for a package (newest-first list → first hit).
    function _latestFailure(name) {
        for (var i = 0; i < root.failureHistory.length; i++)
            if (root.failureHistory[i].name === name)
                return root.failureHistory[i];
        return null;
    }
    // User acknowledges a failure: mark its latest record dismissed (in memory +
    // sidecar) so it drops out of the unresolved surfacing but stays in history.
    function dismissFailure(name) {
        var e = _latestFailure(name);
        if (!e) return;
        var list = root.failureHistory.slice();
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === e.name && list[i].when === e.when) {
                var upd = JSON.parse(JSON.stringify(list[i]));
                upd.dismissed = true;
                list[i] = upd;
                break;
            }
        }
        root.failureHistory = list;
        _writeFailurePatch(e.name, e.when, { dismissed: true });
    }
    // Mark packages that were attempted in the last run but did NOT fail as
    // resolved — the only reliable "it succeeded" signal for -git/devel packages,
    // which stay perpetually "pending" even after a good build.
    function _resolveSucceeded(succeededNames) {
        if (!succeededNames || succeededNames.length === 0) return;
        var list = root.failureHistory.slice();
        var changed = false;
        for (var n = 0; n < succeededNames.length; n++) {
            var name = succeededNames[n];
            for (var i = 0; i < list.length; i++) {
                if (list[i].name === name) { // latest record for this name
                    if (!list[i].resolved) {
                        var upd = JSON.parse(JSON.stringify(list[i]));
                        upd.resolved = true;
                        list[i] = upd;
                        changed = true;
                        _writeFailurePatch(list[i].name, list[i].when, { resolved: true });
                    }
                    break;
                }
            }
        }
        if (changed)
            root.failureHistory = list;
    }
    function _loadPersistedState() {
        _ensureSettings(); // settings fall back to the file too (CC instance)
        if (pluginService && pluginService.loadPluginState) {
            loadFailureHistory();
            try {
                root.failedPackages = JSON.parse(pluginService.loadPluginState(pluginId, "failedPackages", "[]"));
            } catch (e) {}
            try {
                root.lastRunSummary = JSON.parse(pluginService.loadPluginState(pluginId, "lastRunSummary", "null"));
            } catch (e2) {}
            try {
                root.newsSeen = JSON.parse(pluginService.loadPluginState(pluginId, "newsSeen", "{}")) || {};
                root.newsInit = pluginService.loadPluginState(pluginId, "newsInit", "false") === "true";
            } catch (e3) {}
        }
        // Fallback (also when the pluginService store came back empty, as it can
        // for the control-center instance): read the on-disk state file. Cheap
        // (one cat) and only reached when we have no failures in memory.
        if (root.failureHistory.length === 0)
            stateFileProc.running = true;
    }
    // Values in the state file are JSON strings (double-encoded), so each is
    // parsed twice.
    function _decodeStateValue(v) {
        try { return typeof v === "string" ? JSON.parse(v) : v; } catch (e) { return null; }
    }
    Process {
        id: stateFileProc
        command: ["cat", root._statePath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text || "{}");
                    var fh = root._decodeStateValue(d.failureHistory);
                    if (Array.isArray(fh))
                        root.failureHistory = root._pruneFailureHistory(fh);
                    var fp = root._decodeStateValue(d.failedPackages);
                    if (Array.isArray(fp))
                        root.failedPackages = fp;
                    var lrs = root._decodeStateValue(d.lastRunSummary);
                    if (lrs)
                        root.lastRunSummary = lrs;
                    root._mergeAiSidecar();
                } catch (e) {}
            }
        }
        stderr: StdioCollector { onStreamFinished: {} }
    }
    // Tail of the captured (ANSI-stripped) session log, bounded so the state
    // file stays small. Stored per failure so the detail view can show why it
    // failed even long after the live log ($XDG_RUNTIME_DIR) is gone.
    function _logExcerpt(clean) {
        if (!clean)
            return "";
        var lines = String(clean).split("\n");
        while (lines.length && lines[lines.length - 1].trim() === "")
            lines.pop();
        var tail = lines.slice(Math.max(0, lines.length - 60)).join("\n");
        if (tail.length > 4000)
            tail = "…\n" + tail.slice(tail.length - 4000);
        return tail;
    }
    // Append the just-detected failures (with version/source resolved from the
    // still-pending update list) and persist + broadcast the pruned log.
    // reasonByName overrides `reason` for specific packages (mixed-cause runs).
    function _recordFailures(failedNames, reason, cleanLog, reasonByName) {
        if (!failedNames || failedNames.length === 0)
            return;
        var pool = root.pacmanUpdates.concat(root.aurUpdates).concat(root.flatpakUpdates).concat(root.appimageUpdates);
        var byName = {};
        for (var i = 0; i < pool.length; i++)
            byName[pool[i].name] = pool[i];
        var stamp = _nowStamp();
        var excerpt = _logExcerpt(cleanLog);
        var additions = [];
        for (var j = 0; j < failedNames.length; j++) {
            var it = byName[failedNames[j]] || {};
            additions.push({
                when: stamp,
                name: failedNames[j],
                source: it.source || "pacman",
                oldVersion: it.oldVersion || "",
                newVersion: it.newVersion || "",
                reason: (reasonByName && reasonByName[failedNames[j]]) || reason || "",
                log: excerpt
            });
        }
        root.failureHistory = _pruneFailureHistory(additions.concat(root.failureHistory));
        if (pluginService && pluginService.savePluginState)
            pluginService.savePluginState(pluginId, "failureHistory", JSON.stringify(root.failureHistory));
    }

    // The framework rebinds the popout height to the content's implicitHeight on
    // load, so we only need the width; content sizes the popout in both modes.
    popoutWidth: 460

    // Uniform inner padding for popout content + per-row height in the list.
    readonly property int popoutPad: Theme.spacingL
    readonly property int detailRowHeight: 62

    // =====================================================================
    // Update checking (chained per-source; stdout is clean JSON, stderr is
    // captured separately so Shelly's hook warnings don't corrupt parsing).
    // =====================================================================
    property var _checkQueue: []
    property string _currentSrc: ""

    // Shelly races on its ~/.cache/Shelly/db/local rebuild and crashes when run
    // concurrently (each monitor gets its own widget instance, so their checks
    // would otherwise overlap). Serialize every shelly call through one flock.
    readonly property string lockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shelly-updater.lock"
    function withLock(args) {
        return ["flock", "-w", "300", lockPath].concat(args);
    }

    // Captured output + exit code of the most recent terminal run (for failure
    // detection and the "View log" action).
    readonly property string logPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shelly-updater-last.log"
    readonly property string statusPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shelly-updater-last.status"
    // The update terminal is launched DETACHED (Quickshell.execDetached) so it
    // survives a DMS crash/restart. Since a detached process gives no exit
    // callback, the terminal writes this per-run token to donePath when it ends
    // (via a shell trap, so it fires on normal exit or window-close); the plugin
    // polls donePath and matches the token to know the run finished.
    readonly property string donePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shelly-updater-last.done"
    property double _runToken: 0
    property bool _awaitingTerminal: false
    // Consecutive completion-polls where the marker was absent AND nothing
    // related to the update was running — drives the watchdog that force-clears
    // a stuck isUpgrading if a terminal died without writing its marker.
    property int _doneIdleStreak: 0

    // Each monitor gets its own plugin instance with independent state. A local
    // refresh() only updates this instance; refreshAll() broadcasts to every
    // instance so all monitors re-check together (used after updates and manual
    // refreshes). The broadcast rides DMS's shared plugin-state change signal.
    property double _refreshToken: 0

    // Escape hatch for a wedged refresh/upgrade: clear every in-flight flag and
    // re-check from a clean slate — the practical equivalent of reloading the
    // plugin, without restarting DMS. (The stuck-terminal watchdog normally
    // prevents a wedge, but this is a guaranteed manual recovery.) NOTE: this
    // does NOT touch a terminal that may still be running — it only resets the
    // widget's own state; a genuinely in-progress build will be re-detected by
    // the busy probe on the re-check.
    function resetState() {
        isChecking = false;
        isUpgrading = false;
        _awaitingTerminal = false;
        _doneIdleStreak = 0;
        _awaitingUpgradeResult = false;
        _externalBusy = false;
        _probing = false;
        _checkQueue = [];
        _writeUpgradeBeat(0); // stop the cross-monitor "updating" spinner
        refreshAll();     // sync the other monitors' instances
        refresh(false);   // guarantee a local re-check (the CC instance gets no broadcast)
    }
    function refreshAll() {
        var token = Date.now();
        _refreshToken = token;
        if (pluginService && pluginService.savePluginState)
            pluginService.savePluginState(pluginId, "refreshToken", token);
        refresh(false);
    }

    // Shared "an update is running" state so every monitor's widget animates
    // while any instance is upgrading. The upgrading instance writes a heartbeat
    // timestamp; others treat it as active only if fresh (self-heals if the
    // upgrading instance dies — the spinner stops instead of sticking forever).
    readonly property int _beatIntervalMs: 12000
    readonly property int _beatStaleMs: 40000
    property double _upgradeBeat: 0
    property bool remoteUpgrading: false

    function _evalRemoteUpgrading() {
        remoteUpgrading = _upgradeBeat > 0 && (Date.now() - _upgradeBeat) < _beatStaleMs;
    }
    function _writeUpgradeBeat(v) {
        _upgradeBeat = v;
        if (pluginService && pluginService.savePluginState)
            pluginService.savePluginState(pluginId, "upgradeBeat", v);
        _evalRemoteUpgrading();
    }

    Timer {
        // Owner heartbeat while this instance is running an upgrade.
        interval: root._beatIntervalMs
        repeat: true
        running: root.isUpgrading
        onTriggered: root._writeUpgradeBeat(Date.now())
    }
    Timer {
        // Freshness re-check so a stale heartbeat stops the animation; also
        // ticks _clock so the "checked Nm ago" label stays current.
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            root._evalRemoteUpgrading();
            root._clock++;
        }
    }

    Connections {
        target: root.pluginService
        function onPluginStateChanged(changedPluginId) {
            if (changedPluginId !== root.pluginId || !root.pluginService.loadPluginState)
                return;
            var token = root.pluginService.loadPluginState(root.pluginId, "refreshToken", 0);
            if (token !== root._refreshToken) {
                root._refreshToken = token;
                root.refresh(false);
            }
            root._upgradeBeat = root.pluginService.loadPluginState(root.pluginId, "upgradeBeat", 0);
            root._evalRemoteUpgrading();
            var fp = root.pluginService.loadPluginState(root.pluginId, "failedPackages", "[]");
            try {
                root.failedPackages = JSON.parse(fp);
            } catch (e) {
                // keep current value
            }
            var lrs = root.pluginService.loadPluginState(root.pluginId, "lastRunSummary", "null");
            try {
                root.lastRunSummary = JSON.parse(lrs);
            } catch (elrs) {
                // keep current value
            }
            var fh = root.pluginService.loadPluginState(root.pluginId, "failureHistory", "[]");
            try {
                root.failureHistory = root._pruneFailureHistory(JSON.parse(fh));
            } catch (e2) {
                // keep current value
            }
        }
    }

    // Was the in-flight check a background (auto/startup) one? Only those fire
    // update notifications — a manual refresh means the user is already looking.
    property bool _bgCheck: false

    // An external package operation (a terminal `yay`/`pacman -Syu`, or any
    // makepkg build) is in progress. `shelly aur list-updates` STALLS for the
    // entire build — measured ~30s+ during a big -git build — which would pin
    // isChecking=true and leave the pill spinning the whole time. So we probe
    // for an in-progress update before every check and, when one is running,
    // skip this cycle (keep current data, no spinner) and re-probe on a short
    // timer; the moment the build finishes the retry runs a real check.
    property bool _externalBusy: false
    property bool _probing: false
    property bool _pendingBg: false

    function refresh(isBackground) {
        if (isChecking || isUpgrading || _probing)
            return;
        _pendingBg = isBackground === true;
        _probing = true;
        busyProbe.running = true;
    }

    // busyProbe result: `busy` = a pacman transaction (db.lck) or a makepkg /
    // pacman process is running right now.
    function _onBusyProbe(busy) {
        if (!_probing)
            return; // already handled (stdout + onExited can both fire)
        _probing = false;
        if (busy) {
            _externalBusy = true; // busyRetry timer polls until it clears
            return;
        }
        _externalBusy = false;
        _doRefresh(_pendingBg);
    }

    function _doRefresh(isBackground) {
        if (isChecking || isUpgrading)
            return;
        // Old shelly → every call breaks. Surface once, skip the broken checks.
        if (shellyUnsupported) {
            hasError = true;
            errorMessage = "Requires Shelly v3 or newer (found " + shellyVersionRaw + "). Update the shelly package.";
            return;
        }
        isChecking = true;
        _bgCheck = isBackground === true;
        if (isBackground !== true)
            newsProc.running = true; // refresh Arch news on user-initiated checks only
        hasError = false;
        errorMessage = "";
        pacmanUpdates = [];
        aurUpdates = [];
        flatpakUpdates = [];
        appimageUpdates = [];
        loadIgnored();
        // Shelly v3 grammar: `list-updates <type> --json` (was `<type> list-updates`).
        // Kept per-backend (not the combined `list-updates all`) so the enable
        // flags still skip the slow AUR RPC / flatpak calls when disabled.
        var q = [{ src: "pacman", cmd: ["shelly", "list-updates", "standard", "--json"] }];
        if (enableAur)
            q.push({ src: "aur", cmd: ["shelly", "list-updates", "aur", "--json"] });
        if (enableFlatpak)
            q.push({ src: "flatpak", cmd: ["shelly", "list-updates", "flatpak", "--json"] });
        if (enableAppimage)
            q.push({ src: "appimage", cmd: ["shelly", "list-updates", "appimage", "--json"] });
        _checkQueue = q;
        _runNextCheck();
    }

    // Cheap "is a system update running?" probe. db.lck covers an active
    // pacman/yay transaction; `pgrep -x makepkg` covers the (long) AUR build
    // phase, which holds no db lock; `pgrep -x pacman` covers a bare -Sy sync.
    Process {
        id: busyProbe
        command: ["sh", "-c",
            "if [ -e /var/lib/pacman/db.lck ] || pgrep -x makepkg >/dev/null 2>&1 || pgrep -x pacman >/dev/null 2>&1; then echo busy; else echo free; fi"]
        stdout: StdioCollector {
            onStreamFinished: root._onBusyProbe((text || "").trim() === "busy")
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
        // Fallback: if the probe couldn't produce output, don't get wedged —
        // proceed as if free (the check itself will just run as before).
        onExited: root._onBusyProbe(false)
    }

    // While an external update is running, re-probe periodically so the widget
    // refreshes on its own shortly after the build/transaction finishes.
    Timer {
        id: busyRetry
        interval: 15000
        repeat: true
        running: root._externalBusy
        onTriggered: root.refresh(root._pendingBg)
    }

    function _runNextCheck() {
        if (_checkQueue.length === 0) {
            isChecking = false;
            lastChecked = Date.now();
            if (_awaitingUpgradeResult) {
                _computeFailed();
                _awaitingUpgradeResult = false;
            }
            if (_bgCheck) {
                _maybeNotify();
                _maybeNotifyFailuresRepeat();
            }
            return;
        }
        var job = _checkQueue.shift();
        _currentSrc = job.src;
        checkProc.command = withLock(job.cmd);
        checkProc.running = true;
    }

    // Normalise one raw Shelly record into a common shape.
    function _normalize(o, src) {
        var name = o.Name || o.name || o.Application || o.AppId || o.Id || "";
        var id = o.Application || o.AppId || o.Id || o.PackageBase || o.id || name;
        var oldV = o.CurrentVersion || o.OldVersion || o.Version || o.currentVersion || "";
        var newV = o.NewVersion || o.newVersion || o.Version || "";
        var desc = o.Description || o.description || "";
        var repo = o.Repository || o.repository || o.Origin || o.origin || "";
        return {
            name: name,
            id: id,
            oldVersion: oldV,
            newVersion: newV,
            description: desc,
            repository: repo,
            source: src,
            // Size fields (present on ALPM list-updates records; 0/absent
            // elsewhere). Kept so the header can total them and the pacman
            // detail view can render without a second CLI round-trip.
            downloadSize: o.DownloadSize !== undefined ? o.DownloadSize : (o.downloadSize || 0),
            installedSize: o.InstalledSize !== undefined ? o.InstalledSize : (o.installedSize || 0),
            sizeDifference: o.SizeDifference !== undefined ? o.SizeDifference : (o.sizeDifference || 0),
            // Full original record — the ALPM list already carries Depends,
            // Licenses, Url, etc., so the detail panel can show instantly.
            raw: o
        };
    }

    function _parseInto(src, text) {
        var trimmed = (text || "").trim();
        if (trimmed.length === 0)
            return [];
        var data = JSON.parse(trimmed);
        var arr = Array.isArray(data) ? data : (data.Packages || []);
        var out = [];
        for (var i = 0; i < arr.length; i++)
            out.push(_normalize(arr[i], src));
        return out;
    }

    Process {
        id: checkProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = root._parseInto(root._currentSrc, text);
                    if (root._currentSrc === "pacman")
                        root.pacmanUpdates = parsed;
                    else if (root._currentSrc === "aur")
                        root.aurUpdates = parsed;
                    else if (root._currentSrc === "flatpak")
                        root.flatpakUpdates = parsed;
                    else if (root._currentSrc === "appimage")
                        root.appimageUpdates = parsed;
                } catch (e) {
                    root.hasError = true;
                    root.errorMessage = "Failed to parse " + root._currentSrc + " output: " + String(e);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                // Shelly emits benign warnings to stderr; only treat as an
                // error if the process also produced no usable data.
                if (text && text.toLowerCase().indexOf("error") !== -1) {
                    root.errorMessage = String(text).trim();
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && !root.hasError) {
                root.hasError = true;
                if (!root.errorMessage)
                    root.errorMessage = "shelly " + root._currentSrc + " exited with code " + exitCode;
            }
            root._runNextCheck();
        }
    }

    // =====================================================================
    // Running updates
    // =====================================================================
    // touchesKernel: when true and "always confirm kernel updates" is enabled,
    // the interactive prompt is forced even if global confirmations are off.
    function runInTerminal(shellyArgs, title, touchesKernel, forceInteractive) {
        if (isUpgrading)
            return;
        var forceConfirm = alwaysConfirmKernel && touchesKernel === true;
        // forceInteractive (the "run interactive update" buttons) never appends
        // --no-confirm, so Shelly can prompt to review/accept a changed PKGBUILD
        // even when global confirmations are off.
        var full = (!confirmations && !forceConfirm && forceInteractive !== true) ? shellyArgs.concat(["--no-confirm"]) : shellyArgs;
        // flock only wraps the shelly command (released before the read prompt),
        // so background checks on other monitors wait rather than colliding.
        // The resource prefix (nice/ionice/job-limit) is inherited by every
        // build child that shelly spawns, keeping the desktop responsive.
        var cmd = "flock -w 300 " + lockPath + " " + _resourcesPrefix() + full.join(" ");
        // When failure detection is on, record the session with `script` (a real
        // pty, so the run stays fully interactive — sudo/confirm prompts and
        // progress bars still work) and stash the command's exit code. When off,
        // run the command bare (original behaviour, no wrapper).
        var work = detectFailedUpdates
            ? "script -qe -c " + _shq(cmd) + " " + _shq(logPath) + "; echo $? > " + _shq(statusPath)
            : cmd;
        // Signal completion via a marker file since a detached process has no
        // exit callback. A trap writes the token on normal exit AND on
        // window-close signals, so the poller never hangs.
        _runToken = Date.now();
        var doneCmd = "echo " + _runToken + " > " + _shq(donePath);
        // With closeTerminalOnDone the window exits as soon as the run finishes
        // (the EXIT trap then fires the marker). Otherwise the window holds open
        // on a "Press Enter" prompt — but we emit the marker RIGHT AFTER the work
        // finishes (status + log are already written by then), so the counts
        // refresh immediately instead of waiting for the user to close the
        // window. The EXIT trap remains a fallback for a window closed mid-run.
        // Interactive runs (the per-package "run in terminal" buttons) always hold
        // the window open on a "Press Enter" prompt so the user can read whatever
        // output was produced, regardless of the global closeTerminalOnDone setting.
        var keepOpen = !closeTerminalOnDone || forceInteractive === true;
        var body = keepOpen
            ? work + "; " + doneCmd + "; echo; echo '── " + (title || "Done") + " ── Press Enter to close'; read _"
            : work;
        var inner = "trap " + _shq(doneCmd) + " EXIT; trap exit HUP TERM INT; " + body;
        Quickshell.execDetached(_launchArgv(inner));
        isUpgrading = true;
        _writeUpgradeBeat(Date.now()); // broadcast "updating" to all monitors
        _doneIdleStreak = 0; // reset the stuck-terminal watchdog for this run
        _awaitingTerminal = true; // start polling for the completion marker
    }

    // Build the argv for the update terminal. With surviveRestart the terminal
    // is placed in its OWN systemd scope (its own cgroup, a sibling of
    // dms.service) so `dms restart` — which kills the dms.service cgroup —
    // leaves it running. Detach (execDetached) alone is NOT enough: the process
    // is reparented but stays in dms.service's cgroup and dies with the service.
    function _launchArgv(inner) {
        var words = terminal.split(" ").filter(function (s) { return s.length; });
        var base = (words[0] || "").split("/").pop();
        // Single-instance terminals hand the window to a shared process (which
        // may live under dms.service); force a standalone instance so the window
        // is its own process inside our scope. ghostty is the common one.
        var standalone = [];
        if (base === "ghostty")
            standalone = ["--gtk-single-instance=false"];
        var termArgv = words.concat(standalone).concat(["-e", "sh", "-c", inner]);
        if (!surviveRestart)
            return termArgv;
        var pfx = _survivePrefix();
        return pfx.length ? pfx.concat(termArgv) : termArgv;
    }

    // Launcher prefix that puts the terminal in its own systemd scope. Honors a
    // user/DMS-configured launch prefix, else defaults to systemd-run.
    function _survivePrefix() {
        var p = "";
        if (typeof SettingsData !== "undefined" && SettingsData.launchPrefix)
            p = String(SettingsData.launchPrefix).trim();
        if (!p)
            p = Quickshell.env("DMS_DEFAULT_LAUNCH_PREFIX") || "";
        if (!p)
            p = "systemd-run --user --scope --quiet --";
        return p.split(" ").filter(function (s) { return s.length; });
    }

    // Single-quote a string for safe embedding in the sh -c command line.
    function _shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // Command prefix that throttles the upgrade so large builds don't peg the
    // CPU. `nice`/`ionice` lower scheduling+IO priority (build yields to the
    // desktop; nearly free when the box is otherwise idle) and the -j env vars
    // cap parallel build jobs. Both are inherited by shelly's makepkg children;
    // env vars are best-effort (a PKGBUILD/makepkg.conf that hard-sets MAKEFLAGS
    // wins, and ninja has no jobs env). Empty string when disabled → runs
    // exactly as before. Values have no spaces, so no quoting is needed.
    function _resourcesPrefix() {
        if (!limitBuildResources)
            return "";
        var parts = [];
        if (lowerPriority)
            parts = parts.concat(["nice", "-n", "19", "ionice", "-c", "3"]);
        if (maxBuildJobs > 0) {
            var n = String(maxBuildJobs);
            parts = parts.concat(["env", "MAKEFLAGS=-j" + n, "CARGO_BUILD_JOBS=" + n, "CMAKE_BUILD_PARALLEL_LEVEL=" + n]);
        }
        return parts.length ? parts.join(" ") + " " : "";
    }

    // Record which packages an upgrade is attempting, so we can tell afterward
    // which ones didn't apply. Clears any prior failure flags for a fresh run.
    // No-op when failure detection is disabled.
    function _beginUpgrade(names) {
        if (!detectFailedUpdates)
            return;
        root.attemptedUpdate = names || [];
        root._awaitingUpgradeResult = true;
        root.failedPackages = [];
        root._broadcastFailed();
    }

    function _namesOf(items) {
        return items.map(function (i) { return i.name; });
    }

    function updateAll() {
        // Shelly v3: `upgrade all` (was `upgrade-all`); --no-* still valid here.
        var args = ["shelly", "upgrade", "all"];
        if (!enableAur) args.push("--no-aur");
        if (!enableFlatpak) args.push("--no-flatpak");
        if (!enableAppimage) args.push("--no-appimage");
        _beginUpgrade(_namesOf(allShownItems()));
        runInTerminal(args, "Update All", hasKernelUpdate);
    }
    function updatePacman() {
        _beginUpgrade(_namesOf(pacmanUpdatesShown));
        runInTerminal(["shelly", "upgrade", "standard"], "System Packages", hasKernelUpdate);
    }
    function updateAur() {
        _beginUpgrade(_namesOf(aurUpdatesShown));
        runInTerminal(["shelly", "upgrade", "aur"], "AUR", false);
    }
    function updateFlatpak() {
        _beginUpgrade(_namesOf(flatpakUpdates));
        runInTerminal(["shelly", "upgrade", "flatpak"], "Flatpak", false);
    }
    function updateAppimage() {
        _beginUpgrade(_namesOf(appimageUpdates));
        runInTerminal(["shelly", "upgrade", "appimage"], "AppImage", false);
    }

    function updateOne(item) {
        // Shelly v3 grammar: `update <type> <name>` (was `<type> update <name>`).
        var args;
        if (item.source === "pacman")
            args = ["shelly", "update", "standard", item.name];
        else if (item.source === "aur")
            args = ["shelly", "update", "aur", item.name];
        else if (item.source === "flatpak")
            args = ["shelly", "update", "flatpak", item.id];
        else if (item.source === "appimage")
            args = ["shelly", "upgrade", "appimage"];
        else
            return;
        _beginUpgrade([item.name]);
        runInTerminal(args, item.name, item.source === "pacman" && _isKernel(item));
    }

    // Re-run a single package's update INTERACTIVELY (visible terminal, never
    // --no-confirm) so the user can accept a changed PKGBUILD / review prompt
    // that a non-interactive upgrade silently skipped. Accepts an updates item
    // or a failure entry — both carry {name, source} (flatpak also {id}).
    function runInteractiveUpdate(item) {
        if (!item || !item.name)
            return;
        var args;
        if (item.source === "aur")
            args = ["shelly", "update", "aur", item.name];
        else if (item.source === "pacman")
            args = ["shelly", "update", "standard", item.name];
        else if (item.source === "flatpak")
            args = ["shelly", "update", "flatpak", item.id || item.name];
        else
            return;
        _beginUpgrade([item.name]);
        runInTerminal(args, "Update " + item.name, false, true); // forceInteractive
    }

    // Downgrade a standard package (Shelly lists installable older versions to
    // pick). Shelly v3 removed interactive AUR version selection — `install aur
    // -v` now requires an explicit git commit — so AUR downgrade is disabled
    // until the commit-picker lands (2.1.0); the button is hidden for AUR.
    function downgradeOne(item) {
        if (!item || item.source !== "pacman")
            return;
        runInTerminal(["shelly", "downgrade", item.name], "Downgrade " + item.name, _isKernel(item));
    }

    // Maintenance — Shelly v3: `cache-clean` → `purify standard -c` (retain
    // default 3 versions); bare `purify` → `purify standard -o` (include orphans).
    function cleanCache() { runInTerminal(["shelly", "purify", "standard", "-c"], "Clean Package Cache", false); }
    function removeOrphans() { runInTerminal(["shelly", "purify", "standard", "-o"], "Remove Orphans", false); }

    // Poll the detached terminal's completion marker. `cat` prints the token the
    // trap wrote; matching it to this run's token means the terminal finished.
    Timer {
        id: donePoller
        interval: 3000
        repeat: true
        running: root._awaitingTerminal
        onTriggered: doneCheckProc.running = true
    }
    Process {
        id: doneCheckProc
        // Read the marker AND probe whether the update pipeline is still alive.
        // `script`/`flock` wrap the whole session; `shelly` is alive even while
        // sitting at an interactive prompt; makepkg/pacman/db.lck cover the build
        // and transaction. Tab-separated: "<marker>\t<live|idle>".
        command: ["sh", "-c",
            "m=$(cat " + _shq(root.donePath) + " 2>/dev/null); " +
            "if pgrep -x script >/dev/null 2>&1 || pgrep -x flock >/dev/null 2>&1 || pgrep -x shelly >/dev/null 2>&1 || pgrep -x makepkg >/dev/null 2>&1 || pgrep -x pacman >/dev/null 2>&1 || [ -e /var/lib/pacman/db.lck ]; then a=live; else a=idle; fi; " +
            "printf '%s\\t%s' \"$m\" \"$a\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = String(text || "").split("\t");
                var marker = (parts[0] || "").trim();
                var live = (parts[1] || "").trim() === "live";
                if (marker === String(root._runToken)) {
                    root._doneIdleStreak = 0;
                    root._awaitingTerminal = false;
                    root._onTerminalDone();
                    return;
                }
                // Watchdog: the marker never arrived (terminal died/failed to
                // launch without writing it). If nothing update-related is
                // running for a few consecutive polls (~9s), treat the run as
                // finished so isUpgrading can't stay stuck until a DMS restart.
                // Stays armed through interactive review because `shelly` is
                // alive then (→ live → streak resets).
                if (live) {
                    root._doneIdleStreak = 0;
                } else if (++root._doneIdleStreak >= 3) {
                    root._doneIdleStreak = 0;
                    root._awaitingTerminal = false;
                    root._onTerminalDone();
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
    }

    // Runs when the detached update terminal finishes (marker detected). Mirrors
    // what the old termProc.onExited did.
    function _onTerminalDone() {
        isUpgrading = false;
        _writeUpgradeBeat(0); // stop the "updating" animation everywhere
        if (_awaitingUpgradeResult)
            statusProc.running = true; // read exit code + log, then re-check
        else
            refreshAll();
    }

    // Reads the exit code the terminal stashed, then reads the captured log,
    // then kicks off the re-check. A missing/garbled status is treated as 0.
    Process {
        id: statusProc
        command: ["cat", root.statusPath]
        stdout: StdioCollector {
            onStreamFinished: {
                var n = parseInt((text || "").trim(), 10);
                root._lastUpgradeExit = isNaN(n) ? 0 : n;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
        onExited: catLogProc.running = true
    }
    Process {
        id: catLogProc
        command: ["cat", root.logPath]
        stdout: StdioCollector {
            onStreamFinished: root._lastLogText = text || ""
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
        onExited: root.refreshAll()
    }

    // Strip terminal escape sequences from a captured `script` log so it can be
    // scanned as plain text.
    function _stripAnsi(s) {
        return String(s)
            .replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "")        // CSI (colors, cursor)
            .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "") // OSC
            .replace(/\x1b[=>@-Z\\-_]/g, "")                   // other escapes
            .replace(/[\r\x07]/g, "");
    }

    // Determine which packages failed from the captured log. Shelly can't be
    // trusted here: it exits 0 even when a build fails OR the whole transaction
    // aborts ("Upgrade failed"), and devel/-git packages always re-appear as
    // "pending" regardless of success — so neither the exit code nor a plain
    // still-pending diff is reliable on its own.
    //
    //   1. Per-package build failures print "· (n/m) failed <pkg>" — pin those
    //      exactly (correctly leaves succeeded -git packages unflagged).
    //   2. AUR builds cancelled because the PKGBUILD changed print "Cancelled
    //      because of pkgbuild diff." but still end in "Update complete." with
    //      exit 0 (with --no-confirm Shelly can't prompt for review, so it
    //      skips the build and reports success). Attribute each cancel marker
    //      to the nearest preceding ":: (n/m) downloading <pkg>" line.
    //   3. A transaction/hard-error marker (no per-package line) means the run
    //      failed but didn't name a culprit — flag every attempted package
    //      still pending (incl. devel, since nothing applied).
    readonly property string reasonPkgbuildDiff: "PKGBUILD changed — review required"
    readonly property string reasonDepConflict: "Dependency conflict — coordinated rebuild needed"
    function _computeFailed() {
        var clean = _stripAnsi(root._lastLogText);
        var names = {};

        var re = /::\s*\(\d+\/\d+\)\s+failed\s+([A-Za-z0-9@._+\-]+)/g;
        var m;
        while ((m = re.exec(clean)) !== null)
            names[m[1]] = true;
        var hasPerPkg = Object.keys(names).length > 0;

        var cancelled = {};
        var dlRe = /::\s*\(\d+\/\d+\)\s+downloading\s+([A-Za-z0-9@._+\-]+)/g;
        var dls = [];
        while ((m = dlRe.exec(clean)) !== null)
            dls.push({ idx: m.index, name: m[1] });
        var cancelRe = /cancelled because of pkgbuild diff/gi;
        while ((m = cancelRe.exec(clean)) !== null) {
            var who = "";
            for (var d = 0; d < dls.length && dls[d].idx < m.index; d++)
                who = dls[d].name;
            if (who)
                cancelled[who] = true;
        }

        var hardFail = /transaction failed|upgrade failed|==>\s*error:|\berror:\s|failed to (?:build|commit|prepare|install|synchronize)/i.test(clean);

        // A dependency/soname conflict: pacman refuses the transaction because an
        // upgrade needs a newer shared library than a held or AUR package provides
        // (e.g. the hypr* -git stack crossing a libhyprutils soname bump). Held
        // packages aren't upgraded but still constrain resolution, so the whole
        // group has to be rebuilt together. Label it distinctly so the failure
        // detail view can show targeted recovery guidance instead of a bare error.
        var depConflict = /breaks dependency/i.test(clean)
            && /could not satisfy dependencies|failed to prepare transaction/i.test(clean);

        if (!hasPerPkg && (hardFail || root._lastUpgradeExit !== 0)) {
            var shownNames = _namesOf(allShownItems());
            for (var i = 0; i < root.attemptedUpdate.length; i++) {
                var nm = root.attemptedUpdate[i];
                if (shownNames.indexOf(nm) !== -1)
                    names[nm] = true;
            }
        }

        var failed = [];
        var reasonByName = {};
        for (var k in names)
            failed.push(k);
        for (var c in cancelled) {
            if (!names[c])
                failed.push(c);
            reasonByName[c] = root.reasonPkgbuildDiff;
        }
        root.failedPackages = failed;
        var reason = hasPerPkg ? "Build failed"
            : (depConflict ? root.reasonDepConflict
            : (hardFail ? "Transaction failed"
            : (root._lastUpgradeExit !== 0 ? "Update failed" : "Did not apply")));
        _recordFailures(failed, reason, clean, reasonByName);
        // Anything we attempted that did NOT fail this run counts as succeeded —
        // mark those resolved so a prior failure clears (esp. -git/devel, which
        // stay perpetually pending and can't auto-resolve via the pending list).
        var failedSet = {};
        for (var fi = 0; fi < failed.length; fi++)
            failedSet[failed[fi]] = true;
        var succeeded = [];
        for (var ci = 0; ci < root.attemptedUpdate.length; ci++)
            if (!failedSet[root.attemptedUpdate[ci]])
                succeeded.push(root.attemptedUpdate[ci]);
        _resolveSucceeded(succeeded);
        // Record the run summary for the History menu label. attempted = what we
        // submitted; successful = attempted that didn't end up failed.
        var attempted = (root.attemptedUpdate || []).length;
        root.lastRunSummary = {
            when: _nowStamp(),
            attempted: attempted,
            failed: failed.length,
            successful: Math.max(0, attempted - failed.length)
        };
        root._broadcastFailed();
        _notifyFailures(failed);
    }
    function _broadcastFailed() {
        if (pluginService && pluginService.savePluginState) {
            pluginService.savePluginState(pluginId, "failedPackages", JSON.stringify(root.failedPackages));
            pluginService.savePluginState(pluginId, "lastRunSummary", JSON.stringify(root.lastRunSummary));
        }
    }

    function viewLastLog() {
        // ANSI-laden `script` capture renders correctly when cat'd to a TTY.
        var inner = "cat " + _shq(logPath) + "; echo; echo '── End of log ── Press Enter to close'; read _";
        logProc.command = terminal.split(" ").concat(["-e", "sh", "-c", inner]);
        logProc.running = true;
    }
    Process {
        id: logProc
    }

    // =====================================================================
    // Package detail (extended info for a single package)
    // =====================================================================
    function _fmtBytes(n) {
        n = Number(n) || 0;
        if (n <= 0)
            return "";
        var u = ["B", "KiB", "MiB", "GiB", "TiB"];
        var i = 0;
        var v = n;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? v.toFixed(0) : v.toFixed(v < 10 ? 2 : 1)) + " " + u[i];
    }

    // Accepts ISO strings ("2025-12-10T22:01:46") or epoch seconds (AUR uses
    // Unix timestamps). Returns "" for missing values so the row is skipped.
    function _fmtDate(s) {
        if (s === undefined || s === null || s === "")
            return "";
        var d;
        if (typeof s === "number")
            d = new Date(s * 1000);
        else {
            d = new Date(String(s));
            if (isNaN(d.getTime()))
                return String(s);
        }
        if (isNaN(d.getTime()))
            return String(s);
        return Qt.formatDateTime(d, "yyyy-MM-dd hh:mm");
    }

    function _fmtList(a) {
        if (a === undefined || a === null)
            return "";
        if (Array.isArray(a))
            return a.length ? a.join(", ") : "";
        return String(a);
    }

    // Fold a raw Shelly record (or the row itself, for sources we can't query)
    // into a flat label/value list, dropping empty fields.
    function _buildDetail(item, raw) {
        var fields = [];
        function add(label, val, mono, link) {
            var v = (val === undefined || val === null) ? "" : (typeof val === "string" ? val : String(val));
            if (v.trim() === "")
                return;
            fields.push({ label: label, value: v, mono: mono === true, link: link === true });
        }
        var verArrow = (item.oldVersion || "?") + "  →  " + (item.newVersion || "?");
        var desc = item.description || "";

        if (item.source === "pacman") {
            var d = raw || {};
            desc = d.Description || desc;
            add("Repository", d.Repository);
            add("Version", verArrow, true);
            add("Download size", root._fmtBytes(d.DownloadSize));
            add("Installed size", root._fmtBytes(d.InstalledSize));
            if (d.SizeDifference !== undefined && d.SizeDifference !== null && Number(d.SizeDifference) !== 0)
                add("Net change", root._fmtBytesSigned(d.SizeDifference));
            add("Build date", root._fmtDate(d.BuildDate));
            add("URL", d.Url, false, true);
            add("Licenses", root._fmtList(d.Licenses));
            add("Groups", root._fmtList(d.Groups));
            add("Provides", root._fmtList(d.Provides));
            add("Depends on", root._fmtList(d.Depends));
            add("Optional deps", root._fmtList(d.OptDepends));
            add("Conflicts", root._fmtList(d.Conflicts));
            add("Replaces", root._fmtList(d.Replaces));
            add("Required by", root._fmtList(d.RequiredBy));
        } else if (item.source === "aur") {
            var arr = Array.isArray(raw) ? raw : (raw && raw.Results ? raw.Results : []);
            var r = null;
            for (var i = 0; i < arr.length; i++) {
                if ((arr[i].Name || "") === item.name) {
                    r = arr[i];
                    break;
                }
            }
            r = r || (arr.length ? arr[0] : {});
            desc = r.Description || desc;
            add("Repository", "AUR");
            add("Version", verArrow, true);
            add("Maintainer", r.Maintainer);
            add("Votes", (r.NumVotes !== undefined && r.NumVotes !== null) ? r.NumVotes : "");
            add("Popularity", (r.Popularity !== undefined && r.Popularity !== null) ? Number(r.Popularity).toFixed(2) : "");
            add("Last modified", root._fmtDate(r.LastModified));
            add("First submitted", root._fmtDate(r.FirstSubmitted));
            add("URL", r.Url, false, true);
            add("Licenses", root._fmtList(r.License));
            add("Depends on", root._fmtList(r.Depends));
            add("Make deps", root._fmtList(r.MakeDepends));
            add("Optional deps", root._fmtList(r.OptDepends));
            add("Keywords", root._fmtList(r.Keywords));
            if (r.OutOfDate)
                add("Flagged out of date", root._fmtDate(r.OutOfDate));
        } else {
            add("Source", item.source);
            add("Version", verArrow, true);
            add("Repository", item.repository);
        }
        return { title: item.name, source: item.source, description: desc, fields: fields };
    }

    // Load a package's detail into shared state (no navigation) — used by both
    // the bar popout (openDetail) and the control-center detail sub-view.
    function loadDetail(item) {
        if (!item)
            return;
        root.detailItem = item;
        root.detailError = "";
        if (item.source === "pacman") {
            // The list record already carries almost everything — render at
            // once (no spinner), then quietly fetch the query for the one extra
            // field it lacks (build date). If that fails, we keep the seed.
            root.detailData = root._buildDetail(item, item.raw || null);
            root.detailLoading = false;
            detailProc.command = withLock(["shelly", "search", "standard", item.name, "--json"]);
            detailProc.running = true;
        } else if (item.source === "aur") {
            root.detailData = null;
            root.detailLoading = true;
            detailProc.command = withLock(["shelly", "search", "aur", item.name, "--json"]);
            detailProc.running = true;
        } else {
            root.detailData = root._buildDetail(item, null);
            root.detailLoading = false;
        }
    }

    function openDetail(item) {
        if (!item)
            return;
        loadDetail(item);
        root.popoutMode = "detail";
        if (!root.popoutOpen)
            triggerPopout();
    }

    function closeDetail() {
        root.popoutMode = "updates";
    }

    Process {
        id: detailProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var t = (text || "").trim();
                    var parsed = t.length ? JSON.parse(t) : null;
                    // pacman: merge query result over the list seed so both the
                    // size fields (from the list) and build date (from the
                    // query) survive. aur: parsed is the search-results array.
                    if (root.detailItem && root.detailItem.source === "pacman" && parsed && !Array.isArray(parsed))
                        parsed = Object.assign({}, root.detailItem.raw || {}, parsed);
                    root.detailData = root._buildDetail(root.detailItem, parsed);
                } catch (e) {
                    // A seeded pacman view stays usable; only surface if empty.
                    if (!root.detailData)
                        root.detailError = "Failed to load details: " + String(e);
                }
                root.detailLoading = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
        onExited: exitCode => {
            if (exitCode !== 0 && !root.detailData && !root.detailError)
                root.detailError = "shelly search exited with code " + exitCode;
            root.detailLoading = false;
        }
    }

    Process {
        id: uiProc
    }
    function openShellyUi() {
        uiProc.command = ["shelly-ui"];
        uiProc.running = true;
    }

    // Signed byte delta for the "net change" field ("+38.2 MiB" / "−12 MiB").
    function _fmtBytesSigned(n) {
        n = Number(n) || 0;
        if (n === 0)
            return "";
        return (n > 0 ? "+" : "−") + root._fmtBytes(Math.abs(n));
    }

    // =====================================================================
    // Held / ignored packages (shelly ignore list)
    // =====================================================================
    function loadIgnored() {
        // Shelly v3: `mark ignore -l/-a/-r` (was `ignore --list/--add/--remove`).
        // `-l -j` returns a bare JSON array of names.
        ignoreProc.command = withLock(["shelly", "mark", "ignore", "-l", "--json"]);
        ignoreProc.running = true;
    }
    function holdPackage(name) {
        if (!name)
            return;
        ignoreMutateProc.command = withLock(["shelly", "mark", "ignore", "-a", name, "-n"]);
        ignoreMutateProc.running = true;
    }
    function unholdPackage(name) {
        if (!name)
            return;
        ignoreMutateProc.command = withLock(["shelly", "mark", "ignore", "-r", name, "-n"]);
        ignoreMutateProc.running = true;
    }

    Process {
        id: ignoreProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var t = (text || "").trim();
                    var d = t.length ? JSON.parse(t) : [];
                    root.ignoredPackages = Array.isArray(d) ? d : (d.Packages || d.Ignored || []);
                } catch (e) {
                    root.ignoredPackages = [];
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
    }
    Process {
        id: ignoreMutateProc
        // A hold/unhold changes the actionable set on every monitor, so
        // broadcast a full re-check (which also reloads the ignore list).
        // Reload the list directly too, in case refresh() is guarded out by an
        // in-flight check — the held view/count should still update immediately.
        onExited: {
            root.loadIgnored();
            root.refreshAll();
        }
    }

    // =====================================================================
    // Update history (parsed from the ALPM log, which records every repo AND
    // AUR up/downgrade — Shelly installs AUR builds through pacman too. The log
    // is world-readable, so no sudo/shelly call is needed.)
    // =====================================================================
    property var historyItems: []          // [{when, action, name, oldVersion, newVersion}]
    property bool historyLoading: false
    readonly property int historyLimit: 300

    // Successful up/downgrades (from pacman.log) merged with our own failed-
    // update log, sorted newest-first. Failed rows carry action:"failed".
    readonly property var historyCombined: {
        var out = root.historyItems.slice();
        for (var i = 0; i < root.failureHistory.length; i++) {
            var f = root.failureHistory[i];
            out.push({
                when: f.when, action: "failed", name: f.name,
                oldVersion: f.oldVersion, newVersion: f.newVersion,
                source: f.source, reason: f.reason, log: f.log, ai: f.ai
            });
        }
        out.sort(function (a, b) { return root._stampToEpoch(b.when) - root._stampToEpoch(a.when); });
        return out;
    }

    function loadHistory() {
        historyLoading = true;
        // Only up/downgrades (version changes) — the "update" history — newest
        // last from grep; reversed to newest-first when parsed.
        historyProc.command = ["sh", "-c",
            "grep -E '\\] (upgraded|downgraded) ' /var/log/pacman.log 2>/dev/null | tail -n " + historyLimit];
        historyProc.running = true;
    }
    function openHistory() {
        _loadPersistedState();
        loadHistory();
        openMode("history");
    }

    // The failed-history entry the user clicked, shown in the faildetail view.
    property var failureDetail: null
    function openFailureDetail(entry) {
        if (!entry)
            return;
        root.aiError = "";
        root.failureDetail = entry;
        openMode("faildetail");
    }
    // One-click path to the last run's failures (banner button, notification
    // action): a single failure jumps straight to its detail view, several go
    // to the history list (failed rows at top by recency). History is loaded
    // either way so the detail view's back button lands somewhere populated.
    function openFailures(runAi) {
        _loadPersistedState();
        loadHistory();
        var entry = root.unresolvedFailures.length === 1 ? root.unresolvedFailures[0] : null;
        if (entry) {
            openFailureDetail(entry);
            if (runAi === true && root.aiReady && !entry.ai)
                requestAiSuggestion();
        } else {
            openMode("history");
        }
    }
    function closeFailureDetail() {
        openMode("history");
    }
    // "2026-07-06T22:30:54-0400" -> "2026-07-06 22:30" (avoids Date parsing of
    // the colon-less timezone, which some JS engines reject).
    function _fmtHistoryWhen(s) {
        var m = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/.exec(String(s));
        return m ? (m[1] + " " + m[2]) : String(s);
    }

    Process {
        id: historyProc
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [];
                var re = /^\[([^\]]+)\]\s+\[ALPM\]\s+(upgraded|downgraded)\s+(\S+)\s+\((.+?)\s+->\s+(.+?)\)\s*$/;
                var lines = (text || "").split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var m = re.exec(lines[i]);
                    if (m)
                        out.push({ when: m[1], action: m[2], name: m[3], oldVersion: m[4], newVersion: m[5] });
                }
                out.reverse(); // newest first
                root.historyItems = out;
                root.historyLoading = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
        onExited: root.historyLoading = false
    }

    // =====================================================================
    // Update notifications (background checks only, de-duplicated so multiple
    // monitors don't each fire — flock serializes the checks, so the first
    // instance to finish writes the signature and the rest see it and skip).
    // =====================================================================
    function _updateSignature(items) {
        var parts = [];
        for (var i = 0; i < items.length; i++)
            parts.push(items[i].source + ":" + items[i].name + "@" + items[i].newVersion);
        return parts.sort().join(",");
    }
    function _maybeNotify() {
        if (!notifyOnUpdates)
            return;
        var items = allShownItems();
        if (items.length < Math.max(1, notifyThreshold))
            return;
        var sig = _updateSignature(items);
        var last = (pluginService && pluginService.loadPluginState)
            ? pluginService.loadPluginState(pluginId, "notifiedSignature", "") : "";
        if (sig === last)
            return;
        if (pluginService && pluginService.savePluginState)
            pluginService.savePluginState(pluginId, "notifiedSignature", sig);
        var summary = items.length + (items.length === 1 ? " update available" : " updates available");
        var names = [];
        for (var i = 0; i < items.length && i < 8; i++)
            names.push(items[i].name);
        var body = names.join(", ") + (items.length > 8 ? " …" : "");
        notifyProc.command = ["notify-send", "-a", "Shelly Updater", "-i", "system-software-update", summary, body];
        notifyProc.running = true;
    }
    Process {
        id: notifyProc
    }

    // Failure notification — fired by the instance that ran the upgrade (so no
    // cross-monitor de-dup is needed). notify-send's -A flag makes it wait and
    // print the chosen action key, letting the user jump straight from the
    // notification to the failure details (optionally with the AI breakdown).
    function _sendFailureNotification(names, summary) {
        if (!names || names.length === 0)
            return;
        var body = names.slice(0, 8).join(", ") + (names.length > 8 ? " …" : "");
        var cmd = ["notify-send", "-a", "Shelly Updater", "-i", "dialog-error",
                   "-A", "details=View details"];
        if (aiReady)
            cmd.push("-A", "ai=Explain with AI");
        cmd.push(summary, body);
        failNotifyProc.command = cmd;
        failNotifyProc.running = true;
    }
    function _notifyFailures(failed) {
        if (!notifyOnFailures || !failed || failed.length === 0)
            return;
        // Only notify for actionable failures — a transaction abort flags every
        // pending package but is advisory, so it shouldn't fire "N updates failed".
        var actionable = root.unresolvedFailures.filter(function (f) {
            return failed.indexOf(f.name) !== -1;
        }).map(function (f) { return f.name; });
        if (actionable.length === 0)
            return;
        var summary = actionable.length === 1
            ? actionable[0] + " failed to update"
            : actionable.length + " updates failed";
        _sendFailureNotification(actionable, summary);
    }
    // Persistent reminder on background checks while failures remain unresolved.
    function _maybeNotifyFailuresRepeat() {
        if (!notifyOnFailures || !notifyFailuresRepeat)
            return;
        var uf = root.unresolvedFailures;
        if (uf.length === 0)
            return;
        var names = uf.map(function (f) { return f.name; });
        var summary = names.length === 1
            ? names[0] + " still needs attention"
            : names.length + " failed updates still need attention";
        _sendFailureNotification(names, summary);
    }
    Process {
        id: failNotifyProc
        stdout: StdioCollector {
            onStreamFinished: {
                var action = (text || "").trim();
                if (action === "details")
                    root.openFailures(false);
                else if (action === "ai")
                    root.openFailures(true);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
    }

    // =====================================================================
    // AI failure analysis. The configured command runs via sh with the prompt
    // passed as a positional arg and piped to its stdin — no temp files, no
    // shell-escaping of the prompt, no API keys handled by the plugin.
    // =====================================================================
    property bool aiLoading: false
    property string aiError: ""
    property string _aiStdout: ""
    property string _aiStderr: ""
    // Conversation state: "initial" = first suggestion (saved to entry.ai),
    // "followup" = a Check-result/free follow-up (appended to entry.aiChat).
    property string _aiMode: "initial"
    property string _aiPendingUser: "" // the user turn awaiting this run's reply

    // Fill the template. split/join instead of String.replace so log content
    // containing "$&"-style sequences can't corrupt the substitution.
    function _aiPrompt(entry) {
        function fill(t, key, val) { return t.split("{" + key + "}").join(val); }
        var t = root.aiPromptTemplate;
        t = fill(t, "environment", root.environmentInfo !== "" ? root.environmentInfo : "(environment details unavailable)");
        t = fill(t, "package", entry.name || "?");
        t = fill(t, "source", entry.source || "?");
        t = fill(t, "oldVersion", entry.oldVersion || "?");
        t = fill(t, "newVersion", entry.newVersion || "?");
        t = fill(t, "reason", entry.reason || "unknown");
        t = fill(t, "log", entry.log && entry.log !== "" ? entry.log : "(no log was saved)");
        return t;
    }

    // Detected once at load: distro (incl. Arch derivative), kernel, arch, and
    // Shelly version — the parts of the environment that change what fix is
    // correct. Filled into the {environment} prompt placeholder. Read-only
    // probe, so it doesn't need the shelly db flock.
    property string environmentInfo: ""
    Process {
        id: envProc
        command: ["sh", "-c",
            "{ . /etc/os-release 2>/dev/null; " +
            "echo \"OS: ${PRETTY_NAME:-${NAME:-Linux}}\"; " +
            "[ -n \"$ID_LIKE\" ] && echo \"Based on: $ID_LIKE\"; " +
            "echo \"Kernel: $(uname -r)\"; " +
            "echo \"Architecture: $(uname -m)\"; " +
            "v=$(shelly --version 2>/dev/null | head -n1); [ -n \"$v\" ] && echo \"Shelly: $v\"; " +
            "[ -n \"$XDG_CURRENT_DESKTOP\" ] && echo \"Desktop: $XDG_CURRENT_DESKTOP\"; }"]
        stdout: StdioCollector {
            onStreamFinished: root.environmentInfo = (text || "").trim()
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
    }

    function _runAi(promptText) {
        root.aiError = "";
        root._aiStdout = "";
        root._aiStderr = "";
        root.aiLoading = true;
        aiProc.command = ["sh", "-c", "printf '%s' \"$1\" | ( " + aiCommand + " )", "shelly-ai", promptText];
        aiProc.running = true;
    }
    function requestAiSuggestion() {
        if (!aiReady || aiLoading || !root.failureDetail)
            return;
        root._aiMode = "initial";
        root._aiPendingUser = "";
        _runAi(_aiPrompt(root.failureDetail));
    }
    // Assemble the conversation so far as plain text, so any configured CLI can
    // continue it (we don't rely on a tool-specific --continue/session flag).
    function _conversationText(entry) {
        var lines = [];
        if (entry.ai)
            lines.push("Assistant (your earlier suggestion):\n" + entry.ai);
        var chat = entry.aiChat || [];
        for (var i = 0; i < chat.length; i++)
            lines.push((chat[i].role === "user" ? "User:\n" : "Assistant:\n") + chat[i].content);
        return lines.join("\n\n");
    }
    // Send a follow-up turn (free text or the Check-result canned message). The
    // latest inline command output is attached so the AI can see what happened.
    function _sendAiTurn(userMsg) {
        var e = root.failureDetail;
        if (!aiReady || aiLoading || !e || !userMsg || !userMsg.trim())
            return;
        var p = _aiPrompt(e)
            + "\n\n=== Conversation so far ===\n" + _conversationText(e)
            + "\n\n=== The user now says ===\n" + userMsg;
        if (root.aiRunOutput && root.aiRunOutput.trim() !== "")
            p += "\n\nOutput of the command(s) the user just ran (`" + root.aiRunCmd + "`):\n" + root.aiRunOutput;
        p += "\n\nReply concisely, continuing to use \"$ \"-prefixed lines for any runnable commands. "
            + "If the problem now looks resolved, say so plainly.";
        root._aiMode = "followup";
        root._aiPendingUser = userMsg;
        _runAi(p);
    }
    function sendAiFollowup(userMsg) {
        _sendAiTurn(userMsg);
    }
    function checkAiResult() {
        _sendAiTurn("I applied your steps. Using the command output above (if any) and the current package state, tell me whether the failure is resolved. If it isn't, give corrected next steps.");
    }
    function cancelAiSuggestion() {
        if (aiProc.running)
            aiProc.running = false;
        root.aiLoading = false;
    }
    Process {
        id: aiProc
        stdout: StdioCollector {
            onStreamFinished: root._aiStdout = text || ""
        }
        stderr: StdioCollector {
            onStreamFinished: root._aiStderr = text || ""
        }
        onExited: (exitCode) => root._aiFinished(exitCode)
    }
    function _aiFinished(exitCode) {
        if (!root.aiLoading)
            return; // cancelled
        root.aiLoading = false;
        var out = (root._aiStdout || "").trim();
        if (out === "") {
            var err = (root._aiStderr || "").trim().split("\n").slice(-3).join("\n");
            root.aiError = exitCode !== 0
                ? ("AI command failed (exit " + exitCode + ")" + (err ? ":\n" + err : ""))
                : "AI command produced no output.";
            return;
        }
        if (out.length > 6000)
            out = out.slice(0, 6000) + " …";
        if (root._aiMode === "followup")
            _appendAiChat(root._aiPendingUser, out);
        else
            _saveAiResult(out);
        root._aiPendingUser = "";
    }
    // Append a user turn + the assistant reply to the failure's conversation,
    // persisting the whole transcript (sidecar + pluginService).
    function _appendAiChat(userMsg, assistantMsg) {
        var e = root.failureDetail;
        if (!e)
            return;
        var list = root.failureHistory.slice();
        var updEntry = null;
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === e.name && list[i].when === e.when) {
                var upd = JSON.parse(JSON.stringify(list[i]));
                var chat = (upd.aiChat || []).slice();
                chat.push({ role: "user", content: userMsg });
                chat.push({ role: "assistant", content: assistantMsg });
                upd.aiChat = chat;
                list[i] = upd;
                updEntry = upd;
                break;
            }
        }
        if (!updEntry)
            return;
        root.failureHistory = list;
        root.failureDetail = updEntry;
        if (pluginService && pluginService.savePluginState)
            pluginService.savePluginState(pluginId, "failureHistory", JSON.stringify(root.failureHistory));
        _writeFailurePatch(updEntry.name, updEntry.when, { aiChat: updEntry.aiChat });
    }
    // Attach the answer to the failure record so it survives view changes and
    // restarts, and shows on every monitor.
    function _saveAiResult(answer) {
        var e = root.failureDetail;
        if (!e)
            return;
        var list = root.failureHistory.slice();
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === e.name && list[i].when === e.when) {
                var upd = JSON.parse(JSON.stringify(list[i]));
                upd.ai = answer;
                list[i] = upd;
                root.failureDetail = upd;
                break;
            }
        }
        root.failureHistory = list;
        if (pluginService && pluginService.savePluginState)
            pluginService.savePluginState(pluginId, "failureHistory", JSON.stringify(root.failureHistory));
        // Persist to the sidecar too, so an answer generated in the control
        // center (no pluginService) survives a reopen.
        _writeFailurePatch(e.name, e.when, { ai: answer });
    }
    // Wipe the AI conversation for a failure (suggestion + all follow-ups). The
    // failure itself stays; only the AI history is cleared.
    function clearAiConversation() {
        var e = root.failureDetail;
        if (!e)
            return;
        var list = root.failureHistory.slice();
        var updEntry = null;
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === e.name && list[i].when === e.when) {
                var upd = JSON.parse(JSON.stringify(list[i]));
                upd.ai = "";
                upd.aiChat = [];
                list[i] = upd;
                updEntry = upd;
                break;
            }
        }
        if (!updEntry)
            return;
        root.aiError = "";
        root.failureHistory = list;
        root.failureDetail = updEntry;
        if (pluginService && pluginService.savePluginState)
            pluginService.savePluginState(pluginId, "failureHistory", JSON.stringify(root.failureHistory));
        _writeFailurePatch(updEntry.name, updEntry.when, { ai: "", aiChat: [] });
    }

    // Split an AI answer into ordered segments: prose text blocks and runnable
    // commands (lines the prompt asked the model to prefix with "$ "). Each
    // segment is { cmd: bool, value: string }.
    function _aiSegments(text) {
        var out = [];
        var buf = [];
        function flush() {
            var t = buf.join("\n").replace(/^\s+|\s+$/g, "");
            if (t !== "")
                out.push({ cmd: false, value: t });
            buf = [];
        }
        var lines = String(text || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var mi = /^\s*\$!\s+(\S.*?)\s*$/.exec(lines[i]); // "$! " → needs a terminal
            var m = /^\s*\$\s+(\S.*?)\s*$/.exec(lines[i]);   // "$ "  → runs inline
            if (mi) {
                flush();
                out.push({ cmd: true, interactive: true, value: mi[1] });
            } else if (m) {
                flush();
                out.push({ cmd: true, interactive: false, value: m[1] });
            } else {
                buf.push(lines[i]);
            }
        }
        flush();
        return out;
    }
    // Flatten a failure's whole AI conversation into render segments: the first
    // suggestion + each follow-up turn. Assistant text/commands become
    // text/cmd segments; user turns become { user: true } bubbles.
    function _aiConversationSegments(entry) {
        var segs = [];
        if (entry && entry.ai)
            _aiSegments(entry.ai).forEach(function (s) { segs.push(s); });
        var chat = (entry && entry.aiChat) || [];
        for (var i = 0; i < chat.length; i++) {
            if (chat[i].role === "user")
                segs.push({ user: true, value: chat[i].content });
            else
                _aiSegments(chat[i].content).forEach(function (s) { segs.push(s); });
        }
        return segs;
    }
    // Grouped by turn (for chat bubbles): assistant turns carry parsed segments
    // (text + $ commands); user turns carry raw text.
    function _aiConversationTurns(entry) {
        var turns = [];
        if (entry && entry.ai)
            turns.push({ role: "assistant", segments: _aiSegments(entry.ai) });
        var chat = (entry && entry.aiChat) || [];
        for (var i = 0; i < chat.length; i++) {
            if (chat[i].role === "user")
                turns.push({ role: "user", text: chat[i].content });
            else
                turns.push({ role: "assistant", segments: _aiSegments(chat[i].content) });
        }
        return turns;
    }
    // Run an AI-suggested command in a VISIBLE terminal (it may need sudo, and
    // the user should see exactly what runs and be able to abort). Held open on
    // a prompt afterwards. Deliberately NOT wrapped in shelly/flock.
    function runAiCommand(cmd) {
        if (!cmd || !cmd.trim())
            return;
        var inner = cmd + "; echo; echo '── Command finished ── Press Enter to close'; read _";
        Quickshell.execDetached(_launchArgv(inner));
    }

    // ---- Inline command execution (streamed output in the failure detail) ----
    // Runs the command with stdout+stderr merged and streams it into an in-widget
    // panel — no separate window. No TTY, so it can't answer a sudo password or
    // interactive confirmation prompt: those fail fast (the panel shows the
    // error) and the user falls back to the terminal button. State lives on root
    // so output survives the popout closing mid-run.
    property string aiRunCmd: ""
    property string aiRunOutput: ""
    property bool aiRunning: false
    property bool aiRunDone: false
    property int aiRunExit: 0
    function runAiCommandInline(cmd) {
        if (!cmd || !cmd.trim() || aiRunning)
            return;
        root.aiRunCmd = cmd;
        root.aiRunOutput = "";
        root.aiRunExit = 0;
        root.aiRunDone = false;
        root.aiRunning = true;
        // exec </dev/null so anything that reads stdin (a pacman/yay "Proceed?"
        // prompt, a sudo password read) gets EOF and fails fast instead of
        // hanging forever — inline has no TTY to answer prompts. Query commands
        // don't read stdin, so they're unaffected.
        aiRunProc.command = ["sh", "-c", "exec </dev/null; " + cmd + " 2>&1"];
        aiRunProc.running = true;
    }
    function cancelAiRun() {
        if (aiRunProc.running)
            aiRunProc.running = false;
        root.aiRunning = false;
    }
    Process {
        id: aiRunProc
        stdout: SplitParser {
            onRead: data => {
                var s = root.aiRunOutput + data + "\n";
                if (s.length > 40000)          // keep the panel bounded
                    s = "…\n" + s.slice(s.length - 40000);
                root.aiRunOutput = s;
            }
        }
        onExited: (code, status) => {
            root.aiRunExit = code;
            root.aiRunning = false;
            root.aiRunDone = true;
        }
    }

    function openPluginSettings() {
        if (typeof PopoutService !== "undefined" && PopoutService.openSettings)
            PopoutService.openSettings();
    }

    // =====================================================================
    // Click dispatch
    // =====================================================================
    function dispatch(action) {
        if (action === "updates")
            openMode("updates");
        else if (action === "menu")
            openMode("menu");
        else if (action === "ui")
            openShellyUi();
        // "none" -> nothing
    }

    function openMode(mode) {
        if (!hasPopout)
            return;
        if (popoutOpen && popoutMode !== mode) {
            popoutMode = mode; // switch view, keep popout open
            return;
        }
        popoutMode = mode;
        triggerPopout();
    }

    // "Held Packages" manager — reached from the menu, returns there.
    function openHeld() {
        loadIgnored();
        openMode("held");
    }

    // Relative "checked N ago" label. References _clock so it re-evaluates as
    // the tick advances.
    function lastCheckedText() {
        var tick = root._clock; // establish binding dependency
        if (!root.lastChecked)
            return "";
        var s = Math.max(0, Math.floor((Date.now() - root.lastChecked) / 1000));
        if (s < 45)
            return "checked just now";
        var m = Math.round(s / 60);
        if (m < 60)
            return "checked " + Math.max(1, m) + "m ago";
        var h = Math.floor(m / 60);
        if (h < 24)
            return "checked " + h + "h ago";
        return "checked " + Math.floor(h / 24) + "d ago";
    }

    // =====================================================================
    // Timers / lifecycle
    // =====================================================================
    Timer {
        interval: Math.max(1, root.checkFrequency) * 60000
        repeat: true
        running: root.autoCheck
        triggeredOnStart: false
        onTriggered: root.refresh(true)
    }

    Component.onCompleted: {
        envProc.running = true; // detect {environment} for AI prompts
        shellyVerProc.running = true; // detect Shelly major version (v3+ required)
        newsProc.running = true; // fetch Arch news for the pre-update banner
        // pluginService is usually NULL here (assigned after) — _loadPersistedState
        // no-ops then and re-runs from onPluginServiceChanged below.
        _loadPersistedState();
        if (checkAtStartup)
            Qt.callLater(function () { root.refresh(true); });
    }
    // pluginService arrives after Component.onCompleted. The bar recovers via
    // state broadcasts, but a fresh control-center instance gets none — so load
    // persisted state (failure history, failed flags, last-run summary) as soon
    // as the service is wired, or the CC history shows no failures. Separate
    // Connections so we don't clobber any base onPluginServiceChanged handler.
    Connections {
        target: root
        function onPluginServiceChanged() { root._loadPersistedState(); }
    }

    // Detect the installed Shelly major version once at startup. `shelly
    // --version` prints a single line like "3.0.0+9"; the leading integer is the
    // major. If it's older than 3, shellyUnsupported gates refresh and shows a
    // clear banner rather than letting every v3-grammar call fail as parse noise.
    Process {
        id: shellyVerProc
        command: ["shelly", "--version"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = (text || "").trim();
                root.shellyVersionRaw = t;
                var m = t.match(/(\d+)/);
                root.shellyMajor = m ? parseInt(m[1], 10) : 0;
                if (root.shellyUnsupported) {
                    root.hasError = true;
                    root.errorMessage = "Requires Shelly v3 or newer (found " + t + "). Update the shelly package.";
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: {} }
    }

    // Fetch the latest Arch news (all entries, not just unread — `shelly news`
    // without -a marks entries viewed in its own cache, which would consume the
    // badge before the user sees it). Unread is derived locally against newsSeen.
    Process {
        id: newsProc
        command: ["shelly", "news", "-a", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse((text || "").trim() || "[]");
                    if (!Array.isArray(d)) d = [];
                    var items = [];
                    for (var i = 0; i < d.length; i++) {
                        var o = d[i];
                        if (!o || !o.Link) continue;
                        items.push({ title: o.Title || o.Link, link: o.Link, desc: o.Description || "", pubDate: o.PubDate || "" });
                    }
                    root.newsItems = items;
                    // First run: acknowledge everything currently known so the
                    // badge only fires for news that lands later — no flood of
                    // old notices the user already saw via the CLI/wizard.
                    if (!root.newsInit) {
                        var seed = {};
                        for (var j = 0; j < items.length; j++)
                            seed[items[j].link] = true;
                        root.newsSeen = seed;
                        root.newsInit = true;
                        root._saveNewsState();
                    }
                } catch (e) {}
            }
        }
        stderr: StdioCollector { onStreamFinished: {} }
    }
    function _saveNewsState() {
        if (pluginService && pluginService.savePluginState) {
            pluginService.savePluginState(pluginId, "newsSeen", JSON.stringify(root.newsSeen));
            pluginService.savePluginState(pluginId, "newsInit", root.newsInit ? "true" : "false");
        }
    }
    function markNewsRead(link) {
        if (!link)
            return;
        var s = {};
        for (var k in root.newsSeen)
            s[k] = root.newsSeen[k];
        s[link] = true;
        root.newsSeen = s;
        _saveNewsState();
    }
    function markAllNewsRead() {
        var s = {};
        for (var k in root.newsSeen)
            s[k] = true;
        for (var i = 0; i < root.newsItems.length; i++)
            s[root.newsItems[i].link] = true;
        root.newsSeen = s;
        _saveNewsState();
    }
    function openNews(link) {
        if (!link)
            return;
        Qt.openUrlExternally(link);
        markNewsRead(link);
    }
    // "Fri, 31 Oct 2025 21:20:51 +0000" → "Oct 31, 2025" (fall back to raw).
    function _fmtNewsDate(s) {
        if (!s)
            return "";
        var d = new Date(s);
        return isNaN(d.getTime()) ? s : Qt.formatDate(d, "MMM d, yyyy");
    }

    Loader {
        id: tooltipLoader
        active: false
        sourceComponent: ShellyTooltip {}
    }

    // Multi-line tooltip (DankTooltip is hard-locked to a single elided line).
    // Modeled on DankTooltip's layershell + positioning, with word wrap.
    component ShellyTooltip: PanelWindow {
        id: tt
        readonly property real maxWidth: 360
        property string text: ""
        property real targetX: 0
        property real targetY: 0
        property var targetScreen: null
        property bool alignLeft: false
        property bool alignRight: false
        property bool fade: false

        // Fade the content in on show (window itself is transparent).
        onVisibleChanged: bg.opacity = visible ? 1 : 0

        function show(t, x, y, screen, leftAlign, rightAlign) {
            tt.text = t;
            targetScreen = screen ?? null;
            targetX = x;
            targetY = y;
            alignLeft = leftAlign ?? false;
            alignRight = rightAlign ?? false;
            visible = true;
        }
        function hide() {
            visible = false;
        }

        WlrLayershell.namespace: "dms:tooltip"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        screen: targetScreen
        color: "transparent"
        visible: false
        implicitWidth: Math.min(maxWidth, Math.max(140, ttText.implicitWidth + Theme.spacingM * 2))
        implicitHeight: ttText.implicitHeight + Theme.spacingM * 2

        anchors {
            top: true
            left: true
        }
        margins {
            left: {
                const sw = targetScreen?.width ?? Screen.width;
                if (alignLeft)
                    return Math.round(Math.max(Theme.spacingS, Math.min(sw - implicitWidth - Theme.spacingS, targetX)));
                if (alignRight)
                    return Math.round(Math.max(Theme.spacingS, Math.min(sw - implicitWidth - Theme.spacingS, targetX - implicitWidth)));
                return Math.round(Math.max(Theme.spacingS, Math.min(sw - implicitWidth - Theme.spacingS, targetX - implicitWidth / 2)));
            }
            top: {
                const sh = targetScreen?.height ?? Screen.height;
                if (alignLeft || alignRight)
                    return Math.round(Math.max(Theme.spacingS, Math.min(sh - implicitHeight - Theme.spacingS, targetY - implicitHeight / 2)));
                return Math.round(Math.max(Theme.spacingS, Math.min(sh - implicitHeight - Theme.spacingS, targetY)));
            }
        }

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            border.width: BlurService.borderWidth
            border.color: BlurService.borderColor
            opacity: 0

            Behavior on opacity {
                NumberAnimation {
                    duration: tt.fade ? 160 : 0
                    easing.type: Easing.OutCubic
                }
            }

            StyledText {
                id: ttText
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                text: tt.text
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
                width: Math.min(implicitWidth, tt.maxWidth - Theme.spacingM * 2)
            }
        }
    }

    function tooltipText() {
        var lines = [];
        if (isChecking)
            return "Shelly: checking for updates…";
        if (hasError)
            return "Shelly: error\n" + errorMessage;
        lines.push(updateCount === 0 ? "System up to date" : "Total updates: " + updateCount);
        if (hasFailures)
            lines.push("⚠ Failed last run: " + failedPackages.join(", "));
        lines.push("Pacman: " + pacmanUpdatesShown.length);
        if (enableAur)
            lines.push("AUR: " + aurUpdatesShown.length);
        if (enableFlatpak)
            lines.push("Flatpak: " + flatpakUpdates.length);
        if (enableAppimage)
            lines.push("AppImage: " + appimageUpdates.length);
        if (ignoredPackages.length > 0)
            lines.push("Held: " + ignoredPackages.length);
        if (tooltipShowPackages && updateCount > 0) {
            var all = allShownItems();
            lines.push("");
            var max = 20;
            for (var i = 0; i < all.length && i < max; i++)
                lines.push("• " + all[i].name);
            if (all.length > max)
                lines.push("… and " + (all.length - max) + " more");
        }
        return lines.join("\n");
    }

    // Reusable menu row (top-level: nested inline components are unsupported).
    // An optional itemSubtitle adds a second, muted line and grows the row.
    component MenuItem: Rectangle {
        property string itemIcon: ""
        property string itemLabel: ""
        property string itemSubtitle: ""
        property string badge: ""
        signal triggered
        width: parent ? parent.width - (parent.leftPadding || 0) - (parent.rightPadding || 0) : 0
        height: itemSubtitle !== "" ? 54 : 44
        radius: Theme.cornerRadius
        color: mHover.containsMouse ? Theme.primaryHoverLight : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.right: mBadge.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingM
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: itemIcon
                size: Theme.iconSize - 2
                color: Theme.surfaceText
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                StyledText {
                    text: itemLabel
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }
                StyledText {
                    text: itemSubtitle
                    visible: itemSubtitle !== ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }
            }
        }
        StyledText {
            id: mBadge
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            text: badge
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.primary
            visible: badge !== ""
            width: visible ? implicitWidth : 0
        }
        MouseArea {
            id: mHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.triggered()
        }
    }

    // =====================================================================
    // Bar pill
    // =====================================================================
    component BarPillContent: Item {
        property bool isVertical: false

        // Count sits before the icon for horizontal "left" / vertical "top".
        readonly property bool countFirst: isVertical ? (root.countPositionV === "top") : (root.countPositionH === "left")
        // Transient states (checking/upgrading/error) show a single status icon;
        // otherwise the pill shows a failure indicator (red) AND/OR a pending-
        // updates indicator so both counts are visible at once.
        readonly property bool busyState: root.isChecking || root.isUpgrading || root.remoteUpgrading || root.hasError
        readonly property bool showFail: !busyState && root.failureCount > 0
        readonly property bool showUpd: !busyState && root.updateCount > 0
        readonly property bool showIdle: !busyState && !showFail && !showUpd
        readonly property int pillIconSize: root.iconSize

        implicitWidth: layout.implicitWidth
        implicitHeight: layout.implicitHeight

        // Flat positioner: each indicator's count + icon are separate children,
        // shown/hidden by visibility (positioners skip invisible items). Order:
        // failure indicator first (priority), then pending updates.
        Grid {
            id: layout
            anchors.centerIn: parent
            rows: isVertical ? 0 : 1
            columns: isVertical ? 1 : 0
            spacing: Theme.spacingXS
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            // Busy status icon (spinner / error), shown alone.
            DankIcon {
                id: statusIcon
                visible: busyState
                name: {
                    if (root.isUpgrading || root.remoteUpgrading) return "sync";
                    if (root.isChecking) return "refresh";
                    return "error"; // hasError
                }
                size: pillIconSize
                color: root.hasError ? Theme.error : Theme.primary
                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    running: root.isChecking || root.isUpgrading || root.remoteUpgrading
                    onRunningChanged: { if (!running) statusIcon.rotation = 0; }
                }
            }

            // Failure indicator (red).
            StyledText {
                text: String(root.failureCount)
                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium
                color: Theme.error
                visible: showFail && root.showCount && countFirst
            }
            DankIcon {
                visible: showFail
                name: root.iconFailures
                size: pillIconSize
                color: Theme.error
            }
            StyledText {
                text: String(root.failureCount)
                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium
                color: Theme.error
                visible: showFail && root.showCount && !countFirst
            }

            // Pending-updates indicator (primary).
            StyledText {
                text: String(root.updateCount)
                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium
                color: Theme.primary
                visible: showUpd && root.showCount && countFirst
            }
            DankIcon {
                visible: showUpd
                name: root.iconUpdates
                size: pillIconSize
                color: Theme.primary
            }
            StyledText {
                text: String(root.updateCount)
                font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium
                color: Theme.primary
                visible: showUpd && root.showCount && !countFirst
            }

            // Up-to-date / idle icon.
            DankIcon {
                visible: showIdle
                name: root.iconDefault
                size: pillIconSize
                color: Theme.surfaceText
            }
        }

        // Show the tooltip below the bar, centered on the icon and clear of the
        // pointer. Positions relative to the bar's own thickness so it always
        // lands just outside the bar edge.
        function showTip() {
            if (!root.showTooltip || !root.parentScreen || root.popoutOpen)
                return;
            tooltipLoader.active = true;
            var tip = tooltipLoader.item;
            if (!tip)
                return;
            tip.fade = root.tooltipFade;
            tip.text = root.tooltipText();
            // Screen-LOCAL (scene) coordinates, NOT mapToGlobal: the tooltip's
            // layershell margins are relative to its target screen's origin, so
            // global coords break on any monitor whose x/y offset isn't 0 (the
            // tooltip landed far off on DP-1 at x=2560; DP-2 at x=0 worked by
            // coincidence). mapToItem(null, …) matches the DMS bar convention.
            var p = layout.mapToItem(null, 0, 0);
            var edge = root.axis?.edge;
            var gap = Theme.spacingS;
            var bt = root.barThickness;
            if (isVertical) {
                var cy = p.y + layout.height / 2;
                if (edge === "right") {
                    var barLeft = p.x - (bt - layout.width) / 2;
                    tip.show(tip.text, barLeft - gap, cy, root.parentScreen, false, true);
                } else {
                    var barRight = p.x + (bt + layout.width) / 2;
                    tip.show(tip.text, barRight + gap, cy, root.parentScreen, true, false);
                }
            } else {
                var cx = p.x + layout.width / 2;
                if (edge === "bottom") {
                    var barTop = p.y - (bt - layout.height) / 2;
                    tip.show(tip.text, cx, barTop - gap - tip.implicitHeight, root.parentScreen, false, false);
                } else {
                    var barBottom = p.y + (bt + layout.height) / 2;
                    tip.show(tip.text, cx, barBottom + gap, root.parentScreen, false, false);
                }
            }
        }
        function hideTip() {
            hoverTimer.stop();
            if (tooltipLoader.item)
                tooltipLoader.item.hide();
            tooltipLoader.active = false;
        }

        Timer {
            id: hoverTimer
            interval: Math.max(0, root.tooltipDelay)
            repeat: false
            onTriggered: showTip()
        }

        // All clicks are handled here. BasePill's own MouseArea sits at z:-1
        // behind this content, so it is fully overridden and we dispatch every
        // button ourselves (BasePill only forwards Left/Right natively).
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton)
                    root.dispatch(root.leftClickAction);
                else if (mouse.button === Qt.RightButton)
                    root.dispatch(root.rightClickAction);
                else if (mouse.button === Qt.MiddleButton)
                    root.dispatch(root.middleClickAction);
            }
            onEntered: {
                if (root.showTooltip && !root.popoutOpen)
                    hoverTimer.restart();
            }
            onExited: hideTip()
            onPressed: hideTip()
        }
    }

    horizontalBarPill: Component {
        BarPillContent { isVertical: false }
    }
    verticalBarPill: Component {
        BarPillContent { isVertical: true }
    }

    // NOTE: pillClickAction / pillRightClickAction are intentionally left null.
    // All buttons are dispatched from the pill's own MouseArea (above), which
    // lets openMode() call triggerPopout() without recursing through
    // pillClickAction, and adds middle-click support the framework lacks.

    // =====================================================================
    // Shared views (Menu + Updates list) — top-level so BOTH the bar popout
    // and the control-center panel can instantiate them from one source.
    // They emit dismissRequested() instead of touching the popout directly,
    // and take `embedded` to hide popout-only chrome in the control center.
    // =====================================================================
    component FailBannerButton: Rectangle {
        id: fbb
        property string icon: ""
        property string label: ""
        signal clicked()
        width: fbbRow.implicitWidth + Theme.spacingM * 2
        height: 30
        radius: Theme.cornerRadius
        color: fbbHover.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : "transparent"
        border.width: 1
        border.color: Theme.withAlpha(Theme.error, 0.35)
        Row {
            id: fbbRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS
            DankIcon { anchors.verticalCenter: parent.verticalCenter; name: fbb.icon; size: Theme.iconSize - 6; color: Theme.error }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: fbb.label
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
            }
        }
        MouseArea {
            id: fbbHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fbb.clicked()
        }
    }

    component UpdatesView: Column {
        id: uv
        // Host asks to dismiss its surface (bar popout closes; control center
        // closes). Emitted instead of calling popout.closePopout() directly, so
        // this view has no knowledge of which surface hosts it.
        signal dismissRequested()
        // A row was left-clicked — the host decides where the detail opens
        // (bar popout → detail mode; control center → its own detail sub-view).
        signal rowActivated(var item)
        // Embedded = rendered inside the control-center panel (not the bar
        // popout): hide popout-only chrome (own header, hint, filter, sort,
        // internal failure banner, Update All) and don't drill into the
        // per-package detail view (the CC has no detail Loader).
        property bool embedded: false
        // In embedded mode the list has no natural height (no detailRows framing
        // it), so the host passes the pixel height the list should fill.
        property real embeddedListHeight: 0
        readonly property real contentWidth: width - leftPadding - rightPadding
        width: parent ? parent.width : 0
        padding: uv.embedded ? 0 : root.popoutPad
        spacing: uv.embedded ? 0 : Theme.spacingM

        readonly property var allItems: root.allShownItems()
        readonly property var failedShown: allItems.filter(function (i) { return root._isFailed(i); })

        // Text filter (matches name/description/version/source).
        property string filterText: ""
        readonly property var filteredItems: filterText === ""
            ? allItems
            : allItems.filter(function (i) { return root._matchesFilter(i, uv.filterText); })

        // Sort: type (pacman→aur→devel→flatpak→appimage) or name.
        readonly property var displayItems: {
            var arr = filteredItems.slice();
            var dir = updSort.asc ? 1 : -1;
            var key = updSort.activeKey;
            arr.sort(function (a, b) {
                var c;
                if (key === "type") {
                    c = root._typeRank(a) - root._typeRank(b);
                    if (c === 0)
                        c = String(a.name || "").localeCompare(String(b.name || ""));
                } else {
                    c = String(a.name || "").localeCompare(String(b.name || ""));
                }
                return c * dir;
            });
            return arr;
        }

        // Header
        Item {
            width: uv.contentWidth
            visible: !uv.embedded
            height: visible ? 44 : 0
            Column {
                anchors.left: parent.left
                anchors.right: headerActions.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                StyledText {
                    text: "Available Updates"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
                // Subtitle: normally "checked Nm ago"; while an external
                // pacman/AUR update is running, an amber notice explaining why
                // a refresh is being held off (clicking refresh lands here).
                StyledText {
                    width: parent.width
                    text: root._externalBusy
                        ? "System update in progress — will refresh when it finishes"
                        : root.lastCheckedText()
                    visible: text !== ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: root._externalBusy ? Theme.warning : Theme.surfaceVariantText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
            Row {
                id: headerActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._externalBusy ? "Locked" : (root.isChecking ? "Checking…" : (root.updateCount === 0 ? "Up to date" : root.updateCount + (root.updateCount === 1 ? " update" : " updates")))
                    font.pixelSize: Theme.fontSizeMedium
                    color: root._externalBusy ? Theme.warning : (root.hasError ? Theme.error : Theme.surfaceVariantText)
                }
                DankActionButton {
                    buttonSize: 28
                    iconName: "refresh"
                    iconSize: 18
                    iconColor: root._externalBusy ? Theme.warning : Theme.surfaceText
                    enabled: !root.isChecking
                    opacity: enabled ? 1.0 : 0.5
                    tooltipText: root._externalBusy
                        ? "A system update is running — checks are paused until it finishes"
                        : "Refresh"
                    onClicked: root.refreshAll()
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1000
                        loops: Animation.Infinite; running: root.isChecking
                    }
                }
            }
        }

        // Interaction hint — only shown when there are packages that
        // support the click actions (pacman/AUR rows can be held). Hidden when
        // embedded (row-click doesn't open detail there).
        Row {
            width: uv.contentWidth
            spacing: Theme.spacingXS
            visible: !uv.embedded && uv.allItems.length > 0
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "info"
                size: Theme.fontSizeSmall + 2
                color: Theme.surfaceVariantText
            }
            StyledText {
                width: parent.width - (Theme.fontSizeSmall + 2) - Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                text: "Click a package for details · right-click to hold (ignore) it"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }

        // Text filter — search the update list by package name,
        // description, version or source. Shown only when there is
        // something to filter. Hidden when embedded (the CC panel keeps the
        // list compact; filtering lives in the full popout).
        DankTextField {
            width: uv.contentWidth
            height: visible ? 40 : 0
            visible: !uv.embedded && uv.allItems.length > 0
            leftIconName: "search"
            showClearButton: true
            placeholderText: "Filter packages…"
            text: uv.filterText
            onTextEdited: uv.filterText = text
        }

        // Sort selector (type / name).
        SortChips {
            id: updSort
            visible: !uv.embedded && uv.allItems.length > 0
            height: visible ? implicitHeight : 0
            activeKey: "type"
            asc: true
            options: [ { key: "type", label: "Type" }, { key: "name", label: "Name" } ]
        }

        // Failure banner — appears whenever the last upgrade left
        // failures (based on failedPackages, not just visible rows, so
        // filters/holds can't hide it). "Details" jumps to the failure
        // record (reason + fix hint + AI); "Log" opens the raw session
        // output.
        Rectangle {
            width: uv.contentWidth
            visible: !uv.embedded && root.hasFailures
            height: visible ? 44 : 0
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.error, 0.12)
            border.width: 1
            border.color: Theme.withAlpha(Theme.error, 0.35)

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.right: failBtns.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "error"
                    size: Theme.iconSize - 4
                    color: Theme.error
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - (Theme.iconSize - 4) - Theme.spacingS)
                    text: root.failureCount + (root.failureCount === 1 ? " update failed and needs attention" : " updates failed and need attention")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
            Row {
                id: failBtns
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                FailBannerButton { icon: "troubleshoot"; label: "Details"; onClicked: root.openFailures(false) }
                FailBannerButton { icon: "description"; label: "Log"; onClicked: root.viewLastLog() }
            }
        }

        // Arch news banner — surfaces unread Arch Linux news (manual-intervention
        // notices etc.) right where the user updates. Read state is tracked
        // locally; "Review" expands the headlines, a headline opens it in the
        // browser and marks it read, "Mark read" clears the badge.
        Column {
            width: uv.contentWidth
            visible: !uv.embedded && root.newsUnreadCount > 0
            spacing: Theme.spacingXS

            Rectangle {
                width: parent.width
                height: 44
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.warning, 0.12)
                border.width: 1
                border.color: Theme.withAlpha(Theme.warning, 0.35)
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: newsBtns.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS
                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "newspaper"
                        size: Theme.iconSize - 4
                        color: Theme.warning
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - (Theme.iconSize - 4) - Theme.spacingS)
                        text: root.newsUnreadCount + (root.newsUnreadCount === 1 ? " new Arch news item — review before updating" : " new Arch news items — review before updating")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
                Row {
                    id: newsBtns
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    FailBannerButton {
                        icon: root.newsExpanded ? "expand_less" : "expand_more"
                        label: root.newsExpanded ? "Hide" : "Review"
                        onClicked: root.newsExpanded = !root.newsExpanded
                    }
                    FailBannerButton {
                        icon: "done_all"
                        label: "Mark read"
                        onClicked: { root.markAllNewsRead(); root.newsExpanded = false; }
                    }
                }
            }

            // Expanded headlines (unread only). Each row opens the article.
            Rectangle {
                width: parent.width
                visible: root.newsExpanded
                height: visible ? newsCol.implicitHeight + Theme.spacingS * 2 : 0
                radius: Theme.cornerRadius
                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.1)
                Column {
                    id: newsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingXS
                    Repeater {
                        model: root.newsItems.filter(function (n) { return !root.newsSeen[n.link]; })
                        delegate: Rectangle {
                            width: newsCol.width
                            height: nrow.implicitHeight + Theme.spacingXS * 2
                            radius: Theme.cornerRadius
                            color: nMouse.containsMouse ? Theme.withAlpha(Theme.warning, 0.10) : "transparent"
                            Row {
                                id: nrow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingXS
                                anchors.rightMargin: Theme.spacingXS
                                spacing: Theme.spacingS
                                DankIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "open_in_new"
                                    size: Theme.iconSize - 8
                                    color: Theme.surfaceVariantText
                                }
                                Column {
                                    width: Math.max(0, nrow.width - (Theme.iconSize - 8) - Theme.spacingS)
                                    spacing: 0
                                    StyledText {
                                        width: parent.width
                                        text: modelData.title
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        width: parent.width
                                        visible: !!modelData.pubDate
                                        text: root._fmtNewsDate(modelData.pubDate)
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            MouseArea {
                                id: nMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNews(modelData.link)
                            }
                        }
                    }
                }
            }
        }

        // List — height follows the configured number of rows in the popout,
        // or fills the control-center panel (embeddedListHeight) when embedded.
        Rectangle {
            width: uv.contentWidth
            height: uv.embedded
                ? Math.max(root.detailRowHeight, uv.embeddedListHeight)
                : Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.1)

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingL * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: uv.filteredItems.length === 0
                text: {
                    if (uv.allItems.length > 0)
                        return "No packages match \"" + uv.filterText + "\"";
                    if (root._externalBusy)
                        return "A system update is running.\nUpdates will refresh once it finishes.";
                    return root.isChecking ? "Checking for updates…" : (root.hasError ? ("Failed to check for updates:\n" + root.errorMessage) : "Your system is up to date!");
                }
                color: root.hasError && uv.allItems.length === 0 ? Theme.error : Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }

            DankListView {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                visible: uv.displayItems.length > 0
                clip: true
                spacing: Theme.spacingXS
                model: uv.displayItems

                delegate: Rectangle {
                    required property var modelData
                    // VCS/devel AUR packages (churny "latest-commit" updates) get
                    // a muted "devel" chip + a dimmed row so they recede visually.
                    readonly property bool rowIsKernel: root._isKernel(modelData)
                    readonly property bool rowIsDevel: modelData.source === "aur" && root._isDevelAur(modelData)
                    // Attempted last run but still pending → didn't apply.
                    readonly property bool rowIsFailed: root._isFailed(modelData)
                    // Failed because the PKGBUILD changed → needs an interactive re-run.
                    readonly property bool rowNeedsInteractive: root._needsInteractive(modelData)
                    // Per-package interactive update applies to everything but AppImage
                    // (which has no per-item interactive form).
                    readonly property bool rowCanInteractive: modelData.source === "pacman" || modelData.source === "aur" || modelData.source === "flatpak"
                    width: ListView.view ? ListView.view.width : 0
                    height: root.detailRowHeight
                    radius: Theme.cornerRadius
                    color: itemHover.containsMouse ? Theme.primaryHoverLight : (rowIsFailed ? Theme.withAlpha(Theme.error, 0.09) : "transparent")

                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

                    // Left-click the row (anywhere but the download
                    // button, which sits on top with its own handler)
                    // opens the extended package-detail view; right-click
                    // holds it (pacman/AUR only — where ignore applies).
                    MouseArea {
                        id: itemHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (modelData.source === "pacman" || modelData.source === "aur")
                                    root.holdPackage(modelData.name);
                            } else {
                                uv.rowActivated(modelData);
                            }
                        }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM
                        // Failed devel rows stay full-opacity so they stand out.
                        opacity: (rowIsDevel && !rowIsFailed) ? 0.55 : 1.0

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            height: 20
                            radius: Theme.cornerRadius
                            color: rowIsFailed ? Theme.withAlpha(Theme.error, 0.22)
                                : (rowIsKernel ? Theme.withAlpha(Theme.warning, 0.22) : Theme.secondaryHover)
                            StyledText {
                                anchors.centerIn: parent
                                text: rowIsFailed ? "failed" : (rowIsKernel ? "kernel" : (rowIsDevel ? "devel" : modelData.source))
                                font.pixelSize: Theme.fontSizeSmall - 1
                                font.weight: (rowIsFailed || rowIsKernel) ? Font.Bold : Font.Normal
                                color: rowIsFailed ? Theme.error : (rowIsKernel ? Theme.warning : Theme.surfaceVariantText)
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 52 - 32 - (rowCanInteractive ? 30 + Theme.spacingM : 0) - Theme.spacingM * 3
                            spacing: 2
                            StyledText {
                                width: parent.width
                                text: modelData.name
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                width: parent.width
                                text: {
                                    var v = (modelData.oldVersion || "?") + " → " + (modelData.newVersion || "?");
                                    var ds = Number(modelData.downloadSize) || 0;
                                    if (ds > 0)
                                        v += "  ·  " + root._fmtBytes(ds);
                                    return v;
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.primary
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                width: parent.width
                                text: modelData.description
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                                visible: modelData.description !== ""
                            }
                        }

                        // Per-row interactive update: run THIS package's update in a
                        // terminal (never --no-confirm). Always offered as a pre-emptive
                        // option; highlighted amber when the package is flagged
                        // review-required (a changed PKGBUILD that skipped silently).
                        DankActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: rowCanInteractive
                            buttonSize: 30
                            iconName: "terminal"
                            iconSize: 18
                            iconColor: rowNeedsInteractive ? Theme.warning : Theme.surfaceVariantText
                            // Stay enabled (so a click is consumed here, not passed
                            // through to the row → detail view) but dim + no-op while
                            // an update is already running.
                            opacity: root.isUpgrading ? 0.4 : 1.0
                            tooltipText: rowNeedsInteractive
                                ? "Review required — run an interactive update to accept the changed PKGBUILD"
                                : "Run this update in a terminal (interactive)"
                            onClicked: {
                                if (root.isUpgrading)
                                    return;
                                root.runInteractiveUpdate(modelData);
                                uv.dismissRequested();
                            }
                        }
                        DankActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: 30
                            iconName: "download"
                            iconSize: 18
                            iconColor: Theme.primary
                            opacity: root.isUpgrading ? 0.4 : 1.0
                            onClicked: {
                                if (root.isUpgrading)
                                    return;
                                root.updateOne(modelData);
                                uv.dismissRequested();
                            }
                        }
                    }
                }
            }
        }

        // Update All button (hidden when embedded — the CC panel's Menu tab
        // already carries Update All and the per-source actions).
        Rectangle {
            width: uv.contentWidth
            visible: !uv.embedded
            height: visible ? 48 : 0
            radius: Theme.cornerRadius
            color: updateAllHover.containsMouse ? Theme.primaryHover : Theme.secondaryHover
            opacity: root.updateCount > 0 && !root.isUpgrading ? 1.0 : 0.5
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                DankIcon { name: "download"; size: Theme.iconSize; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Update All"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.primary
                }
            }
            MouseArea {
                id: updateAllHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.updateCount > 0 && !root.isUpgrading
                onClicked: {
                    root.updateAll();
                    uv.dismissRequested();
                }
            }
        }
    }

    component SortChips: Row {
        id: sc
        property var options: []          // [{ key, label }]
        property string activeKey: ""
        property bool asc: true
        spacing: Theme.spacingXS

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Sort"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
        Repeater {
            model: sc.options
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: modelData.key === sc.activeKey
                anchors.verticalCenter: parent.verticalCenter
                height: 24
                width: chipRow.implicitWidth + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: active ? Theme.primaryHoverLight : (chHover.containsMouse ? Theme.secondaryHover : "transparent")
                border.width: active ? 0 : 1
                border.color: Theme.outlineMedium
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 2
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: active ? Font.Medium : Font.Normal
                        color: active ? Theme.primary : Theme.surfaceVariantText
                    }
                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: active
                        name: sc.asc ? "arrow_upward" : "arrow_downward"
                        size: Theme.fontSizeSmall
                        color: Theme.primary
                    }
                }
                MouseArea {
                    id: chHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (sc.activeKey === modelData.key)
                            sc.asc = !sc.asc;
                        else
                            sc.activeKey = modelData.key;
                    }
                }
            }
        }
    }

    // A single on/off filter chip (e.g. "Failed only").
    component FilterChip: Rectangle {
        id: fc
        property string label: ""
        property string icon: ""
        property bool active: false
        property color activeColor: Theme.primary
        signal toggled
        height: 24
        width: fcRow.implicitWidth + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: active ? Theme.withAlpha(activeColor, 0.18) : (fcHover.containsMouse ? Theme.secondaryHover : "transparent")
        border.width: active ? 0 : 1
        border.color: Theme.outlineMedium
        Row {
            id: fcRow
            anchors.centerIn: parent
            spacing: 3
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: fc.icon !== ""
                name: fc.icon
                size: Theme.fontSizeSmall
                color: fc.active ? fc.activeColor : Theme.surfaceVariantText
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: fc.label
                font.pixelSize: Theme.fontSizeSmall
                font.weight: fc.active ? Font.Medium : Font.Normal
                color: fc.active ? fc.activeColor : Theme.surfaceVariantText
            }
        }
        MouseArea {
            id: fcHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fc.toggled()
        }
    }

    component MenuView: Column {
        id: mv
        // See UpdatesView: dismissRequested() decouples this from its host, and
        // embedded hides popout-only chrome. In the control center the history
        // and held-packages entries are hidden — they navigate to popout-only
        // views the CC panel doesn't host.
        signal dismissRequested()
        // Open the update-history view — the host decides where (bar popout
        // history mode; control-center history sub-view).
        signal historyRequested()
        property bool embedded: false
        readonly property real contentWidth: width - leftPadding - rightPadding
        width: parent ? parent.width : 0
        padding: mv.embedded ? 0 : root.popoutPad
        spacing: Theme.spacingXS

        Item {
            width: mv.contentWidth
            visible: !mv.embedded
            height: visible ? 32 : 0
            StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Shelly Updater"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
                color: Theme.surfaceText
            }
        }

        MenuItem {
            itemIcon: "download"; itemLabel: "Update All"
            badge: root.updateCount > 0 ? String(root.updateCount) : ""
            onTriggered: { root.updateAll(); mv.dismissRequested(); }
        }
        MenuItem {
            itemIcon: "terminal"; itemLabel: "Update System Packages (Pacman)"
            badge: root.pacmanUpdatesShown.length > 0 ? String(root.pacmanUpdatesShown.length) : ""
            onTriggered: { root.updatePacman(); mv.dismissRequested(); }
        }
        MenuItem {
            visible: root.enableAur; height: visible ? 44 : 0
            itemIcon: "deployed_code"; itemLabel: "Update AUR"
            badge: root.aurUpdatesShown.length > 0 ? String(root.aurUpdatesShown.length) : ""
            onTriggered: { root.updateAur(); mv.dismissRequested(); }
        }
        MenuItem {
            visible: root.enableFlatpak; height: visible ? 44 : 0
            itemIcon: "package_2"; itemLabel: "Update Flatpak"
            badge: root.flatpakUpdates.length > 0 ? String(root.flatpakUpdates.length) : ""
            onTriggered: { root.updateFlatpak(); mv.dismissRequested(); }
        }
        MenuItem {
            visible: root.enableAppimage; height: visible ? 44 : 0
            itemIcon: "widgets"; itemLabel: "Update AppImage"
            badge: root.appimageUpdates.length > 0 ? String(root.appimageUpdates.length) : ""
            onTriggered: { root.updateAppimage(); mv.dismissRequested(); }
        }

        Rectangle { width: mv.contentWidth; height: 1; color: Theme.outline; opacity: 0.3 }

        MenuItem {
            // Shown in both surfaces; the host routes historyRequested().
            itemIcon: "history"; itemLabel: "Update History…"
            itemSubtitle: root.lastRunSummaryText()
            onTriggered: mv.historyRequested()
        }
        MenuItem {
            visible: !mv.embedded; height: visible ? 44 : 0
            itemIcon: "block"; itemLabel: "Held Packages…"
            badge: root.ignoredPackages.length > 0 ? String(root.ignoredPackages.length) : ""
            onTriggered: root.openHeld()
        }
        MenuItem {
            itemIcon: "cleaning_services"; itemLabel: "Clean Package Cache"
            onTriggered: { root.cleanCache(); mv.dismissRequested(); }
        }
        MenuItem {
            itemIcon: "delete_sweep"; itemLabel: "Remove Orphans"
            onTriggered: { root.removeOrphans(); mv.dismissRequested(); }
        }

        Rectangle { width: mv.contentWidth; height: 1; color: Theme.outline; opacity: 0.3 }

        MenuItem {
            visible: root.showOpenShellyMenuItem; height: visible ? 44 : 0
            itemIcon: "open_in_new"; itemLabel: "Open Shelly UI"
            onTriggered: { root.openShellyUi(); mv.dismissRequested(); }
        }
        MenuItem {
            itemIcon: "restart_alt"; itemLabel: "Reset"
            itemSubtitle: "Clear a stuck refresh/update and re-check"
            onTriggered: { root.resetState(); mv.dismissRequested(); }
        }
        MenuItem {
            itemIcon: "settings"; itemLabel: "Settings"
            onTriggered: { root.openPluginSettings(); mv.dismissRequested(); }
        }
    }

    // ---------------- Held-packages manager ----------------

    // =====================================================================
    // Package-detail view (top-level so the control-center panel can host it
    // too). backRequested/dismissRequested decouple it from the popout;
    // embedded + embeddedBodyHeight let it fit the CC panel.
    // =====================================================================
    component DetailView: Column {
        id: dv
        // backRequested = the back arrow / after a hold (return to the list);
        // dismissRequested = an action that closes the whole surface (update /
        // downgrade launches a terminal). Each host wires them to its own nav.
        signal backRequested()
        signal dismissRequested()
        // Embedded in the control-center panel: zero padding and a host-driven
        // body height (the popout sizes the body from detailRows instead).
        property bool embedded: false
        property real embeddedBodyHeight: 0
        readonly property real contentWidth: width - leftPadding - rightPadding
        width: parent ? parent.width : 0
        padding: dv.embedded ? 0 : root.popoutPad
        spacing: dv.embedded ? Theme.spacingS : Theme.spacingM

        readonly property var detail: root.detailData
        readonly property var pkg: root.detailItem
        readonly property bool rowIsKernel: pkg ? root._isKernel(pkg) : false

        // Header: back button + package name + source chip
        Item {
            width: dv.contentWidth
            height: 40
            DankActionButton {
                id: backBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 28
                iconName: "arrow_back"
                iconSize: 18
                iconColor: Theme.surfaceText
                onClicked: dv.backRequested()
            }
            StyledText {
                anchors.left: backBtn.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: srcChip.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: dv.pkg ? dv.pkg.name : ""
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
            }
            Rectangle {
                id: srcChip
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                height: 20
                radius: Theme.cornerRadius
                color: dv.rowIsKernel ? Theme.withAlpha(Theme.warning, 0.22) : Theme.secondaryHover
                StyledText {
                    anchors.centerIn: parent
                    text: dv.rowIsKernel ? "kernel" : (dv.pkg ? dv.pkg.source : "")
                    font.pixelSize: Theme.fontSizeSmall - 1
                    font.weight: dv.rowIsKernel ? Font.Bold : Font.Normal
                    color: dv.rowIsKernel ? Theme.warning : Theme.surfaceVariantText
                }
            }
        }

        // Body: scrollable field list (bounded so the popout height
        // stays comparable to the other modes; host-driven when embedded).
        Rectangle {
            width: dv.contentWidth
            height: dv.embedded
                ? Math.max(root.detailRowHeight, dv.embeddedBodyHeight)
                : Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.1)

            // Loading / error placeholder
            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                width: parent.width - Theme.spacingL * 2
                visible: root.detailLoading || root.detailError !== ""
                DankIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.detailError !== "" ? "error" : "hourglass_top"
                    size: Theme.iconSize
                    color: root.detailError !== "" ? Theme.error : Theme.surfaceVariantText
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1000
                        loops: Animation.Infinite; running: root.detailLoading
                    }
                }
                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.detailError !== "" ? root.detailError : "Loading details…"
                    color: root.detailError !== "" ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                }
            }

            Flickable {
                id: fieldFlick
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                clip: true
                visible: !root.detailLoading && root.detailError === "" && dv.detail !== null
                contentHeight: fieldCol.height
                contentWidth: width
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: fieldCol
                    width: fieldFlick.width
                    spacing: Theme.spacingS

                    // Full-width description
                    StyledText {
                        width: parent.width
                        visible: dv.detail && dv.detail.description !== ""
                        text: dv.detail ? dv.detail.description : ""
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outline
                        opacity: 0.25
                        visible: dv.detail && dv.detail.description !== "" && dv.detail.fields.length > 0
                    }

                    // Label / value rows
                    Repeater {
                        model: dv.detail ? dv.detail.fields : []
                        delegate: Row {
                            required property var modelData
                            width: fieldCol.width
                            spacing: Theme.spacingM
                            StyledText {
                                width: 104
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                width: parent.width - 104 - Theme.spacingM
                                text: modelData.value
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: modelData.mono ? Theme.monoFontFamily : Theme.fontFamily
                                // Link fields render as an underlined,
                                // primary-colored, clickable URL that
                                // opens in the default browser.
                                font.underline: modelData.link === true
                                color: modelData.link === true ? Theme.primary : Theme.surfaceText
                                wrapMode: Text.WrapAnywhere

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: modelData.link === true
                                    hoverEnabled: enabled
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally(modelData.value)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Update this package
        Rectangle {
            width: dv.contentWidth
            height: 48
            radius: Theme.cornerRadius
            color: detailUpdateHover.containsMouse ? Theme.primaryHover : Theme.secondaryHover
            opacity: !root.isUpgrading ? 1.0 : 0.5
            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                DankIcon { name: "download"; size: Theme.iconSize; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Update This Package"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.primary
                }
            }
            MouseArea {
                id: detailUpdateHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !root.isUpgrading
                onClicked: {
                    root.updateOne(dv.pkg);
                    dv.dismissRequested();
                }
            }
        }

        // Secondary actions: hold/unhold + downgrade.
        Row {
            width: dv.contentWidth
            spacing: Theme.spacingS
            readonly property bool isHeld: dv.pkg ? root._isHeld(dv.pkg.name) : false
            // ignore/downgrade apply to pacman/AUR, not flatpak/appimage.
            readonly property bool canHold: dv.pkg && (dv.pkg.source === "pacman" || dv.pkg.source === "aur")
            // v3: AUR downgrade needs a commit-picker (2.1.0) — standard only for now.
            readonly property bool canDowngrade: dv.pkg && dv.pkg.source === "pacman"

            DetailActionButton {
                visible: parent.canHold
                width: parent.canDowngrade ? (parent.width - Theme.spacingS) / 2 : parent.width
                icon: parent.isHeld ? "check_circle" : "block"
                label: parent.isHeld ? "Unhold" : "Hold"
                onTriggered: {
                    if (parent.isHeld)
                        root.unholdPackage(dv.pkg.name);
                    else
                        root.holdPackage(dv.pkg.name);
                    dv.backRequested();
                }
            }
            DetailActionButton {
                visible: parent.canDowngrade
                width: parent.canHold ? (parent.width - Theme.spacingS) / 2 : parent.width
                icon: "history"
                label: "Downgrade"
                btnEnabled: !root.isUpgrading
                onTriggered: {
                    root.downgradeOne(dv.pkg);
                    dv.dismissRequested();
                }
            }
        }
    }

    // Small secondary button used in the detail view's action row.
    component DetailActionButton: Rectangle {
        property string icon: ""
        property string label: ""
        property bool btnEnabled: true
        signal triggered
        height: 40
        radius: Theme.cornerRadius
        color: dabHover.containsMouse ? Theme.primaryHoverLight : Theme.secondaryHover
        opacity: btnEnabled ? 1.0 : 0.5
        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingXS
            DankIcon { name: icon; size: Theme.iconSize - 2; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: label
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }
        }
        MouseArea {
            id: dabHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: parent.btnEnabled
            onClicked: parent.triggered()
        }
    }

    // Segmented-toggle button for the control-center panel's Menu|Updates
    // switch. Top-level so the ccDetailContent Component can use it.
    component CcSegButton: Rectangle {
        id: seg
        property string segKey: ""
        property string segIcon: ""
        property string segLabel: ""
        property bool active: false
        signal picked()
        height: 34
        radius: Theme.cornerRadius
        color: active ? Theme.primary : (segHover.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh)
        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingXS
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: seg.segIcon
                size: Theme.iconSize - 6
                color: seg.active ? Theme.surface : Theme.surfaceText
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: seg.segLabel
                font.pixelSize: Theme.fontSizeSmall
                font.weight: seg.active ? Font.Bold : Font.Normal
                color: seg.active ? Theme.surface : Theme.surfaceText
            }
        }
        MouseArea {
            id: segHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: seg.picked()
        }
    }

    // =====================================================================
    // Control-center widget. DMS surfaces this in the control center's "add
    // widget" grid because ccWidgetIcon is non-empty; with ccDetailContent set
    // it renders as a CompoundPill (icon + status + expand chevron). Expanding
    // shows a Menu | Updates segmented panel. Status mirrors the bar pill.
    // =====================================================================
    ccWidgetIcon: {
        if (hasFailures) return iconFailures;
        return updateCount > 0 ? iconUpdates : iconDefault;
    }
    ccWidgetPrimaryText: "Shelly Updater"
    ccWidgetSecondaryText: {
        if (isChecking) return "Checking for updates…";
        if (isUpgrading || remoteUpgrading) return "Updating…";
        if (_externalBusy) return "System update running…";
        if (hasError) return "Update check failed";
        if (hasFailures) return failureCount + (failureCount === 1 ? " update failed" : " updates failed");
        return updateCount === 0 ? "Up to date" : updateCount + (updateCount === 1 ? " update available" : " updates available");
    }
    ccWidgetIsActive: updateCount > 0 || hasFailures
    ccDetailHeight: 360
    onCcWidgetToggled: {} // body tap: no-op; the expand chevron opens the panel

    ccDetailContent: Component {
        Rectangle {
            id: ccPanel
            radius: Theme.cornerRadius
            color: Theme.nestedSurface
            border.color: Theme.outlineMedium
            border.width: Theme.layerOutlineWidth
            // Default to the menu (counts + actions); flip to the detailed list.
            property string ccView: "menu"
            // Open the failure surfacing in-panel: a single unresolved failure
            // jumps to its detail; several go to the history list.
            function showFailures() {
                root.loadHistory();
                root._loadPersistedState();
                if (root.unresolvedFailures.length === 1) {
                    root.aiError = "";
                    root.failureDetail = root.unresolvedFailures[0];
                    ccView = "faildetail";
                } else {
                    ccView = "history";
                }
            }

            // Pinned failure banner — visible on both tabs so the "something
            // failed" signal never hides behind the toggle. "Log" opens the
            // captured session output (works from any surface).
            Rectangle {
                id: ccBanner
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacingS
                visible: root.hasFailures
                height: visible ? 36 : 0
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.error, 0.12)
                border.width: 1
                border.color: Theme.withAlpha(Theme.error, 0.35)
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: ccBannerBtns.left
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    DankIcon { anchors.verticalCenter: parent.verticalCenter; name: "error"; size: Theme.iconSize - 6; color: Theme.error }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.failureCount + (root.failureCount === 1 ? " update needs attention" : " updates need attention")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }
                }
                Row {
                    id: ccBannerBtns
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    FailBannerButton { icon: "troubleshoot"; label: "Details"; onClicked: ccPanel.showFailures() }
                    FailBannerButton { icon: "description"; label: "Log"; onClicked: root.viewLastLog() }
                }
            }

            // Segmented toggle + refresh (refresh sits with the toggle so it's
            // reachable from either tab — the embedded list has no header).
            Row {
                id: ccToggle
                anchors.top: ccBanner.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.spacingS
                anchors.rightMargin: Theme.spacingS
                anchors.topMargin: Theme.spacingS
                height: 34
                spacing: Theme.spacingXS
                // Two segments share the width left after the 34px refresh
                // button and the two inter-item gaps.
                readonly property real segWidth: (width - 34 - Theme.spacingXS * 2) / 2
                CcSegButton {
                    width: ccToggle.segWidth
                    segKey: "menu"; segIcon: "menu"; segLabel: "Menu"
                    // History / failure-detail are reached from the menu.
                    active: ccPanel.ccView === "menu" || ccPanel.ccView === "history" || ccPanel.ccView === "faildetail"
                    onPicked: ccPanel.ccView = "menu"
                }
                CcSegButton {
                    width: ccToggle.segWidth
                    segKey: "updates"; segIcon: "format_list_bulleted"
                    segLabel: "Updates" + (root.updateCount > 0 ? " (" + root.updateCount + ")" : "")
                    // Stays active while drilled into a package's detail.
                    active: ccPanel.ccView === "updates" || ccPanel.ccView === "detail"
                    onPicked: ccPanel.ccView = "updates"
                }
                Rectangle {
                    id: ccRefresh
                    width: 34
                    height: 34
                    radius: Theme.cornerRadius
                    color: ccRefreshHover.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh
                    opacity: root.isChecking ? 0.6 : 1.0
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    DankIcon {
                        id: ccRefreshIcon
                        anchors.centerIn: parent
                        name: "refresh"
                        size: Theme.iconSize - 6
                        color: root.isChecking ? Theme.primary : Theme.surfaceText
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 1000
                            loops: Animation.Infinite; running: root.isChecking
                            onRunningChanged: { if (!running) ccRefreshIcon.rotation = 0; }
                        }
                    }
                    MouseArea {
                        id: ccRefreshHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.isChecking
                        onClicked: root.refreshAll()
                    }
                }
            }

            // Content region — fills the rest of the panel; each tab scrolls
            // within it (no nested outer scroll).
            Item {
                id: ccContent
                anchors.top: ccToggle.bottom
                anchors.topMargin: Theme.spacingS
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Theme.spacingS
                anchors.rightMargin: Theme.spacingS
                anchors.bottomMargin: Theme.spacingS
                clip: true

                // Menu tab (scrolls if the actions overflow).
                Flickable {
                    anchors.fill: parent
                    visible: ccPanel.ccView === "menu"
                    clip: true
                    contentWidth: width
                    contentHeight: ccMenu.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    MenuView {
                        id: ccMenu
                        embedded: true
                        onDismissRequested: PopoutService.closeControlCenter && PopoutService.closeControlCenter()
                        onHistoryRequested: {
                            root.loadHistory();
                            root._loadPersistedState(); // pluginService-or-file
                            ccPanel.ccView = "history";
                        }
                    }
                }

                // Updates tab (the list fills the region and scrolls itself).
                // A row click loads that package's detail and drills into the
                // in-panel detail sub-view.
                UpdatesView {
                    visible: ccPanel.ccView === "updates"
                    embedded: true
                    embeddedListHeight: ccContent.height
                    onDismissRequested: PopoutService.closeControlCenter && PopoutService.closeControlCenter()
                    onRowActivated: item => {
                        root.loadDetail(item);
                        ccPanel.ccView = "detail";
                    }
                }

                // Detail sub-view (drill-in from the Updates list). Back returns
                // to the list; update/downgrade close the control center. Body
                // height fills what's left after the fixed header + action rows.
                DetailView {
                    visible: ccPanel.ccView === "detail"
                    embedded: true
                    embeddedBodyHeight: Math.max(root.detailRowHeight, ccContent.height - 140)
                    onBackRequested: ccPanel.ccView = "updates"
                    onDismissRequested: PopoutService.closeControlCenter && PopoutService.closeControlCenter()
                }

                // History sub-view (from the Menu). Back returns to the menu; a
                // failed row drills into the failure detail.
                HistoryView {
                    visible: ccPanel.ccView === "history"
                    embedded: true
                    embeddedListHeight: Math.max(root.detailRowHeight, ccContent.height - 96)
                    onBackRequested: ccPanel.ccView = "menu"
                    onFailureActivated: entry => {
                        root.aiError = "";
                        root.failureDetail = entry;
                        ccPanel.ccView = "faildetail";
                    }
                }

                // Failure-detail sub-view (from history). Scrolls as a whole so
                // the reason, AI suggestion and log never clip. Back → history.
                Flickable {
                    anchors.fill: parent
                    visible: ccPanel.ccView === "faildetail"
                    clip: true
                    contentWidth: width
                    contentHeight: ccFailDetail.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    FailDetailView {
                        id: ccFailDetail
                        embedded: true
                        embeddedBodyHeight: 140
                        onBackRequested: ccPanel.ccView = "history"
                        onDismissRequested: PopoutService.closeControlCenter && PopoutService.closeControlCenter()
                    }
                }
            }
        }
    }

    // =====================================================================
    // History + failure-detail views (top-level so the control-center panel
    // can host them too). backRequested/dismissRequested decouple from the
    // popout; embedded fits the CC panel.
    // =====================================================================
    // ---------------- Update history ----------------
    component HistoryView: Column {
        id: hyv
        // backRequested = back to the menu; failureActivated = a failed row was
        // clicked (host opens its failure-detail view). embedded fits the CC.
        signal backRequested()
        signal failureActivated(var entry)
        property bool embedded: false
        property real embeddedListHeight: 0
        readonly property real contentWidth: width - leftPadding - rightPadding
        width: parent ? parent.width : 0
        padding: hyv.embedded ? 0 : root.popoutPad
        spacing: hyv.embedded ? Theme.spacingS : Theme.spacingM

        // Text filter (matches name/version) + optional failed-only / AI-only.
        property string filterText: ""
        property bool failedOnly: false
        property bool aiOnly: false
        readonly property bool hasFailures: root.historyCombined.some(function (i) { return i.action === "failed"; })
        readonly property bool hasAi: root.historyCombined.some(function (i) { return i.ai !== undefined && i.ai !== ""; })
        readonly property var filteredItems: {
            var base = root.historyCombined;
            if (aiOnly)
                base = base.filter(function (i) { return i.ai !== undefined && i.ai !== ""; });
            else if (failedOnly)
                base = base.filter(function (i) { return i.action === "failed"; });
            if (filterText !== "")
                base = base.filter(function (i) { return root._matchesFilter(i, hyv.filterText); });
            return base;
        }
        // Sort: name or update date.
        readonly property var displayItems: {
            var arr = filteredItems.slice();
            var dir = histSort.asc ? 1 : -1;
            var key = histSort.activeKey;
            arr.sort(function (a, b) {
                var c;
                if (key === "name") {
                    c = String(a.name || "").localeCompare(String(b.name || ""));
                    if (c === 0)
                        c = root._stampToEpoch(a.when) - root._stampToEpoch(b.when);
                } else {
                    c = root._stampToEpoch(a.when) - root._stampToEpoch(b.when);
                }
                return c * dir;
            });
            return arr;
        }

        // Header: back to menu + title + count
        Item {
            width: hyv.contentWidth
            height: 40
            DankActionButton {
                id: histBack
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 28
                iconName: "arrow_back"
                iconSize: 18
                iconColor: Theme.surfaceText
                onClicked: hyv.backRequested()
            }
            StyledText {
                anchors.left: histBack.right
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: "Update History"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
                color: Theme.surfaceText
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.historyLoading ? "Loading…" : (hyv.displayItems.length + " entries")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
                DankActionButton {
                    buttonSize: 28
                    iconName: "refresh"
                    iconSize: 18
                    iconColor: Theme.surfaceText
                    onClicked: root.loadHistory()
                }
            }
        }

        // Text filter — search history by package name or version.
        DankTextField {
            width: hyv.contentWidth
            height: 40
            visible: root.historyCombined.length > 0
            leftIconName: "search"
            showClearButton: true
            placeholderText: "Filter history…"
            text: hyv.filterText
            onTextEdited: hyv.filterText = text
        }

        // Sort selector (name / date) + failed-only filter toggle.
        Item {
            width: hyv.contentWidth
            height: 24
            visible: root.historyCombined.length > 0
            SortChips {
                id: histSort
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                activeKey: "date"
                asc: false
                options: [ { key: "date", label: "Date" }, { key: "name", label: "Name" } ]
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                FilterChip {
                    visible: hyv.hasAi
                    label: "AI fix"
                    icon: "neurology"
                    activeColor: Theme.primary
                    active: hyv.aiOnly
                    onToggled: { hyv.aiOnly = !hyv.aiOnly; if (hyv.aiOnly) hyv.failedOnly = false; }
                }
                FilterChip {
                    visible: hyv.hasFailures
                    label: "Failed only"
                    icon: "error"
                    activeColor: Theme.error
                    active: hyv.failedOnly
                    onToggled: { hyv.failedOnly = !hyv.failedOnly; if (hyv.failedOnly) hyv.aiOnly = false; }
                }
            }
        }

        Rectangle {
            width: hyv.contentWidth
            height: hyv.embedded
                ? Math.max(root.detailRowHeight, hyv.embeddedListHeight)
                : Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.1)

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingL * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: !root.historyLoading && hyv.displayItems.length === 0
                text: {
                    if (root.historyCombined.length === 0)
                        return "No update history found in the package log.";
                    if (hyv.failedOnly && hyv.filterText === "")
                        return "No failed updates recorded.";
                    return "No history entries match \"" + hyv.filterText + "\"";
                }
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }

            DankListView {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                visible: hyv.displayItems.length > 0
                clip: true
                spacing: Theme.spacingXS
                model: hyv.displayItems

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool isFailed: modelData.action === "failed"
                    readonly property bool isDowngrade: modelData.action === "downgraded"
                    // Accent color per row kind: failed → error, downgrade
                    // → warning, upgrade → primary.
                    readonly property color accent: isFailed ? Theme.error : (isDowngrade ? Theme.warning : Theme.primary)
                    width: ListView.view ? ListView.view.width : 0
                    height: root.detailRowHeight
                    radius: Theme.cornerRadius
                    color: histHover.containsMouse ? Theme.primaryHoverLight
                        : (isFailed ? Theme.withAlpha(Theme.error, 0.08) : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                    // Failed rows open a detail view (reason + captured
                    // log); successful rows are informational only.
                    MouseArea {
                        id: histHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: isFailed ? Qt.PointingHandCursor : Qt.ArrowCursor
                        acceptedButtons: isFailed ? Qt.LeftButton : Qt.NoButton
                        onClicked: {
                            if (isFailed)
                                hyv.failureActivated(modelData);
                        }
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            radius: 12
                            color: Theme.withAlpha(accent, isFailed ? 0.18 : (isDowngrade ? 0.20 : 0.15))
                            DankIcon {
                                anchors.centerIn: parent
                                name: isFailed ? "error" : (isDowngrade ? "arrow_downward" : "arrow_upward")
                                size: Theme.fontSizeSmall + 2
                                color: accent
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24 - Theme.spacingM * 2 - whenText.width - (isFailed ? chev.width + Theme.spacingM : 0)
                            spacing: 2
                            Row {
                                width: parent.width
                                spacing: Theme.spacingXS
                                StyledText {
                                    width: Math.min(implicitWidth, parent.width
                                        - (failChip.visible ? failChip.width + Theme.spacingXS : 0)
                                        - (aiChip.visible ? aiChip.width + Theme.spacingXS : 0))
                                    text: modelData.name
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    wrapMode: Text.NoWrap
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                }
                                // Small "failed" chip so a failed row reads
                                // as a failure even at a glance.
                                Rectangle {
                                    id: failChip
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: isFailed
                                    width: failChipText.implicitWidth + Theme.spacingS
                                    height: 16
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.error, 0.22)
                                    StyledText {
                                        id: failChipText
                                        anchors.centerIn: parent
                                        text: "failed"
                                        font.pixelSize: Theme.fontSizeSmall - 2
                                        font.weight: Font.Bold
                                        color: Theme.error
                                    }
                                }
                                // "AI" chip when this failure has a saved AI fix.
                                Rectangle {
                                    id: aiChip
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.ai !== undefined && modelData.ai !== ""
                                    width: aiChipRow.implicitWidth + Theme.spacingS
                                    height: 16
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.primary, 0.20)
                                    Row {
                                        id: aiChipRow
                                        anchors.centerIn: parent
                                        spacing: 1
                                        DankIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "neurology"
                                            size: Theme.fontSizeSmall - 1
                                            color: Theme.primary
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "AI"
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                            font.weight: Font.Bold
                                            color: Theme.primary
                                        }
                                    }
                                }
                            }
                            StyledText {
                                width: parent.width
                                text: {
                                    var ver = (modelData.oldVersion || "?") + "  →  " + (modelData.newVersion || "?");
                                    if (isFailed) {
                                        var hasVer = (modelData.oldVersion || "") !== "" || (modelData.newVersion || "") !== "";
                                        return (modelData.reason || "Failed") + (hasVer ? "  ·  " + ver : "");
                                    }
                                    return ver;
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: accent
                                wrapMode: Text.NoWrap
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }
                        }

                        StyledText {
                            id: whenText
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._fmtHistoryWhen(modelData.when)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        // Click affordance — only failed rows are clickable.
                        DankIcon {
                            id: chev
                            anchors.verticalCenter: parent.verticalCenter
                            visible: isFailed
                            name: "chevron_right"
                            size: Theme.iconSize - 4
                            color: Theme.error
                        }
                    }
                }
            }
        }
    }

    // Detail for a single failed update: reason, attempted version,
    // source, full timestamp, and the captured log tail (if saved).
    component FailDetailView: Column {
        id: fdv
        // backRequested = back to the history list; dismissRequested = close the
        // whole surface (so running a command hands focus to the new terminal).
        // embedded fits the CC panel (host-driven body/log height).
        signal backRequested()
        signal dismissRequested()
        property bool embedded: false
        property real embeddedBodyHeight: 0
        // Collapsible sections (AI open by default, the verbose log closed).
        property bool aiExpanded: true
        property bool logExpanded: false
        property bool outputExpanded: true
        property bool confirmingClear: false // "delete conversation?" prompt
        readonly property real contentWidth: width - leftPadding - rightPadding
        width: parent ? parent.width : 0
        padding: fdv.embedded ? 0 : root.popoutPad
        spacing: fdv.embedded ? Theme.spacingS : Theme.spacingM

        readonly property var entry: root.failureDetail || ({})
        readonly property string logText: entry && entry.log ? entry.log : ""
        readonly property bool hasVersions: (entry.oldVersion || "") !== "" || (entry.newVersion || "") !== ""
        readonly property var fields: {
            // Source + version now live in the header; keep Reason/When/Fix here.
            var f = [{ label: "Reason", value: entry.reason || "Failed", err: true }];
            f.push({ label: "When", value: root._fmtHistoryWhen(entry.when || ""), err: false });
            if (entry.reason === root.reasonPkgbuildDiff)
                f.push({ label: "Fix", value: "The package's PKGBUILD changed, so Shelly refused to build it non-interactively. Use \"Run interactive update\" below (or run \"shelly update aur " + (entry.name || "<pkg>") + "\" in a terminal), review the diff, and accept it — updates will work again afterwards.", err: false });
            if (entry.reason === root.reasonDepConflict)
                f.push({ label: "Fix", value: "An upgrade needs a newer shared library (soname) than a held or AUR package provides — held packages aren't upgraded but still block resolution, so the whole transaction is refused. This usually means a package group must be rebuilt together against the new library (e.g. the hypr* -git stack after a libhyprutils soname bump): rebuild the whole group in one go, then run the update again. See the \"breaks dependency …\" lines in the log below for the exact library and packages involved.", err: false });
            return f;
        }

        // Header: back + package name / version transition + source & failed
        // chips (mirrors the package-detail header).
        Item {
            width: fdv.contentWidth
            height: 52
            DankActionButton {
                id: fdBack
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 28
                iconName: "arrow_back"
                iconSize: 18
                iconColor: Theme.surfaceText
                onClicked: fdv.backRequested()
            }
            Column {
                anchors.left: fdBack.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: fdChips.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                StyledText {
                    width: parent.width
                    text: fdv.entry.name || ""
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    visible: fdv.hasVersions
                    text: (fdv.entry.oldVersion || "?") + "  →  " + (fdv.entry.newVersion || "?")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    elide: Text.ElideRight
                }
            }
            Row {
                id: fdChips
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (fdv.entry.source || "") !== ""
                    width: fdSrcText.implicitWidth + Theme.spacingS
                    height: 20
                    radius: Theme.cornerRadius
                    color: Theme.secondaryHover
                    StyledText {
                        id: fdSrcText
                        anchors.centerIn: parent
                        text: fdv.entry.source || ""
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceVariantText
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52
                    height: 20
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.error, 0.22)
                    StyledText {
                        anchors.centerIn: parent
                        text: "failed"
                        font.pixelSize: Theme.fontSizeSmall - 1
                        font.weight: Font.Bold
                        color: Theme.error
                    }
                }
            }
        }

        // Structured fields
        Column {
            width: fdv.contentWidth
            spacing: Theme.spacingXS
            Repeater {
                model: fdv.fields
                delegate: Row {
                    required property var modelData
                    width: fdv.contentWidth
                    spacing: Theme.spacingM
                    StyledText {
                        width: 96
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    StyledText {
                        width: parent.width - 96 - Theme.spacingM
                        text: modelData.value
                        font.pixelSize: Theme.fontSizeSmall
                        color: modelData.err ? Theme.error : Theme.surfaceText
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }

        // Review-required failure (changed PKGBUILD): the actual fix is an
        // interactive re-run where the user accepts the diff. Primary action,
        // shown above the AI/log buttons for the reasons that need it.
        DetailActionButton {
            width: fdv.contentWidth
            visible: fdv.entry && root._reasonNeedsInteractive(fdv.entry.reason) && !root.isUpgrading
            icon: "rate_review"
            label: "Run interactive update"
            onTriggered: {
                root.runInteractiveUpdate(fdv.entry);
                fdv.dismissRequested();
            }
        }

        // ---- AI failure analysis ----
        readonly property string aiText: (entry && entry.ai) ? entry.ai : ""

        DetailActionButton {
            width: fdv.contentWidth
            visible: root.aiReady && fdv.aiText === "" && !root.aiLoading
            icon: "neurology"
            label: "Suggest fix with AI"
            onTriggered: root.requestAiSuggestion()
        }
        StyledText {
            width: fdv.contentWidth
            visible: root.aiError !== "" && !root.aiLoading
            text: root.aiError
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.WordWrap
        }
        // "AI suggestion" collapsible header with a re-run button (regenerate —
        // useful when a prior run errored, e.g. the AI CLI wasn't authenticated
        // and its error text got saved as the "answer"). Click the row to
        // collapse/expand; the re-run button sits on top and captures its clicks.
        Item {
            width: fdv.contentWidth
            visible: fdv.aiText !== ""
            height: visible ? 28 : 0
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: fdv.aiExpanded = !fdv.aiExpanded
            }
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: fdv.aiExpanded ? "expand_more" : "chevron_right"
                    size: Theme.iconSize - 6
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AI suggestion"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                DankActionButton {
                    buttonSize: 24
                    iconName: "delete"
                    iconSize: 14
                    iconColor: Theme.surfaceVariantText
                    enabled: !root.aiLoading
                    opacity: enabled ? 1.0 : 0.4
                    tooltipText: "Delete this conversation"
                    onClicked: fdv.confirmingClear = true
                }
                DankActionButton {
                    buttonSize: 24
                    iconName: "refresh"
                    iconSize: 14
                    iconColor: Theme.surfaceVariantText
                    enabled: root.aiReady && !root.aiLoading
                    opacity: enabled ? 1.0 : 0.4
                    tooltipText: root.aiReady ? "Re-run the AI suggestion" : "Configure an AI command in Settings → AI"
                    onClicked: root.requestAiSuggestion()
                }
            }
        }
        // "Delete conversation?" confirmation — shown in place of the box.
        Rectangle {
            width: fdv.contentWidth
            visible: fdv.aiText !== "" && fdv.confirmingClear
            height: visible ? clearCol.implicitHeight + Theme.spacingM * 2 : 0
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.error, 0.10)
            border.width: 1
            border.color: Theme.withAlpha(Theme.error, 0.35)
            Column {
                id: clearCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS
                StyledText {
                    width: parent.width
                    text: "Delete this AI conversation? The suggestion and all follow-ups will be permanently lost."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                }
                Row {
                    anchors.right: parent.right
                    spacing: Theme.spacingS
                    Rectangle {
                        width: cancelClearText.implicitWidth + Theme.spacingM * 2
                        height: 30
                        radius: Theme.cornerRadius
                        color: cancelClearHover.containsMouse ? Theme.primaryHoverLight : Theme.secondaryHover
                        StyledText { id: cancelClearText; anchors.centerIn: parent; text: "Cancel"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText }
                        MouseArea { id: cancelClearHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: fdv.confirmingClear = false }
                    }
                    Rectangle {
                        width: doClearRow.implicitWidth + Theme.spacingM * 2
                        height: 30
                        radius: Theme.cornerRadius
                        color: doClearHover.containsMouse ? Theme.withAlpha(Theme.error, 0.30) : Theme.withAlpha(Theme.error, 0.18)
                        Row {
                            id: doClearRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            DankIcon { anchors.verticalCenter: parent.verticalCenter; name: "delete"; size: Theme.iconSize - 6; color: Theme.error }
                            StyledText { anchors.verticalCenter: parent.verticalCenter; text: "Delete"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.error }
                        }
                        MouseArea {
                            id: doClearHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.clearAiConversation();
                                fdv.confirmingClear = false;
                            }
                        }
                    }
                }
            }
        }
        Rectangle {
            width: fdv.contentWidth
            visible: fdv.aiText !== "" && fdv.aiExpanded && !fdv.confirmingClear
            // Full content height — the surrounding view scrolls as a whole, so
            // the conversation isn't trapped behind a small nested scroll.
            height: visible ? aiCol.implicitHeight + Theme.spacingM * 2 : 0
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.primary, 0.08)
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, 0.25)

            Flickable {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                clip: true
                contentHeight: aiCol.implicitHeight
                contentWidth: width
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: aiCol
                    width: parent.width
                    spacing: Theme.spacingS
                    Repeater {
                        // One bubble per conversation turn: AI on the left,
                        // the user's follow-ups on the right.
                        model: root._aiConversationTurns(fdv.entry)
                        delegate: Item {
                            required property var modelData
                            readonly property bool isUser: modelData.role === "user"
                            width: aiCol.width
                            implicitHeight: bubble.height
                            Rectangle {
                                id: bubble
                                width: aiCol.width * 0.9
                                x: isUser ? (aiCol.width - width) : 0
                                height: bubbleCol.implicitHeight + Theme.spacingS * 2
                                radius: Theme.cornerRadius
                                color: isUser ? Theme.withAlpha(Theme.secondary, 0.16)
                                              : Theme.withAlpha(Theme.primary, 0.10)
                                Column {
                                    id: bubbleCol
                                    x: Theme.spacingS
                                    y: Theme.spacingS
                                    width: bubble.width - Theme.spacingS * 2
                                    spacing: Theme.spacingXS
                                    // User turn: plain text.
                                    StyledText {
                                        visible: isUser
                                        width: parent.width
                                        text: modelData.text || ""
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        wrapMode: Text.WordWrap
                                    }
                                    // Assistant turn: prose blocks + "$ " command
                                    // rows with copy/run buttons.
                                    Repeater {
                                        model: isUser ? [] : modelData.segments
                                        delegate: Item {
                                            required property var modelData
                                            readonly property bool interactive: modelData.interactive === true
                                            width: bubbleCol.width
                                            implicitHeight: modelData.cmd
                                                ? (cmdRow.height + (interactive ? interactiveHint.height + 2 : 0))
                                                : txtBlock.implicitHeight
                                            StyledText {
                                                id: txtBlock
                                                visible: !modelData.cmd
                                                width: parent.width
                                                text: modelData.value
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceText
                                                wrapMode: Text.WordWrap
                                            }
                                            // "Needs a terminal" hint under an interactive command.
                                            Row {
                                                id: interactiveHint
                                                visible: modelData.cmd && parent.interactive
                                                y: cmdRow.height + 2
                                                x: Theme.spacingS
                                                height: visible ? intHintText.implicitHeight : 0
                                                spacing: 3
                                                DankIcon {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    name: "terminal"
                                                    size: Theme.fontSizeSmall
                                                    color: Theme.warning
                                                }
                                                StyledText {
                                                    id: intHintText
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "Interactive — opens a terminal (can't run inline)"
                                                    font.pixelSize: Theme.fontSizeSmall - 2
                                                    color: Theme.warning
                                                }
                                            }
                                            Rectangle {
                                                id: cmdRow
                                                visible: modelData.cmd
                                                width: parent.width
                                                height: visible ? Math.max(30, cmdText.implicitHeight + Theme.spacingXS * 2) : 0
                                                radius: Theme.cornerRadius
                                                color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.35)
                                                StyledText {
                                                    id: cmdText
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: Theme.spacingS
                                                    anchors.right: cmdBtns.left
                                                    anchors.rightMargin: Theme.spacingXS
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.value
                                                    font.family: Theme.monoFontFamily
                                                    font.pixelSize: Theme.fontSizeSmall - 1
                                                    color: Theme.primary
                                                    wrapMode: Text.Wrap
                                                }
                                                Row {
                                                    id: cmdBtns
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: Theme.spacingXS
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 0
                                                    DankActionButton {
                                                        buttonSize: 26
                                                        iconName: "content_copy"
                                                        iconSize: 14
                                                        iconColor: Theme.surfaceVariantText
                                                        tooltipText: "Copy"
                                                        onClicked: Quickshell.execDetached(["dms", "cl", "copy", modelData.value])
                                                    }
                                                    // Inline run — hidden for commands the AI
                                                    // flagged interactive ("$! "), which need a TTY.
                                                    DankActionButton {
                                                        visible: !modelData.interactive
                                                        buttonSize: 26
                                                        iconName: "play_arrow"
                                                        iconSize: 16
                                                        iconColor: Theme.primary
                                                        enabled: !root.aiRunning
                                                        opacity: enabled ? 1.0 : 0.4
                                                        tooltipText: "Run here (output shown below)"
                                                        onClicked: {
                                                            fdv.outputExpanded = true;
                                                            root.runAiCommandInline(modelData.value);
                                                        }
                                                    }
                                                    DankActionButton {
                                                        buttonSize: 26
                                                        iconName: "open_in_new"
                                                        iconSize: 15
                                                        // Emphasised (primary) for interactive commands —
                                                        // the terminal is the intended way to run them.
                                                        iconColor: modelData.interactive ? Theme.primary : Theme.surfaceVariantText
                                                        tooltipText: modelData.interactive ? "Needs a terminal — run here" : "Run in a terminal window"
                                                        onClicked: {
                                                            root.runAiCommand(modelData.value);
                                                            fdv.dismissRequested();
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // In-flight indicator (click to cancel) — placed below the conversation
        // so a follow-up's "Asking the AI…" flows under the existing chat.
        Rectangle {
            width: fdv.contentWidth
            visible: root.aiLoading
            height: visible ? 40 : 0
            radius: Theme.cornerRadius
            color: Theme.secondaryHover
            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                DankIcon {
                    id: aiSpinner
                    anchors.verticalCenter: parent.verticalCenter
                    name: "progress_activity"
                    size: Theme.iconSize - 2
                    color: Theme.primary
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1000
                        loops: Animation.Infinite; running: root.aiLoading
                        onRunningChanged: { if (!running) aiSpinner.rotation = 0; }
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Asking the AI… (click to cancel)"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cancelAiSuggestion()
            }
        }

        // Continue the conversation: Check-result verifies the fix (auto-feeding
        // the last inline command output), and the input sends a free follow-up.
        // Both carry the full transcript so the AI has the original context.
        Column {
            width: fdv.contentWidth
            visible: fdv.aiText !== "" && fdv.aiExpanded && !fdv.confirmingClear
            spacing: Theme.spacingXS
            DetailActionButton {
                width: fdv.contentWidth
                btnEnabled: root.aiReady && !root.aiLoading
                icon: "fact_check"
                label: "Check whether it worked"
                onTriggered: root.checkAiResult()
            }
            Row {
                width: parent.width
                spacing: Theme.spacingXS
                DankTextField {
                    id: followupField
                    width: parent.width - followupSend.width - Theme.spacingXS
                    height: 36
                    placeholderText: "Ask a follow-up…"
                    enabled: root.aiReady && !root.aiLoading
                    onAccepted: {
                        if (text.trim() !== "") {
                            root.sendAiFollowup(text);
                            text = "";
                        }
                    }
                }
                DankActionButton {
                    id: followupSend
                    buttonSize: 34
                    iconName: "send"
                    iconSize: 16
                    iconColor: Theme.primary
                    enabled: root.aiReady && !root.aiLoading && followupField.text.trim() !== ""
                    opacity: enabled ? 1.0 : 0.4
                    tooltipText: "Send follow-up"
                    onClicked: {
                        root.sendAiFollowup(followupField.text);
                        followupField.text = "";
                    }
                }
            }
        }

        // ---- Inline command output (from the "Run here" button) ----
        Item {
            width: fdv.contentWidth
            visible: root.aiRunCmd !== ""
            height: visible ? 28 : 0
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: fdv.outputExpanded = !fdv.outputExpanded
            }
            Row {
                anchors.left: parent.left
                anchors.right: outCancel.left
                anchors.rightMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: fdv.outputExpanded ? "expand_more" : "chevron_right"
                    size: Theme.iconSize - 6
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Command output"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }
                DankIcon {
                    id: outSpinner
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.aiRunning
                    name: "progress_activity"
                    size: Theme.iconSize - 8
                    color: Theme.primary
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1000
                        loops: Animation.Infinite; running: root.aiRunning
                        onRunningChanged: { if (!running) outSpinner.rotation = 0; }
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.aiRunDone && !root.aiRunning
                    text: root.aiRunExit === 0 ? "exit 0" : ("exit " + root.aiRunExit)
                    font.pixelSize: Theme.fontSizeSmall - 1
                    font.weight: Font.Medium
                    color: root.aiRunExit === 0 ? Theme.primary : Theme.error
                }
            }
            DankActionButton {
                id: outCancel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.aiRunning
                buttonSize: 24
                iconName: "stop"
                iconSize: 14
                iconColor: Theme.error
                tooltipText: "Cancel"
                onClicked: root.cancelAiRun()
            }
        }
        Rectangle {
            width: fdv.contentWidth
            visible: root.aiRunCmd !== "" && fdv.outputExpanded
            height: !visible ? 0 : (fdv.embedded
                ? Math.max(root.detailRowHeight, fdv.embeddedBodyHeight)
                : Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2)
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.1)

            Flickable {
                id: outFlick
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                clip: true
                contentHeight: outCol.height
                contentWidth: width
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                // Keep pinned to the bottom as output streams in (terminal-like).
                onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                Column {
                    id: outCol
                    width: outFlick.width
                    StyledText {
                        width: parent.width
                        text: "$ " + root.aiRunCmd
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.primary
                        wrapMode: Text.WrapAnywhere
                    }
                    StyledText {
                        width: parent.width
                        visible: root.aiRunOutput !== ""
                        text: root.aiRunOutput
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceText
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }

        // Captured log tail — collapsible header (verbose, collapsed by default).
        Item {
            width: fdv.contentWidth
            height: 28
            MouseArea {
                anchors.fill: parent
                enabled: fdv.logText !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: fdv.logExpanded = !fdv.logExpanded
            }
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fdv.logText !== ""
                    name: fdv.logExpanded ? "expand_more" : "chevron_right"
                    size: Theme.iconSize - 6
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: fdv.logText !== "" ? "Log (tail of the failed run)" : "No log was saved for this failure."
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }
            }
        }
        Rectangle {
            width: fdv.contentWidth
            visible: fdv.logText !== "" && fdv.logExpanded
            // Full content height (outer view scrolls the whole detail).
            height: !visible ? 0 : logCol.height + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.1)

            Item {
                id: logFlick
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                clip: true

                Column {
                    id: logCol
                    width: logFlick.width
                    StyledText {
                        width: parent.width
                        text: fdv.logText
                        font.family: Theme.monoFontFamily
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceText
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }

        // Open the full live log — only meaningful for the most recent run
        // (older runs' logs are gone; we only kept the excerpt), so gate on the
        // last-run failure set rather than the broader unresolved set.
        DetailActionButton {
            width: fdv.contentWidth
            visible: root.failedPackages.indexOf(fdv.entry.name) !== -1
            icon: "description"
            label: "View full log"
            onTriggered: root.viewLastLog()
        }
        // Acknowledge: drop this from the unresolved surfacing (stays in
        // history). Only offered while it's still surfaced as unresolved.
        DetailActionButton {
            width: fdv.contentWidth
            visible: root._isFailed(fdv.entry.name)
            icon: "notifications_off"
            label: "Dismiss (acknowledge)"
            onTriggered: {
                root.dismissFailure(fdv.entry.name);
                fdv.backRequested();
            }
        }
    }

    // =====================================================================
    // Popout (mode-switching: updates view or menu)
    // =====================================================================
    popoutContent: Component {
        PopoutComponent {
            id: popout
            showCloseButton: false

            // Track the popout's REAL visibility. DankPopout keeps this content
            // loaded across open/close (only shouldBeVisible toggles), so the old
            // onCompleted/onDestruction latch went stale — leaving popoutOpen
            // stuck true and swallowing the first click of the opposite button.
            Component.onCompleted: {
                if (root.popoutMode === "updates" && root.updateCount === 0 && !root.isChecking)
                    root.refresh(false);
            }
            Component.onDestruction: root.popoutOpen = false
            onParentPopoutChanged: {
                if (parentPopout)
                    root.popoutOpen = parentPopout.shouldBeVisible;
            }
            Connections {
                target: popout.parentPopout
                enabled: popout.parentPopout !== null
                function onShouldBeVisibleChanged() {
                    const vis = popout.parentPopout.shouldBeVisible;
                    root.popoutOpen = vis;
                    if (vis && root.popoutMode === "updates" && root.updateCount === 0 && !root.isChecking)
                        root.refresh(false);
                }
            }

            // ---------------- Updates view ----------------
            Loader {
                active: root.popoutMode === "updates"
                visible: active
                width: parent.width
                sourceComponent: UpdatesView {
                    onDismissRequested: popout.closePopout && popout.closePopout()
                    onRowActivated: item => root.openDetail(item)
                }
            }

            // ---------------- Menu view ----------------
            Loader {
                active: root.popoutMode === "menu"
                visible: active
                width: parent.width
                sourceComponent: MenuView {
                    onDismissRequested: popout.closePopout && popout.closePopout()
                    onHistoryRequested: root.openHistory()
                }
            }

            // ---------------- Package-detail view ----------------
            Loader {
                active: root.popoutMode === "detail"
                visible: active
                width: parent.width
                sourceComponent: DetailView {
                    onBackRequested: root.closeDetail()
                    onDismissRequested: popout.closePopout && popout.closePopout()
                }
            }

            // ---------------- Held-packages manager ----------------
            Loader {
                active: root.popoutMode === "held"
                visible: active
                width: parent.width
                sourceComponent: HeldView {}
            }

            // ---------------- Update history ----------------
            Loader {
                active: root.popoutMode === "history"
                visible: active
                width: parent.width
                sourceComponent: HistoryView {
                    onBackRequested: root.openMode("menu")
                    onFailureActivated: entry => root.openFailureDetail(entry)
                }
            }

            // ---------------- Failure detail ----------------
            // Wrapped in a Flickable capped at the screen height so the whole
            // detail (AI conversation + output + log) scrolls as one — the
            // popout can't grow past the screen, so without this the bottom is
            // unreachable.
            Loader {
                active: root.popoutMode === "faildetail"
                visible: active
                width: parent.width
                sourceComponent: Flickable {
                    readonly property real maxH: Math.max(320, (root.parentScreen ? root.parentScreen.height : Screen.height) - 160)
                    implicitHeight: Math.min(fdItem.implicitHeight, maxH)
                    height: implicitHeight
                    contentHeight: fdItem.implicitHeight
                    contentWidth: width
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    FailDetailView {
                        id: fdItem
                        width: parent.width
                        onBackRequested: root.closeFailureDetail()
                        onDismissRequested: popout.closePopout && popout.closePopout()
                    }
                }
            }

            component HeldView: Column {
                id: hv
                readonly property real contentWidth: width - leftPadding - rightPadding
                width: parent ? parent.width : 0
                padding: root.popoutPad
                spacing: Theme.spacingM

                // Header: back to menu + title
                Item {
                    width: hv.contentWidth
                    height: 40
                    DankActionButton {
                        id: heldBack
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: 28
                        iconName: "arrow_back"
                        iconSize: 18
                        iconColor: Theme.surfaceText
                        onClicked: root.openMode("menu")
                    }
                    StyledText {
                        anchors.left: heldBack.right
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Held Packages"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                }

                Rectangle {
                    width: hv.contentWidth
                    height: Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.1)

                    StyledText {
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingL * 2
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: root.ignoredPackages.length === 0
                        text: "No held packages.\nRight-click a package in the updates list, or use Hold in its details, to pin it here."
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    DankListView {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        visible: root.ignoredPackages.length > 0
                        clip: true
                        spacing: Theme.spacingXS
                        model: root.ignoredPackages

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            height: 44
                            radius: Theme.cornerRadius
                            color: heldHover.containsMouse ? Theme.primaryHoverLight : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
                            MouseArea { id: heldHover; anchors.fill: parent; hoverEnabled: true }

                            StyledText {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.right: unholdBtn.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                            }
                            DankActionButton {
                                id: unholdBtn
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingXS
                                anchors.verticalCenter: parent.verticalCenter
                                buttonSize: 30
                                iconName: "delete"
                                iconSize: 18
                                iconColor: Theme.error
                                onClicked: root.unholdPackage(modelData)
                            }
                        }
                    }
                }
            }

        }
    }
}
