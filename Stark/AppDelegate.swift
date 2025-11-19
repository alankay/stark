//
//  AppDelegate.swift
//  Stark
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var signalProcess: Process?
    var linkProcess: Process?

    // Persisted flag: have we already linked this installation?
    private let linkedFlagKey = "SparkSignalLinkedV6"
    var isLinked: Bool {
        get { UserDefaults.standard.bool(forKey: linkedFlagKey) }
        set { UserDefaults.standard.set(newValue, forKey: linkedFlagKey) }
    }

    // Your Signal account
    let signalAccount = "+447577347230"

    var socketURL: URL {
        return URL(fileURLWithPath: "/tmp/spark.sock")
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let windowSize = NSRect(x: 0, y: 0, width: 1200, height: 800)

        window = NSWindow(
            contentRect: windowSize,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Spark"
        window.makeKeyAndOrderFront(nil)

        let split = MainSplitViewController()
        window.contentViewController = split

        startSignalDaemon()

        // If we already linked before, tell the UI immediately
        if isLinked {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(name: .signalLinked, object: nil)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        signalProcess?.terminate()
        linkProcess?.terminate()
    }

    // ------------------------------------------------------------
    // MARK: - Start signal-cli daemon
    // ------------------------------------------------------------
    func startSignalDaemon() {
        guard let resourcesURL = Bundle.main.resourceURL else {
            print("ERROR: No resourceURL")
            return
        }

        let javaURL = resourcesURL
            .appendingPathComponent("jre")
            .appendingPathComponent("Contents")
            .appendingPathComponent("Home")
            .appendingPathComponent("bin")
            .appendingPathComponent("java")

        let classpath = resourcesURL
            .appendingPathComponent("signal-cli-0.13.20")
            .appendingPathComponent("lib")
            .path + "/*"

        print("=== STARTING SIGNAL-CLI DAEMON ===")
        print("java = \(javaURL.path)")
        print("classpath = \(classpath)")
        print("socket = \(socketURL.path)")

        let socketPath = socketURL.path
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        signalProcess = Process()
        signalProcess?.executableURL = javaURL
        signalProcess?.currentDirectoryURL = resourcesURL
        signalProcess?.arguments = [
            "-cp", classpath,
            "org.asamk.signal.Main",
            "daemon",
            "--socket", socketURL.path
        ]

        do {
            try signalProcess?.run()
            print("Daemon started OK")
        } catch {
            print("ERROR: Failed to start daemon: \(error)")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NotificationCenter.default.post(name: .signalDaemonReady, object: nil)
        }
    }

    // ------------------------------------------------------------
    // MARK: - QR provisioning via `signal-cli link`
    // ------------------------------------------------------------
    func generateProvisioningQRCode(completion: @escaping (NSImage?) -> Void) {
        // If we’re already linked, don’t try to link again
        if isLinked {
            print("generateProvisioningQRCode: already linked, skipping")
            completion(nil)
            return
        }
        if linkProcess != nil {
            print("generateProvisioningQRCode: link process already running")
            completion(nil)
            return
        }

        guard let resourcesURL = Bundle.main.resourceURL else {
            completion(nil)
            return
        }

        let javaURL = resourcesURL
            .appendingPathComponent("jre")
            .appendingPathComponent("Contents")
            .appendingPathComponent("Home")
            .appendingPathComponent("bin")
            .appendingPathComponent("java")

        let classpath = resourcesURL
            .appendingPathComponent("signal-cli-0.13.20")
            .appendingPathComponent("lib")
            .path + "/*"

        let process = Process()
        process.executableURL = javaURL
        process.currentDirectoryURL = resourcesURL
        process.arguments = [
            "-cp", classpath,
            "org.asamk.signal.Main",
            "link",
            "-n", "Spark"
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        var stdoutBuffer = Data()
        var stderrBuffer = Data()
        var qrProvided = false

        outHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            stdoutBuffer.append(chunk)

            guard let strongSelf = self else { return }
            guard let text = String(data: stdoutBuffer, encoding: .utf8) else { return }

            if let newlineRange = text.range(of: "\n") {
                let line = String(text[..<newlineRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)

                if !line.isEmpty, !qrProvided {
                    qrProvided = true
                    print("Provisioning URI: \(line)")

                    let image = strongSelf.makeQR(from: line)
                    DispatchQueue.main.async {
                        completion(image)
                    }

                    outHandle.readabilityHandler = nil
                }
            }
        }

        errHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            stderrBuffer.append(chunk)
            if let text = String(data: stderrBuffer, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("signal-cli link stderr (stream):\n\(text)")
            }
        }

        process.terminationHandler = { [weak self] proc in
            print("link process terminated with status \(proc.terminationStatus)")
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil

            DispatchQueue.main.async {
                if let text = String(data: stderrBuffer, encoding: .utf8),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("signal-cli link stderr (final):\n\(text)")
                }

                if proc.terminationStatus == 0 {
                    print("Link completed successfully, posting .signalLinked")
                    self?.isLinked = true
                    NotificationCenter.default.post(name: .signalLinked, object: nil)
                } else {
                    print("Link failed with status \(proc.terminationStatus)")
                }
            }

            self?.linkProcess = nil
        }

        do {
            try process.run()
            print("Started signal-cli link process (PID \(process.processIdentifier))")
            self.linkProcess = process
        } catch {
            print("ERROR: Could not start link process: \(error)")
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            DispatchQueue.main.async { completion(nil) }
        }
    }

    // ------------------------------------------------------------
    // MARK: - Generic CLI helper
    // ------------------------------------------------------------
    private func runSignalCommand(args: [String],
                                 completion: @escaping (_ stdout: String, _ stderr: String, _ exitCode: Int32) -> Void) {
        DispatchQueue.global().async {
            guard let resourcesURL = Bundle.main.resourceURL else {
                DispatchQueue.main.async { completion("", "No resourceURL", -1) }
                return
            }

            let javaURL = resourcesURL
                .appendingPathComponent("jre")
                .appendingPathComponent("Contents")
                .appendingPathComponent("Home")
                .appendingPathComponent("bin")
                .appendingPathComponent("java")

            let classpath = resourcesURL
                .appendingPathComponent("signal-cli-0.13.20")
                .appendingPathComponent("lib")
                .path + "/*"

            let process = Process()
            process.executableURL = javaURL
            process.currentDirectoryURL = resourcesURL
            process.arguments = [
                "-cp", classpath,
                "org.asamk.signal.Main"
            ] + args

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    completion("", "Failed to start signal-cli: \(error)", -1)
                }
                return
            }

            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            let outText = String(data: outData, encoding: .utf8) ?? ""
            let errText = String(data: errData, encoding: .utf8) ?? ""
            let code = process.terminationStatus

            DispatchQueue.main.async {
                completion(outText, errText, code)
            }
        }
    }

    // ------------------------------------------------------------
    // MARK: - Public helpers for UI
    // ------------------------------------------------------------

    func receiveMessagesOnce(timeoutSeconds: Int = 10,
                             completion: @escaping (_ output: String, _ error: String) -> Void) {
        runSignalCommand(
            args: ["-a", signalAccount, "receive", "-t", "\(timeoutSeconds)"]
        ) { stdout, stderr, code in
            print("receiveMessagesOnce exit code: \(code)")
            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("receive stderr:\n\(stderr)")
            }
            completion(stdout, stderr)
        }
    }

    func listConversations(completion: @escaping (_ output: String, _ error: String) -> Void) {
        runSignalCommand(
            args: ["-a", signalAccount, "listContacts"]
        ) { stdout, stderr, code in
            print("listConversations exit code: \(code)")
            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("listContacts stderr:\n\(stderr)")
            }
            completion(stdout, stderr)
        }
    }

    func sendMessage(to recipient: String,
                     message: String,
                     completion: @escaping (_ success: Bool, _ error: String?) -> Void) {
        guard !recipient.isEmpty, !message.isEmpty else {
            completion(false, "Recipient or message is empty")
            return
        }

        runSignalCommand(
            args: ["-a", signalAccount, "send", "-m", message, recipient]
        ) { stdout, stderr, code in
            print("sendMessage exit code: \(code)")
            if !stdout.isEmpty {
                print("send stdout:\n\(stdout)")
            }
            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("send stderr:\n\(stderr)")
            }
            completion(code == 0, code == 0 ? nil : stderr)
        }
    }

    // ------------------------------------------------------------
    // MARK: - QR Generator
    // ------------------------------------------------------------
    private func makeQR(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage?
                .transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else {
            return nil
        }

        let rep = NSCIImageRep(ciImage: ciImage)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

extension Notification.Name {
    static let signalDaemonReady = Notification.Name("signalDaemonReady")
    static let signalLinked      = Notification.Name("signalLinked")
}
