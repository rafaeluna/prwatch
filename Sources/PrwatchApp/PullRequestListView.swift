import AppKit
import PrwatchCore
import SwiftUI

struct PullRequestListView: View {
    let monitor: Monitor
    let settings: AppSettings
    let openSettings: () -> Void
    let minimize: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            PullRequestListContent(
                pullRequests: monitor.pullRequests,
                now: monitor.now,
                lastUpdated: monitor.lastUpdated,
                problem: monitor.problem,
                isFetching: monitor.isFetching,
                onRefresh: monitor.refresh,
                onOpenSettings: openSettings,
                onMinimize: minimize
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onContentHeightChange($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.never)
        .environment(\.listStyle, settings.listStyle)
    }
}

struct PullRequestListContent: View {
    let pullRequests: [PullRequest]
    let now: Date
    let lastUpdated: Date?
    let problem: String?
    let isFetching: Bool
    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onMinimize: () -> Void = {}
    @Environment(\.listStyle) private var style

    /// Yours with comments, the reviews you owe, your approved ones, then the ones waiting on others,
    /// with a line between groups. Each group arrives oldest first.
    private var groups: [[PullRequest]] {
        let kinds: [PullRequest.Attention] = [.comments, .review, .approved]
        return (kinds.map { kind in pullRequests.filter { $0.attention == kind } } + [pullRequests.waiting]).filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Header(pullRequests: pullRequests, isFetching: isFetching, onRefresh: onRefresh, onOpenSettings: onOpenSettings, onMinimize: onMinimize)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(style.font(11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            if let emptyMessage {
                Text(emptyMessage)
                    .font(style.font(12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 || emptyMessage != nil {
                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
                ForEach(group) { pullRequest in
                    PullRequestRow(pullRequest: pullRequest, now: now)
                }
            }
            Divider()
                .padding(.horizontal, 8)
                .padding(.top, 4)
            Footer(now: now, lastUpdated: lastUpdated, isEmpty: pullRequests.isEmpty)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyMessage: String? {
        if lastUpdated == nil {
            return problem == nil ? "Asking GitHub…" : nil
        }
        if pullRequests.isEmpty {
            return "No open pull requests"
        }
        return pullRequests.actionable.isEmpty ? "Nothing is waiting on you" : nil
    }
}

private struct Header: View {
    let pullRequests: [PullRequest]
    let isFetching: Bool
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onMinimize: () -> Void
    @Environment(\.listStyle) private var style

    var body: some View {
        let withComments = pullRequests.count(.comments)
        let toReview = pullRequests.count(.review)
        let approved = pullRequests.count(.approved)
        HStack(spacing: 10) {
            Text("PRs")
                .font(style.font(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if withComments > 0 {
                Count(number: withComments, label: "to answer", color: .orange)
            }
            if toReview > 0 {
                Count(number: toReview, label: "to review", color: .blue)
            }
            if approved > 0 {
                Count(number: approved, label: "approved", color: .green)
            }
            HeaderButton(symbol: "arrow.clockwise", help: "Ask GitHub now", action: onRefresh)
                .opacity(isFetching ? 0.35 : 1)
            HeaderButton(symbol: "minus", help: "Minimize to the Dock", action: onMinimize)
            HeaderButton(symbol: "gearshape", help: "Settings", action: onOpenSettings)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WindowDragArea())
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.listStyle) private var style

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(style.font(11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: style.scaled(14), height: style.scaled(14))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// How fresh the list is, and a reminder of what clicking does.
private struct Footer: View {
    let now: Date
    let lastUpdated: Date?
    let isEmpty: Bool
    @Environment(\.listStyle) private var style

    var body: some View {
        HStack(spacing: 8) {
            Text(freshness)
            Spacer(minLength: 8)
            Text(isEmpty ? "Checks every two minutes" : "Click to open on GitHub")
        }
        .font(style.font(10))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowDragArea())
    }

    private var freshness: String {
        guard let lastUpdated else { return "Not updated yet" }
        let age = now.timeIntervalSince(lastUpdated)
        return age < 60 ? "Updated just now" : "Updated \(Elapsed.short(age)) ago"
    }
}

private struct Count: View {
    let number: Int
    let label: String
    let color: Color
    @Environment(\.listStyle) private var style

    var body: some View {
        Text("\(Text("\(number)").foregroundStyle(color).bold()) \(label)")
            .font(style.font(11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

private struct PullRequestRow: View {
    let pullRequest: PullRequest
    let now: Date
    @State private var isHovered = false
    @Environment(\.listStyle) private var style

    private static let commentsShown = 3

    /// Pull requests waiting on you get the full row; the rest shrink to a faded line until it's your move.
    var body: some View {
        let isActionable = pullRequest.attention.isActionable
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                StateDot(attention: pullRequest.attention)
                Text(pullRequest.shortTitle)
                    .font(style.font(isActionable ? 13 : 12, weight: isActionable ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(stateLabel)
                    .font(style.font(11))
                    .monospacedDigit()
                    .foregroundStyle(pullRequest.attention == .approved ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if isActionable {
                VStack(alignment: .leading, spacing: 2) {
                    PlaceLabel(pullRequest: pullRequest)
                    if pullRequest.attention == .review {
                        ReviewLine(pullRequest: pullRequest)
                    }
                    ForEach(pullRequest.comments.prefix(Self.commentsShown)) { comment in
                        CommentRow(comment: comment)
                    }
                    if pullRequest.comments.count > Self.commentsShown {
                        Text("and \(pullRequest.comments.count - Self.commentsShown) more")
                            .font(style.font(11))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, style.scaled(14))
                    }
                }
                .padding(.leading, style.scaled(15))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isActionable ? 6 : 3)
        .background(.white.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 9, style: .continuous))
        .opacity(isActionable || isHovered ? 1 : 0.45)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture { NSWorkspace.shared.open(pullRequest.urlToOpen) }
        .contextMenu {
            Button("Open Conversation", systemImage: "bubble.left.and.bubble.right") { NSWorkspace.shared.open(pullRequest.url) }
            Button("Open Changes", systemImage: "plusminus") { NSWorkspace.shared.open(pullRequest.url.appending(path: "files")) }
            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pullRequest.url.absoluteString, forType: .string)
            }
        }
        .help("\(pullRequest.title)\n\(pullRequest.url.absoluteString)")
    }

    /// The dot's color already says comments or review, so those rows only show how long it has waited.
    private var stateLabel: String {
        let elapsed = Elapsed.short(now.timeIntervalSince(pullRequest.since))
        return switch pullRequest.attention {
        case .comments, .review: elapsed
        case .approved: "approved"
        case .waiting: pullRequest.attention.label(elapsed: elapsed)
        }
    }
}

private struct StateDot: View {
    let attention: PullRequest.Attention
    @Environment(\.listStyle) private var style

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: style.scaled(7)))
            .foregroundStyle(color)
            .symbolEffect(.pulse, options: .repeating, isActive: attention == .comments)
            .frame(width: style.scaled(7))
    }

    private var color: Color {
        switch attention {
        case .comments: .orange
        case .review: .blue
        case .approved: .green
        case .waiting: .gray
        }
    }
}

private struct PlaceLabel: View {
    let pullRequest: PullRequest
    @Environment(\.listStyle) private var style

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.pull")
                .font(style.font(9))
            Text("\(pullRequest.repository) #\(String(pullRequest.number))")
                .lineLimit(1)
        }
        .font(style.font(11))
        .foregroundStyle(.tertiary)
    }
}

/// Who is asking and how much there is to read.
private struct ReviewLine: View {
    let pullRequest: PullRequest
    @Environment(\.listStyle) private var style

    var body: some View {
        Text("\(Text(pullRequest.author).fontWeight(.semibold)) \(details)")
            .font(style.font(11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var details: String {
        var parts: [String] = []
        if let size = pullRequest.size {
            parts.append("\(size.text) in \(size.files) \(size.files == 1 ? "file" : "files")")
        }
        if pullRequest.isDraft {
            parts.append("draft")
        }
        if let team = pullRequest.requestedTeam {
            parts.append("asked \(team)")
        }
        return parts.joined(separator: ", ")
    }
}

/// One comment waiting on you. Clicking it opens that comment, not just the pull request.
private struct CommentRow: View {
    let comment: Comment
    @State private var isHovered = false
    @Environment(\.listStyle) private var style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "arrow.turn.down.right")
                .font(style.font(9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("\(Text(comment.author).fontWeight(.semibold)) \(comment.text)")
                .font(style.font(11))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture { NSWorkspace.shared.open(comment.url) }
        .help(comment.text)
    }
}

/// The panel has no title bar, so the header and footer move it.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
