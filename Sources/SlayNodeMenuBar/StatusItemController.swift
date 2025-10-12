import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let preferences: PreferencesStore
    
    init(preferences: PreferencesStore) {
        self.preferences = preferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
    }
    
    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Ensure content is created before showing
            ensurePopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageOnly
        button.toolTip = "Slaynode"
        button.appearsDisabled = false
        button.isBordered = false
        button.focusRingType = .none
        // Try sword-like or kill-related SF symbols
        if let symbol = NSImage(systemSymbolName: "staroflife.fill", accessibilityDescription: "Slaynode") {
            symbol.size = NSSize(width: 20, height: 20)
            symbol.isTemplate = true
            button.image = symbol
        } else if let symbol = NSImage(systemSymbolName: "cross.fill", accessibilityDescription: "Slaynode") {
            symbol.size = NSSize(width: 20, height: 20)
            symbol.isTemplate = true
            button.image = symbol
        } else if let symbol = NSImage(systemSymbolName: "xmark.shield.fill", accessibilityDescription: "Slaynode") {
            symbol.size = NSSize(width: 20, height: 20)
            symbol.isTemplate = true
            button.image = symbol
        } else if let symbol = NSImage(systemSymbolName: "poweroff", accessibilityDescription: "Slaynode") {
            symbol.size = NSSize(width: 20, height: 20)
            symbol.isTemplate = true
            button.image = symbol
        } else if let symbol = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Slaynode") {
            symbol.size = NSSize(width: 20, height: 20)
            symbol.isTemplate = true
            button.image = symbol
        } else {
            // Fallback: Use the working X symbol
            if let symbol = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Slaynode") {
                symbol.size = NSSize(width: 20, height: 20)
                symbol.isTemplate = true
                button.image = symbol
            } else {
                button.title = "S"
            }
        }
    }
    
    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 700)
        // Defer view creation until popover is shown
    }

    private func ensurePopoverContent() {
        if popover.contentViewController == nil {
            // Create a simplified MenuContentView with minimal MenuViewModel
            let contentView = MenuContentView(preferences: preferences)
            popover.contentViewController = NSHostingController(rootView: contentView)
        }
    }
}
