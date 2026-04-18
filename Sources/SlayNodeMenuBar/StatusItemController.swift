import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let preferences: PreferencesStore
    private let monitor: any ProcessMonitoring
    
    init(preferences: PreferencesStore, monitor: any ProcessMonitoring) {
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
        button.toolTip = "SlayNode"
        button.setAccessibilityLabel("SlayNode")
        button.appearsDisabled = false
        button.isBordered = false
        button.focusRingType = .none
        if let menuBarIcon = menuBarTemplateImage() {
            menuBarIcon.size = NSSize(width: 18, height: 18)
            menuBarIcon.isTemplate = true
            button.image = menuBarIcon
        } else if let fallbackSymbol = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "SlayNode") {
            fallbackSymbol.size = NSSize(width: 18, height: 18)
            fallbackSymbol.isTemplate = true
            button.image = fallbackSymbol
        } else {
            button.title = "S"
        }
    }
    
    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 700)
        popover.delegate = self
    }

    private func ensurePopoverContent() {
        if popover.contentViewController == nil {
            let contentView = MenuContentView(preferences: preferences, monitor: monitor)
            popover.contentViewController = NSHostingController(rootView: contentView)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    private func menuBarTemplateImage() -> NSImage? {
        if let directURL = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: directURL) {
            return image
        }

        if let imagesetURL = Bundle.module.url(
            forResource: "MenuBarIcon",
            withExtension: "png",
            subdirectory: "Assets.xcassets/MenuBarIcon.imageset"
        ), let image = NSImage(contentsOf: imagesetURL) {
            return image
        }

        return nil
    }
}
