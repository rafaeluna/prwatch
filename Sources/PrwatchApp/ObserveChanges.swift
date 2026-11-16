import Foundation
import Observation

/// Runs `apply` now and again whenever an observable value it read changes.
@MainActor
func observeChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { observeChanges(apply) }
        }
    }
}
