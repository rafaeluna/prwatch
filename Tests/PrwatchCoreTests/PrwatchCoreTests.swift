import Foundation
import Testing
@testable import PrwatchCore

private let person = #"{"login":"sam","__typename":"User"}"#
private let me = #"{"login":"me","__typename":"User"}"#

/// One of your own pull requests, as GitHub returns it. The last push is at 12:00 on the 10th.
private func mine(
    number: Int = 1,
    isDraft: Bool = false,
    reviewDecision: String = "null",
    checks: String = "SUCCESS",
    mergeable: String = "MERGEABLE",
    reviews: [String] = [],
    comments: [String] = [],
    threads: [String] = []
) -> String {
    """
    {"number":\(number),"title":"Mine \(number)","url":"https://github.com/org/repo/pull/\(number)","isDraft":\(isDraft),
     "createdAt":"2026-11-01T00:00:00Z","reviewDecision":\(reviewDecision),"mergeable":"\(mergeable)",
     "repository":{"name":"repo"},"author":\(me),
     "commits":{"nodes":[{"commit":{"committedDate":"2026-11-10T12:00:00Z","statusCheckRollup":{"state":"\(checks)"}}}]},
     "latestReviews":{"nodes":[\(reviews.joined(separator: ","))]},
     "comments":{"nodes":[\(comments.joined(separator: ","))]},
     "reviewThreads":{"nodes":[\(threads.joined(separator: ","))]}}
    """
}

private func remark(by author: String = person, at date: String, _ text: String = "Please rename this") -> String {
    #"{"author":\#(author),"createdAt":"\#(date)","bodyText":"\#(text)","url":"https://github.com/org/repo/pull/1#c-\#(date)"}"#
}

private func thread(isResolved: Bool = false, lastCommentBy author: String = person, at date: String = "2026-11-09T00:00:00Z") -> String {
    #"{"isResolved":\#(isResolved),"comments":{"nodes":[\#(remark(by: author, at: date))]}}"#
}

private func review(state: String, at date: String, _ text: String = "") -> String {
    #"{"author":\#(person),"state":"\#(state)","submittedAt":"\#(date)","bodyText":"\#(text)","url":"https://github.com/org/repo/pull/1#r-\#(date)"}"#
}

