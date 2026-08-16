import Testing
import FreshlyEngine

@Suite("Install reservations")
struct InstallReservationsTests {
    @Test("A duplicate request cannot reserve the same install slot")
    func duplicateRequest() {
        var reservations = InstallReservations<String>()

        let firstRequest = reservations.reserve("com.example.App")
        let duplicateRequest = reservations.reserve("com.example.App")
        #expect(firstRequest)
        #expect(!duplicateRequest)
        #expect(reservations.contains("com.example.App"))

        reservations.release("com.example.App")
        #expect(!reservations.contains("com.example.App"))
        let retry = reservations.reserve("com.example.App")
        #expect(retry)
    }

    @Test("Different apps reserve independently")
    func independentApps() {
        var reservations = InstallReservations<String>()

        let firstApp = reservations.reserve("com.example.One")
        let secondApp = reservations.reserve("com.example.Two")
        #expect(firstApp)
        #expect(secondApp)
    }
}
