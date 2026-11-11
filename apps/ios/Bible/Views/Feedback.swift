import MessageUI
import SwiftUI
import UIKit

/// Settings → About → Send feedback: an email to the developer, written in Apple's own mail screen
/// and sent from the reader's own Mail. The app itself sends nothing and opens no connection, so
/// "never goes online" stays true. App Review guideline 1.5 asks for an easy way to make contact
/// from inside the app as well as from the support page; this is it, and it is the only one.
enum Feedback {
    static let address = "support@lamplens.app"
    static let subject = "Lamplens feedback"

    /// The message the reader starts from: room to write at the top, then, under a rule, the three
    /// facts that answer "which build is this?" without a reply having to ask. The reader sees all
    /// of it before sending and can delete any of it.
    static var body: String {
        let device = UIDevice.current
        return "\n\n\n———\nLamplens \(SettingsView.version)\n\(model) · \(device.systemName) \(device.systemVersion)"
    }

    /// Apple's own identifier for the model, such as "iPhone16,1". A marketing name ("iPhone 15 Pro")
    /// would need a table that goes stale with every new phone; the identifier never does.
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// False when this phone has no Mail account set up: then the row offers the address to copy.
    static var canCompose: Bool { MFMailComposeViewController.canSendMail() }
}

/// Apple's mail screen, addressed and filled in. Sending, saving a draft or cancelling all close it.
struct FeedbackMail: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients([Feedback.address])
        mail.setSubject(Feedback.subject)
        mail.setMessageBody(Feedback.body, isHTML: false)
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var isPresented: Bool

        init(isPresented: Binding<Bool>) { _isPresented = isPresented }

        func mailComposeController(
            _ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            isPresented = false
        }
    }
}
