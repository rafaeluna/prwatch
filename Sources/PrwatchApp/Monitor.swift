import AppKit
import Observation
import PrwatchCore

/// Asks GitHub every two minutes off the main thread and publishes the result. It also asks when the
/// Mac wakes, and when you bring the panel back after a while.
@MainActor
@Observable
final class Monitor {
    private(set) var pullRequests: [PullRequest] = []
    /// Ticks twice a minute so the ages count up between fetches.
    private(set) var now = Date()
    private(set) var lastUpdated: Date?
    /// Why the last fetch failed. The list keeps what the last good one returned.
    private(set) var problem: String?
    private(set) var isFetching = false
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private let client = GitHubClient()
    @ObservationIgnored private let queue = DispatchQueue(label: "prwatch.fetch", qos: .utility)
    @ObservationIgnored private var timers: [Timer] = []

    private static let fetchInterval: TimeInterval = 120
    private static let staleAfter: TimeInterval = 20

    func start() {
        refresh()
        schedule(every: Self.fetchInterval) { $0.refresh() }
        schedule(every: 30) { $0.now = .now }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refreshNow() {
        publish(Result { try client.fetchPullRequests() })
    }

    func refresh() {
        guard !isFetching else { return }
        isFetching = true
        let client = client
        queue.async {
            let result = Result { try client.fetchPullRequests() }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.isFetching = false
                    self.publish(result)
                }
            }
        }
    }

    /// For when the panel comes back into view: fetch unless the list is fresh anyway.
    func refreshIfStale() {
        if let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < Self.staleAfter { return }
        refresh()
    }

    private func publish(_ result: Result<[PullRequest], Error>) {
        now = .now
        switch result {
        case .success(let pullRequests):
            if pullRequests != self.pullRequests {
                self.pullRequests = pullRequests
            }
            lastUpdated = now
            problem = nil
        case .failure(let error):
            problem = (error as? GitHubClient.Failure)?.message ?? error.localizedDescription
        }
        onUpdate?()
    }

    private func schedule(every interval: TimeInterval, _ action: @escaping @MainActor (Monitor) -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }
}
