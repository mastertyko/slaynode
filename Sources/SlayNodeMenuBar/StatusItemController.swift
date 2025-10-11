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
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.size = NSSize(width: 22, height: 22)
            icon.isTemplate = true
            button.image = icon
        } else if let symbol = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "Slaynode") {
            symbol.size = NSSize(width: 20, height: 20)
            symbol.isTemplate = true
            button.image = symbol
        }
        button.image?.isTemplate = true
    }
    
    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 440)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(preferences: preferences))
    }
}
