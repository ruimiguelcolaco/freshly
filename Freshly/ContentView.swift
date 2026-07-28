import SwiftUI

struct ContentView: View {
    @State private var selection = AppListCategory.updates

    var body: some View {
        NavigationSplitView {
            AppSidebarView(selection: $selection)
        } detail: {
            AppListDetailView(category: selection)
        }
    }
}
