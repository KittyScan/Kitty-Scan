import SwiftUI

struct ContentView: View {
    @Environment(LanguageManager.self) var lang

    var body: some View {
        TabView {
            CameraView()
                .tabItem { Label(lang.loc("tab.detect"), systemImage: "pawprint.fill") }
            DiaryView()
                .tabItem {
                    Label(lang.isChineseSelected ? "日记" : "Diary",
                          systemImage: "calendar")
                }
            HistoryView()
                .tabItem { Label(lang.loc("tab.history"), systemImage: "clock.fill") }
            SettingsView()
                .tabItem { Label(lang.loc("tab.settings"), systemImage: "gearshape.fill") }
        }
    }
}
