import AppKit
import Combine

@MainActor
final class TaskStore: ObservableObject {
    enum Connection {
        case unconfigured
        case signedOut
        case connected
    }

    enum Completion: Equatable {
        case saving(TaskLocation)
        case confirmed(TaskLocation)
    }

    @Published private(set) var connection: Connection = .unconfigured
    @Published private(set) var groups: [TaskGroup] = [] {
        didSet {
            openGroups = groups.compactMap { group in
                let tasks = group.tasks.filter { !$0.isCompleted }
                return tasks.isEmpty ? nil : TaskGroup(list: group.list, tasks: tasks)
            }
            completedTasks = CompletedTaskEntry.newestFirst(in: groups)
        }
    }
    @Published private(set) var hasLoaded = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSigningIn = false
    @Published private(set) var isSaving = false
    @Published private(set) var completion: Completion?
    @Published var language = AppLanguage.saved {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey) }
    }
    @Published private var actionError: (any Error)?
    @Published private var refreshError: (any Error)?
    private(set) var openGroups: [TaskGroup] = []
    private(set) var completedTasks: [CompletedTaskEntry] = []

    private let api = GoogleTasksAPI()
    private let oauth = GoogleOAuth()
    private var credentials: GoogleCredentials?
    private var accessToken: (value: String, expiresAt: Date)?
    private var lastRefreshAttempt: Date?
    private var signInTask: Task<Void, Never>?
    private var isOpeningTasksInChrome = false
    private lazy var completionSound = Bundle.main.url(forResource: "TaskComplete", withExtension: "wav")
        .flatMap { NSSound(contentsOf: $0, byReference: true) } ?? NSSound(named: "Tink")

    var isBusy: Bool {
        isRefreshing || isSigningIn || isSaving || completion != nil
    }

    var openCount: Int { openGroups.reduce(0) { $0 + $1.tasks.count } }
    var error: String? { (actionError ?? refreshError).map(message(for:)) }

    static func openCount(in groups: [TaskGroup]) -> Int {
        groups.reduce(0) { count, group in
            count + group.tasks.count(where: { !$0.isCompleted })
        }
    }

    init() {
        do {
            credentials = try CredentialStore.load()
            if let credentials {
                connection = credentials.refreshToken == nil ? .signedOut : .connected
            }
        } catch {
            actionError = error
        }
    }

    func importClient(from url: URL) {
        guard !isBusy else { return }
        do {
            let client = try GoogleOAuthClient.load(from: url)
            if client != credentials?.client {
                let updated = GoogleCredentials(client: client)
                try CredentialStore.save(updated)
                credentials = updated
                resetSession()
            }
            actionError = nil
        } catch {
            actionError = error
        }
    }

    func signIn() {
        guard !isBusy, connection == .signedOut, let credentials else { return }
        isSigningIn = true
        actionError = nil
        signInTask = Task {
            do {
                let token = try await oauth.signIn(client: credentials.client, language: language)
                try Task.checkCancellation()
                guard let refreshToken = token.refresh_token else {
                    throw GoogleOAuth.Error.missingRefreshToken
                }
                var updated = credentials
                updated.refreshToken = refreshToken
                try CredentialStore.save(updated)
                self.credentials = updated
                remember(token)
                connection = .connected
            } catch is CancellationError {
                // The user closed the login flow.
            } catch {
                if !Task.isCancelled { actionError = error }
            }
            signInTask = nil
            isSigningIn = false
            await refresh(force: true)
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    func signOut() {
        guard !isBusy else { return }
        do {
            try clearSession()
            actionError = nil
        } catch {
            actionError = error
        }
    }

    func dismissError() {
        actionError = nil
        refreshError = nil
    }

    func refresh(force: Bool = false) async {
        guard connection == .connected, !isBusy else { return }
        if !force, let lastRefreshAttempt, Date().timeIntervalSince(lastRefreshAttempt) < 15 { return }
        isRefreshing = true
        lastRefreshAttempt = Date()
        if force { dismissError() }
        defer { isRefreshing = false }
        do {
            groups = try await authorized { try await api.fetchGroups(token: $0) }
            hasLoaded = true
            refreshError = nil
        } catch {
            refreshError = error
        }
    }

    func add(_ task: NewTask, to listID: String) async -> Bool {
        guard connection == .connected, !isBusy,
              let index = groups.firstIndex(where: { $0.id == listID }) else { return false }
        actionError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await authorized { try await api.add(task, to: listID, token: $0) }
            groups[index].tasks.insert(created, at: 0)
            Task { await refresh(force: true) }
            return true
        } catch {
            actionError = error
            return false
        }
    }

    func complete(_ task: GoogleTask, in listID: String, playSound: Bool) async {
        guard connection == .connected, !isBusy, !task.isCompleted,
              let groupIndex = groups.firstIndex(where: { $0.id == listID }),
              let taskIndex = groups[groupIndex].tasks.firstIndex(where: { $0.id == task.id }) else { return }
        actionError = nil
        let location = TaskLocation(listID: listID, taskID: task.id)
        completion = .saving(location)
        defer { completion = nil }
        do {
            let completed = try await authorized {
                try await api.complete(taskID: task.id, listID: listID, token: $0)
            }
            guard completed.isCompleted else {
                actionError = AppMessage("Google Tasks did not confirm completion. Refresh the list and try again.")
                return
            }
            completion = .confirmed(location)
            if playSound {
                completionSound?.play()
            }
            // Keep the checked row visible briefly before moving it to the completed list.
            try? await Task.sleep(for: .milliseconds(450))
            groups[groupIndex].tasks[taskIndex] = completed
            Task { await refresh(force: true) }
        } catch {
            actionError = error
        }
    }

    func openTasksInChrome() async {
        guard !isOpeningTasksInChrome else { return }
        isOpeningTasksInChrome = true
        defer { isOpeningTasksInChrome = false }
        if ChromeTasksTab.activateIfOpen() { return }
        await openInChrome(ChromeTasksTab.url)
    }

    func openInChrome(_ url: URL) async {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ChromeTasksTab.browserID) else {
            actionError = AppMessage("Install Google Chrome to open tasks in your browser.")
            return
        }
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: .init())
        } catch {
            actionError = AppMessage("Could not open a tab in Google Chrome.")
        }
    }

    private func authorized<Value>(_ request: (String) async throws -> Value) async throws -> Value {
        let token = try await validAccessToken()
        do {
            return try await request(token)
        } catch let error as GoogleTasksAPI.RequestError where error.status == 401 {
            accessToken = nil
            let renewed = try await validAccessToken()
            return try await request(renewed)
        }
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, accessToken.expiresAt.timeIntervalSinceNow > 60 { return accessToken.value }
        guard var credentials, let refreshToken = credentials.refreshToken else {
            throw GoogleOAuth.Error.missingRefreshToken
        }
        do {
            let token = try await oauth.refresh(client: credentials.client, refreshToken: refreshToken)
            if let updatedToken = token.refresh_token, updatedToken != refreshToken {
                credentials.refreshToken = updatedToken
                try CredentialStore.save(credentials)
                self.credentials = credentials
            }
            remember(token)
            return token.access_token
        } catch GoogleOAuth.Error.requestFailed(_, "invalid_grant") {
            try clearSession()
            throw GoogleOAuth.Error.requestFailed(status: 400, code: "invalid_grant")
        }
    }

    private func remember(_ token: GoogleOAuth.Token) {
        accessToken = (token.access_token, Date().addingTimeInterval(TimeInterval(token.expires_in)))
    }

    private func clearSession() throws {
        guard var credentials else { return }
        credentials.refreshToken = nil
        try CredentialStore.save(credentials)
        self.credentials = credentials
        resetSession()
    }

    private func resetSession() {
        accessToken = nil
        groups = []
        hasLoaded = false
        lastRefreshAttempt = nil
        refreshError = nil
        connection = .signedOut
    }

    private func message(for error: any Error) -> String {
        if let localized = error as? any AppLocalizedError { return localized.message(in: language) }
        if let networkError = error as? URLError {
            return networkError.code == .notConnectedToInternet
                ? language.text("No internet connection.")
                : language.text("Could not connect to Google. Try again.")
        }
        if error is DecodingError { return language.text("Could not read the data.") }
        return error.localizedDescription
    }
}