private func reviewRequest(number: Int, createdAt: String, requests: [(reviewer: String, at: String)]) -> String {
    let reviewers = requests.map { #"{"requestedReviewer":\#($0.reviewer)}"# }
    let events = requests.map { #"{"createdAt":"\#($0.at)","requestedReviewer":\#($0.reviewer)}"# }
    return """
    {"number":\(number),"title":"Theirs \(number)","url":"https://github.com/org/repo/pull/\(number)","isDraft":false,
     "createdAt":"\(createdAt)","additions":120,"deletions":30,"changedFiles":5,
     "repository":{"name":"repo"},"author":\(person),
     "reviewRequests":{"nodes":[\(reviewers.joined(separator: ","))]},
     "timelineItems":{"nodes":[\(events.joined(separator: ","))]}}
    """
}

private func pullRequests(mine: [String] = [], toReview: [String] = []) throws -> [PullRequest] {
    let json = """
    {"data":{"viewer":{"login":"me"},
     "mine":{"nodes":[\(mine.joined(separator: ","))]},
     "toReview":{"nodes":[\(toReview.joined(separator: ","))]}}}
    """
    return try GitHubResponse.pullRequests(from: Data(json.utf8))
}

private func date(_ text: String) -> Date {
    try! Date(text, strategy: .iso8601)
}

@Test func anOpenThreadWaitsOnYouUntilYouAnswerOrResolveIt() throws {
    let waiting = try pullRequests(mine: [mine(threads: [thread()])])
    let answered = try pullRequests(mine: [mine(threads: [thread(lastCommentBy: me)])])
    let resolved = try pullRequests(mine: [mine(threads: [thread(isResolved: true)])])

    #expect(waiting.first?.attention == .comments)
    #expect(waiting.first?.comments.map(\.text) == ["Please rename this"])
    #expect(answered.first?.attention == .waiting(.inReview))
    #expect(resolved.first?.attention == .waiting(.inReview))
}

@Test func aBotsThreadCountsButItsConversationCommentsDoNot() throws {
    let bot = #"{"login":"deploy-bot","__typename":"User"}"#
    let app = #"{"login":"cursor","__typename":"Bot"}"#

    let chatter = try pullRequests(mine: [mine(comments: [remark(by: bot, at: "2026-11-11T00:00:00Z"), remark(by: app, at: "2026-11-11T00:00:00Z")])])
    let finding = try pullRequests(mine: [mine(threads: [thread(lastCommentBy: app)])])

    #expect(chatter.first?.attention == .waiting(.inReview))
    #expect(finding.first?.comments.map(\.author) == ["cursor"])
}

@Test func aConversationCommentWaitsUntilYouPushOrReply() throws {
    let beforeYourPush = try pullRequests(mine: [mine(comments: [remark(at: "2026-11-10T08:00:00Z")])])
    let afterYourPush = try pullRequests(mine: [mine(comments: [remark(at: "2026-11-11T08:00:00Z")])])
    let youReplied = try pullRequests(mine: [mine(comments: [remark(at: "2026-11-11T08:00:00Z"), remark(by: me, at: "2026-11-11T09:00:00Z")])])

    #expect(beforeYourPush.first?.attention == .waiting(.inReview))
    #expect(afterYourPush.first?.attention == .comments)
    #expect(youReplied.first?.attention == .waiting(.inReview))
}

@Test func aReviewSummaryCountsAndRequestedChangesNeedNoSummary() throws {
    let reviews = [
        review(state: "COMMENTED", at: "2026-11-11T00:00:00Z", "Had a couple of questions\\nmore below"),
        review(state: "COMMENTED", at: "2026-11-11T01:00:00Z"),
        review(state: "CHANGES_REQUESTED", at: "2026-11-11T02:00:00Z"),
    ]

    let pullRequest = try #require(try pullRequests(mine: [mine(reviewDecision: #""CHANGES_REQUESTED""#, reviews: reviews)]).first)

    #expect(pullRequest.comments.map(\.text) == ["Had a couple of questions", "Requested changes"])
    #expect(pullRequest.since == date("2026-11-11T00:00:00Z"))
}

@Test func yoursWithNothingToAnswerSaysWhyItWaits() throws {
    let approval = review(state: "APPROVED", at: "2026-11-11T00:00:00Z", "Ship it")
    let all = try pullRequests(mine: [
        mine(number: 1, reviewDecision: #""APPROVED""#, reviews: [approval]),
        mine(number: 2, isDraft: true, checks: "FAILURE"),
        mine(number: 3, checks: "FAILURE"),
        mine(number: 4, mergeable: "CONFLICTING"),
        mine(number: 5, reviewDecision: #""REVIEW_REQUIRED""#),
    ])

    #expect(all.map(\.attention) == [.approved, .waiting(.draft), .waiting(.checksFailing), .waiting(.conflicts), .waiting(.inReview)])
    #expect(all.first?.since == date("2026-11-11T00:00:00Z"))
}

@Test func reviewsYouOweStartWithTheOldestRequest() throws {
    let team = #"{"__typename":"Team","name":"web"}"#
    let all = try pullRequests(toReview: [
        // Opened first, but you were only asked again yesterday.
        reviewRequest(number: 1, createdAt: "2026-11-01T00:00:00Z", requests: [(me, "2026-11-02T00:00:00Z"), (me, "2026-11-12T00:00:00Z")]),
        reviewRequest(number: 2, createdAt: "2026-11-05T00:00:00Z", requests: [(person, "2026-11-05T00:00:00Z"), (me, "2026-11-06T00:00:00Z")]),
        reviewRequest(number: 3, createdAt: "2026-11-08T00:00:00Z", requests: [(team, "2026-11-09T00:00:00Z")]),
    ])

    #expect(all.map(\.number) == [2, 3, 1])
    #expect(all.map(\.requestedTeam) == [nil, "web", nil])
    #expect(all.first?.size == Size(additions: 120, deletions: 30, files: 5))
    #expect(all.first?.urlToOpen.absoluteString == "https://github.com/org/repo/pull/2/files")
}

@Test func whatYouCanActOnComesFirst() throws {
    let all = try pullRequests(
        mine: [
            mine(number: 1),
            mine(number: 2, reviewDecision: #""APPROVED""#),
            mine(number: 3, threads: [thread()]),
        ],
        toReview: [reviewRequest(number: 4, createdAt: "2026-11-01T00:00:00Z", requests: [(me, "2026-11-01T00:00:00Z")])]
    )

    #expect(all.map(\.number) == [3, 4, 2, 1])
    #expect(all.actionable.count == 3)
}

@Test func aRefusalFromGitHubIsReported() {
    let json = Data(#"{"errors":[{"message":"API rate limit exceeded"}]}"#.utf8)

    #expect(throws: GitHubResponse.Failure(message: "API rate limit exceeded")) {
        try GitHubResponse.pullRequests(from: json)
    }
}

@Test func titlesDropTheirBracketedTags() {
    func shortTitle(_ title: String) -> String {
        PullRequest(repository: "repo", number: 1, title: title, url: URL(string: "https://github.com")!, author: "me", attention: .review, since: .now).shortTitle
    }

    #expect(shortTitle("[WEB-12] [mid] Fix login") == "Fix login")
    #expect(shortTitle("[OPS-7] Rotate the logs [mid]") == "Rotate the logs")
    #expect(shortTitle("Fix items[0] lookup") == "Fix items[0] lookup")
    #expect(shortTitle("[wip]") == "[wip]")
}

@Test func agesStayShort() {
    #expect(Elapsed.short(42) == "42s")
    #expect(Elapsed.short(3720) == "1h")
    #expect(Elapsed.short(2 * 86400) == "2d")
}
