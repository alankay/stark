//
//  SidebarViewController.swift
//  Stark
//

import Cocoa

class SidebarViewController: NSViewController {

    // MARK: - Public

    weak var selectionDelegate: SidebarSelectionDelegate?

    // Header
    let titleLabel = NSTextField(labelWithString: "Spark")
    let themeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    let refreshButton = NSButton(title: "Refresh chats", target: nil, action: nil)

    // Conversation list
    let scrollView = NSScrollView()
    let stackView = NSStackView()

    // Very simple “conversation” model: just the raw line for now
    private var conversations: [String] = []

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupHeader()
        setupConversationList()

        // Hook up refresh
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)

        // Load conversations once at startup
        refreshConversations()
    }

    // --------------------------------------------------------
    // MARK: - UI setup
    // --------------------------------------------------------

    private func setupHeader() {
        titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)

        // Theme menu
        let menu = NSMenu()
        ["System", "Light", "Dark"].forEach { title in
            let item = NSMenuItem(title: title, action: #selector(changeTheme(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        themeButton.menu = menu

        // Refresh button
        refreshButton.bezelStyle = .rounded

        // Header stack
        let headerStack = NSStackView(views: [titleLabel, NSView(), themeButton])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8

        view.addSubview(headerStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // Place refresh button under header
        view.addSubview(refreshButton)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            refreshButton.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            refreshButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
        ])
    }

    private func setupConversationList() {
        // Stack view inside scroll view
        stackView.orientation = .vertical
        stackView.spacing = 6
        stackView.alignment = .leading

        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }

    // --------------------------------------------------------
    // MARK: - Actions
    // --------------------------------------------------------

    @objc private func changeTheme(_ sender: NSMenuItem) {
        switch sender.title {
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }

    @objc private func refreshTapped() {
        refreshConversations()
    }

    // --------------------------------------------------------
    // MARK: - Data loading
    // --------------------------------------------------------

    private func refreshConversations() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            print("Sidebar: Could not get AppDelegate")
            return
        }

        print("Sidebar: refreshing conversations via listChats")

        appDelegate.listConversations { [weak self] stdout, stderr in
            guard let self = self else { return }

            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Sidebar listChats stderr:\n\(stderr)")
            }

            // Very simple parsing: each non-empty line = one "conversation"
            let lines = stdout
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            self.conversations = lines
            self.reloadConversationViews()
        }
    }

    private func reloadConversationViews() {
        // Remove old labels
        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        if conversations.isEmpty {
            let label = NSTextField(labelWithString: "No conversations yet.\nClick \"Receive messages\" or send a message to yourself.")
            label.font = NSFont.systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
            label.alignment = .left
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            stackView.addArrangedSubview(label)
            return
        }

        // Add one clickable label per conversation line
        for (index, line) in conversations.enumerated() {
            let button = NSButton(title: line, target: self, action: #selector(conversationTapped(_:)))
            button.tag = index
            button.setButtonType(.momentaryChange)
            button.bezelStyle = .inline
            button.isBordered = false
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 13)
            stackView.addArrangedSubview(button)
        }
    }

    @objc private func conversationTapped(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < conversations.count else { return }
        let convo = conversations[index]
        print("Sidebar: selected conversation: \(convo)")
        selectionDelegate?.sidebar(didSelectConversation: convo)
    }
}
