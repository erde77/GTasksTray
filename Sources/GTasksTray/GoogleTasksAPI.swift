import Foundation

struct GoogleTaskList: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
}

struct GoogleTask: Decodable, Identifiable, Sendable {
    struct SourceLink: Decodable, Sendable {
        let description: String?
        let link: String
    }

    struct AssignmentInfo: Decodable, Sendable {
        let linkToTask: String?
    }

    let id: String
    let title: String?
    let notes: String?
    let due: String?
    let completed: String?
    let status: String
    let parent: String?
    let links: [SourceLink]?
    let assignmentInfo: AssignmentInfo?
    let deleted: Bool?

    var isCompleted: Bool { status == "completed" }

    var sourceLinks: [SourceLink] {
        let links = links ?? []
        guard let link = assignmentInfo?.linkToTask, !links.contains(where: { $0.link == link }) else {
            return links
        }
        return links + [SourceLink(description: nil, link: link)]
    }

    func displayTitle(in language: AppLanguage) -> String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return language.text("Untitled")
        }
        return title
    }
}

struct TaskGroup: Identifiable, Sendable {
    let list: GoogleTaskList
    var tasks: [GoogleTask]

    var id: String { list.id }
}

struct TaskLocation: Hashable {
    let listID: String
    let taskID: String
}

struct CompletedTaskEntry: Identifiable {
    let list: GoogleTaskList
    let task: GoogleTask
    let completedAt: Date?

    var id: TaskLocation { TaskLocation(listID: list.id, taskID: task.id) }

    static func newestFirst(in groups: [TaskGroup]) -> [Self] {
        groups.flatMap { group in
            group.tasks.compactMap { task in
                guard task.isCompleted else { return nil }
                return Self(list: group.list, task: task, completedAt: task.completed.flatMap(TaskDate.completionDate))
            }
        }.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
}

struct NewTask: Encodable, Sendable {
    let title: String
    let notes: String?
    let due: String?
}

enum TaskDate {
    static func encode(_ date: Date, calendar: Calendar = .current) -> String {
        // Google stores the UTC calendar day, while the picker supplies a local day.
        let day = Calendar(identifier: .gregorian).dateComponents(in: calendar.timeZone, from: date)
        return String(
            format: "%04d-%02d-%02dT00:00:00Z",
            day.year!, day.month!, day.day!
        )
    }

    static func scheduledDay(_ value: String, locale: Locale) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(value.prefix(10))) else { return nil }
        formatter.locale = locale
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    static func completionDate(_ value: String) -> Date? {
        (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(value, strategy: .iso8601))
    }
}

struct GoogleTasksAPI: Sendable {
    struct RequestError: AppLocalizedError {
        let status: Int

        func message(in language: AppLanguage) -> String {
            switch status {
            case 403: language.text("Google denied access. Check that the Google Tasks API is enabled and your account has access.")
            case 404: language.text("Google could not find this task or list. Refresh your tasks.")
            case 429: language.text("Google is limiting requests. Try again in a moment.")
            default: language.format("Google Tasks returned an error (HTTP %ld).", status)
            }
        }
    }

    private struct Page<Item: Decodable>: Decodable {
        let items: [Item]?
        let nextPageToken: String?
    }

    private struct CompletedTask: Encodable {
        let status = "completed"
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchGroups(token: String) async throws -> [TaskGroup] {
        let lists: [GoogleTaskList] = try await fetchPages(
            path: ["users", "@me", "lists"],
            query: ["maxResults": "1000"],
            token: token
        )
        return try await withThrowingTaskGroup(of: (Int, TaskGroup).self) { group in
            var results = [TaskGroup?](repeating: nil, count: lists.count)
            var remaining = lists.enumerated().makeIterator()

            func enqueueNext() {
                guard let (index, list) = remaining.next() else { return }
                group.addTask {
                    let tasks: [GoogleTask] = try await fetchPages(
                        path: ["lists", list.id, "tasks"],
                        query: [
                            "maxResults": "100",
                            "showCompleted": "true",
                            "showHidden": "true",
                            "showAssigned": "true"
                        ],
                        token: token
                    )
                    return (index, TaskGroup(list: list, tasks: tasks.filter { $0.deleted != true }))
                }
            }

            for _ in 0..<min(6, lists.count) { enqueueNext() }
            while let (index, result) = try await group.next() {
                results[index] = result
                enqueueNext()
            }
            return results.compactMap { $0 }
        }
    }

    func add(_ task: NewTask, to listID: String, token: String) async throws -> GoogleTask {
        try await send(
            path: ["lists", listID, "tasks"],
            method: "POST",
            body: JSONEncoder().encode(task),
            token: token
        )
    }

    func complete(taskID: String, listID: String, token: String) async throws -> GoogleTask {
        try await send(
            path: ["lists", listID, "tasks", taskID],
            method: "PATCH",
            body: JSONEncoder().encode(CompletedTask()),
            token: token
        )
    }

    private func fetchPages<Item: Decodable>(
        path: [String],
        query: [String: String],
        token: String
    ) async throws -> [Item] {
        var items: [Item] = []
        var pageToken: String?
        repeat {
            var parameters = query
            parameters["pageToken"] = pageToken
            let page: Page<Item> = try await send(path: path, query: parameters, token: token)
            items.append(contentsOf: page.items ?? [])
            pageToken = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil
        return items
    }

    private func send<Response: Decodable>(
        path: [String],
        query: [String: String] = [:],
        method: String = "GET",
        body: Data? = nil,
        token: String
    ) async throws -> Response {
        let root = URL(string: "https://tasks.googleapis.com/tasks/v1/")!
        let url = path.reduce(root) { $0.appending(component: $1) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw RequestError(status: http.statusCode) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
