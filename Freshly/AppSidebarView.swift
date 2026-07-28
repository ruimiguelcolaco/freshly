import SwiftUI

struct AppSidebarView: View {
    @Environment(AppListStore.self) private var store
    @Binding var selection: AppListCategory

    var body: some View {
        List(selection: $selection) {
            categoryRow(.updates, count: store.outdated.count)
            categoryRow(.all, count: store.statuses.count)

            Section("Library") {
                categoryRow(.upToDate, count: store.upToDate.count)
                categoryRow(.skipped, count: store.skipped.count)
                categoryRow(.notCheckable, count: store.notCheckable.count)
            }
        }
        .navigationTitle("Freshly")
        .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
    }

    private func categoryRow(_ category: AppListCategory, count: Int) -> some View {
        Label {
            HStack {
                Text(category.title)
                Spacer()
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: category.systemImage)
        }
        .tag(category)
    }
}
