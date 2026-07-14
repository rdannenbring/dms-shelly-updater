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

    // ---- Settings (bound to pluginData so they react to changes) ----
    readonly property bool autoCheck: pluginData.autoCheck !== undefined ? pluginData.autoCheck : true
    readonly property int checkFrequency: parseInt(pluginData.checkFrequency || "60") // minutes
    readonly property bool checkAtStartup: pluginData.checkAtStartup !== undefined ? pluginData.checkAtStartup : true
    readonly property bool confirmations: pluginData.confirmations !== undefined ? pluginData.confirmations : true
    readonly property bool enableAur: pluginData.enableAur !== undefined ? pluginData.enableAur : true
    readonly property bool enableFlatpak: pluginData.enableFlatpak !== undefined ? pluginData.enableFlatpak : true
    readonly property bool enableAppimage: pluginData.enableAppimage !== undefined ? pluginData.enableAppimage : false
    readonly property bool excludeDevelAur: pluginData.excludeDevelAur !== undefined ? pluginData.excludeDevelAur : false
    readonly property bool alwaysConfirmKernel: pluginData.alwaysConfirmKernel !== undefined ? pluginData.alwaysConfirmKernel : false
    readonly property string iconDefault: pluginData.iconDefault || "check_circle"
    readonly property string iconUpdates: pluginData.iconUpdates || "system_update_alt"
    readonly property bool showCount: pluginData.showCount !== undefined ? pluginData.showCount : true
    readonly property string countPositionH: pluginData.countPositionH || "right" // left | right
    readonly property string countPositionV: pluginData.countPositionV || "bottom" // top | bottom
    readonly property bool showTooltip: pluginData.showTooltip !== undefined ? pluginData.showTooltip : false
    readonly property bool tooltipShowPackages: pluginData.tooltipShowPackages !== undefined ? pluginData.tooltipShowPackages : false
    readonly property int tooltipDelay: parseInt(pluginData.tooltipDelay !== undefined ? pluginData.tooltipDelay : 500) // ms
    readonly property bool tooltipFade: pluginData.tooltipFade !== undefined ? pluginData.tooltipFade : true
    readonly property int detailRows: parseInt(pluginData.detailRows !== undefined ? pluginData.detailRows : 6)
    readonly property bool showOpenShellyMenuItem: pluginData.showOpenShellyMenuItem !== undefined ? pluginData.showOpenShellyMenuItem : true
    readonly property bool notifyOnUpdates: pluginData.notifyOnUpdates !== undefined ? pluginData.notifyOnUpdates : false
    readonly property int notifyThreshold: parseInt(pluginData.notifyThreshold !== undefined ? pluginData.notifyThreshold : 1)
    readonly property string leftClickAction: pluginData.leftClickAction || "updates" // updates | menu | ui | none
    readonly property string middleClickAction: pluginData.middleClickAction || "none"
    readonly property string rightClickAction: pluginData.rightClickAction || "menu"
    readonly property string terminal: pluginData.terminal || Quickshell.env("TERMINAL") || "kitty"
    readonly property bool closeTerminalOnDone: pluginData.closeTerminalOnDone !== undefined ? pluginData.closeTerminalOnDone : false
    readonly property bool detectFailedUpdates: pluginData.detectFailedUpdates !== undefined ? pluginData.detectFailedUpdates : true
    // Retention for the self-kept failed-update log (days). Capped by the
    // settings slider; clamped defensively here too.
    readonly property int failureHistoryDays: Math.max(1, Math.min(180, parseInt(pluginData.failureHistoryDays !== undefined ? pluginData.failureHistoryDays : 30)))
    // Resource limits so big (AUR) builds don't peg the machine and make the
    // desktop unresponsive. Off by default (no change to how updates run).
    readonly property bool limitBuildResources: pluginData.limitBuildResources !== undefined ? pluginData.limitBuildResources : false
    readonly property bool lowerPriority: pluginData.lowerPriority !== undefined ? pluginData.lowerPriority : true
    readonly property int maxBuildJobs: parseInt(pluginData.maxBuildJobs !== undefined ? pluginData.maxBuildJobs : 0) // 0 = unlimited

    // ---- Live state ----
    property var pacmanUpdates: []
    property var aurUpdates: []
    property var flatpakUpdates: []
    property var appimageUpdates: []
    property bool isChecking: false
    property bool isUpgrading: false
    property bool hasError: false
    property string errorMessage: ""

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
    property var failedPackages: []           // names that didn't apply
    property bool _awaitingUpgradeResult: false
    property int _lastUpgradeExit: 0
    property string _lastLogText: ""          // captured session output of last run
    function _isFailed(nameOrItem) {
        var n = (typeof nameOrItem === "string") ? nameOrItem : ((nameOrItem && nameOrItem.name) || "");
        return root.failedPackages.indexOf(n) !== -1;
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
        var cutoff = Date.now() - root.failureHistoryDays * 86400000;
        return (list || []).filter(function (e) { return root._stampToEpoch(e.when) >= cutoff; });
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
    function _recordFailures(failedNames, reason, cleanLog) {
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
                reason: reason || "",
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

    // Each monitor gets its own plugin instance with independent state. A local
    // refresh() only updates this instance; refreshAll() broadcasts to every
    // instance so all monitors re-check together (used after updates and manual
    // refreshes). The broadcast rides DMS's shared plugin-state change signal.
    property double _refreshToken: 0

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

    function refresh(isBackground) {
        if (isChecking || isUpgrading)
            return;
        isChecking = true;
        _bgCheck = isBackground === true;
        hasError = false;
        errorMessage = "";
        pacmanUpdates = [];
        aurUpdates = [];
        flatpakUpdates = [];
        appimageUpdates = [];
        loadIgnored();
        var q = [{ src: "pacman", cmd: ["shelly", "list-updates", "--json"] }];
        if (enableAur)
            q.push({ src: "aur", cmd: ["shelly", "aur", "list-updates", "--json"] });
        if (enableFlatpak)
            q.push({ src: "flatpak", cmd: ["shelly", "flatpak", "list-updates", "--json"] });
        if (enableAppimage)
            q.push({ src: "appimage", cmd: ["shelly", "appimage", "list-updates", "--json"] });
        _checkQueue = q;
        _runNextCheck();
    }

    function _runNextCheck() {
        if (_checkQueue.length === 0) {
            isChecking = false;
            lastChecked = Date.now();
            if (_awaitingUpgradeResult) {
                _computeFailed();
                _awaitingUpgradeResult = false;
            }
            if (_bgCheck)
                _maybeNotify();
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
    function runInTerminal(shellyArgs, title, touchesKernel) {
        if (isUpgrading)
            return;
        var forceConfirm = alwaysConfirmKernel && touchesKernel === true;
        var full = (!confirmations && !forceConfirm) ? shellyArgs.concat(["--no-confirm"]) : shellyArgs;
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
        // With closeTerminalOnDone the window exits as soon as the run finishes;
        // otherwise it holds open on a "Press Enter" prompt.
        var inner = closeTerminalOnDone
            ? work
            : work + "; echo; echo '── " + (title || "Done") + " ── Press Enter to close'; read _";
        termProc.command = terminal.split(" ").concat(["-e", "sh", "-c", inner]);
        isUpgrading = true;
        _writeUpgradeBeat(Date.now()); // broadcast "updating" to all monitors
        termProc.running = true;
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
        var args = ["shelly", "upgrade-all"];
        if (!enableAur) args.push("--no-aur");
        if (!enableFlatpak) args.push("--no-flatpak");
        if (!enableAppimage) args.push("--no-appimage");
        _beginUpgrade(_namesOf(allShownItems()));
        runInTerminal(args, "Update All", hasKernelUpdate);
    }
    function updatePacman() {
        _beginUpgrade(_namesOf(pacmanUpdatesShown));
        runInTerminal(["shelly", "upgrade"], "System Packages", hasKernelUpdate);
    }
    function updateAur() {
        _beginUpgrade(_namesOf(aurUpdatesShown));
        runInTerminal(["shelly", "aur", "upgrade"], "AUR", false);
    }
    function updateFlatpak() {
        _beginUpgrade(_namesOf(flatpakUpdates));
        runInTerminal(["shelly", "flatpak", "upgrade"], "Flatpak", false);
    }
    function updateAppimage() {
        _beginUpgrade(_namesOf(appimageUpdates));
        runInTerminal(["shelly", "appimage", "upgrade"], "AppImage", false);
    }

    function updateOne(item) {
        var args;
        if (item.source === "pacman")
            args = ["shelly", "update", item.name];
        else if (item.source === "aur")
            args = ["shelly", "aur", "update", item.name];
        else if (item.source === "flatpak")
            args = ["shelly", "flatpak", "update", item.id];
        else if (item.source === "appimage")
            args = ["shelly", "appimage", "upgrade"];
        else
            return;
        _beginUpgrade([item.name]);
        runInTerminal(args, item.name, item.source === "pacman" && _isKernel(item));
    }

    // Interactive downgrade (Shelly lists installable older versions to pick).
    function downgradeOne(item) {
        if (!item)
            return;
        if (item.source === "aur")
            runInTerminal(["shelly", "aur", "install-version", item.name], "Downgrade " + item.name, false);
        else
            runInTerminal(["shelly", "downgrade", item.name], "Downgrade " + item.name, _isKernel(item));
    }

    // Maintenance
    function cleanCache() { runInTerminal(["shelly", "cache-clean"], "Clean Package Cache", false); }
    function removeOrphans() { runInTerminal(["shelly", "purify"], "Remove Orphans", false); }

    Process {
        id: termProc
        onExited: {
            root.isUpgrading = false;
            root._writeUpgradeBeat(0); // stop the "updating" animation everywhere
            if (root._awaitingUpgradeResult)
                statusProc.running = true; // read exit code, then re-check
            else
                root.refreshAll();
        }
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
    //   2. A transaction/hard-error marker (no per-package line) means the run
    //      failed but didn't name a culprit — flag every attempted package
    //      still pending (incl. devel, since nothing applied).
    function _computeFailed() {
        var clean = _stripAnsi(root._lastLogText);
        var names = {};

        var re = /::\s*\(\d+\/\d+\)\s+failed\s+([A-Za-z0-9@._+\-]+)/g;
        var m;
        while ((m = re.exec(clean)) !== null)
            names[m[1]] = true;
        var hasPerPkg = Object.keys(names).length > 0;

        var hardFail = /transaction failed|upgrade failed|==>\s*error:|\berror:\s|failed to (?:build|commit|prepare|install|synchronize)/i.test(clean);

        if (!hasPerPkg && (hardFail || root._lastUpgradeExit !== 0)) {
            var shownNames = _namesOf(allShownItems());
            for (var i = 0; i < root.attemptedUpdate.length; i++) {
                var nm = root.attemptedUpdate[i];
                if (shownNames.indexOf(nm) !== -1)
                    names[nm] = true;
            }
        }

        var failed = [];
        for (var k in names)
            failed.push(k);
        root.failedPackages = failed;
        var reason = hasPerPkg ? "Build failed" : (hardFail ? "Transaction failed" : (root._lastUpgradeExit !== 0 ? "Update failed" : "Did not apply"));
        _recordFailures(failed, reason, clean);
        root._broadcastFailed();
    }
    function _broadcastFailed() {
        if (pluginService && pluginService.savePluginState)
            pluginService.savePluginState(pluginId, "failedPackages", JSON.stringify(root.failedPackages));
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

    function openDetail(item) {
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
            detailProc.command = withLock(["shelly", "query", item.name, "--detail", "-a", "--json"]);
            detailProc.running = true;
        } else if (item.source === "aur") {
            root.detailData = null;
            root.detailLoading = true;
            detailProc.command = withLock(["shelly", "aur", "search", item.name, "--json"]);
            detailProc.running = true;
        } else {
            root.detailData = root._buildDetail(item, null);
            root.detailLoading = false;
        }
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
                root.detailError = "shelly query exited with code " + exitCode;
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
        ignoreProc.command = withLock(["shelly", "ignore", "--list", "--json"]);
        ignoreProc.running = true;
    }
    function holdPackage(name) {
        if (!name)
            return;
        ignoreMutateProc.command = withLock(["shelly", "ignore", "--add", name, "-n"]);
        ignoreMutateProc.running = true;
    }
    function unholdPackage(name) {
        if (!name)
            return;
        ignoreMutateProc.command = withLock(["shelly", "ignore", "--remove", name, "-n"]);
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
                source: f.source, reason: f.reason, log: f.log
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
        loadFailureHistory();
        loadHistory();
        openMode("history");
    }

    // The failed-history entry the user clicked, shown in the faildetail view.
    property var failureDetail: null
    function openFailureDetail(entry) {
        if (!entry)
            return;
        root.failureDetail = entry;
        openMode("faildetail");
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
        loadFailureHistory();
        if (checkAtStartup)
            Qt.callLater(function () { root.refresh(true); });
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
    component MenuItem: Rectangle {
        property string itemIcon: ""
        property string itemLabel: ""
        property string badge: ""
        signal triggered
        width: parent ? parent.width - (parent.leftPadding || 0) - (parent.rightPadding || 0) : 0
        height: 44
        radius: Theme.cornerRadius
        color: mHover.containsMouse ? Theme.primaryHoverLight : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingM
            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: itemIcon
                size: Theme.iconSize - 2
                color: Theme.surfaceText
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: itemLabel
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }
        }
        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            text: badge
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.primary
            visible: badge !== ""
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
        readonly property bool countVisible: root.showCount && root.updateCount > 0 && !root.isChecking

        implicitWidth: layout.implicitWidth
        implicitHeight: layout.implicitHeight

        // Positioners skip invisible children, so we declare a count on each
        // side of the icon and show exactly one — no reparenting needed.
        Grid {
            id: layout
            anchors.centerIn: parent
            rows: isVertical ? 0 : 1
            columns: isVertical ? 1 : 0
            spacing: Theme.spacingXS
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            StyledText {
                text: String(root.updateCount)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.primary
                visible: countVisible && countFirst
            }

            DankIcon {
                id: dankIcon
                name: {
                    // "updating" takes priority so every monitor shows the SAME
                    // glyph while an upgrade runs (local isUpgrading or the
                    // broadcast remoteUpgrading), distinct from the check spinner.
                    if (root.isUpgrading || root.remoteUpgrading) return "sync";
                    if (root.isChecking) return "refresh";
                    if (root.hasError) return "error";
                    return root.updateCount > 0 ? root.iconUpdates : root.iconDefault;
                }
                size: Theme.barIconSize(root.barThickness, -4, root.barConfig?.noBackground)
                color: {
                    if (root.hasError) return Theme.error;
                    if (root.updateCount > 0 || root.isChecking || root.isUpgrading || root.remoteUpgrading) return Theme.primary;
                    return Theme.surfaceText;
                }

                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    running: root.isChecking || root.isUpgrading || root.remoteUpgrading
                    onRunningChanged: {
                        if (!running)
                            dankIcon.rotation = 0;
                    }
                }
            }

            StyledText {
                text: String(root.updateCount)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.primary
                visible: countVisible && !countFirst
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
            var p = dankIcon.mapToItem(null, 0, 0);
            var edge = root.axis?.edge;
            var gap = Theme.spacingS;
            var bt = root.barThickness;
            if (isVertical) {
                var cy = p.y + dankIcon.height / 2;
                if (edge === "right") {
                    var barLeft = p.x - (bt - dankIcon.width) / 2;
                    tip.show(tip.text, barLeft - gap, cy, root.parentScreen, false, true);
                } else {
                    var barRight = p.x + (bt + dankIcon.width) / 2;
                    tip.show(tip.text, barRight + gap, cy, root.parentScreen, true, false);
                }
            } else {
                var cx = p.x + dankIcon.width / 2;
                if (edge === "bottom") {
                    var barTop = p.y - (bt - dankIcon.height) / 2;
                    tip.show(tip.text, cx, barTop - gap - tip.implicitHeight, root.parentScreen, false, false);
                } else {
                    var barBottom = p.y + (bt + dankIcon.height) / 2;
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
                sourceComponent: UpdatesView {}
            }

            // ---------------- Menu view ----------------
            Loader {
                active: root.popoutMode === "menu"
                visible: active
                width: parent.width
                sourceComponent: MenuView {}
            }

            // ---------------- Package-detail view ----------------
            Loader {
                active: root.popoutMode === "detail"
                visible: active
                width: parent.width
                sourceComponent: DetailView {}
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
                sourceComponent: HistoryView {}
            }

            // ---------------- Failure detail ----------------
            Loader {
                active: root.popoutMode === "faildetail"
                visible: active
                width: parent.width
                sourceComponent: FailDetailView {}
            }

            component UpdatesView: Column {
                id: uv
                readonly property real contentWidth: width - leftPadding - rightPadding
                width: parent ? parent.width : 0
                padding: root.popoutPad
                spacing: Theme.spacingM

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
                    height: 44
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
                        // Subtitle: when the list was last refreshed.
                        StyledText {
                            width: parent.width
                            text: root.lastCheckedText()
                            visible: text !== ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
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
                            text: root.isChecking ? "Checking…" : (root.updateCount === 0 ? "Up to date" : root.updateCount + (root.updateCount === 1 ? " update" : " updates"))
                            font.pixelSize: Theme.fontSizeMedium
                            color: root.hasError ? Theme.error : Theme.surfaceVariantText
                        }
                        DankActionButton {
                            buttonSize: 28
                            iconName: "refresh"
                            iconSize: 18
                            iconColor: Theme.surfaceText
                            enabled: !root.isChecking
                            opacity: enabled ? 1.0 : 0.5
                            onClicked: root.refreshAll()
                            RotationAnimation on rotation {
                                from: 0; to: 360; duration: 1000
                                loops: Animation.Infinite; running: root.isChecking
                            }
                        }
                    }
                }

                // Interaction hint — only shown when there are packages that
                // support the click actions (pacman/AUR rows can be held).
                Row {
                    width: uv.contentWidth
                    spacing: Theme.spacingXS
                    visible: uv.allItems.length > 0
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
                // something to filter.
                DankTextField {
                    width: uv.contentWidth
                    height: 40
                    visible: uv.allItems.length > 0
                    leftIconName: "search"
                    showClearButton: true
                    placeholderText: "Filter packages…"
                    text: uv.filterText
                    onTextEdited: uv.filterText = text
                }

                // Sort selector (type / name).
                SortChips {
                    id: updSort
                    visible: uv.allItems.length > 0
                    activeKey: "type"
                    asc: true
                    options: [ { key: "type", label: "Type" }, { key: "name", label: "Name" } ]
                }

                // Failure banner — appears when packages from the last upgrade
                // are still pending (marked in red below). "View log" opens the
                // captured session output.
                Rectangle {
                    width: uv.contentWidth
                    visible: uv.failedShown.length > 0
                    height: visible ? 44 : 0
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.error, 0.12)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.error, 0.35)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: viewLogBtn.left
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
                            text: uv.failedShown.length + (uv.failedShown.length === 1 ? " update didn't apply on the last run" : " updates didn't apply on the last run")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        id: viewLogBtn
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        width: viewLogRow.implicitWidth + Theme.spacingM * 2
                        height: 30
                        radius: Theme.cornerRadius
                        color: viewLogHover.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : "transparent"
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.error, 0.35)
                        Row {
                            id: viewLogRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            DankIcon { anchors.verticalCenter: parent.verticalCenter; name: "description"; size: Theme.iconSize - 6; color: Theme.error }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "View log"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.error
                            }
                        }
                        MouseArea {
                            id: viewLogHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewLastLog()
                        }
                    }
                }

                // List — height follows the configured number of rows.
                Rectangle {
                    width: uv.contentWidth
                    height: Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2
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
                                        root.openDetail(modelData);
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
                                    width: parent.width - 52 - 32 - Theme.spacingM * 3
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

                                DankActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    buttonSize: 30
                                    iconName: "download"
                                    iconSize: 18
                                    iconColor: Theme.primary
                                    enabled: !root.isUpgrading
                                    onClicked: {
                                        root.updateOne(modelData);
                                        popout.closePopout && popout.closePopout();
                                    }
                                }
                            }
                        }
                    }
                }

                // Update All button
                Rectangle {
                    width: uv.contentWidth
                    height: 48
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
                            popout.closePopout && popout.closePopout();
                        }
                    }
                }
            }

            component DetailView: Column {
                id: dv
                readonly property real contentWidth: width - leftPadding - rightPadding
                width: parent ? parent.width : 0
                padding: root.popoutPad
                spacing: Theme.spacingM

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
                        onClicked: root.closeDetail()
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
                // stays comparable to the other modes).
                Rectangle {
                    width: dv.contentWidth
                    height: Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2
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
                            popout.closePopout && popout.closePopout();
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
                    readonly property bool canDowngrade: canHold

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
                            root.closeDetail();
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
                            popout.closePopout && popout.closePopout();
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

            // Inline "Sort by …" selector: a label + one chip per option. The
            // active chip shows a direction arrow; clicking it flips asc/desc,
            // clicking another switches the key. Owns activeKey/asc (the view
            // reads them by id).
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
                readonly property real contentWidth: width - leftPadding - rightPadding
                width: parent ? parent.width : 0
                padding: root.popoutPad
                spacing: Theme.spacingXS

                Item { width: mv.contentWidth; height: 32
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
                    onTriggered: { root.updateAll(); popout.closePopout && popout.closePopout(); }
                }
                MenuItem {
                    itemIcon: "terminal"; itemLabel: "Update System Packages (Pacman)"
                    badge: root.pacmanUpdatesShown.length > 0 ? String(root.pacmanUpdatesShown.length) : ""
                    onTriggered: { root.updatePacman(); popout.closePopout && popout.closePopout(); }
                }
                MenuItem {
                    visible: root.enableAur; height: visible ? 44 : 0
                    itemIcon: "deployed_code"; itemLabel: "Update AUR"
                    badge: root.aurUpdatesShown.length > 0 ? String(root.aurUpdatesShown.length) : ""
                    onTriggered: { root.updateAur(); popout.closePopout && popout.closePopout(); }
                }
                MenuItem {
                    visible: root.enableFlatpak; height: visible ? 44 : 0
                    itemIcon: "package_2"; itemLabel: "Update Flatpak"
                    badge: root.flatpakUpdates.length > 0 ? String(root.flatpakUpdates.length) : ""
                    onTriggered: { root.updateFlatpak(); popout.closePopout && popout.closePopout(); }
                }
                MenuItem {
                    visible: root.enableAppimage; height: visible ? 44 : 0
                    itemIcon: "widgets"; itemLabel: "Update AppImage"
                    badge: root.appimageUpdates.length > 0 ? String(root.appimageUpdates.length) : ""
                    onTriggered: { root.updateAppimage(); popout.closePopout && popout.closePopout(); }
                }

                Rectangle { width: mv.contentWidth; height: 1; color: Theme.outline; opacity: 0.3 }

                MenuItem {
                    itemIcon: "history"; itemLabel: "Update History…"
                    onTriggered: root.openHistory()
                }
                MenuItem {
                    itemIcon: "block"; itemLabel: "Held Packages…"
                    badge: root.ignoredPackages.length > 0 ? String(root.ignoredPackages.length) : ""
                    onTriggered: root.openHeld()
                }
                MenuItem {
                    itemIcon: "cleaning_services"; itemLabel: "Clean Package Cache"
                    onTriggered: { root.cleanCache(); popout.closePopout && popout.closePopout(); }
                }
                MenuItem {
                    itemIcon: "delete_sweep"; itemLabel: "Remove Orphans"
                    onTriggered: { root.removeOrphans(); popout.closePopout && popout.closePopout(); }
                }

                Rectangle { width: mv.contentWidth; height: 1; color: Theme.outline; opacity: 0.3 }

                MenuItem {
                    visible: root.showOpenShellyMenuItem; height: visible ? 44 : 0
                    itemIcon: "open_in_new"; itemLabel: "Open Shelly UI"
                    onTriggered: { root.openShellyUi(); popout.closePopout && popout.closePopout(); }
                }
                MenuItem {
                    itemIcon: "settings"; itemLabel: "Settings"
                    onTriggered: { root.openPluginSettings(); popout.closePopout && popout.closePopout(); }
                }
            }

            // ---------------- Held-packages manager ----------------
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

            // ---------------- Update history ----------------
            component HistoryView: Column {
                id: hyv
                readonly property real contentWidth: width - leftPadding - rightPadding
                width: parent ? parent.width : 0
                padding: root.popoutPad
                spacing: Theme.spacingM

                // Text filter (matches name/version) + optional failed-only.
                property string filterText: ""
                property bool failedOnly: false
                readonly property bool hasFailures: root.historyCombined.some(function (i) { return i.action === "failed"; })
                readonly property var filteredItems: {
                    var base = root.historyCombined;
                    if (failedOnly)
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
                        onClicked: root.openMode("menu")
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
                    FilterChip {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: hyv.hasFailures
                        label: "Failed only"
                        icon: "error"
                        activeColor: Theme.error
                        active: hyv.failedOnly
                        onToggled: hyv.failedOnly = !hyv.failedOnly
                    }
                }

                Rectangle {
                    width: hyv.contentWidth
                    height: Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2
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
                                        root.openFailureDetail(modelData);
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
                                            width: Math.min(implicitWidth, parent.width - (failChip.visible ? failChip.width + Theme.spacingXS : 0))
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
                readonly property real contentWidth: width - leftPadding - rightPadding
                width: parent ? parent.width : 0
                padding: root.popoutPad
                spacing: Theme.spacingM

                readonly property var entry: root.failureDetail || ({})
                readonly property string logText: entry && entry.log ? entry.log : ""
                readonly property bool hasVersions: (entry.oldVersion || "") !== "" || (entry.newVersion || "") !== ""
                readonly property var fields: {
                    var f = [{ label: "Reason", value: entry.reason || "Failed", err: true }];
                    if (entry.source)
                        f.push({ label: "Source", value: entry.source, err: false });
                    if (hasVersions)
                        f.push({ label: "Attempted", value: (entry.oldVersion || "?") + "  →  " + (entry.newVersion || "?"), err: false });
                    f.push({ label: "When", value: root._fmtHistoryWhen(entry.when || ""), err: false });
                    return f;
                }

                // Header: back to history + name + "failed" chip
                Item {
                    width: fdv.contentWidth
                    height: 40
                    DankActionButton {
                        id: fdBack
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: 28
                        iconName: "arrow_back"
                        iconSize: 18
                        iconColor: Theme.surfaceText
                        onClicked: root.closeFailureDetail()
                    }
                    StyledText {
                        anchors.left: fdBack.right
                        anchors.leftMargin: Theme.spacingS
                        anchors.right: fdChip.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: fdv.entry.name || ""
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        id: fdChip
                        anchors.right: parent.right
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

                // Captured log tail
                StyledText {
                    width: fdv.contentWidth
                    text: fdv.logText !== "" ? "Log (tail of the failed run)" : "No log was saved for this failure."
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }
                Rectangle {
                    width: fdv.contentWidth
                    visible: fdv.logText !== ""
                    height: Math.max(root.detailRowHeight, root.detailRows * (root.detailRowHeight + Theme.spacingXS)) + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.1)

                    Flickable {
                        id: logFlick
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        clip: true
                        contentHeight: logCol.height
                        contentWidth: width
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

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

                // Open the full live log — only meaningful for the most recent
                // run (older runs' logs are gone; we only kept the excerpt).
                DetailActionButton {
                    width: fdv.contentWidth
                    visible: root._isFailed(fdv.entry.name)
                    icon: "description"
                    label: "View full log"
                    onTriggered: root.viewLastLog()
                }
            }
        }
    }
}
