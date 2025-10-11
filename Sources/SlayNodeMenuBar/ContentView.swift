import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    
    var body: some View {
        MenuContentView(preferences: preferences)
            .frame(minWidth: 420, minHeight: 520)
    }
}
