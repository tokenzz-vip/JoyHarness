import Foundation

struct IssueFeedback: Encodable {
    static let titleByteLimit = 240
    static let bodyByteLimit = 12_000

    let title: String
    let body: String

    var validationMessage: String? {
        if title.utf8.count > Self.titleByteLimit { return "请缩短标题。" }
        if body.utf8.count > Self.bodyByteLimit { return "请缩短问题描述或取消附上诊断信息。" }
        return nil
    }

    var githubDraft: (url: URL, needsBodyPaste: Bool) {
        let newIssue = AppInfo.repository.appending(path: "issues/new")
        var components = URLComponents(url: newIssue, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        if let url = components.url, url.absoluteString.utf8.count <= 7_000 { return (url, false) }

        components.queryItems = [URLQueryItem(name: "title", value: title)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return (components.url ?? newIssue, true)
    }

    static var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "JoyHarnessFeedbackURL") as? String,
              let url = URL(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }

    @MainActor
    func submit(to endpoint: URL, using session: URLSession = .shared) async throws -> CreatedIssue {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(self)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 429 { throw SubmissionError.rateLimited }
        guard status == 201, let issue = try? JSONDecoder().decode(CreatedIssue.self, from: data), issue.number > 0 else {
            throw SubmissionError.unconfirmed
        }
        return issue
    }

    struct CreatedIssue: Decodable {
        let number: Int

        var url: URL { AppInfo.repository.appending(path: "issues/\(number)") }
    }

    enum SubmissionError: Error {
        case rateLimited
        case unconfirmed
    }
}
