import Foundation

/// An open pull request and whether it's your move.
public struct PullRequest: Identifiable, Sendable, Equatable {
    public enum Attention: Sendable, Equatable {
        /// Yours, and someone is waiting on your answer.
        case comments
        /// Someone else's, and they asked for your review.
        case review
        /// Yours, approved, with nothing left to answer.
        case approved
        /// Yours, and the next move is someone else's.
        case waiting(Waiting)
    }

    public enum Waiting: Sendable, Equatable {
        case draft
        case checksFailing
        case conflicts
        case inReview
    }

    public var repository: String
    public var number: Int
    public var title: String
    public var url: URL
    public var author: String
    public var isDraft: Bool
    public var attention: Attention
    /// When it became your move: the oldest comment still waiting on you, the review request, or the
    /// approval. For a pull request that's waiting on others, when it was opened.
    public var since: Date
    /// The comments waiting on you, oldest first.
    public var comments: [Comment]
    public var size: Size?
    /// Set when the review was asked of a team you're on, not of you by name.
    public var requestedTeam: String?

    public var id: String { url.absoluteString }

    public init(
        repository: String,
        number: Int,
        title: String,
        url: URL,
        author: String,
        isDraft: Bool = false,
        attention: Attention,
        since: Date,
        comments: [Comment] = [],
        size: Size? = nil,
        requestedTeam: String? = nil
    ) {
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.author = author
        self.isDraft = isDraft
        self.attention = attention
        self.since = since
        self.comments = comments
        self.size = size
        self.requestedTeam = requestedTeam
    }

    /// What you can act on comes first: your pull requests with comments, then the reviews you owe,
    /// then your approved ones, then the ones waiting on others. Oldest first within each, so the one
    /// that has waited longest is on top.
    public static func comesBefore(_ lhs: PullRequest, _ rhs: PullRequest) -> Bool {
        if lhs.attention.rank != rhs.attention.rank {
            return lhs.attention.rank < rhs.attention.rank
        }
        if lhs.since != rhs.since {
            return lhs.since < rhs.since
        }
        return lhs.number < rhs.number
    }

    /// The title without the bracketed tags teams put around it, like `[WEB-12] [mid] Fix login`, so a
    /// narrow panel spends its width on the words.
    public var shortTitle: String {
        var text = Substring(title).trimmingPrefix(while: \.isWhitespace)
        while text.hasPrefix("["), let end = text.firstIndex(of: "]") {
            text = text[text.index(after: end)...].trimmingPrefix(while: \.isWhitespace)
        }
        while text.hasSuffix("]"), let start = text.lastIndex(of: "[") {
            text = text[..<start]
            while text.last?.isWhitespace == true { text.removeLast() }
        }
        return text.isEmpty ? title : String(text)
    }

    /// Where a click should land: the changes for a review, the conversation for everything else.
    public var urlToOpen: URL {
        attention == .review ? url.appending(path: "files") : url
    }
}

extension PullRequest.Attention {
    public var isActionable: Bool {
        if case .waiting = self { return false }
        return true
    }

    public func label(elapsed: String) -> String {
        switch self {
        case .comments: "comments \(elapsed)"
        case .review: "review \(elapsed)"
        case .approved: "approved \(elapsed)"
        case .waiting(.draft): "draft \(elapsed)"
        case .waiting(.checksFailing): "checks failing"
        case .waiting(.conflicts): "conflicts"
        case .waiting(.inReview): "in review \(elapsed)"
        }
    }

    var rank: Int {
        switch self {
        case .comments: 0
        case .review: 1
        case .approved: 2
        case .waiting: 3
        }
    }
}

/// A comment someone is waiting on you to answer.
public struct Comment: Identifiable, Sendable, Equatable {
    public var author: String
    /// Its first line.
    public var text: String
    public var url: URL
    public var at: Date

    public var id: String { url.absoluteString }

    public init(author: String, text: String, url: URL, at: Date) {
        self.author = author
        self.text = text
        self.url = url
        self.at = at
    }
}

/// How much there is to read in a review.
public struct Size: Sendable, Equatable {
    public var additions: Int
    public var deletions: Int
    public var files: Int

    public init(additions: Int, deletions: Int, files: Int) {
        self.additions = additions
        self.deletions = deletions
        self.files = files
    }

    public var text: String {
        "+\(additions) −\(deletions)"
    }
}

extension Array where Element == PullRequest {
    public func count(_ attention: PullRequest.Attention) -> Int {
        count { $0.attention == attention }
    }

    public var actionable: [PullRequest] {
        filter { $0.attention.isActionable }
    }

    public var waiting: [PullRequest] {
        filter { !$0.attention.isActionable }
    }
}

public enum Elapsed {
    public static func short(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }
        return "\(hours / 24)d"
    }
}
