import XCTest
@testable import GTasksTray

@MainActor
final class GoogleTasksTests: XCTestCase {
    func testListsAndTasksArePaginatedAndCompletedTasksDoNotCount() async throws {
        let groups = try await fixtureAPI().fetchGroups(token: "test-token")

        XCTAssertEqual(groups.map(\.id), ["personal", "work"])
        XCTAssertEqual(groups[0].tasks.map(\.id), ["open", "completed"])
        XCTAssertEqual(groups[0].tasks[0].notes, "Buy two")
        XCTAssertEqual(groups[1].tasks.map(\.id), ["assigned"])
        XCTAssertEqual(TaskStore.openCount(in: groups), 2)
        XCTAssertEqual(TaskStore.openCount(in: []), 0)
    }

    func testAddingAndCompletingSendTheExpectedRequests() async throws {
        let api = fixtureAPI()
        let draft = NewTask(title: "Read", notes: "Chapter 1", due: "2026-11-03T00:00:00Z")
        let created = try await api.add(draft, to: "personal", token: "test-token")
        XCTAssertEqual(created.id, "new")
        XCTAssertFalse(created.isCompleted)

        let completed = try await api.complete(taskID: created.id, listID: "personal", token: "test-token")
        XCTAssertEqual(completed.id, created.id)
        XCTAssertTrue(completed.isCompleted)
    }

    func testSchedulingPreservesTheDayInTheLocalTimeZone() throws {
        var warsaw = Calendar(identifier: .gregorian)
        warsaw.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Warsaw"))
        let midnight = try XCTUnwrap(warsaw.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        XCTAssertEqual(TaskDate.encode(midnight, calendar: warsaw), "2026-11-03T00:00:00Z")
        XCTAssertEqual(TaskDate.scheduledDay("2026-11-03T00:00:00.000Z"), "3 lis 2026")
    }

    func testRecentCompletedTasksAreOrderedAcrossLists() throws {
        let decoder = JSONDecoder()
        let personal = try decoder.decode([GoogleTask].self, from: Data("""
            [
              {"id":"old","status":"completed","completed":"2026-11-01T09:00:00Z"},
              {"id":"third","status":"completed","completed":"2026-11-03T10:00:00Z"},
              {"id":"missing","status":"completed"},
              {"id":"second","status":"completed","completed":"2026-11-03T10:00:00.123Z"}
            ]
            """.utf8))
        let work = try decoder.decode([GoogleTask].self, from: Data("""
            [
              {"id":"open","status":"needsAction"},
              {"id":"fourth","status":"completed","completed":"2026-11-03T10:59:00+01:00"},
              {"id":"first","status":"completed","completed":"2026-11-03T10:01:00Z"},
              {"id":"fifth","status":"completed","completed":"2026-11-02T08:00:00Z"}
            ]
            """.utf8))
        let entries = CompletedTaskEntry.newestFirst(in: [
            TaskGroup(list: .init(id: "personal", title: "Osobiste"), tasks: personal),
            TaskGroup(list: .init(id: "work", title: "Praca"), tasks: work)
        ])

        XCTAssertEqual(entries.prefix(5).map(\.id.taskID), ["first", "second", "third", "fourth", "fifth"])
        XCTAssertEqual(entries.dropFirst(5).map(\.id.taskID), ["old", "missing"])
    }

    private func fixtureAPI() -> GoogleTasksAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TasksFixture.self]
        return GoogleTasksAPI(session: URLSession(configuration: configuration))
    }
}

private final class TasksFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let client else { return }
        XCTAssertEqual(url.host, "tasks.googleapis.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let page = query.first { $0.name == "pageToken" }?.value
        let payload: String
        let status: Int

        switch (request.httpMethod, url.path, page) {
        case ("GET", "/tasks/v1/users/@me/lists", nil):
            payload = #"{"items":[{"id":"personal","title":"Personal"}],"nextPageToken":"list+2"}"#
            status = 200
        case ("GET", "/tasks/v1/users/@me/lists", "list+2"):
            XCTAssertTrue(url.absoluteString.contains("pageToken=list%2B2"))
            payload = #"{"items":[{"id":"work","title":"Work"}]}"#
            status = 200
        case ("GET", "/tasks/v1/lists/personal/tasks", nil):
            for flag in ["showHidden", "showCompleted", "showAssigned"] {
                XCTAssertTrue(query.contains(URLQueryItem(name: flag, value: "true")))
            }
            payload = #"{"items":[{"id":"open","title":"Groceries","notes":"Buy two","status":"needsAction"}],"nextPageToken":"tasks-2"}"#
            status = 200
        case ("GET", "/tasks/v1/lists/personal/tasks", "tasks-2"):
            payload = #"{"items":[{"id":"completed","status":"completed"},{"id":"deleted","status":"needsAction","deleted":true}]}"#
            status = 200
        case ("GET", "/tasks/v1/lists/work/tasks", nil):
            payload = #"{"items":[{"id":"assigned","status":"needsAction"}]}"#
            status = 200
        case ("POST", "/tasks/v1/lists/personal/tasks", nil):
            XCTAssertEqual(body(), ["title": "Read", "notes": "Chapter 1", "due": "2026-11-03T00:00:00Z"])
            payload = #"{"id":"new","title":"Read","status":"needsAction"}"#
            status = 200
        case ("PATCH", "/tasks/v1/lists/personal/tasks/new", nil):
            XCTAssertEqual(body(), ["status": "completed"])
            payload = #"{"id":"new","title":"Read","status":"completed"}"#
            status = 200
        default:
            payload = "{}"
            status = 404
        }

        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: Data(payload.utf8))
        client.urlProtocolDidFinishLoading(self)
    }

    private func body() -> [String: String]? {
        if let data = request.httpBody {
            return try? JSONDecoder().decode([String: String].self, from: data)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while case let size = stream.read(&buffer, maxLength: buffer.count), size > 0 {
            data.append(contentsOf: buffer.prefix(size))
        }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}
