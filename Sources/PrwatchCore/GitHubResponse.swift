import Foundation

/// The one GraphQL request behind the list, and how its answer becomes pull requests.
public enum GitHubResponse {
    public static let query = """
        {
          viewer { login }
          mine: search(query: "is:pr is:open author:@me archived:false", type: ISSUE, first: 30) {
            nodes { ... on PullRequest {
              number title url isDraft createdAt reviewDecision mergeable
              repository { name }
              author { login __typename }
              commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
              latestReviews(first: 20) { nodes { author { login __typename } state submittedAt bodyText url } }
              comments(last: 20) { nodes { author { login __typename } createdAt bodyText url } }
              reviewThreads(last: 50) { nodes { isResolved comments(last: 1) { nodes { author { login __typename } createdAt bodyText url } } } }
            } }
          }
          toReview: search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 30) {
            nodes { ... on PullRequest {
              number title url isDraft createdAt additions deletions changedFiles
              repository { name }
              author { login __typename }
              reviewRequests(first: 20) { nodes { requestedReviewer { __typename ... on User { login } ... on Team { name } } } }
              timelineItems(last: 30, itemTypes: [REVIEW_REQUESTED_EVENT]) { nodes { ... on ReviewRequestedEvent { createdAt requestedReviewer { __typename ... on User { login } ... on Team { name } } } } }
            } }
          }
        }
        """

    public struct Failure: Error, Equatable {
        public var message: String
    }

    /// Your pull requests and the ones you were asked to review, sorted with what you can act on first.
    public static func pullRequests(from json: Data) throws -> [PullRequest] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(Response.self, from: json)
        guard let data = response.data else {
            throw Failure(message: response.errors?.first?.message ?? "GitHub sent no data")
        }
        let viewer = data.viewer.login
        let mine = data.mine.nodes.compactMap { $0.asMine(viewer: viewer) }
        let toReview = data.toReview.nodes.compactMap { $0.asReviewRequest(viewer: viewer) }
        return (mine + toReview).sorted(by: PullRequest.comesBefore)
    }
}

private struct Response: Decodable {
    struct Payload: Decodable {
        var viewer: Viewer
        var mine: Nodes<PullRequestNode>
        var toReview: Nodes<PullRequestNode>
    }

    struct Viewer: Decodable {
        var login: String
    }

    struct GraphQLError: Decodable {
        var message: String
    }

    var data: Payload?
    var errors: [GraphQLError]?
}

private struct Nodes<Node: Decodable>: Decodable {
    var nodes: [Node]
}

private struct Actor: Decodable {
    var login: String
    var typename: String?

    enum CodingKeys: String, CodingKey {
        case login
        case typename = "__typename"
    }

    /// Some bots post as ordinary user accounts, so the name counts too.
    var isBot: Bool {
        typename == "Bot" || login.lowercased().hasSuffix("bot") || login.hasSuffix("[bot]")
    }
}

private struct Remark: Decodable {
    var author: Actor?
    var createdAt: Date
    var bodyText: String
    var url: URL
}

private struct Review: Decodable {
    var author: Actor?
    var state: String
    var submittedAt: Date?
    var bodyText: String
    var url: URL
}

private struct ReviewThread: Decodable {
    var isResolved: Bool
    var comments: Nodes<Remark>
}

private struct CommitNode: Decodable {
    struct Commit: Decodable {
        struct Rollup: Decodable {
            var state: String
        }

        var committedDate: Date
        var statusCheckRollup: Rollup?
    }

    var commit: Commit
}

private struct Reviewer: Decodable {
    var typename: String
    var login: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case login, name
        case typename = "__typename"
    }
}

private struct ReviewRequest: Decodable {
    var requestedReviewer: Reviewer?
    var createdAt: Date?
}

/// One search result. The fields past `author` are only asked for on one of the two searches.
private struct PullRequestNode: Decodable {
    struct Repository: Decodable {
        var name: String
    }

    var number: Int?
    var title: String?
    var url: URL?
    var isDraft: Bool?
    var createdAt: Date?
    var repository: Repository?
    var author: Actor?

    var reviewDecision: String?
    var mergeable: String?
    var commits: Nodes<CommitNode>?
    var latestReviews: Nodes<Review>?
    var comments: Nodes<Remark>?
    var reviewThreads: Nodes<ReviewThread>?

    var additions: Int?
    var deletions: Int?
    var changedFiles: Int?
    var reviewRequests: Nodes<ReviewRequest>?
    var timelineItems: Nodes<ReviewRequest>?

