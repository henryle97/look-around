import Foundation

// Minimal, dependency-free test harness.
//
// This repo builds with `swiftc` alone (see build.sh) — no Xcode, so
// neither XCTest (needs Xcode's `xctest` utility) nor `swift test`
// (SwiftPM's manifest step fails to link under CLT-only here) are
// available. Same idea as `tools/axdrive`: a small standalone tool
// compiled directly with swiftc. See docs/unit-testing.md.

struct ExpectationFailure: Error {
    let message: String
    let file: StaticString
    let line: UInt
}

/// Fails the current test unless `condition` is true.
func expectTrue(
    _ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "expected true",
    file: StaticString = #file, line: UInt = #line
) throws {
    if !condition() {
        throw ExpectationFailure(message: message(), file: file, line: line)
    }
}

/// Fails the current test unless `condition` is false.
func expectFalse(
    _ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "expected false",
    file: StaticString = #file, line: UInt = #line
) throws {
    try expectTrue(!condition(), message(), file: file, line: line)
}

/// Fails the current test unless `a == b`, printing both sides.
func expectEqual<T: Equatable>(
    _ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
    file: StaticString = #file, line: UInt = #line
) throws {
    let (lhs, rhs) = (a(), b())
    if lhs != rhs {
        throw ExpectationFailure(message: "\(lhs) != \(rhs)", file: file, line: line)
    }
}

/// Fails the current test unless `value` is nil.
func expectNil<T>(
    _ value: @autoclosure () -> T?, _ message: @autoclosure () -> String? = nil,
    file: StaticString = #file, line: UInt = #line
) throws {
    if let value = value() {
        let suffix = message().map { " — \($0)" } ?? ""
        throw ExpectationFailure(message: "expected nil, got \(value)\(suffix)", file: file, line: line)
    }
}

/// Fails the current test unless `value` is non-nil; returns the unwrapped value.
@discardableResult
func expectNotNil<T>(
    _ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line
) throws -> T {
    guard let value = value() else {
        throw ExpectationFailure(message: "expected non-nil", file: file, line: line)
    }
    return value
}

final class TestRunner {
    private var passCount = 0
    private var failCount = 0

    /// Runs one test case. `body` may throw an `ExpectationFailure` (from
    /// the `expect*` helpers above) or any other error — both are caught
    /// and reported as a failure, not a crash of the whole suite.
    func run(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passCount += 1
            print("✓ \(name)")
        } catch let failure as ExpectationFailure {
            failCount += 1
            let fileName = ("\(failure.file)" as NSString).lastPathComponent
            print("✗ \(name) — \(failure.message) (\(fileName):\(failure.line))")
        } catch {
            failCount += 1
            print("✗ \(name) — threw \(error)")
        }
    }

    /// Prints the pass/fail summary and returns a process exit code.
    func finish() -> Int32 {
        print("")
        print("\(passCount) passed, \(failCount) failed")
        return failCount == 0 ? 0 : 1
    }
}
