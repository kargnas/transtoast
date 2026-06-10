import Foundation
import UserNotifications

final class LocalModelWarmupNotifier {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func warmingUp(modelTitle: String) {
        deliver(
            title: "Warming up local model",
            body: "\(modelTitle) is loading. The previous local backend will finish or stop first."
        )
    }

    func completed(modelTitle: String) {
        deliver(
            title: "Local model ready",
            body: "\(modelTitle) finished warming up."
        )
    }

    func failed(modelTitle: String, error: Error) {
        deliver(
            title: "Local model warmup failed",
            body: "\(modelTitle): \(error.localizedDescription)"
        )
    }

    private func deliver(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: "transtoast.local-model-warmup.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
