import Foundation

// Minimal test harness — no XCTest dependency, so it runs on a
// Command-Line-Tools-only toolchain. Exits non-zero on any failure (TESTING.md §1,
// blocking in CI).

enum Skip: Error { case skip(String) }
func skip(_ reason: String) throws -> Never { throw Skip.skip(reason) }

struct Expect: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func expect(_ cond: Bool, _ message: @autoclosure () -> String = "condition was false") throws {
    if !cond { throw Expect(message: message()) }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "") throws {
    if a != b { throw Expect(message: "expectEqual failed (\(a) != \(b)) \(message())") }
}

func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "") throws {
    if a == b { throw Expect(message: "expectNotEqual failed (both \(a)) \(message())") }
}

func expectThrows(_ body: () throws -> Void, _ message: @autoclosure () -> String = "expected an error") throws {
    var threw = false
    do { try body() } catch { threw = true }
    if !threw { throw Expect(message: message()) }
}

func expectThrowsError(_ body: () throws -> Void, _ check: (Error) -> Bool) throws {
    var caught: Error?
    do { try body() } catch { caught = error }
    guard let c = caught else { throw Expect(message: "expected an error, none thrown") }
    if !check(c) { throw Expect(message: "unexpected error: \(c)") }
}

final class Harness {
    private var passed = 0
    private var failed = 0
    private var skipped = 0
    private var failures: [String] = []

    func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("  ✓ \(name)")
        } catch let Skip.skip(reason) {
            skipped += 1
            print("  ~ \(name)  [skipped: \(reason)]")
        } catch {
            failed += 1
            failures.append("\(name): \(error)")
            print("  ✗ \(name): \(error)")
        }
    }

    func section(_ name: String) { print("\n\(name)") }

    func finish() -> Never {
        print("\n────────────────────────────────────────")
        print("\(passed) passed · \(failed) failed · \(skipped) skipped")
        if !failures.isEmpty {
            print("\nFAILURES:")
            for f in failures { print("  - \(f)") }
        }
        exit(failed == 0 ? 0 : 1)
    }
}
