# Contributing

Thanks for helping. Issues and pull requests are welcome.

## Setup

```sh
brew install xcodegen swiftlint
swift test
swiftlint
scripts/build-app.sh
```

`swift test` covers all the logic in `WardenCore` and only uses temporary directories. To try the app safely, run `scripts/demo.sh`: it uses a Debug build and a throwaway fake home. Only Debug builds honor `WARDEN_HOME`.

## Common changes

**Add a detection rule**
1. Add a case to `RuleID` in `Sources/WardenCore/Risk/RiskRule.swift`.
2. Implement it in `ConfigRules` or `InstructionRules`, and register it in the list of rules there.
3. Add its English and French wording in `FallbackTemplates`. Tests fail if it is missing.
4. Add one test that fires and, for instruction patterns, one legitimate case that does not.

**Watch a new file or key**
Edit `Sources/WardenCore/Policy/WatchCatalog.swift`, the single source of truth, then update the tables in `README.md`. A test fails if they disagree.

**Change interface text**
Add the French translation to `App/Resources/Localizable.xcstrings`.

## Rules that must hold

- Warden never changes a watched file unless the user asks.
- No networking API, anywhere. `NoNetworkTests` enforces it.
- Severity and recommendations come from rules, never from the model.
- Secrets are masked before reaching the model or the screen.
- Session content and project code are never read.
- No third-party runtime dependency.

## Reporting a vulnerability

Please use [GitHub private vulnerability reporting](https://github.com/williamtrde/warden/security/advisories/new) rather than a public issue.
