//
//  ChatViewController.swift
//  Stark
//

import Cocoa

class ChatViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    // Simple message model
    struct Message {
        let contactNumber: String
        let fromSelf: Bool
        let body: String
        let timestamp: Date
    }

    // MARK: - UI elements

    let qrImageView = NSImageView()
    let statusLabel = NSTextField(labelWithString: "Waiting for Signal daemon…")

    // Conversation table
    let messagesTableView = NSTableView()
    let messagesScrollView = NSScrollView()

    // Debug log + controls
    let logTextView = NSTextView()
    let receiveButton = NSButton(title: "Receive messages", target: nil, action: nil)
    let listButton = NSButton(title: "List contacts (raw)", target: nil, action: nil)
    let recipientField = NSTextField(string: "")
    let messageField = NSTextField(string: "")
    let sendButton = NSButton(title: "Send message", target: nil, action: nil)

    // MARK: - State

    private var didRequestQR = false
    private var selectedContactNumber: String?
    private var messagesByContact: [String: [Message]] = [:]

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        print("ChatViewController.viewDidLoad")

        setupUI()

        // If already linked from previous run
        if let appDelegate = NSApp.delegate as? AppDelegate, appDelegate.isLinked {
            qrImageView.alphaValue = 0.0
            statusLabel.stringValue = "✅ Linked! Spark is now connected to your Signal account."
            appendLog("Already linked, skipping QR.")
            didRequestQR = true
            messagesScrollView.isHidden = false
        }

        // Daemon ready
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(daemonReady),
            name: .signalDaemonReady,
            object: nil
        )

        // Link completed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(linkCompleted),
            name: .signalLinked,
            object: nil
        )

        // Fallback if we somehow miss the ready notification
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            print("ChatViewController: fallback trigger for QR")
            self?.daemonReady()
        }
    }

    // MARK: - UI setup

    private func setupUI() {
        // QR view (for initial linking)
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(qrImageView)
        qrImageView.translatesAutoresizingMaskIntoConstraints = false

        // Status label
        statusLabel.font = NSFont.systemFont(ofSize: 16)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Conversation table
        let msgColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MessageColumn"))
        msgColumn.title = "Conversation"
        messagesTableView.addTableColumn(msgColumn)
        messagesTableView.headerView = nil
        messagesTableView.rowHeight = 44
        messagesTableView.delegate = self
        messagesTableView.dataSource = self

        messagesScrollView.documentView = messagesTableView
        messagesScrollView.hasVerticalScroller = true
        messagesScrollView.borderType = .bezelBorder
        messagesScrollView.isHidden = true  // hidden until linked
        view.addSubview(messagesScrollView)
        messagesScrollView.translatesAutoresizingMaskIntoConstraints = false

        // Debug log
        let logScrollView = NSScrollView()
        logScrollView.borderType = .bezelBorder
        logScrollView.hasVerticalScroller = true
        logScrollView.documentView = logTextView
        logTextView.isEditable = false
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.addSubview(logScrollView)
        logScrollView.translatesAutoresizingMaskIntoConstraints = false

        // Controls
        recipientField.placeholderString = "Recipient (e.g. +4475...)"
        messageField.placeholderString = "Message"
        receiveButton.target = self
        receiveButton.action = #selector(receiveTapped)
        listButton.target = self
        listButton.action = #selector(listTapped)
        sendButton.target = self
        sendButton.action = #selector(sendTapped)

        let buttonsStack = NSStackView(views: [receiveButton, listButton])
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.alignment = .centerY
        view.addSubview(buttonsStack)
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false

        let sendStack = NSStackView(views: [recipientField, messageField, sendButton])
        sendStack.orientation = .horizontal
        sendStack.spacing = 8
        sendStack.alignment = .centerY
        view.addSubview(sendStack)
        sendStack.translatesAutoresizingMaskIntoConstraints = false

        // Layout
        NSLayoutConstraint.activate([
            // Status
            statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 500),

            // QR in the middle (for first-time linking)
            qrImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qrImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            qrImageView.widthAnchor.constraint(equalToConstant: 260),
            qrImageView.heightAnchor.constraint(equalToConstant: 260),

            // Conversation view
            messagesScrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            messagesScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            messagesScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            messagesScrollView.bottomAnchor.constraint(equalTo: sendStack.topAnchor, constant: -8),

            // Controls (send + receive/list)
            sendStack.leadingAnchor.constraint(equalTo: messagesScrollView.leadingAnchor),
            sendStack.trailingAnchor.constraint(equalTo: messagesScrollView.trailingAnchor),
            sendStack.bottomAnchor.constraint(equalTo: buttonsStack.topAnchor, constant: -8),

            recipientField.widthAnchor.constraint(equalToConstant: 180),
            messageField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            buttonsStack.leadingAnchor.constraint(equalTo: messagesScrollView.leadingAnchor),
            buttonsStack.bottomAnchor.constraint(equalTo: logScrollView.topAnchor, constant: -8),

            // Log at the bottom
            logScrollView.leadingAnchor.constraint(equalTo: messagesScrollView.leadingAnchor),
            logScrollView.trailingAnchor.constraint(equalTo: messagesScrollView.trailingAnchor),
            logScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            logScrollView.heightAnchor.constraint(equalToConstant: 130)
        ])

        statusLabel.stringValue = "Scan with your phone to link Spark"
    }

    private func setStatus(_ text: String) {
        print("Status: \(text)")
        statusLabel.stringValue = text
    }

    private func appendLog(_ text: String) {
        let current = logTextView.string
        let newText = current.isEmpty ? text : current + "\n" + text
        logTextView.string = newText
        logTextView.scrollToEndOfDocument(nil)
        print("LOG: \(text)")
    }

    // MARK: - QR / Linking

    @objc private func daemonReady() {
        guard !didRequestQR else { return }

        if let appDelegate = NSApp.delegate as? AppDelegate, appDelegate.isLinked {
            // Already linked; skip QR
            qrImageView.alphaValue = 0.0
            messagesScrollView.isHidden = false
            didRequestQR = true
            setStatus("✅ Linked! Spark is now connected to your Signal account.")
            return
        }

        didRequestQR = true
        print("ChatViewController.daemonReady received – fetching QR")
        fetchAndShowQRCode()
    }

    @objc private func fetchAndShowQRCode() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            print("ERROR: Could not get AppDelegate")
            return
        }

        setStatus("Requesting link from Signal…")

        appDelegate.generateProvisioningQRCode { [weak self] image in
            guard let self = self else { return }

            if let image = image {
                print("ChatViewController: got QR image")
                self.qrImageView.image = image
                self.setStatus("Scan with your phone to link Spark")
            } else {
                print("ChatViewController: no QR image returned")
                if let appDelegate = NSApp.delegate as? AppDelegate, appDelegate.isLinked {
                    self.qrImageView.alphaValue = 0.0
                    self.messagesScrollView.isHidden = false
                    self.setStatus("✅ Linked! Spark is now connected to your Signal account.")
                } else {
                    self.setStatus("Failed to get QR code. Check the log output.")
                    self.didRequestQR = false
                }
            }
        }
    }

    @objc private func linkCompleted() {
        print("ChatViewController.linkCompleted – link successful")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.qrImageView.animator().alphaValue = 0.0
        }

        messagesScrollView.isHidden = false
        setStatus("✅ Linked! Spark is now connected to your Signal account.")
        appendLog("Linked successfully as a Signal device.")
    }

    // MARK: - CLI Actions

    @objc private func receiveTapped() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appendLog("== Receive messages ==")

        appDelegate.receiveMessagesOnce(timeoutSeconds: 10) { [weak self] stdout, stderr in
            guard let self = self else { return }

            if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.appendLog(stdout)
                self.parseAndStoreMessages(from: stdout)
            } else {
                self.appendLog("(no messages)")
            }

            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.appendLog("stderr: \(stderr)")
            }

            self.updateConversationView()
        }
    }

    @objc private func listTapped() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appendLog("== Raw listContacts output ==")

        appDelegate.listConversations { [weak self] stdout, stderr in
            guard let self = self else { return }

            if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.appendLog(stdout)
            } else {
                self.appendLog("(no contacts)")
            }
            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.appendLog("stderr: \(stderr)")
            }
        }
    }

    @objc private func sendTapped() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        let recipient = recipientField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        appendLog("== Send message to \(recipient) ==")

        appDelegate.sendMessage(to: recipient, message: message) { [weak self] success, error in
            guard let self = self else { return }

            if success {
                self.appendLog("Message sent ✅")
                self.messageField.stringValue = ""

                // Locally append as outgoing
                let msg = Message(
                    contactNumber: recipient,
                    fromSelf: true,
                    body: message,
                    timestamp: Date()
                )
                var arr = self.messagesByContact[recipient] ?? []
                arr.append(msg)
                self.messagesByContact[recipient] = arr

                // If no conversation selected yet, select this one
                if self.selectedContactNumber == nil {
                    self.selectedContactNumber = recipient
                }

                self.updateConversationView()
            } else {
                self.appendLog("Send failed: \(error ?? "unknown error")")
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Message parsing

    private func parseAndStoreMessages(from text: String) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let myNumber = appDelegate.signalAccount

        var currentSender: String?
        var currentRecipient: String?
        var inSyncSentBlock = false

        func resetBlock() {
            currentSender = nil
            currentRecipient = nil
            inSyncSentBlock = false
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("Envelope from:") {
                // Example: Envelope from: “Name” +4475... (device: 1) to +4475...
                let tokens = line.components(separatedBy: " ")
                let numbers = tokens.filter { $0.hasPrefix("+") }
                if numbers.count >= 1 {
                    currentSender = numbers[0]
                }
                if numbers.count >= 2 {
                    currentRecipient = numbers[1]
                }
            } else if trimmed.contains("Received sync sent message") {
                inSyncSentBlock = true
            } else if trimmed.hasPrefix("To:") {
                // e.g. "To: “Name” +4475..."
                let tokens = trimmed.components(separatedBy: " ")
                if let num = tokens.last, num.hasPrefix("+") {
                    currentRecipient = num
                }
            } else if trimmed.hasPrefix("Body:") {
                let bodyPart = trimmed.components(separatedBy: "Body:").last ?? ""
                let body = bodyPart.trimmingCharacters(in: .whitespaces)

                var contact = currentSender ?? currentRecipient ?? myNumber
                var fromSelf = false

                if inSyncSentBlock {
                    fromSelf = true
                    if let rec = currentRecipient, rec != myNumber {
                        contact = rec
                    }
                } else {
                    fromSelf = (currentSender == myNumber)
                    if let snd = currentSender, snd != myNumber {
                        contact = snd
                    }
                }

                let msg = Message(
                    contactNumber: contact,
                    fromSelf: fromSelf,
                    body: body,
                    timestamp: Date()
                )
                var arr = messagesByContact[contact] ?? []
                arr.append(msg)
                messagesByContact[contact] = arr

                // If nothing selected yet, auto-focus this conversation
                if selectedContactNumber == nil {
                    selectedContactNumber = contact
                }

                print("Parsed message for \(contact): \(fromSelf ? "[self]" : "[them]") \(body)")
            } else if line.isEmpty {
                resetBlock()
            }
        }
    }

    private func updateConversationView() {
        messagesTableView.reloadData()
    }

    private func messagesForCurrentSelection() -> [Message] {
        // If no contact selected, show all messages (grouped, but flattened)
        if selectedContactNumber == nil {
            return messagesByContact.values.flatMap { $0 }.sorted { $0.timestamp < $1.timestamp }
        }
        return messagesByContact[selectedContactNumber!] ?? []
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return messagesForCurrentSelection().count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let msgs = messagesForCurrentSelection()
        guard row >= 0 && row < msgs.count else { return nil }
        let msg = msgs[row]

        let identifier = NSUserInterfaceItemIdentifier("MessageCell")
        let cell: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byWordWrapping
            textField.maximumNumberOfLines = 0
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4)
            ])
        }

        let prefix = msg.fromSelf ? "You: " : "Them: "
        cell.textField?.stringValue = prefix + msg.body

        return cell
    }
}

// MARK: - SidebarSelectionDelegate

extension ChatViewController: SidebarSelectionDelegate {
    func sidebar(didSelectConversation conversation: String) {
        // Very simple parsing: try to extract a phone number from the line
        // e.g. "Some Chat (+4475...)" or just "+4475..."
        let parts = conversation.split(separator: " ")
        let maybeNumber = parts.first(where: { $0.hasPrefix("+") })

        let contactNumber = maybeNumber.map(String.init) ?? conversation

        selectedContactNumber = contactNumber
        recipientField.stringValue = contactNumber
        appendLog("Selected conversation: \(conversation)")
        updateConversationView()
    }
}

