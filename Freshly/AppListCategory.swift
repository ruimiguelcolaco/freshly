import SwiftUI

enum AppListCategory: String, CaseIterable, Identifiable {
    case updates
    case all
    case upToDate
    case skipped
    case notCheckable

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .updates: "Updates"
        case .all: "All Applications"
        case .upToDate: "Up to Date"
        case .skipped: "Skipped"
        case .notCheckable: "No Update Source"
        }
    }

    var systemImage: String {
        switch self {
        case .updates: "arrow.down.circle"
        case .all: "square.grid.2x2"
        case .upToDate: "checkmark.circle"
        case .skipped: "eye.slash"
        case .notCheckable: "questionmark.circle"
        }
    }
}
