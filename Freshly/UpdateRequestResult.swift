enum UpdateRequestResult: Sendable, Equatable {
    case started
    case requiresQuitConfirmation
    case handedOff
    case ignored
}
