import SwiftUI

struct SettingsView: View {
    @Environment(AppListStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("checkIntervalHours") private var checkIntervalHours = 6
    @AppStorage("notifyNewUpdates") private var notifyNewUpdates = true
    @AppStorage("showDockIcon") private var showDockIcon = true
    @State private var loginItem = LoginItemModel()
    @State private var token = TokenStore.load() ?? ""

    var body: some View {
        Form {
            Section("Updates") {
                Picker("Check for updates", selection: $checkIntervalHours) {
                    Text("Manually").tag(0)
                    Text("Every hour").tag(1)
                    Text("Every 6 hours").tag(6)
                    Text("Every day").tag(24)
                }
                .onChange(of: checkIntervalHours) {
                    store.applySchedule()
                }

                LabeledContent {
                    if let nextCheckAt = store.nextAutomaticCheckAt {
                        Text(nextCheckAt, style: .relative)
                    } else {
                        Text("Off")
                    }
                } label: {
                    Text(nextCheckLabel)
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if let error = loginItem.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(loginErrorTransition)
                }

                Toggle("Notify about new updates", isOn: $notifyNewUpdates)

                Toggle("Show the Dock icon while a window is open", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) {
                        FreshlyAppDelegate.applyDockIconPreference()
                    }
            }

            Section("GitHub") {
                SecureField("GitHub token (optional)", text: $token)
                    .onChange(of: token) {
                        TokenStore.save(token)
                    }
                Text("Raises GitHub's rate limit for release checks. Stored in your keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
                Link("View on GitHub", destination: Self.repositoryURL)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .animation(loginErrorAnimation, value: loginItem.lastError != nil)
    }

    private static let repositoryURL = URL(string: "https://github.com/ruimiguelcolaco/freshly")!

    private var nextCheckLabel: LocalizedStringResource {
        store.isAutomaticRetryPending ? "Next retry" : "Next automatic check"
    }

    private var loginErrorAnimation: Animation {
        .snappy(duration: reduceMotion ? 0.12 : 0.2)
    }

    private var loginErrorTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return build.isEmpty || build == short ? short : "\(short) (\(build))"
    }
}
