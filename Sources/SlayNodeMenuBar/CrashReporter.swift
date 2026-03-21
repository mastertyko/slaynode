import Foundation
import Sentry

@MainActor
enum CrashReporter {
    private static var isInitialized = false
    
    static func start(dsn: String? = nil) {
        guard !isInitialized else { return }
        
        let sentryDsn = dsn ?? ProcessInfo.processInfo.environment["SENTRY_DSN"]
        
        guard let dsn = sentryDsn, !dsn.isEmpty else {
            Log.general.info("Sentry DSN not configured, crash reporting disabled")
            return
        }
        
        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            
            options.enableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = 60000
            
            options.attachStacktrace = true
            options.enableCaptureFailedRequests = false
            
            options.tracesSampleRate = 0.1
            
            options.beforeSend = { event in
                event.tags?["app.version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                event.tags?["app.build"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                return event
            }
        }
        
        isInitialized = true
        Log.general.info("Sentry crash reporting initialized")
    }
    
    static func captureError(_ error: Error, context: [String: Any]? = nil) {
        guard isInitialized else { return }
        
        SentrySDK.capture(error: error) { scope in
            if let context = context {
                for (key, value) in context {
                    scope.setExtra(value: value, key: key)
                }
            }
        }
    }
    
    static func captureMessage(_ message: String, level: SentryLevel = .info) {
        guard isInitialized else { return }
        
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
        }
    }
    
    static func addBreadcrumb(category: String, message: String, level: SentryLevel = .info) {
        guard isInitialized else { return }
        
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        crumb.timestamp = Date()
        SentrySDK.addBreadcrumb(crumb)
    }
    
    static func setUser(id: String?) {
        guard isInitialized else { return }
        
        if let id = id {
            let user = User(userId: id)
            SentrySDK.setUser(user)
        } else {
            SentrySDK.setUser(nil)
        }
    }
}
