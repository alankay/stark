//
//  SidebarSelectionDelegate.swift
//  Stark
//

import Foundation

protocol SidebarSelectionDelegate: AnyObject {
    /// Called when the user selects a conversation in the sidebar.
    func sidebar(didSelectConversation conversation: String)
}
