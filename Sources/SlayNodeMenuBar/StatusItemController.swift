import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let preferences: PreferencesStore
    private let monitor: ProcessMonitor
    
    init(preferences: PreferencesStore, monitor: ProcessMonitor) {
        self.preferences = preferences
        self.monitor = monitor
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
        // Create content eagerly so ProcessMonitor starts immediately
        ensurePopoverContent()
    }

    private func ensurePopoverContent() {
        if popover.contentViewController == nil {
            let contentView = MenuContentView(preferences: preferences, monitor: monitor)
            popover.contentViewController = NSHostingController(rootView: contentView)
        }
    }
}
