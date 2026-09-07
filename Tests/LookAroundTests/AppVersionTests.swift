import Foundation

func registerAppVersionTests(_ r: TestRunner) {
    r.run("AppVersion.compare: equal versions") {
        try expectEqual(AppVersion.compare("1.2.3", "1.2.3"), 0)
    }
    r.run("AppVersion.compare: patch difference") {
        try expectEqual(AppVersion.compare("1.2.4", "1.2.3"), 1)
        try expectEqual(AppVersion.compare("1.2.3", "1.2.4"), -1)
    }
    r.run("AppVersion.compare: shorter version pads missing components with zero") {
        try expectEqual(AppVersion.compare("1.2", "1.2.0"), 0)
        try expectEqual(AppVersion.compare("1.3", "1.2.9"), 1)
    }
    r.run("AppVersion.compare: leading 'v' is ignored") {
        try expectEqual(AppVersion.compare("v1.2.3", "1.2.3"), 0)
    }
    r.run("AppVersion.compare: prerelease/build suffix is ignored") {
        try expectEqual(AppVersion.compare("1.2.3-beta.1", "1.2.3"), 0)
        try expectEqual(AppVersion.compare("1.2.3+build5", "1.2.3"), 0)
    }
    r.run("AppVersion.isNewer") {
        try expectTrue(AppVersion.isNewer("0.2.0", than: "0.1.1"))
        try expectFalse(AppVersion.isNewer("0.1.0", than: "0.1.0"))
        try expectFalse(AppVersion.isNewer("0.1.0", than: "0.2.0"))
    }
}
