import SwiftUI
import AVFoundation

/// Camera view that reports the first QR code it sees.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ vc: ScannerVC, context: Context) {}
}

final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { if ok { self.setup() } }
        }
    }

    private func setup() {
        guard let dev = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else { return }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer

        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { if s.isRunning { s.stopRunning() } }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !done,
              let s = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(s)
    }
}

/// Full-screen scan sheet with a viewfinder frame.
struct ScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Return nil on success, or an error message to show.
    let onScan: (String) -> String?
    @State private var error = ""

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { code in
                    if let e = onScan(code) {
                        error = e
                    } else {
                        dismiss()
                    }
                }
                .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 4)
                    .frame(width: 260, height: 260)

                VStack {
                    Spacer()
                    Text(error.isEmpty ? "Run pair.bat on your PC and point at the QR" : error)
                        .font(.callout)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("Scan to pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
