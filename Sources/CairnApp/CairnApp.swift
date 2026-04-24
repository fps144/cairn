import SwiftUI
import CairnUI

@main
struct CairnApp: App {
    var body: some Scene {
        WindowGroup("Cairn") {
            ContentView()
        }
        .defaultSize(width: 900, height: 600)
    }
}
