import SwiftUI
import QuickLook
import UIKit

/// SwiftUI wrapper around `QLPreviewController` — lets users view exported PNG/PDF/JSON
/// natively inside the app with built-in share, print, markup (PDF).
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIViewController {
        let nav = UINavigationController(rootViewController: PreviewController(url: url,
                                                                                onDone: { dismiss() }))
        nav.modalPresentationStyle = .fullScreen
        return nav
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class PreviewController: QLPreviewController, QLPreviewControllerDataSource {
    private let url: URL
    private let onDone: () -> Void

    init(url: URL, onDone: @escaping () -> Void) {
        self.url = url
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
        dataSource = self
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done)
        )
    }

    @objc private func done() { onDone() }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController,
                           previewItemAt index: Int) -> any QLPreviewItem {
        url as NSURL
    }
}
