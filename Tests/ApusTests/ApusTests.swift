import Testing
@testable import Apus

@Test func harfbuzzVersion() {
    let version = Apus.harfbuzzVersion()
    #expect(version == "12.3.0")
}

@Test func freetypeVersion() {
    let version = Apus.freetypeVersion()
    #expect(version.major == 2)
    #expect(version.minor >= 13)
}

@Test func verify() {
    #expect(Apus.verify())
}
