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
        
        // Prioritize our custom Slaynode icon!
        // Try to load the original icon for menu bar
        if let path = Bundle.main.path(forResource: "icon-iOS-Default-1024x1024@1x", ofType: "png"),
           let originalIcon = NSImage(contentsOfFile: path) {
            // Resize for menu bar
            let resizedImage = NSImage(size: NSSize(width: 22, height: 22))
            resizedImage.lockFocus()
            originalIcon.draw(in: NSRect(x: 0, y: 0, width: 22, height: 22))
            resizedImage.unlockFocus()
            button.image = resizedImage
            button.image?.isTemplate = false  // Preserve our green colors!
            print("✅ Loaded Slaynode icon for menu bar")
        } else if let path = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
                  let menuBarIcon = NSImage(contentsOfFile: path) {
            button.image = menuBarIcon
            button.image?.isTemplate = false  // Preserve colors
            print("✅ Loaded MenuBarIcon")
        } else {
            // Only use SF Symbol as last resort
            button.image = NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: "SlayNode")
            button.image?.isTemplate = true
            print("⚠️ Using fallback SF Symbol")
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(preferences: preferences))
    }
}
