import Foundation

/// Centralized constants for the SlayNode application.
/// All magic numbers, paths, and timeouts should be defined here.
enum Constants {
    
    // MARK: - Timeouts
    
    enum Timeout {
        /// Default interval for process monitoring (seconds)
        static let monitorInterval: TimeInterval = 5.0
        
        /// Maximum time to wait for process collection (seconds)
        static let collectionTimeout: TimeInterval = 10.0
        
        /// Timeout for lsof port resolution (seconds)
        static let lsofTimeout: TimeInterval = 2.0
        
        /// Timeout for individual shell commands (seconds)
        static let commandTimeout: TimeInterval = 5.0
        
        /// Grace period before SIGKILL (seconds)
        static let gracePeriod: TimeInterval = 1.5
        
        /// Grace period for child processes (half of parent's grace period)
        static let childGracePeriod: TimeInterval = 0.75
        
        /// Total timeout waiting for complete process shutdown (seconds)
        static let shutdownTimeout: TimeInterval = 10.0
        
        /// Polling interval for shutdown verification (nanoseconds)
        static let shutdownPollingInterval: UInt64 = 500_000_000 // 500ms
        
        /// Polling interval for process group termination (nanoseconds)
        static let terminationPollingInterval: UInt64 = 100_000_000 // 100ms
        
        /// Initial delay before first process scan (nanoseconds)
        static let initialScanDelay: UInt64 = 1_000_000_000 // 1 second
        
        /// Delay for visual feedback after process stop (nanoseconds)
        static let visualFeedbackDelay: UInt64 = 500_000_000 // 500ms
    }
    
    // MARK: - Paths
    
    enum Path {
        static let ps = "/bin/ps"
        static let lsof = "/usr/sbin/lsof"
        static let pgrep = "/usr/bin/pgrep"
    }
    
    // MARK: - Buffers & Limits
    
    enum Buffer {
        /// Maximum number of PIDs to allocate for process listing
        static let maxPidCount = 10_000
        
        /// Maximum output size from shell commands (bytes)
        static let maxOutputSize = 1_024 * 1_024 // 1MB
        
        /// Maximum expected process count for pre-allocation
        static let maxProcessCount = 2_000
        
        /// Maximum length for executable names
        static let maxExecutableNameLength = 256
        
        /// Valid port range
        static let validPortRange = 1...65535
    }
    
    // MARK: - UI Constants
    
    enum UI {
        /// Main panel corner radius
        static let panelCornerRadius: CGFloat = 24
        
        /// Header section corner radius
        static let headerCornerRadius: CGFloat = 18
        
        /// Process tile corner radius
        static let tileCornerRadius: CGFloat = 16
        
        /// Error banner corner radius
        static let bannerCornerRadius: CGFloat = 14
        
        /// Main panel padding
        static let panelPadding: CGFloat = 22
        
        /// Header horizontal padding
        static let headerHorizontalPadding: CGFloat = 18
        
        /// Header vertical padding
        static let headerVerticalPadding: CGFloat = 14
        
        /// Process tile padding
        static let tilePadding: CGFloat = 16
        
        /// Empty state padding
        static let emptyStatePadding: CGFloat = 24
        
        /// Main panel width
        static let panelWidth: CGFloat = 380
        
        /// Maximum scroll view height
        static let maxScrollHeight: CGFloat = 600
        
        /// Minimum content height
        static let minContentHeight: CGFloat = 300
        
        /// Button width for icon-only buttons
        static let iconButtonSize: CGFloat = 44
        
        /// Empty state icon size
        static let emptyStateIconSize: CGFloat = 42
        
        /// Countdown threshold for status text (seconds)
        static let countdownThreshold: TimeInterval = 5
        
        /// Recent update threshold (seconds)
        static let recentUpdateThreshold: TimeInterval = 30
    }
    
    // MARK: - Preferences
    
    enum Preferences {
        /// Valid range for refresh interval (seconds)
        static let refreshIntervalRange: ClosedRange<TimeInterval> = 2...30
        
        /// Default refresh interval (seconds)
        static let defaultRefreshInterval: TimeInterval = 5.0
        
        /// UserDefaults key for refresh interval
        static let refreshIntervalKey = "com.slaynode.preferences.refreshInterval"
    }
    
    // MARK: - Time Conversions
    
    enum Time {
        /// Seconds per minute
        static let secondsPerMinute: TimeInterval = 60
        
        /// Seconds per hour
        static let secondsPerHour: TimeInterval = 3600
        
        /// Seconds per day
        static let secondsPerDay: TimeInterval = 86400
        
        /// Nanoseconds per second
        static let nanosecondsPerSecond: UInt64 = 1_000_000_000
        
        /// Microseconds per second (for time calculations)
        static let microsecondsPerSecond: TimeInterval = 1_000_000
    }
    
    // MARK: - Opacity Values
    
    enum Opacity {
        /// Primary text opacity
        static let primaryText: Double = 0.92
        
        /// Secondary text opacity (improved for accessibility)
        static let secondaryText: Double = 0.85
        
        /// Tertiary text opacity
        static let tertiaryText: Double = 0.78
        
        /// Subtle border opacity
        static let subtleBorder: Double = 0.25
        
        /// Very subtle border opacity
        static let verySubtleBorder: Double = 0.14
        
        /// Divider overlay opacity
        static let dividerOverlay: Double = 0.08
        
        /// Category badge background opacity
        static let badgeBackground: Double = 0.15
        
        /// Info chip background opacity
        static let chipBackground: Double = 0.06
    }
    
    // MARK: - Animation
    
    enum Animation {
        /// Spring response for list animations
        static let springResponse: Double = 0.32
        
        /// Spring damping fraction
        static let springDamping: Double = 0.88
        
        /// Standard easing duration
        static let easeDuration: Double = 0.25
        
        /// Process row animation duration
        static let rowAnimationDuration: Double = 0.4
        
        /// Stopping scale effect
        static let stoppingScale: Double = 0.98
        
        /// Stopping opacity
        static let stoppingOpacity: Double = 0.8
    }
    
    // MARK: - Shadow
    
    enum Shadow {
        /// Panel shadow radius
        static let panelRadius: CGFloat = 24
        
        /// Panel shadow Y offset
        static let panelYOffset: CGFloat = 18
        
        /// Panel shadow opacity
        static let panelOpacity: Double = 0.22
        
        /// Header shadow radius
        static let headerRadius: CGFloat = 14
        
        /// Header shadow Y offset
        static let headerYOffset: CGFloat = 8
        
        /// Header shadow opacity
        static let headerOpacity: Double = 0.35
        
        /// Tile shadow radius
        static let tileRadius: CGFloat = 10
        
        /// Tile shadow Y offset
        static let tileYOffset: CGFloat = 5
        
        /// Tile shadow opacity
        static let tileOpacity: Double = 0.12
    }
}
