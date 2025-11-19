import Cocoa

class MainSplitViewController: NSSplitViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let sidebar = SidebarViewController()
        let chat = ChatViewController()
        
        // Let the sidebar tell the chat view which contact was selected
        sidebar.selectionDelegate = chat
        
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 240
        addSplitViewItem(sidebarItem)
        
        let chatItem = NSSplitViewItem(viewController: chat)
        chatItem.minimumThickness = 500
        addSplitViewItem(chatItem)
    }
}
