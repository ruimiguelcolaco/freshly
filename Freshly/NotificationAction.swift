enum NotificationAction: Sendable, Equatable {
    case openFreshly
    case updateApp(path: String)
    case updateAll
}
