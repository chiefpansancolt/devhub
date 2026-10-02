import Testing
@testable import DevHubCore

@Suite struct PackageVersionTests {
    @Test(arguments: [
        ("2.47.0", "2.56.0"),
        ("1.9.0", "1.10.0"),
        ("0.40.4", "0.40.8"),
        ("11.19.0", "12.2.0"),
        ("10.47_1", "10.49"),
        ("8.0.0-rc.19", "8.0.0"),
        ("1.0.0-beta", "1.0.0"),
        ("2.13.3", "2.14.2"),
        ("7.1.0.rc2", "7.1.0.rc10"),
        ("1.0.9", "1.0.10a"),
        ("9a", "10a"),
        ("99999999999", "99999999999999999999999")
    ])
    func orders(older: String, newer: String) {
        #expect(PackageVersion(older) < PackageVersion(newer))
        #expect(!(PackageVersion(newer) < PackageVersion(older)))
    }

    @Test(arguments: [("1.0", "1.0.0"), ("v24.21.0", "24.21.0"), ("3.5a", "3.5a")])
    func treatsAsEqual(left: String, right: String) {
        #expect(PackageVersion(left) == PackageVersion(right))
    }
}
