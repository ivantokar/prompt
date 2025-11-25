# Repository Guidelines

## Project Structure & Module Organization
SwiftPM drives everything: library code resides in `Sources/Prompt` with subfolders for `Core` (symbols, log levels), `Terminal` (size and rendering helpers), `FileSearch`, and `Input`. The high-level API lives in `PromptService.swift`. Tests belong in `Tests/PromptTests`, mirroring the same folder names so suites are easy to find. Store examples directly in doc comments or `README.md`; no extra assets directory is required.

## Build, Test, and Development Commands
- `swift build` compiles the library against macOS 13 and surfaces dependency issues quickly.
- `swift test` runs all suites; append `--filter PromptTests.<SuiteName>` when focusing on one behavior.
- `swift test --enable-code-coverage` exports `.profdata` that Xcode can visualize for release gating.

## Coding Style & Naming Conventions
Stick to Swift 5.9 defaults: four-space indentation, braces on the same line, and trailing commas for multi-line literals. Types use `UpperCamelCase`, members use `lowerCamelCase`, and shared constants stay in dedicated structs or enums (see `Symbols.swift`). Keep ANSI escape codes centralized, prefer protocol-first abstractions, and inject dependencies like terminal controllers through initializers.

## Testing Guidelines
Add tests beside their production counterparts (`SpinnerTests` for `Spinner`, etc.) and stub `TerminalController` so output strings remain deterministic. Cover stateful flows such as spinners, multi-select validation, and file search edge cases before merging. Store any golden-output fixtures under `Tests/PromptTests/__Fixtures__` and run `swift test` locally before creating a pull request.

## Commit & Pull Request Guidelines
History uses Conventional Commits (`feat:`, `fix:`, `docs:`). Keep subjects under 72 characters and add bullet points in the body for complex work. Pull requests must summarize intent, list validation steps (`swift test`, coverage run), include screenshots or terminal captures for UI tweaks, and link issues. Call out any change that impacts ANSI rendering or supported macOS versions so reviewers can double-check compatibility.

## Security & Configuration Tips
Rainbow is the only external dependency; run `swift package update` before releases to pick up fixes. Avoid echoing raw user input without sanitizing or truncating to block malicious escape codes. When changing glyphs for panels or spinners, verify they render under UTF-8 and plain ASCII terminals to keep downstream tools safe.