    private func pullRequest(attention: PullRequest.Attention, since: Date) -> PullRequest? {
        guard let number, let title, let url, let repository else { return nil }
        return PullRequest(
            repository: repository.name,
            number: number,
            title: title,
            url: url,
            author: author?.login ?? "ghost",
            isDraft: isDraft ?? false,
            attention: attention,
            since: since
        )
    }

    func asMine(viewer: String) -> PullRequest? {
        guard let createdAt else { return nil }
        let waitingComments = commentsWaiting(on: viewer)
        if let oldest = waitingComments.first {
            var pullRequest = pullRequest(attention: .comments, since: oldest.at)
            pullRequest?.comments = waitingComments
            return pullRequest
        }
        let reviews = latestReviews?.nodes ?? []
        let isApproved = reviewDecision == "APPROVED"
            || (reviewDecision == nil && reviews.contains { $0.state == "APPROVED" } && !reviews.contains { $0.state == "CHANGES_REQUESTED" })
        if isApproved, isDraft != true {
            let approvedAt = reviews.filter { $0.state == "APPROVED" }.compactMap(\.submittedAt).max()
            return pullRequest(attention: .approved, since: approvedAt ?? createdAt)
        }
        return pullRequest(attention: .waiting(whyWaiting), since: createdAt)
    }

    func asReviewRequest(viewer: String) -> PullRequest? {
        guard let createdAt else { return nil }
        let reviewers = reviewRequests?.nodes.compactMap(\.requestedReviewer) ?? []
        let isAskedByName = reviewers.contains { $0.login == viewer }
        let team = isAskedByName ? nil : reviewers.first { $0.typename == "Team" }?.name
        let requestedAt = timelineItems?.nodes
            .filter { isAskedByName ? $0.requestedReviewer?.login == viewer : $0.requestedReviewer?.typename == "Team" }
            .compactMap(\.createdAt)
            .max()
        var pullRequest = pullRequest(attention: .review, since: requestedAt ?? createdAt)
        pullRequest?.requestedTeam = team
        if let additions, let deletions, let changedFiles {
            pullRequest?.size = Size(additions: additions, deletions: deletions, files: changedFiles)
        }
        return pullRequest
    }

    /// Review threads have a resolved flag, so an open one counts until you answer it or resolve it,
    /// whoever wrote it. Comments on the conversation and review summaries have no such flag: those
    /// count when a person wrote them after your last push and your last comment there.
    private func commentsWaiting(on viewer: String) -> [Comment] {
        var waiting: [Comment] = []
        for thread in reviewThreads?.nodes ?? [] where !thread.isResolved {
            guard let latest = thread.comments.nodes.last, latest.author?.login != viewer else { continue }
            waiting.append(Comment(author: latest.author?.login ?? "ghost", text: Self.firstLine(of: latest.bodyText) ?? "Comment", url: latest.url, at: latest.createdAt))
        }

        let conversation = comments?.nodes ?? []
        let lastPush = commits?.nodes.last?.commit.committedDate
        let lastReply = conversation.filter { $0.author?.login == viewer }.map(\.createdAt).max()
        let answeredThrough = [lastPush, lastReply].compactMap { $0 }.max() ?? .distantPast
        func isFromSomeoneWaiting(_ author: Actor?, at date: Date) -> Bool {
            guard let author else { return false }
            return author.login != viewer && !author.isBot && date > answeredThrough
        }

        for remark in conversation where isFromSomeoneWaiting(remark.author, at: remark.createdAt) {
            waiting.append(Comment(author: remark.author?.login ?? "ghost", text: Self.firstLine(of: remark.bodyText) ?? "Comment", url: remark.url, at: remark.createdAt))
        }
        for review in latestReviews?.nodes ?? [] {
            guard let submittedAt = review.submittedAt, isFromSomeoneWaiting(review.author, at: submittedAt) else { continue }
            let requestedChanges = review.state == "CHANGES_REQUESTED"
            guard requestedChanges || review.state == "COMMENTED" else { continue }
            // A review with no summary only carries its threads, which are already counted above.
            guard let text = Self.firstLine(of: review.bodyText) ?? (requestedChanges ? "Requested changes" : nil) else { continue }
            waiting.append(Comment(author: review.author?.login ?? "ghost", text: text, url: review.url, at: submittedAt))
        }
        return waiting.sorted { $0.at < $1.at }
    }

    private var whyWaiting: PullRequest.Waiting {
        if isDraft == true { return .draft }
        let checks = commits?.nodes.last?.commit.statusCheckRollup?.state
        if checks == "FAILURE" || checks == "ERROR" { return .checksFailing }
        if mergeable == "CONFLICTING" { return .conflicts }
        return .inReview
    }

    private static func firstLine(of text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(200)) }
    }
}
