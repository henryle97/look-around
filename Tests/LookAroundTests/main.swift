import Foundation

// Entry point for the standalone unit-test binary. Run via
// `./scripts/test-unit.sh` (compiles this directory + the pure-logic
// Sources/LookAround files together, then executes the result).

let runner = TestRunner()
registerOfficeHoursTests(runner)
registerSmartPauseTests(runner)
registerTimeFmtTests(runner)
registerAppearanceSettingsTests(runner)
registerSettingsStoreTests(runner)
registerPromptPickerTests(runner)

exit(runner.finish())
