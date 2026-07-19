import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CodeIslandCore

// MARK: - Navigation Model

enum SettingsPage: String, Identifiable, Hashable {
    case general
    case behavior
    case appearance
    case mascots
    case sound
    case shortcuts
    case usage
    case remote
    case hooks
    case buddy
    case about

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .behavior: return "slider.horizontal.3"
        case .appearance: return "paintbrush.fill"
        case .mascots: return "person.2.fill"
        case .sound: return "speaker.wave.2.fill"
        case .shortcuts: return "command.circle.fill"
        case .usage: return "chart.bar.fill"
        case .remote: return "network"
        case .hooks: return "link.circle.fill"
        case .buddy: return "dot.radiowaves.left.and.right"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .behavior: return .orange
        case .appearance: return .blue
        case .mascots: return .pink
        case .sound: return .green
        case .shortcuts: return .indigo
        case .usage: return .teal
        case .remote: return .mint
        case .hooks: return .purple
        case .buddy: return .red
        case .about: return .cyan
        }
    }
}

private struct SidebarGroup: Hashable {
    let title: String?
    let pages: [SettingsPage]
}

private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(title: nil, pages: [.general, .behavior, .appearance, .mascots, .sound, .shortcuts, .usage]),
    SidebarGroup(title: "CodeIsland", pages: [.remote, .hooks, .buddy, .about]),
]

// MARK: - Main View

struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedPage: SettingsPage = .general
    var appState: AppState?
    var initialPage: SettingsPage? = nil

    init(appState: AppState?, initialPage: SettingsPage? = nil) {
        self.appState = appState
        self.initialPage = initialPage
        if let page = initialPage {
            _selectedPage = State(initialValue: page)
        }
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                ForEach(sidebarGroups, id: \.title) { group in
                    Section {
                        ForEach(group.pages) { page in
                            SidebarRow(page: page)
                                .tag(page)
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedPage {
                case .general: GeneralPage()
                case .behavior: BehaviorPage(appState: appState)
                case .appearance: AppearancePage()
                case .mascots: MascotsPage()
                case .sound: SoundPage()
                case .shortcuts: ShortcutsPage()
                case .usage: UsagePage(appState: appState)
                case .remote: RemoteHostsPage()
                case .hooks: HooksPage()
                case .buddy: BuddyPage()
                case .about: AboutPage()
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
    }
}

// MARK: - Remote Page

private struct RemoteHostsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var remoteManager = RemoteManager.shared

    @State private var name = ""
    @State private var host = ""
    @State private var user = ""
    @State private var port = ""
    @State private var identityFile = ""
    @State private var authSocket = ""
    @State private var cwdFilter = ""
    @State private var autoConnect = false

    var body: some View {
        Form {
            Section(l10n["remote_hosts"]) {
                if remoteManager.hosts.isEmpty {
                    Text(l10n["remote_hosts_empty"])
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(remoteManager.hosts) { remoteHost in
                        RemoteHostRow(host: remoteHost)
                    }
                }
            }

            Section(l10n["add_remote_host"]) {
                TextField(l10n["remote_name"], text: $name)
                TextField(l10n["remote_host"], text: $host)
                TextField(l10n["remote_user"], text: $user)
                TextField(l10n["remote_port"], text: $port)
                TextField(l10n["remote_identity"], text: $identityFile)
                TextField(l10n["remote_auth_socket"], text: $authSocket,
                          prompt: Text(l10n["remote_auth_socket_placeholder"]))
                TextField(l10n["remote_cwd_filter"], text: $cwdFilter,
                          prompt: Text(l10n["remote_cwd_filter_placeholder"]))
                Text(l10n["remote_cwd_filter_hint"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(l10n["remote_auto_connect"], isOn: $autoConnect)

                Button(l10n["remote_add_button"]) {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty, !trimmedHost.isEmpty else { return }

                    remoteManager.addHost(RemoteHost(
                        name: trimmedName,
                        host: trimmedHost,
                        user: user.trimmingCharacters(in: .whitespacesAndNewlines),
                        port: Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
                        identityFile: identityFile.trimmingCharacters(in: .whitespacesAndNewlines),
                        autoConnect: autoConnect,
                        authSocket: authSocket.trimmingCharacters(in: .whitespacesAndNewlines),
                        cwdFilter: cwdFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))

                    name = ""
                    host = ""
                    user = ""
                    port = ""
                    identityFile = ""
                    authSocket = ""
                    cwdFilter = ""
                    autoConnect = false
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                Text(l10n["remote_hint"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RemoteHostRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var remoteManager = RemoteManager.shared
    let host: RemoteHost

    @State private var cwdFilterDraft = ""

    private var status: SSHForwarder.Status {
        remoteManager.connectionStatus[host.id] ?? .disconnected
    }

    private var statusText: String {
        switch status {
        case .connected:
            return l10n["remote_connected"]
        case .connecting:
            return l10n["remote_connecting"]
        case .disconnected:
            return l10n["remote_disconnected"]
        case .failed(let message):
            return message
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                    Text(host.displayAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if remoteManager.installRunning[host.id] == true {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let message = remoteManager.lastMessage[host.id], !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            // Editable per-host session scope (#240) — saved on submit / focus loss.
            TextField(l10n["remote_cwd_filter"], text: $cwdFilterDraft,
                      prompt: Text(l10n["remote_cwd_filter_placeholder"]))
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onAppear { cwdFilterDraft = host.cwdFilter }
                .onChange(of: host.cwdFilter) { _, newValue in cwdFilterDraft = newValue }
                .onSubmit { saveCwdFilter() }

            HStack(spacing: 8) {
                switch status {
                case .connected, .connecting:
                    Button(l10n["remote_disconnect"]) {
                        remoteManager.disconnect(id: host.id)
                    }
                default:
                    Button(l10n["remote_connect"]) {
                        remoteManager.connect(id: host.id)
                    }
                }

                Button(l10n["reinstall"]) {
                    remoteManager.reconnect(id: host.id)
                }

                Button(role: .destructive) {
                    remoteManager.removeHost(id: host.id)
                } label: {
                    Text(l10n["remote_remove"])
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func saveCwdFilter() {
        let trimmed = cwdFilterDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != host.cwdFilter else { return }
        var updated = host
        updated.cwdFilter = trimmed
        remoteManager.updateHost(updated)
    }
}

private struct PageHeader: View {
    let title: String
    var body: some View {
        EmptyView()
    }
}

private struct SidebarRow: View {
    @ObservedObject private var l10n = L10n.shared
    let page: SettingsPage

    var body: some View {
        Label {
            Text(l10n[page.rawValue])
                .font(.system(size: 13))
                .padding(.leading, 2)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.color.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - General Page

private struct GeneralPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.displayChoice) private var displayChoice = SettingsDefaults.displayChoice
    @AppStorage(SettingsKey.allowHorizontalDrag) private var allowHorizontalDrag = SettingsDefaults.allowHorizontalDrag
    @AppStorage(SettingsKey.avoidMenuBarIcons) private var avoidMenuBarIcons = SettingsDefaults.avoidMenuBarIcons
    @State private var launchAtLogin: Bool

    init() {
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
    }

    var body: some View {
        Form {
            Section {
                Picker(l10n["language"], selection: $l10n.language) {
                    Text(l10n["system_language"]).tag("system")
                    Text("English").tag("en")
                    Text("简体中文").tag("zh")
                    Text("繁體中文").tag("zh-Hant")
                    Text("Deutsch").tag("de")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                    Text("Türkçe").tag("tr")
                }
                Toggle(l10n["launch_at_login"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        SettingsManager.shared.launchAtLogin = v
                    }
                Toggle(l10n["allow_horizontal_drag"], isOn: $allowHorizontalDrag)
                    .onChange(of: allowHorizontalDrag) { _, enabled in
                        if !enabled {
                            SettingsManager.shared.panelHorizontalOffset = 0
                        }
                    }
                Text(l10n["allow_horizontal_drag_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(l10n["avoid_menu_bar_icons"], isOn: $avoidMenuBarIcons)
                Text(l10n["avoid_menu_bar_icons_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(l10n["display"], selection: $displayChoice) {
                    Text(l10n["auto"]).tag("auto")
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        let name = screen.localizedName
                        let isBuiltin = name.contains("Built-in") || name.contains("内置")
                        let label = isBuiltin ? l10n["builtin_display"] : name
                        Text(label).tag("screen_\(index)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behavior Page

private struct BehaviorPage: View {
    @ObservedObject private var l10n = L10n.shared
    var appState: AppState?

    @AppStorage(SettingsKey.hideInFullscreen) private var hideInFullscreen = SettingsDefaults.hideInFullscreen
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.collapseOnMouseLeave) private var collapseOnMouseLeave = SettingsDefaults.collapseOnMouseLeave
    @AppStorage(SettingsKey.autoCollapseAfterSessionJump) private var autoCollapseAfterSessionJump = SettingsDefaults.autoCollapseAfterSessionJump
    // Seeded through the migration shim so a legacy autoExpandOnCompletion=false
    // shows up as "off" here; writes go to the new key via onChange.
    @State private var completionStyle: String = AppState.completionStyle().rawValue
    @AppStorage(SettingsKey.pluginSessionMode) private var pluginSessionMode = SettingsDefaults.pluginSessionMode
    @AppStorage(SettingsKey.hapticOnHover) private var hapticOnHover = SettingsDefaults.hapticOnHover
    @AppStorage(SettingsKey.hapticIntensity) private var hapticIntensity = SettingsDefaults.hapticIntensity
    @AppStorage(SettingsKey.sessionTimeout) private var sessionTimeout = SettingsDefaults.sessionTimeout
    @AppStorage(SettingsKey.rotationInterval) private var rotationInterval = SettingsDefaults.rotationInterval
    @AppStorage(SettingsKey.maxToolHistory) private var maxToolHistory = SettingsDefaults.maxToolHistory
    @AppStorage(SettingsKey.autoApproveTools) private var autoApproveRaw: String = SettingsDefaults.autoApproveTools
    @AppStorage(SettingsKey.excludedHookCwdSubstrings) private var excludedHookCwdSubstrings: String = SettingsDefaults.excludedHookCwdSubstrings
    @AppStorage(SettingsKey.webhookEnabled) private var webhookEnabled: Bool = SettingsDefaults.webhookEnabled
    @AppStorage(SettingsKey.webhookURL) private var webhookURL: String = SettingsDefaults.webhookURL
    @AppStorage(SettingsKey.webhookEventFilter) private var webhookEventFilter: String = SettingsDefaults.webhookEventFilter

    private var pluginSessionModeBinding: Binding<String> {
        Binding(
            get: { pluginSessionMode },
            set: { newMode in
                guard pluginSessionMode != newMode else { return }
                pluginSessionMode = newMode
                appState?.applyCurrentPluginSessionMode()
            }
        )
    }

    private func autoApproveBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { autoApproveRaw.split(separator: ",").contains(Substring(name)) },
            set: { isOn in
                var set = Set(autoApproveRaw.split(separator: ",").map(String.init))
                if isOn { set.insert(name) } else { set.remove(name) }
                autoApproveRaw = set.sorted().joined(separator: ",")
            }
        )
    }

    var body: some View {
        Form {
            Section(l10n["display_section"]) {
                BehaviorToggleRow(
                    title: l10n["hide_in_fullscreen"],
                    desc: l10n["hide_in_fullscreen_desc"],
                    isOn: $hideInFullscreen,
                    animation: .hideFullscreen
                )
                BehaviorToggleRow(
                    title: l10n["hide_when_no_session"],
                    desc: l10n["hide_when_no_session_desc"],
                    isOn: $hideWhenNoSession,
                    animation: .hideNoSession
                )
                BehaviorToggleRow(
                    title: l10n["smart_suppress"],
                    desc: l10n["smart_suppress_desc"],
                    isOn: $smartSuppress,
                    animation: .smartSuppress
                )
                BehaviorToggleRow(
                    title: l10n["collapse_on_mouse_leave"],
                    desc: l10n["collapse_on_mouse_leave_desc"],
                    isOn: $collapseOnMouseLeave,
                    animation: .collapseMouseLeave
                )
                BehaviorToggleRow(
                    title: l10n["auto_collapse_after_session_jump"],
                    desc: l10n["auto_collapse_after_session_jump_desc"],
                    isOn: $autoCollapseAfterSessionJump,
                    animation: .clickJumpCollapse
                )
                VStack(alignment: .leading, spacing: 2) {
                    Picker(l10n["completion_notification"], selection: $completionStyle) {
                        Text(l10n["completion_style_expand"]).tag(AppState.CompletionStyle.expand.rawValue)
                        Text(l10n["completion_style_glance"]).tag(AppState.CompletionStyle.glance.rawValue)
                        Text(l10n["completion_style_off"]).tag(AppState.CompletionStyle.off.rawValue)
                    }
                    .onChange(of: completionStyle) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: SettingsKey.completionNotificationStyle)
                    }
                    Text(l10n["completion_notification_desc"])
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                BehaviorToggleRow(
                    title: l10n["haptic_on_hover"],
                    desc: l10n["haptic_on_hover_desc"],
                    isOn: $hapticOnHover,
                    animation: .hapticHover
                )
                if hapticOnHover {
                    Picker(selection: $hapticIntensity) {
                        Text(l10n["haptic_light"]).tag(1)
                        Text(l10n["haptic_medium"]).tag(2)
                        Text(l10n["haptic_strong"]).tag(3)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .padding(.leading, 84)
                }
            }

            Section(l10n["auto_approve_tools"]) {
                Text(l10n["auto_approve_tools_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SettingsManager.allAutoApproveTools, id: \.name) { tool in
                    Toggle(isOn: autoApproveBinding(for: tool.name)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.name)
                                .font(.system(size: 12, design: .monospaced))
                            Text(l10n["auto_approve_\(tool.name)"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(l10n["excluded_hook_cwd_title"]) {
                Text(l10n["excluded_hook_cwd_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(l10n["excluded_hook_cwd_placeholder"], text: $excludedHookCwdSubstrings)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            Section(l10n["webhook_title"]) {
                Text(l10n["webhook_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(l10n["webhook_enable"], isOn: $webhookEnabled)
                if webhookEnabled {
                    TextField(l10n["webhook_url_placeholder"], text: $webhookURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled(true)
                    TextField(l10n["webhook_filter_placeholder"], text: $webhookEventFilter)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled(true)
                    Text(l10n["webhook_filter_hint"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(l10n["sessions"]) {
                Picker(selection: $sessionTimeout) {
                    Text(l10n["no_cleanup"]).tag(0)
                    Text(l10n["10_minutes"]).tag(10)
                    Text(l10n["30_minutes"]).tag(30)
                    Text(l10n["1_hour"]).tag(60)
                    Text(l10n["2_hours"]).tag(120)
                } label: {
                    Text(l10n["session_cleanup"])
                    Text(l10n["session_cleanup_desc"])
                }
                Picker(selection: $rotationInterval) {
                    Text(l10n["3_seconds"]).tag(3)
                    Text(l10n["5_seconds"]).tag(5)
                    Text(l10n["8_seconds"]).tag(8)
                    Text(l10n["10_seconds"]).tag(10)
                } label: {
                    Text(l10n["rotation_interval"])
                    Text(l10n["rotation_interval_desc"])
                }
                Picker(selection: $maxToolHistory) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("100").tag(100)
                } label: {
                    Text(l10n["tool_history_limit"])
                    Text(l10n["tool_history_limit_desc"])
                }
                Picker(selection: pluginSessionModeBinding) {
                    Text(l10n["plugin_session_mode_separate"]).tag("separate")
                    Text(l10n["plugin_session_mode_merge"]).tag("merge")
                    Text(l10n["plugin_session_mode_hide"]).tag("hide")
                } label: {
                    Text(l10n["plugin_session_mode"])
                    Text(l10n["plugin_session_mode_desc"])
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hooks Page

private struct HooksPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var cliStatuses: [String: Bool] = [:]
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var refreshKey = 0
    @State private var customName = ""
    @State private var customSource = ""
    @State private var customConfigPath = ""
    @State private var customConfigKey = "hooks"
    @State private var customFormat: HookFormat = .claude

    private func refreshCLIStatuses() {
        for cli in ConfigInstaller.allCLIs {
            cliStatuses[cli.source] = ConfigInstaller.isInstalled(source: cli.source)
        }
        cliStatuses["opencode"] = ConfigInstaller.isInstalled(source: "opencode")
    }

    private func statusText(installed: Bool, exists: Bool) -> String {
        installed ? l10n["activated"] : (exists ? l10n["not_installed"] : l10n["not_detected"])
    }

    var body: some View {
        Form {
            Section(l10n["cli_status"]) {
                ForEach(ConfigInstaller.allCLIs, id: \.source) { cli in
                    let installed = cliStatuses[cli.source] ?? false
                    let exists = ConfigInstaller.cliExists(source: cli.source)
                    CLIStatusRow(
                        name: cli.name,
                        source: cli.source,
                        configPath: cli.displayConfigPath,
                        fullPath: cli.fullPath,
                        installed: installed,
                        exists: exists
                    ) { _ in refreshCLIStatuses() }
                    .id("\(cli.source)-\(refreshKey)")
                }
                // OpenCode (plugin-based, not hooks)
                let ocInstalled = cliStatuses["opencode"] ?? false
                let ocExists = ConfigInstaller.cliExists(source: "opencode")
                CLIStatusRow(
                    name: "OpenCode",
                    source: "opencode",
                    configPath: "~/.config/opencode/config.json",
                    fullPath: NSHomeDirectory() + "/.config/opencode/config.json",
                    installed: ocInstalled,
                    exists: ocExists
                ) { _ in refreshCLIStatuses() }
                .id("opencode-\(refreshKey)")
            }

            Section("Custom CLIs") {
                let customItems = ConfigInstaller.customCLIConfigs()
                if customItems.isEmpty {
                    Text("No custom CLI configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customItems) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text("\(item.source) · \(item.configPath)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                _ = ConfigInstaller.setEnabled(source: item.source, enabled: false)
                                _ = ConfigInstaller.removeCustomCLI(source: item.source)
                                refreshCLIStatuses()
                                refreshKey += 1
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                TextField("Name (e.g. MyTool)", text: $customName)
                TextField("Source (e.g. mytool)", text: $customSource)
                TextField("Config path (e.g. .mytool/settings.json)", text: $customConfigPath)
                TextField("Config key", text: $customConfigKey)
                Picker("Template", selection: $customFormat) {
                    Text("Claude").tag(HookFormat.claude)
                    Text("Codex/Gemini").tag(HookFormat.nested)
                    Text("Cursor").tag(HookFormat.flat)
                    Text("Copilot").tag(HookFormat.copilot)
                }

                Button("Add Custom CLI") {
                    let result = ConfigInstaller.addCustomCLI(
                        name: customName,
                        source: customSource,
                        configPath: customConfigPath,
                        format: customFormat,
                        configKey: customConfigKey
                    )
                    statusMessage = result.message
                    statusIsError = !result.ok
                    guard result.ok else { return }

                    let normalizedSource = customSource
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    _ = ConfigInstaller.setEnabled(source: normalizedSource, enabled: true)
                    customName = ""
                    customSource = ""
                    customConfigPath = ""
                    customConfigKey = "hooks"
                    customFormat = .claude
                    refreshCLIStatuses()
                    refreshKey += 1
                }
            }

            Section(l10n["management"]) {
                HStack(spacing: 8) {
                    Button {
                        // Enable all detected CLIs before reinstalling
                        for cli in ConfigInstaller.allCLIs where ConfigInstaller.cliExists(source: cli.source) {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_\(cli.source)")
                        }
                        if ConfigInstaller.cliExists(source: "opencode") {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_opencode")
                        }
                        if ConfigInstaller.install() {
                            refreshCLIStatuses()
                            refreshKey += 1
                            statusMessage = l10n["hooks_installed"]
                            statusIsError = false
                        } else {
                            statusMessage = l10n["install_failed"]
                            statusIsError = true
                        }
                    } label: {
                        Text(l10n["reinstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        // Disable all CLIs before uninstalling
                        for cli in ConfigInstaller.allCLIs {
                            UserDefaults.standard.set(false, forKey: "cli_enabled_\(cli.source)")
                        }
                        UserDefaults.standard.set(false, forKey: "cli_enabled_opencode")
                        ConfigInstaller.uninstall()
                        refreshCLIStatuses()
                        refreshKey += 1
                        statusMessage = l10n["hooks_uninstalled"]
                        statusIsError = false
                    } label: {
                        Text(l10n["uninstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if !statusMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCLIStatuses() }
    }
}

private struct CLIStatusRow: View {
    @ObservedObject private var l10n = L10n.shared
    let name: String
    let source: String
    let configPath: String
    let fullPath: String
    let installed: Bool
    let exists: Bool
    var onToggle: ((Bool) -> Void)?

    @State private var enabled: Bool

    init(name: String, source: String, configPath: String, fullPath: String,
         installed: Bool, exists: Bool, onToggle: ((Bool) -> Void)? = nil) {
        self.name = name
        self.source = source
        self.configPath = configPath
        self.fullPath = fullPath
        self.installed = installed
        self.exists = exists
        self.onToggle = onToggle
        _enabled = State(initialValue: ConfigInstaller.isEnabled(source: source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let icon = cliIcon(source: source, size: 20) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    if !exists {
                        Text(l10n["not_detected"])
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    } else if installed {
                        HStack(spacing: 2) {
                            Text(configPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fullPath)])
                            } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                if exists {
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .onChange(of: enabled) { _, newValue in
                            ConfigInstaller.setEnabled(source: source, enabled: newValue)
                            onToggle?(newValue)
                        }
                }
            }
        }
    }
}

// MARK: - Appearance Page

private struct AppearancePage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.maxVisibleSessions) private var maxVisibleSessions = SettingsDefaults.maxVisibleSessions
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus
    @AppStorage(SettingsKey.showGitBranch) private var showGitBranch = SettingsDefaults.showGitBranch
    @AppStorage(SettingsKey.showUsageStats) private var showUsageStats = SettingsDefaults.showUsageStats
    @AppStorage(SettingsKey.collapsedWidthScale) private var collapsedWidthScale = SettingsDefaults.collapsedWidthScale
    @AppStorage(SettingsKey.notchHeightMode) private var notchHeightModeRaw = SettingsDefaults.notchHeightMode
    @AppStorage(SettingsKey.customNotchHeight) private var customNotchHeight = SettingsDefaults.customNotchHeight

    private var notchHeightMode: Binding<NotchHeightMode> {
        Binding(
            get: { NotchHeightMode(rawValue: notchHeightModeRaw) ?? .matchNotch },
            set: { notchHeightModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(l10n["preview"]) {
                AppearancePreview(
                    fontSize: contentFontSize,
                    lineLimit: aiMessageLines,
                    showDetails: showAgentDetails
                )
            }

            Section(l10n["panel"]) {
                Picker(selection: $maxVisibleSessions) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("8").tag(8)
                    Text("10").tag(10)
                    Text(l10n["unlimited"]).tag(99)
                } label: {
                    Text(l10n["max_visible_sessions"])
                    Text(l10n["max_visible_sessions_desc"])
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(l10n["collapsed_width_scale"])
                        Spacer()
                        Text("\(collapsedWidthScale)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(collapsedWidthScale) },
                        set: { collapsedWidthScale = Int($0) }
                    ), in: Double(NotchWidthScale.min)...Double(NotchWidthScale.max), step: Double(NotchWidthScale.step))
                    Text(l10n["collapsed_width_scale_desc"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: notchHeightMode) {
                        Text(l10n["notch_height_match_notch"]).tag(NotchHeightMode.matchNotch)
                        Text(l10n["notch_height_match_menubar"]).tag(NotchHeightMode.matchMenuBar)
                        Text(l10n["notch_height_custom"]).tag(NotchHeightMode.custom)
                    } label: {
                        Text(l10n["notch_height_mode"])
                        Text(l10n["notch_height_mode_desc"])
                    }

                    if notchHeightMode.wrappedValue == .custom {
                        HStack {
                            Text(l10n["custom_notch_height"])
                            Spacer()
                            Text("\(Int(customNotchHeight.rounded()))pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $customNotchHeight, in: 15...60, step: 1)
                    }
                }
            }

            Section(l10n["content"]) {
                Picker(l10n["content_font_size"], selection: $contentFontSize) {
                    Text("10pt").tag(10)
                    Text(l10n["11pt_default"]).tag(11)
                    Text("12pt").tag(12)
                    Text("13pt").tag(13)
                }
                Picker(l10n["ai_reply_lines"], selection: $aiMessageLines) {
                    Text(l10n["1_line_default"]).tag(1)
                    Text(l10n["2_lines"]).tag(2)
                    Text(l10n["3_lines"]).tag(3)
                    Text(l10n["5_lines"]).tag(5)
                    Text(l10n["unlimited"]).tag(0)
                }
                Toggle(l10n["show_agent_details"], isOn: $showAgentDetails)
                Toggle(l10n["show_tool_status"], isOn: $showToolStatus)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(l10n["show_git_branch"], isOn: $showGitBranch)
                    Text(l10n["show_git_branch_desc"])
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(l10n["show_usage_stats"], isOn: $showUsageStats)
                    Text(l10n["show_usage_stats_desc"])
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Live preview mimicking the real SessionCard layout.
private struct AppearancePreview: View {
    let fontSize: Int
    let lineLimit: Int
    let showDetails: Bool

    private var fs: CGFloat { CGFloat(fontSize) }
    private let green = Color(red: 0.3, green: 0.85, blue: 0.4)
    private let aiColor = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Column 1: Mascot
            VStack(spacing: 3) {
                MascotView(source: "claude", status: .processing, size: 32)
                if showDetails {
                    HStack(spacing: 1) {
                        MiniAgentIcon(active: true, size: 8)
                        MiniAgentIcon(active: false, size: 8)
                    }
                }
            }
            .frame(width: 36)

            // Column 2: Content
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 6) {
                    Text("my-project")
                        .font(.system(size: fs + 2, weight: .bold, design: .monospaced))
                        .foregroundStyle(green)
                    Spacer()
                    Text("3m")
                        .font(.system(size: max(9, fs - 1.5), weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.08)))
                }

                // Chat
                VStack(alignment: .leading, spacing: 3) {
                    // User prompt
                    HStack(alignment: .top, spacing: 4) {
                        Text(">")
                            .font(.system(size: fs, weight: .bold, design: .monospaced))
                            .foregroundStyle(green)
                        Text("Fix the login bug")
                            .font(.system(size: fs, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    // AI reply
                    HStack(alignment: .top, spacing: 4) {
                        Text("$")
                            .font(.system(size: fs, weight: .bold, design: .monospaced))
                            .foregroundStyle(aiColor)
                        Text("I've analyzed the codebase and found the issue in the authentication module. The token validation was skipping the expiry check when refreshing sessions.")
                            .font(.system(size: fs, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(lineLimit > 0 ? lineLimit : nil)
                            .truncationMode(.tail)
                    }
                    // Working indicator
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: fs, weight: .bold, design: .monospaced))
                            .foregroundStyle(aiColor)
                        Text("Edit src/auth.ts")
                            .font(.system(size: fs, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.05))
        )
        .animation(.easeInOut(duration: 0.25), value: fontSize)
        .animation(.easeInOut(duration: 0.25), value: lineLimit)
        .animation(.easeInOut(duration: 0.25), value: showDetails)
    }
}

// MARK: - Mascots Page

private struct MascotsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var previewStatus: AgentStatus = .processing
    @AppStorage(SettingsKey.mascotSpeed) private var mascotSpeed = SettingsDefaults.mascotSpeed
    @AppStorage(SettingsKey.defaultSource) private var defaultSource = SettingsDefaults.defaultSource

    private let mascotList: [(name: String, source: String, desc: String, color: Color)] = [
        ("Clawd", "claude", "Claude Code", Color(red: 0.871, green: 0.533, blue: 0.427)),
        ("Dex", "codex", "Codex (OpenAI)", Color(red: 0.92, green: 0.92, blue: 0.93)),
        ("Gemini", "gemini", "Gemini CLI", Color(red: 0.278, green: 0.588, blue: 0.894)),
        ("CursorBot", "cursor", "Cursor", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("TraeBot", "trae", "Trae", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("TraeCNBot", "traecn", "Trae CN", Color(red: 0.96, green: 0.31, blue: 0.0)),
        ("CopilotBot", "copilot", "GitHub Copilot", Color(red: 0.35, green: 0.75, blue: 0.95)),
        ("QoderBot", "qoder", "Qoder", Color(red: 0.165, green: 0.859, blue: 0.361)),
        ("QoderBot", "qoderwork", "QoderWork", Color(red: 0.165, green: 0.859, blue: 0.361)),
        ("Droid", "droid", "Factory", Color(red: 0.835, green: 0.416, blue: 0.149)),
        ("Buddy", "codebuddy", "CodeBuddy", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("BuddyCN", "codybuddycn", "CodyBuddyCN", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("StepFun", "stepfun", "StepFun", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("AntiGravity", "antigravity", "AntiGravity", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("WorkBuddy", "workbuddy", "WorkBuddy", Color(red: 0.475, green: 0.380, blue: 0.870)),
        ("Hermes", "hermes", "Hermes", Color(red: 0.424, green: 0.302, blue: 1.0)),
        ("Molty", "openclaw", "OpenClaw", Color(red: 0.93, green: 0.36, blue: 0.24)),
        ("QwenBot", "qwen", "Qwen Code", Color(red: 0.486, green: 0.228, blue: 0.929)),
        ("KimiBot", "kimi", "Kimi Code CLI", Color(red: 0.29, green: 0.56, blue: 1.0)),
        ("Kiro", "kiro", "Kiro", Color(red: 0.62, green: 0.45, blue: 1.0)),
        ("Pi", "pi", "Pi", Color(red: 0.55, green: 0.43, blue: 0.95)),
        ("Oh My Pi", "omp", "Oh My Pi", Color(red: 0.55, green: 0.43, blue: 0.95)),
        ("OpBot", "opencode", "OpenCode", Color(red: 0.55, green: 0.55, blue: 0.57)),
        ("ClineBot", "cline", "Cline", Color(red: 0.00, green: 0.70, blue: 0.49)),
        ("Gemini", "google-antigravity", "Google Antigravity", Color(red: 0.278, green: 0.588, blue: 0.894)),
    ]

    var body: some View {
        Form {
            Section {
                Picker(l10n["preview_status"], selection: $previewStatus) {
                    Text(l10n["processing"]).tag(AgentStatus.processing)
                    Text(l10n["idle"]).tag(AgentStatus.idle)
                    Text(l10n["waiting_approval"]).tag(AgentStatus.waitingApproval)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(l10n["mascot_speed"])
                    Spacer()
                    Text(mascotSpeed == 0
                         ? l10n["speed_off"]
                         : String(format: "%.1f×", Double(mascotSpeed) / 100.0))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(mascotSpeed) },
                    set: { mascotSpeed = Int($0) }
                ), in: 0...300, step: 25)

                Picker(selection: $defaultSource) {
                    ForEach(mascotList, id: \.source) { mascot in
                        Text(mascot.desc).tag(mascot.source)
                    }
                } label: {
                    Text(l10n["default_mascot"])
                    Text(l10n["default_mascot_desc"])
                }
                .onChange(of: defaultSource) { _, _ in
                    ESP32StatePublisher.shared.notifyDirty()
                }
            }

            Section {
                ForEach(mascotList, id: \.source) { mascot in
                    MascotRow(
                        name: mascot.name,
                        source: mascot.source,
                        desc: mascot.desc,
                        color: mascot.color,
                        status: previewStatus
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MascotRow: View {
    let name: String
    let source: String
    let desc: String
    let color: Color
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 56, height: 56)
                MascotView(source: source, status: status, size: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    if let icon = cliIcon(source: source, size: 16) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sound Page

private struct SoundPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.soundVolume) private var soundVolume = SettingsDefaults.soundVolume
    @AppStorage(SettingsKey.soundSessionStart) private var soundSessionStart = SettingsDefaults.soundSessionStart
    @AppStorage(SettingsKey.soundTaskComplete) private var soundTaskComplete = SettingsDefaults.soundTaskComplete
    @AppStorage(SettingsKey.soundTaskError) private var soundTaskError = SettingsDefaults.soundTaskError
    @AppStorage(SettingsKey.soundApprovalNeeded) private var soundApprovalNeeded = SettingsDefaults.soundApprovalNeeded
    @AppStorage(SettingsKey.soundPromptSubmit) private var soundPromptSubmit = SettingsDefaults.soundPromptSubmit
    @AppStorage(SettingsKey.soundBoot) private var soundBoot = SettingsDefaults.soundBoot
    @AppStorage(SettingsKey.quietHoursEnabled) private var quietHoursEnabled = SettingsDefaults.quietHoursEnabled
    @AppStorage(SettingsKey.quietHoursStart) private var quietHoursStart = SettingsDefaults.quietHoursStart
    @AppStorage(SettingsKey.quietHoursEnd) private var quietHoursEnd = SettingsDefaults.quietHoursEnd

    /// DatePicker works in wall-clock Dates; storage is minutes since midnight.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle(l10n["enable_sound"], isOn: $soundEnabled)
                if soundEnabled {
                    HStack(spacing: 8) {
                        Text(l10n["volume"])
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(soundVolume) },
                                set: { soundVolume = Int($0) }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(soundVolume)%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            if soundEnabled {
                Section(l10n["sessions"]) {
                    SoundEventRow(title: l10n["session_start"], subtitle: l10n["new_claude_session"], soundName: "8bit_start", isOn: $soundSessionStart)
                    SoundEventRow(title: l10n["task_complete"], subtitle: l10n["ai_completed_reply"], soundName: "8bit_complete", isOn: $soundTaskComplete)
                    SoundEventRow(title: l10n["task_error"], subtitle: l10n["tool_or_api_error"], soundName: "8bit_error", isOn: $soundTaskError)
                }

                Section(l10n["interaction"]) {
                    SoundEventRow(title: l10n["approval_needed"], subtitle: l10n["waiting_approval_desc"], soundName: "8bit_approval", isOn: $soundApprovalNeeded)
                    SoundEventRow(title: l10n["task_confirmation"], subtitle: l10n["you_sent_message"], soundName: "8bit_submit", isOn: $soundPromptSubmit)
                }

                Section(l10n["system_section"]) {
                    SoundEventRow(title: l10n["boot_sound"], subtitle: l10n["boot_sound_desc"], soundName: "8bit_boot", isOn: $soundBoot)
                }

                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(l10n["quiet_hours"], isOn: $quietHoursEnabled)
                        Text(l10n["quiet_hours_desc"])
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    if quietHoursEnabled {
                        HStack(spacing: 16) {
                            DatePicker(
                                l10n["quiet_hours_start"],
                                selection: timeBinding($quietHoursStart),
                                displayedComponents: .hourAndMinute
                            )
                            DatePicker(
                                l10n["quiet_hours_end"],
                                selection: timeBinding($quietHoursEnd),
                                displayedComponents: .hourAndMinute
                            )
                        }
                        .datePickerStyle(.field)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SoundEventRow: View {
    @ObservedObject private var l10n = L10n.shared
    let title: String
    var subtitle: String? = nil
    let soundName: String
    @Binding var isOn: Bool
    @State private var customPath: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if customPath.isEmpty {
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(l10n["custom_sound_set"].replacingOccurrences(of: "%@", with: URL(fileURLWithPath: customPath).lastPathComponent))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 16)
            // Choose custom sound
            Menu {
                Button {
                    chooseCustomSound()
                } label: {
                    Label(l10n["choose_sound_file"], systemImage: "folder")
                }
                if !customPath.isEmpty {
                    Button {
                        clearCustomSound()
                    } label: {
                        Label(l10n["reset_to_default"], systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                Image(systemName: customPath.isEmpty ? "waveform" : "waveform.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(customPath.isEmpty ? .secondary : Color.orange)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            Button {
                if !customPath.isEmpty {
                    SoundManager.shared.previewCustom(customPath)
                } else {
                    SoundManager.shared.preview(soundName)
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .onAppear {
            customPath = UserDefaults.standard.string(forKey: SettingsKey.soundCustomPath(soundName)) ?? ""
        }
    }

    private func chooseCustomSound() {
        let panel = NSOpenPanel()
        panel.title = l10n["choose_sound_file"]
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
            UserDefaults.standard.set(url.path, forKey: SettingsKey.soundCustomPath(soundName))
        }
    }

    private func clearCustomSound() {
        customPath = ""
        UserDefaults.standard.removeObject(forKey: SettingsKey.soundCustomPath(soundName))
    }
}

// MARK: - Buddy Page

private struct BuddyPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.esp32BridgeEnabled) private var enabled: Bool = SettingsDefaults.esp32BridgeEnabled
    @AppStorage(SettingsKey.esp32HeartbeatSeconds) private var heartbeat: Double = SettingsDefaults.esp32HeartbeatSeconds
    @AppStorage(SettingsKey.buddyScreenBrightnessPercent) private var brightness: Double = SettingsDefaults.buddyScreenBrightnessPercent
    @AppStorage(SettingsKey.buddyScreenOrientation) private var screenOrientation: String = SettingsDefaults.buddyScreenOrientation
    @AppStorage(SettingsKey.appleCompanionEnabled) private var appleCompanionEnabled: Bool = SettingsDefaults.appleCompanionEnabled
    @AppStorage(SettingsKey.appleCompanionHeartbeatSeconds) private var appleCompanionHeartbeat: Double = SettingsDefaults.appleCompanionHeartbeatSeconds
    @ObservedObject private var appleCompanion = AppleCompanionPublisher.shared
    @State private var refreshTick = 0

    private var bridge: ESP32BridgeManager { ESP32BridgeManager.shared }

    private var localizedPowerError: String {
        switch bridge.lastError {
        case "Bluetooth permission denied":
            return l10n["buddy_status_bluetooth_denied"]
        case "Bluetooth unsupported on this Mac":
            return l10n["buddy_status_bluetooth_unsupported"]
        case "Bluetooth is resetting":
            return l10n["buddy_status_bluetooth_resetting"]
        default:
            return l10n["buddy_status_bluetooth_off"]
        }
    }

    private var statusText: String {
        _ = refreshTick // force recompute
        switch bridge.status {
        case .off: return l10n["buddy_status_disabled"]
        case .poweredOff: return localizedPowerError
        case .noSelection: return l10n["buddy_status_no_selection"]
        case .scanning: return l10n["buddy_status_scanning"]
        case .searchingSelected: return l10n["buddy_status_searching_selected"]
        case .connecting: return l10n["buddy_status_connecting"]
        case .pairing: return l10n["buddy_status_pairing"]
        case .pairWaitingConfirm: return l10n["buddy_status_pair_waiting_confirm"]
        case .pairRejected: return l10n["buddy_status_pair_rejected"]
        case .connected: return l10n["buddy_status_connected"]
        case .reconnecting(let s): return String(format: l10n["buddy_status_reconnecting"], s)
        }
    }

    private var statusColor: Color {
        _ = refreshTick
        switch bridge.status {
        case .connected: return .green
        case .scanning, .connecting, .searchingSelected, .pairing: return .orange
        case .pairWaitingConfirm: return .blue
        case .reconnecting: return .yellow
        case .off, .noSelection: return .secondary
        case .poweredOff, .pairRejected: return .red
        }
    }

    private func configurePublisher() {
        ESP32StatePublisher.shared.configure(
            enabled: enabled,
            heartbeatSeconds: heartbeat,
            brightnessPercent: brightness,
            screenOrientation: BuddyScreenOrientation(settingsValue: screenOrientation)
        )
    }

    private func configureAppleCompanion() {
        AppleCompanionPublisher.shared.configure(
            enabled: appleCompanionEnabled,
            heartbeatSeconds: appleCompanionHeartbeat
        )
    }

    var body: some View {
        Form {
            Section(l10n["buddy"]) {
                Toggle(l10n["buddy_enable_bluetooth"], isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        configurePublisher()
                    }

                HStack {
                    Text(l10n["buddy_connection_status"])
                    Spacer()
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if bridge.status == .pairWaitingConfirm {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundStyle(.blue)
                        Text(l10n["buddy_pair_confirm_hint"])
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                if bridge.status == .pairRejected {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(l10n["buddy_pair_rejected_hint"])
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if bridge.usesLegacyPairingFallback {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(l10n["buddy_legacy_firmware_hint"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    bridge.stop()
                    if enabled { bridge.start() }
                } label: {
                    Label(l10n["buddy_reconnect"], systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!enabled || bridge.selectedBuddyIdentifier == nil)
            }

            Section(l10n["buddy_select_section"]) {
                if let selectedId = bridge.selectedBuddyIdentifier {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n["buddy_selected_label"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(bridge.connectedPeripheralName ?? bridge.selectedBuddyName ?? selectedId.uuidString)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            bridge.forgetSelection()
                        } label: {
                            Text(l10n["buddy_forget"])
                        }
                    }
                }

                ForEach(bridge.discovered) { device in
                    Button {
                        bridge.select(buddyId: device.id)
                    } label: {
                        HStack {
                            Image(systemName: device.id == bridge.selectedBuddyIdentifier
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .foregroundStyle(device.id == bridge.selectedBuddyIdentifier ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.body)
                                Text("\(l10n["buddy_signal"]) \(device.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Image(systemName: rssiIconName(device.rssi))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if bridge.discovered.isEmpty {
                    Text(l10n["buddy_no_devices"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        // Restart discovery to force a fresh round of advertising packets.
                        bridge.stopDiscovery()
                        bridge.startDiscovery()
                    } label: {
                        Label(l10n["buddy_refresh"], systemImage: "arrow.clockwise")
                    }
                    .disabled(!enabled)
                    Spacer()
                    if bridge.status == .scanning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(l10n["buddy_scanning"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(l10n["buddy_sync"]) {
                HStack {
                    Text(l10n["buddy_sync_interval"])
                    Spacer()
                    Text(String(format: l10n["buddy_seconds_format"], heartbeat))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $heartbeat, in: 1...30, step: 1)
                    .onChange(of: heartbeat) { _, _ in
                        configurePublisher()
                    }
                Text(l10n["buddy_sync_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n["buddy_display"]) {
                HStack {
                    Text(l10n["buddy_brightness"])
                    Spacer()
                    Text("\(Int(brightness.rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $brightness, in: Double(ESP32Protocol.minBrightnessPercent)...Double(ESP32Protocol.maxBrightnessPercent), step: 1)
                    .onChange(of: brightness) { _, newValue in
                        brightness = Double(ESP32Protocol.clampedBrightnessPercent(newValue))
                        configurePublisher()
                    }
                Text(l10n["buddy_brightness_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(l10n["buddy_screen_orientation"], selection: $screenOrientation) {
                    Text(l10n["buddy_screen_orientation_up"]).tag(BuddyScreenOrientation.up.rawValue)
                    Text(l10n["buddy_screen_orientation_down"]).tag(BuddyScreenOrientation.down.rawValue)
                }
                .pickerStyle(.segmented)
                .onChange(of: screenOrientation) { _, _ in
                    configurePublisher()
                }
                Text(l10n["buddy_screen_orientation_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n["apple_companion"]) {
                Toggle(l10n["apple_companion_enable"], isOn: $appleCompanionEnabled)
                    .onChange(of: appleCompanionEnabled) { _, _ in
                        configureAppleCompanion()
                    }

                HStack {
                    Text(l10n["apple_companion_status"])
                    Spacer()
                    Circle()
                        .fill(appleCompanionStatusColor)
                        .frame(width: 8, height: 8)
                    Text(appleCompanionStatusText)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                }

                if appleCompanion.connectedPeerNames.isEmpty {
                    Label(l10n["apple_companion_no_devices"], systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appleCompanion.connectedPeerNames, id: \.self) { name in
                        Label(name, systemImage: "iphone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(l10n["apple_companion_sync_interval"])
                    Spacer()
                    Text(String(format: l10n["buddy_seconds_format"], appleCompanionHeartbeat))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $appleCompanionHeartbeat, in: 1...30, step: 1)
                    .onChange(of: appleCompanionHeartbeat) { _, _ in
                        configureAppleCompanion()
                    }
                    .disabled(!appleCompanionEnabled)

                Button {
                    appleCompanion.reconnect()
                } label: {
                    Label(l10n["apple_companion_restart"], systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!appleCompanionEnabled)

                if let error = appleCompanion.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(l10n["apple_companion_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(l10n["buddy_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshTick &+= 1
        }
        .onAppear {
            if enabled {
                bridge.startDiscovery()
            }
        }
        .onDisappear {
            bridge.stopDiscovery()
        }
        .onChange(of: enabled) { _, newValue in
            if newValue {
                bridge.startDiscovery()
            } else {
                bridge.stopDiscovery()
            }
        }
    }

    private func rssiIconName(_ rssi: Int) -> String {
        // CoreBluetooth RSSI typically ranges from ~-30 (close) to -100 (far).
        switch rssi {
        case ..<(-85): return "wifi.exclamationmark"
        case ..<(-70): return "wifi"
        default:       return "wifi"
        }
    }

    private var appleCompanionStatusText: String {
        guard appleCompanion.enabled else {
            return l10n["apple_companion_status_off"]
        }
        return appleCompanion.connectedPeerNames.isEmpty
            ? l10n["apple_companion_status_waiting"]
            : l10n["apple_companion_status_connected"]
    }

    private var appleCompanionStatusColor: Color {
        guard appleCompanion.enabled else { return .secondary }
        return appleCompanion.connectedPeerNames.isEmpty ? .orange : .green
    }
}

// MARK: - About Page

private struct AboutPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                AppLogoView(size: 100)

                VStack(spacing: 6) {
                    Text("CodeIsland")
                        .font(.system(size: 26, weight: .bold))
                    Text("Version \(AppVersion.current)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text(l10n["about_desc1"])
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text(l10n["about_desc2"])
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    aboutLink("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/wxtsky/CodeIsland")
                    aboutLink("Issues", icon: "ladybug", url: "https://github.com/wxtsky/CodeIsland/issues")
                }

                // In-app update section
                updateSection

                Button {
                    DiagnosticsExporter.export()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 11))
                        Text(l10n["export_diagnostics"])
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                .onHover { h in
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updater.state {
        case .idle:
            aboutButton(l10n["check_for_updates"], icon: "arrow.triangle.2.circlepath") {
                updater.checkForUpdates()
            }

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(l10n["check_for_updates"])
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            Button {
                updater.checkForUpdates()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13))
                    Text(String(format: l10n["no_update_body"], AppVersion.current))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .onHover { h in
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

        case let .available(version):
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 13))
                    Text(String(format: l10n["update_available_body"], version, AppVersion.current))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if updater.isHomebrewInstall {
                    HStack(spacing: 8) {
                        Text(l10n["update_homebrew_command"])
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                        aboutButton(l10n["update_copy_command"], icon: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(l10n["update_homebrew_command"], forType: .string)
                        }
                    }
                } else {
                    // Sparkle owns the download + install alert; this button just
                    // re-surfaces it if the user dismissed it earlier.
                    aboutButton(l10n["update_now"], icon: "arrow.down.to.line") {
                        updater.checkForUpdates()
                    }
                }
            }

        // Download progress and install state are owned by Sparkle's standard
        // UI, not the About page — those enum cases no longer exist.

        case let .failed(message):
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    Text(String(format: l10n["update_failed_body"], message))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                aboutButton(l10n["update_retry"], icon: "arrow.clockwise") {
                    updater.checkForUpdates()
                }
            }
        }
    }

    private func aboutButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func aboutLink(_ title: String, icon: String, url: String) -> some View {
        aboutButton(title, icon: icon) {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
    }
}

// MARK: - Behavior Animation Previews

private enum BehaviorAnim {
    case hideFullscreen, hideNoSession, smartSuppress, collapseMouseLeave, clickJumpCollapse, hapticHover
}

struct ClickJumpCollapsePreviewTimeline {
    let expand: Double
    let showClickRing: Bool
    let ringOpacity: Double
    let ringRadius: CGFloat
    let cursorX: CGFloat
    let cursorY: CGFloat
    let clickPointY: CGFloat
    let showSuccessArrow: Bool
    let successArrowOpacity: Double
}

func clickJumpCollapsePreviewTimeline(progress: Double) -> ClickJumpCollapsePreviewTimeline {
    // Wrap to [0,1) so loop seam is identical between end and start.
    let p = progress >= 1 ? progress.truncatingRemainder(dividingBy: 1) : min(1, max(0, progress))

    let clickPointY: CGFloat = 16 // lowered ~20% vs previous ~8

    // Seam-friendly phases:
    // [0.00, 0.08): expanded + cursor very fast move in (from offscreen)
    // [0.08, 0.26): expanded + cursor hover before click
    // [0.26, 0.32): click ring pulse
    // [0.32, 0.47): collapse (match mouse-leave collapse speed)
    // [0.47, 0.62): collapsed hold
    // [0.62, 0.80): cursor moves fully offscreen
    // [0.80, 0.93): expand back (match mouse-leave expand speed, after cursor is offscreen)
    // [0.93, 1.00): fully expanded idle with cursor still offscreen
    let expand: Double
    switch p {
    case ..<0.32:
        expand = 1.0
    case ..<0.47:
        expand = max(0, 1.0 - (p - 0.32) / 0.15)
    case ..<0.80:
        expand = 0
    case ..<0.93:
        expand = min(1, (p - 0.80) / 0.13)
    default:
        expand = 1.0
    }

    // Cursor path: offscreen -> click point -> offscreen, aligned to mouse-leave move-out timing.
    let cursorX: CGFloat
    let cursorY: CGFloat
    switch p {
    case ..<0.08:
        let m = p / 0.08
        cursorX = CGFloat((1 - m) * 34)
        cursorY = CGFloat((1 - m) * 28)
    case ..<0.62:
        cursorX = 0
        cursorY = 0
    case ..<0.80:
        let m = (p - 0.62) / 0.18
        cursorX = CGFloat(m * 34)
        cursorY = CGFloat(m * 28)
    default:
        cursorX = 34
        cursorY = 28
    }

    let ringWindow = p >= 0.26 && p <= 0.32
    let ringPhase = ringWindow ? (p - 0.26) / 0.06 : 0
    let ringOpacity = ringWindow ? sin(ringPhase * .pi) : 0
    let ringRadius: CGFloat = 4 + CGFloat(ringPhase) * 6

    let arrowWindow = p >= 0.34 && p <= 0.42
    let arrowPhase = arrowWindow ? (p - 0.34) / 0.08 : 0
    let arrowOpacity = arrowWindow ? sin(arrowPhase * .pi) : 0

    return ClickJumpCollapsePreviewTimeline(
        expand: expand,
        showClickRing: ringWindow,
        ringOpacity: ringOpacity,
        ringRadius: ringRadius,
        cursorX: cursorX,
        cursorY: cursorY,
        clickPointY: clickPointY,
        showSuccessArrow: arrowWindow,
        successArrowOpacity: arrowOpacity
    )
}

private struct BehaviorToggleRow: View {
    let title: String
    let desc: String
    @Binding var isOn: Bool
    let animation: BehaviorAnim

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                NotchMiniAnim(animation: animation)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(desc)
                }
            }
        }
    }
}

/// Canvas-based notch animation with smooth interpolation.
private struct NotchMiniAnim: View {
    let animation: BehaviorAnim
    private let orange = Color(red: 0.96, green: 0.65, blue: 0.14)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
            Canvas { c, sz in
                draw(c, sz: sz, t: ctx.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 72, height: 48)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(min(1, max(0, t)))
    }

    private func draw(_ c: GraphicsContext, sz: CGSize, t: Double) {
        switch animation {
        case .hideFullscreen:   drawFullscreen(c, sz: sz, t: t)
        case .hideNoSession:    drawNoSession(c, sz: sz, t: t)
        case .smartSuppress:    drawSuppress(c, sz: sz, t: t)
        case .collapseMouseLeave: drawMouseLeave(c, sz: sz, t: t)
        case .clickJumpCollapse: drawClickJumpCollapse(c, sz: sz, t: t)
        case .hapticHover:      drawHaptic(c, sz: sz, t: t)
        }
    }

    /// Draw a notch pill: smooth w/h/opacity, with orange eyes + content lines when expanded.
    private func drawPill(_ c: GraphicsContext, sz: CGSize,
                          w: CGFloat, h: CGFloat, op: Double,
                          flashColor: Color? = nil) {
        guard op > 0.01 else { return }
        let x = (sz.width - w) / 2
        let r = min(w, h) * 0.45
        let rect = CGRect(x: x, y: 0, width: w, height: h)
        let pill = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        c.fill(pill, with: .color(Color(white: 0.06).opacity(op)))

        // Eyes — always visible when notch is visible
        let eyeSize: CGFloat = h > 16 ? 3.5 : 2.5
        let eyeY: CGFloat = h > 16 ? 5 : max(2, (h - eyeSize) / 2)
        let eyeGap: CGFloat = h > 16 ? 5 : 3
        c.fill(Path(CGRect(x: sz.width / 2 - eyeGap - eyeSize / 2, y: eyeY,
                           width: eyeSize, height: eyeSize)),
               with: .color(orange.opacity(op)))
        c.fill(Path(CGRect(x: sz.width / 2 + eyeGap - eyeSize / 2, y: eyeY,
                           width: eyeSize, height: eyeSize)),
               with: .color(orange.opacity(op)))

        // Content lines — only when expanded
        if h > 16 {
            let contentOp = op * Double(min(1, (h - 16) / 10))
            let lx = x + 6
            let widths: [CGFloat] = [w * 0.6, w * 0.45, w * 0.55]
            for (i, lw) in widths.enumerated() {
                let ly = 12 + CGFloat(i) * 5
                if ly + 2 < h - 3 {
                    c.fill(Path(CGRect(x: lx, y: ly, width: lw, height: 2)),
                           with: .color(.white.opacity(0.3 * contentOp * (1 - Double(i) * 0.2))))
                }
            }
        }

        // Flash overlay
        if let color = flashColor {
            c.fill(pill, with: .color(color))
        }
    }

    // 1) Fullscreen: notch visible → screen dims → notch fades → restore
    private func drawFullscreen(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let vis: Double = cycle < 0.3 ? 1.0 :
            cycle < 0.45 ? 1.0 - (cycle - 0.3) / 0.15 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)
        // Fullscreen dimming overlay
        if vis < 0.95 {
            c.fill(Path(CGRect(origin: .zero, size: sz)),
                   with: .color(Color(white: 0.08).opacity(0.85 * (1 - vis))))
            // Fullscreen icon
            let iconOp = cycle > 0.45 && cycle < 0.65 ?
                sin((cycle - 0.45) / 0.2 * .pi) * 0.5 : 0
            if iconOp > 0.01 {
                c.draw(Text("⛶").font(.system(size: 16)).foregroundColor(.white.opacity(iconOp)),
                       at: CGPoint(x: sz.width / 2, y: sz.height / 2 + 2))
            }
        }
        drawPill(c, sz: sz, w: 28, h: 10, op: vis)
    }

    // 2) No session: green dots vanish → notch fades
    private func drawNoSession(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let dotOp: Double = cycle < 0.25 ? 1.0 :
            cycle < 0.4 ? 1.0 - (cycle - 0.25) / 0.15 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)
        let pillOp: Double = cycle < 0.35 ? 1.0 :
            cycle < 0.55 ? 1.0 - (cycle - 0.35) / 0.2 :
            cycle < 0.7 ? 0.0 :
            min(1, (cycle - 0.7) / 0.15)

        drawPill(c, sz: sz, w: 28, h: 10, op: pillOp)
        // Green session dots
        if dotOp > 0.01 {
            let cx = sz.width / 2
            for i in 0..<2 {
                let dx: CGFloat = CGFloat(i) * 6 - 3
                c.fill(Path(ellipseIn: CGRect(x: cx + dx - 1.5, y: 3, width: 3, height: 3)),
                       with: .color(.green.opacity(0.85 * dotOp * pillOp)))
            }
        }
    }

    // 3) Smart suppress: event flash → notch pulses but stays collapsed → × indicator
    private func drawSuppress(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.0) / 3.0
        // Two event pulses
        let p1 = (cycle > 0.15 && cycle < 0.4) ? sin((cycle - 0.15) / 0.25 * .pi) : 0.0
        let p2 = (cycle > 0.55 && cycle < 0.75) ? sin((cycle - 0.55) / 0.2 * .pi) : 0.0
        let pulse = max(p1, p2)
        let pw = 28 + CGFloat(pulse) * 8
        let ph: CGFloat = 10 + CGFloat(pulse) * 3

        let flashColor: Color? = pulse > 0.05 ? .green.opacity(0.3 * pulse) : nil
        drawPill(c, sz: sz, w: pw, h: ph, op: 1.0, flashColor: flashColor)

        // × suppress indicator
        let xOp1 = (cycle > 0.3 && cycle < 0.48) ? sin((cycle - 0.3) / 0.18 * .pi) : 0.0
        let xOp2 = (cycle > 0.68 && cycle < 0.82) ? sin((cycle - 0.68) / 0.14 * .pi) : 0.0
        let xOp = max(xOp1, xOp2)
        if xOp > 0.01 {
            c.draw(Text("✕").font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange.opacity(0.7 * xOp)),
                   at: CGPoint(x: sz.width / 2, y: 18))
        }
    }

    // 4) Mouse leave: cursor enters → expand → cursor leaves → collapse
    private func drawMouseLeave(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        // Expand amount: 0→1→0
        let expand: Double = cycle < 0.12 ? 0 :
            cycle < 0.25 ? (cycle - 0.12) / 0.13 :
            cycle < 0.5 ? 1.0 :
            cycle < 0.65 ? 1.0 - (cycle - 0.5) / 0.15 : 0

        let pw = lerp(28, 64, expand)
        let ph = lerp(10, 34, expand)
        drawPill(c, sz: sz, w: pw, h: ph, op: 1.0)

        // Mouse cursor
        let cursorPhase = cycle
        let cursorVis = cursorPhase > 0.05 && cursorPhase < 0.68
        if cursorVis {
            let cx: CGFloat, cy: CGFloat
            if cursorPhase < 0.12 {
                // Moving toward notch
                let t = (cursorPhase - 0.05) / 0.07
                cx = lerp(sz.width / 2 + 15, sz.width / 2 + 2, t)
                cy = lerp(sz.height - 5, 8, t)
            } else if cursorPhase < 0.5 {
                // Hovering near notch
                cx = sz.width / 2 + 2
                cy = lerp(8, 6, expand)
            } else {
                // Moving away
                let t = (cursorPhase - 0.5) / 0.18
                cx = lerp(sz.width / 2 + 2, sz.width - 2, min(1, t))
                cy = lerp(6, sz.height - 2, min(1, t))
            }
            // Draw cursor arrow
            var arrow = Path()
            arrow.move(to: CGPoint(x: cx, y: cy))
            arrow.addLine(to: CGPoint(x: cx, y: cy + 8))
            arrow.addLine(to: CGPoint(x: cx + 2.5, y: cy + 6))
            arrow.addLine(to: CGPoint(x: cx + 5.5, y: cy + 6))
            arrow.closeSubpath()
            c.fill(arrow, with: .color(.white.opacity(0.9)))
            c.stroke(arrow, with: .color(.black.opacity(0.4)), lineWidth: 0.5)
        }
    }

    // 5) Click jump: panel starts expanded -> cursor clicks with ring -> collapse hold -> seamless loop
    private func drawClickJumpCollapse(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.5) / 3.5
        let timeline = clickJumpCollapsePreviewTimeline(progress: cycle)

        let pw = lerp(28, 64, timeline.expand)
        let ph = lerp(10, 34, timeline.expand)
        drawPill(c, sz: sz, w: pw, h: ph, op: 1.0)

        if timeline.showClickRing {
            let r = timeline.ringRadius
            let circle = Path(ellipseIn: CGRect(
                x: sz.width / 2 - r,
                y: timeline.clickPointY - r / 2,
                width: r * 2,
                height: r * 2
            ))
            c.stroke(circle, with: .color(.white.opacity(0.45 * timeline.ringOpacity)), lineWidth: 1)
        }

        if timeline.showSuccessArrow {
            c.draw(
                Text("↗").font(.system(size: 10, weight: .bold)).foregroundColor(.green.opacity(0.75 * timeline.successArrowOpacity)),
                at: CGPoint(x: sz.width / 2 + 13, y: timeline.clickPointY + 10)
            )
        }

        let cx = sz.width / 2 + 2 + timeline.cursorX
        let cy = timeline.clickPointY + timeline.cursorY
        var arrow = Path()
        arrow.move(to: CGPoint(x: cx, y: cy))
        arrow.addLine(to: CGPoint(x: cx, y: cy + 8))
        arrow.addLine(to: CGPoint(x: cx + 2.5, y: cy + 6))
        arrow.addLine(to: CGPoint(x: cx + 5.5, y: cy + 6))
        arrow.closeSubpath()
        c.fill(arrow, with: .color(.white.opacity(0.9)))
        c.stroke(arrow, with: .color(.black.opacity(0.4)), lineWidth: 0.5)
    }

    // 6) Haptic: cursor enters → notch shakes briefly (vibration effect)
    private func drawHaptic(_ c: GraphicsContext, sz: CGSize, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 2.5) / 2.5

        // Cursor approaches and hovers
        let cursorIn = cycle > 0.05 && cycle < 0.55
        // Shake phase: short burst when cursor first arrives
        let shakePhase = (cycle > 0.15 && cycle < 0.35)
        let shakeOffset: CGFloat = shakePhase
            ? CGFloat(sin(cycle * 180)) * 2.5
            : 0

        drawPill(c, sz: CGSize(width: sz.width + shakeOffset, height: sz.height),
                 w: 28, h: 10, op: 1.0)

        // Vibration lines (radiating from notch during shake)
        if shakePhase {
            let lineOp = sin((cycle - 0.15) / 0.2 * .pi)
            let cx = sz.width / 2
            for dx: CGFloat in [-10, -6, 6, 10] {
                let x = cx + dx + shakeOffset / 2
                c.fill(Path(CGRect(x: x, y: 13, width: 0.8, height: 3)),
                       with: .color(orange.opacity(0.6 * lineOp)))
            }
        }

        // Mouse cursor
        if cursorIn {
            let cx: CGFloat, cy: CGFloat
            if cycle < 0.15 {
                let p = (cycle - 0.05) / 0.1
                cx = lerp(sz.width / 2 + 15, sz.width / 2 + 2, p)
                cy = lerp(sz.height - 5, 8, p)
            } else {
                cx = sz.width / 2 + 2
                cy = 8
            }
            var arrow = Path()
            arrow.move(to: CGPoint(x: cx, y: cy))
            arrow.addLine(to: CGPoint(x: cx, y: cy + 8))
            arrow.addLine(to: CGPoint(x: cx + 2.5, y: cy + 6))
            arrow.addLine(to: CGPoint(x: cx + 5.5, y: cy + 6))
            arrow.closeSubpath()
            c.fill(arrow, with: .color(.white.opacity(0.9)))
            c.stroke(arrow, with: .color(.black.opacity(0.4)), lineWidth: 0.5)
        }
    }
}

// MARK: - App Logo

struct AppLogoView: View {
    var size: CGFloat = 100
    var showBackground: Bool = true
    private let orange = Color(red: 0.96, green: 0.65, blue: 0.14)

    var body: some View {
        Canvas { ctx, sz in
            // macOS icon standard: ~10% padding on each side
            let inset = sz.width * 0.1
            let contentRect = CGRect(x: inset, y: inset, width: sz.width - inset * 2, height: sz.height - inset * 2)
            let px = contentRect.width / 16
            if showBackground {
                let bgPath = Path(roundedRect: contentRect, cornerRadius: contentRect.width * 0.22, style: .continuous)
                ctx.fill(bgPath, with: .color(.white))
            }
            // Notch pill
            let pillColor = showBackground ? Color(white: 0.1) : Color(white: 0.5)
            let pillRect = CGRect(x: contentRect.minX + px * 3, y: contentRect.minY + px * 6, width: px * 10, height: px * 4)
            ctx.fill(Path(roundedRect: pillRect, cornerRadius: px * 2, style: .continuous), with: .color(pillColor))
            // Eyes
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 5, y: contentRect.minY + px * 7, width: px * 2, height: px * 2)), with: .color(orange))
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 9, y: contentRect.minY + px * 7, width: px * 2, height: px * 2)), with: .color(orange))
            // Pupils
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 6, y: contentRect.minY + px * 7, width: px, height: px)), with: .color(.white))
            ctx.fill(Path(CGRect(x: contentRect.minX + px * 10, y: contentRect.minY + px * 7, width: px, height: px)), with: .color(.white))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(showBackground ? 0.15 : 0), radius: size * 0.12, y: size * 0.04)
    }
}

// MARK: - Shortcuts Page

private struct ShortcutsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var recordingAction: ShortcutAction?
    @State private var eventMonitor: Any?
    @State private var refreshKey = 0

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRow(
                        action: action,
                        isRecording: recordingAction == action,
                        onStartRecording: { startRecording(action) },
                        onClear: { clearBinding(action) }
                    )
                    .id("\(action.rawValue)-\(refreshKey)")
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape — cancel
                self.stopRecording()
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else {
                return nil
            }
            action.setBinding(keyCode: event.keyCode, modifiers: mods)
            if !action.isEnabled { action.setEnabled(true) }
            self.stopRecording()
            self.refreshKey += 1
            self.notifyChange()
            return nil
        }
    }

    private func clearBinding(_ action: ShortcutAction) {
        action.setEnabled(false)
        refreshKey += 1
        notifyChange()
    }

    private func stopRecording() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
        recordingAction = nil
    }

    private func notifyChange() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.setupGlobalShortcut()
        }
    }
}

// MARK: - Usage / Token History Page

private struct UsagePage: View {
    let appState: AppState?
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title2)
                        .foregroundStyle(.teal)
                    Text("Token Usage History")
                        .font(.title2.bold())
                }
                .padding(.bottom, 5)


                if let usage = appState?.claudeUsage {
                    // 14-day summary
                    UsageSummaryCard(dailyTotals: usage.dailyTotals)

                    // Per-AI breakdown
                    if !usage.perSource.isEmpty {
                        UsagePerSourceCard(sources: usage.perSource)
                    }

                    // 14-day bar chart
                    UsageHistoryCard(dailyTotals: usage.dailyTotals, scannedAt: usage.scannedAt)

                    // Today and 5h breakdown
                    UsageBreakdownCard(last5h: usage.last5h, today: usage.today)

                    // Hourly sparkline (last 12h) with hour labels
                    if !usage.hourlyOutputTokens.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last 12 Hours (Output Tokens)")
                                .font(.headline)
                            VStack(spacing: 4) {
                                UsageSparklineLarge(buckets: usage.hourlyOutputTokens)
                                    .frame(maxWidth: .infinity)

                                // Hour labels under the chart
                                HStack(spacing: 0) {
                                    ForEach(0..<usage.hourlyOutputTokens.count, id: \.self) { i in
                                        let hour = Calendar.current.component(.hour, from: Date().addingTimeInterval(-Double(usage.hourlyOutputTokens.count - 1 - i) * 3600))
                                        Text(String(format: "%d", hour))
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
                    }

                } else {
                    ContentUnavailableView(
                        "No Usage Data",
                        systemImage: "chart.bar",
                        description: Text("Token usage data will appear here once you use Claude Code or OMP sessions.")
                    )
                }

                // Cursor setup — always visible, after usage data
                CursorSetupCard(appState: appState)

                Spacer()
            }
            .padding(24)
        }
        .onAppear { appState?.scanClaudeUsage() }
    }
}

/// Cursor setup card: lets the user extract the Chrome cookie, manually
/// paste a CSV, or open cursor.com in the browser. The automatic scan does
/// NOT touch the Keychain — the user must explicitly request it here.
private struct CursorSetupCard: View {
    @State private var isRefreshing = false
    @State private var refreshResult: String?
    @State private var showManualCSV = false
    @State private var showManualCookie = false
    @State private var manualCSV = ""
    @State private var manualCookie = ""
    @State private var isFetchingCookie = false
    @State private var hasCSV = false
    @State private var showFileImporter = false
    @State private var showConfirmDelete = false
    @State private var saveCookieForReuse = false
    @AppStorage("cursor.autoRefreshEnabled") private var autoRefreshEnabled = false
    @AppStorage("cursor.autoRefreshHours") private var autoRefreshHours = 1
    @State private var hasSavedCookie = false
    weak var appState: AppState?

    private let scanner = CursorScanner()

    init(appState: AppState? = nil) {
        self.appState = appState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    CursorView(status: hasCSV ? .running : .idle, size: 22)
                        .frame(width: 22, height: 22)
                    Text("Cursor Usage Setup")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 6) {
                        if hasCSV {
                            Text("CSV")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("No CSV")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.2))
                        if hasSavedCookie {
                            Image(systemName: "key.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("No cookie")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            Text("Cursor doesn't store token counts locally. CodeIsland reads them from your Chrome session cookie and the Cursor CSV export API. All data stays on your Mac — nothing is shared, sent to servers, or included in telemetry.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Extract from Chrome — first button, on its own row
            Button {
                isRefreshing = true
                refreshResult = nil
                // Chrome cookie extraction needs the main thread for the
                // macOS Keychain permission dialog. We dispatch to the next
                // main-runloop tick so the dialog can appear outside the
                // SwiftUI action closure (which blocks Keychain UI).
                scanner.extractChromeToken { sessionToken in
                    guard let sessionToken = sessionToken else {
                        isRefreshing = false
                        refreshResult = hasSavedCookie
                            ? "Chrome extraction unavailable (unsigned app). Using saved cookie instead — click 'Refresh now' below."
                            : "Chrome extraction needs Keychain access (unsigned app limitation). Use 'Manual cookie extraction' below instead."
                        return
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let ok = scanner.fetchAndCacheCSV(token: sessionToken)
                        DispatchQueue.main.async {
                            isRefreshing = false
                            refreshResult = ok ? "✓ CSV fetched from Chrome" : "Failed — CSV fetch failed. Cookie may be expired."
                            if ok { hasCSV = true; appState?.scanClaudeUsage() }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isRefreshing ? "Extracting…" : "Extract from Chrome")
                    Spacer()
                }
                .frame(height: 20)
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)

            // Open cursor.com
            Button {
                if let url = URL(string: "https://cursor.com/dashboard/usage") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "safari")
                    Text("Open cursor.com")
                }
            }
            .buttonStyle(.bordered)

            // Section 1: Manual cookie extraction
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showManualCookie.toggle()
                        if showManualCookie { showManualCSV = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(hasSavedCookie ? .green : .purple)
                        Text("Manual cookie extraction")
                            .font(.subheadline.weight(.medium))
                        if hasSavedCookie {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Image(systemName: showManualCookie ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.background.tertiary))
                }
                .buttonStyle(.plain)

                if showManualCookie {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open")
                        Link("cursor.com/dashboard/usage", destination: URL(string: "https://cursor.com/dashboard/usage")!)
                            .foregroundStyle(.teal)
                        Text("2. Open browser DevTools (⌥⌘J) → Application tab → Cookies → cursor.com")
                            .font(.caption)
                        HStack(spacing: 4) {
                            Text("3. Find")
                                .font(.caption)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("WorkosCursorSessionToken", forType: .string)
                                refreshResult = "✓ Cookie name copied to clipboard"
                            } label: {
                                Text("WorkosCursorSessionToken")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.teal)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                            Text("(HttpOnly — not visible via document.cookie)")
                                .font(.caption)
                        }
                        Text("4. Double-click the value, copy it, and paste below:")
                            .font(.caption)
                        HStack(spacing: 4) {
                            SecureField("WorkosCursorSessionToken", text: $manualCookie)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            if !manualCookie.isEmpty {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(manualCookie, forType: .string)
                                    refreshResult = "Cookie copied to clipboard"
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        Toggle("Save cookie for auto-refresh (no Keychain prompt)", isOn: $saveCookieForReuse)
                            .font(.caption)
                            .toggleStyle(.checkbox)
                        Button {
                            isFetchingCookie = true
                            let cookie = manualCookie
                            let shouldSave = saveCookieForReuse
                            if shouldSave { scanner.saveCookie(cookie) }
                            DispatchQueue.global(qos: .userInitiated).async {
                                let ok = scanner.refreshCSVWithCookie(cookie)
                                DispatchQueue.main.async {
                                    isFetchingCookie = false
                                    if ok {
                                        refreshResult = "✓ CSV fetched via cookie"
                                        hasCSV = true
                                        if shouldSave { hasSavedCookie = true }
                                        withAnimation { showManualCookie = false }
                                        manualCookie = ""
                                        appState?.scanClaudeUsage()
                                    } else {
                                        refreshResult = "Failed — invalid or expired cookie"
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isFetchingCookie {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                }
                                Text(isFetchingCookie ? "Fetching…" : "Fetch CSV")
                            }
                            .frame(height: 20)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFetchingCookie || manualCookie.isEmpty)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 4)
                }
            }

            // Section 2: Manual CSV extraction
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showManualCSV.toggle()
                        if showManualCSV { showManualCookie = false }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(hasCSV ? .green : .teal)
                        Text("Manual CSV extraction")
                            .font(.subheadline.weight(.medium))
                        if hasCSV {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Image(systemName: showManualCSV ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.background.tertiary))
                }
                .buttonStyle(.plain)

                if showManualCSV {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Download the CSV:")
                            .font(.caption)
                        Link(destination: URL(string: "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                Text("Download usage CSV")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.teal)
                        }
                        Text("2. Import the downloaded file:")
                            .font(.caption)
                        Button {
                            showFileImporter = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import CSV file")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 4)
                    .fileImporter(isPresented: $showFileImporter,
                                   allowedContentTypes: [.commaSeparatedText, .text]) { result in
                        switch result {
                        case .success(let url):
                            if url.startAccessingSecurityScopedResource() {
                                defer { url.stopAccessingSecurityScopedResource() }
                                if let csv = try? String(contentsOf: url, encoding: .utf8),
                                   scanner.saveManualCSV(csv) {
                                    refreshResult = "✓ CSV imported successfully"
                                    withAnimation { showManualCSV = false }
                                    hasCSV = true
                                    appState?.scanClaudeUsage()
                                } else {
                                    refreshResult = "Invalid CSV — must contain a Date header"
                                }
                            }
                        case .failure:
                            refreshResult = "Failed to read file"
                        }
                    }
                }
            }

            if let result = refreshResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.contains("Failed") || result.contains("Invalid") ? .red : .green)
            }

            // Auto-refresh with saved cookie
            if hasSavedCookie {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $autoRefreshEnabled) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundStyle(.teal)
                            Text("Auto-refresh from saved cookie")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    if autoRefreshEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Refresh every")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Refresh every", selection: $autoRefreshHours) {
                                Text("1h").tag(1)
                                Text("3h").tag(3)
                                Text("6h").tag(6)
                                Text("12h").tag(12)
                                Text("24h").tag(24)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    HStack(spacing: 8) {
                        Button {
                            isRefreshing = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                let ok = scanner.refreshFromSavedCookie()
                                DispatchQueue.main.async {
                                    isRefreshing = false
                                    if ok {
                                        refreshResult = "✓ CSV refreshed from saved cookie"
                                        hasCSV = true
                                        appState?.scanClaudeUsage()
                                    } else {
                                        refreshResult = "Failed — cookie may be expired"
                                        autoRefreshEnabled = false
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isRefreshing {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(isRefreshing ? "Refreshing…" : "Refresh now")
                            }
                            .frame(height: 20)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshing)

                        Button(role: .destructive) {
                            scanner.clearSavedCookie()
                            hasSavedCookie = false
                            autoRefreshEnabled = false
                            refreshResult = "Saved cookie removed"
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle")
                                Text("Clear cookie")
                            }
                            .frame(height: 20)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // Destructive: remove cached CSV — at the end, only when cached
            if hasCSV {
                Button(role: .destructive) {
                    showConfirmDelete = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Remove CSV")
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Remove cached Cursor CSV?",
                    isPresented: $showConfirmDelete,
                    titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        try? FileManager.default.removeItem(atPath: scanner.csvCachePath)
                        hasCSV = false
                        refreshResult = "CSV removed"
                        appState?.scanClaudeUsage()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes the cached Cursor usage CSV. You'll need to extract or paste it again to see Cursor data in the breakdown.")
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { hasCSV = scanner.hasCachedCSV; hasSavedCookie = scanner.hasSavedCookie }
        .task(id: "\(autoRefreshEnabled)-\(autoRefreshHours)") {
            guard autoRefreshEnabled, hasSavedCookie else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TimeInterval(autoRefreshHours * 3600)))
                guard !Task.isCancelled else { break }
                let ok = await Task.detached { scanner.refreshFromSavedCookie() }.value
                await MainActor.run {
                    if ok {
                        refreshResult = "✓ Auto-refreshed from saved cookie"
                        hasCSV = true
                        appState?.scanClaudeUsage()
                    } else {
                        refreshResult = "Auto-refresh failed — cookie may be expired"
                        autoRefreshEnabled = false
                    }
                }
            }
        }
    }

}

private struct UsageSummaryCard: View {
    let dailyTotals: [ClaudeUsageTotals]

    var body: some View {
        let totalIn = dailyTotals.reduce(0) { $0 + $1.inputTokens + $1.cacheCreationTokens }
        let totalOut = dailyTotals.reduce(0) { $0 + $1.outputTokens }
        let totalCache = dailyTotals.reduce(0) { $0 + $1.cacheReadTokens }
        let totalMessages = dailyTotals.reduce(0) { $0 + $1.messageCount }

        VStack(alignment: .leading, spacing: 12) {
            Text("14-Day Summary")
                .font(.headline)
            HStack(spacing: 24) {
                UsageMetric(label: "Input", value: ClaudeUsageScanner.formatTokens(totalIn), color: .blue)
                UsageMetric(label: "Output", value: ClaudeUsageScanner.formatTokens(totalOut), color: .teal)
                UsageMetric(label: "Cache Read", value: ClaudeUsageScanner.formatTokens(totalCache), color: .orange)
                UsageMetric(label: "Messages", value: "\(totalMessages)", color: .secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }
}

private struct UsagePerSourceCard: View {
    let sources: [ClaudeUsageScanner.SourceTotals]

    /// Map a usage source name to its mascot's brand color.
    private func sourceColor(_ name: String) -> Color {
        switch name {
        case "Claude Code": return .orange      // Clawd — orange keyboard
        case "OMP":          return .teal         // Pi — teal terminal
        case "Codex":        return .gray         // Dex — black/white cloud
        case "Cursor":      return Color(red: 0.93, green: 0.93, blue: 0.93) // Cursor — light face
        default:            return .teal
        }
    }

    /// Map a usage source name to the MascotView source identifier.
    private func mascotSource(_ name: String) -> String {
        switch name {
        case "Claude Code": return "claude"
        case "OMP":         return "omp"
        case "Codex":       return "codex"
        case "Cursor":      return "cursor"
        default:            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-AI Breakdown (14 Days)")
                .font(.headline)

            ForEach(sources, id: \.name) { source in
                let totalTokens = source.total.inputTokens + source.total.outputTokens
                    + source.total.cacheCreationTokens + source.total.cacheReadTokens
                let allTotal = sources.reduce(0) { $0 + $1.total.inputTokens + $1.total.outputTokens
                    + $1.total.cacheCreationTokens + $1.total.cacheReadTokens }
                let pct = allTotal > 0 ? Double(totalTokens) / Double(allTotal) * 100 : 0
                let color = sourceColor(source.name)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        // Small mascot icon
                        MascotView(source: mascotSource(source.name), status: .idle, size: 24)
                            .frame(width: 24, height: 24)

                        Text(source.name)
                            .font(.system(.body, design: .default).bold())
                        Spacer()
                        Text("\(ClaudeUsageScanner.formatTokens(totalTokens)) · \(String(format: "%.0f%%", pct))")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(color)
                    }

                    // Progress bar — uses source color
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.2))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color.opacity(0.7))
                                    .frame(width: geo.size.width * CGFloat(pct / 100))
                            }
                    }
                    .frame(height: 6)

                    // Mini stats — offset to align with text after mascot
                    HStack(spacing: 16) {
                        Text("In: \(ClaudeUsageScanner.formatTokens(source.total.inputTokens + source.total.cacheCreationTokens))")
                        Text("Out: \(ClaudeUsageScanner.formatTokens(source.total.outputTokens))")
                        Text("Cache: \(ClaudeUsageScanner.formatTokens(source.total.cacheReadTokens))")
                        Text("Msgs: \(source.total.messageCount)")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 34) // align with text after 24pt mascot + 10pt spacing
                }
                .padding(.vertical, 4)
            }

            // Mini bar chart per source
            if sources.count > 1 {
                Divider().padding(.vertical, 4)
                ForEach(sources, id: \.name) { source in
                    let color = sourceColor(source.name)
                    UsageSourceBars(dailyTotals: source.dailyTotals, color: color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }
}

private struct UsageSourceBars: View {
    let dailyTotals: [ClaudeUsageTotals]
    var color: Color = .teal

    var body: some View {
        let peak = max(dailyTotals.map { $0.inputTokens + $0.outputTokens }.max() ?? 0, 1)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(dailyTotals.enumerated()), id: \.offset) { _, total in
                    let value = total.inputTokens + total.outputTokens
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.5))
                        .frame(height: max(2, CGFloat(value) / CGFloat(peak) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 24)
    }
}

private struct UsageMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UsageHistoryCard: View {
    let dailyTotals: [ClaudeUsageTotals]
    let scannedAt: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Usage (14 Days)")
                .font(.headline)
            UsageHistoryBars(dailyTotals: dailyTotals, scannedAt: scannedAt)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }
}

private struct UsageHistoryBars: View {
    let dailyTotals: [ClaudeUsageTotals]
    let scannedAt: Date

    var body: some View {
        let peak = max(dailyTotals.map { $0.inputTokens + $0.outputTokens }.max() ?? 0, 1)
        let cal = Calendar.current
        let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(dailyTotals.enumerated()), id: \.offset) { idx, total in
                let totalTokens = total.inputTokens + total.outputTokens
                let date = cal.date(byAdding: .day, value: -(dailyTotals.count - 1 - idx), to: cal.startOfDay(for: scannedAt)) ?? scannedAt
                let weekday = weekdays[cal.component(.weekday, from: date) - 1]
                let isToday = idx == dailyTotals.count - 1

                VStack(spacing: 3) {
                    Text(totalTokens > 0 ? ClaudeUsageScanner.formatTokens(totalTokens) : "")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isToday ? Color.teal.opacity(0.8) : Color.teal.opacity(0.35))
                        .frame(width: 18, height: max(2, CGFloat(totalTokens) / CGFloat(peak) * 80))
                    Text(weekday)
                        .font(.system(size: 8))
                        .foregroundStyle(isToday ? .teal : .secondary)
                }
                .help("\(cal.component(.month, from: date))/\(cal.component(.day, from: date)): in \(ClaudeUsageScanner.formatTokens(total.inputTokens)) · out \(ClaudeUsageScanner.formatTokens(total.outputTokens))")
            }
        }
        .frame(height: 100, alignment: .bottom)
    }
}

private struct UsageBreakdownCard: View {
    let last5h: ClaudeUsageTotals
    let today: ClaudeUsageTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today Breakdown")
                .font(.headline)
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                Text("Last 5 Hours").font(.caption).foregroundStyle(.secondary)
                    Text("\(ClaudeUsageScanner.formatTokens(last5h.inputTokens + last5h.cacheCreationTokens))↑ \(ClaudeUsageScanner.formatTokens(last5h.outputTokens))↓")
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                VStack(alignment: .leading) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                    Text("\(ClaudeUsageScanner.formatTokens(today.inputTokens + today.cacheCreationTokens))↑ \(ClaudeUsageScanner.formatTokens(today.outputTokens))↓")
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }
}

private struct UsageSparklineLarge: View {
    let buckets: [Int]

    var body: some View {
        let peak = max(buckets.max() ?? 0, 1)
        GeometryReader { geo in
            let n = max(buckets.count, 1)
            let spacing: CGFloat = 3
            let barWidth = max(4, (geo.size.width - CGFloat(n - 1) * spacing) / CGFloat(n))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(value == 0 ? Color.gray.opacity(0.2) : Color.teal.opacity(0.7))
                        .frame(width: barWidth, height: max(3, CGFloat(value) / CGFloat(peak) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 120)
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onClear: () -> Void
    @ObservedObject private var l10n = L10n.shared

    private var conflict: ShortcutAction? { action.conflictingAction() }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n["shortcut_\(action.rawValue)"])
                Text(l10n["shortcut_\(action.rawValue)_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let conflict {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("\(l10n["shortcut_conflict"]) \(l10n["shortcut_\(conflict.rawValue)"])")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
            if isRecording {
                Text(l10n["shortcut_recording"])
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(.orange, lineWidth: 1))
            } else if action.isEnabled {
                HStack(spacing: 6) {
                    Text(action.binding.displayString)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        .onTapGesture { onStartRecording() }

                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(l10n["shortcut_none"])
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .onTapGesture { onStartRecording() }
            }
        }
        .contentShape(Rectangle())
    }
}
