# Prompt

A comprehensive Swift library for building beautiful and interactive command-line interfaces.

## Features

- **Rich Terminal UI Components**: Spinners, progress indicators, tables, boxes, and panels
- **Interactive Prompts**: Multi-select menus with arrow key navigation, confirmations, and text inputs
- **Colored Output**: Status indicators with automatic color support detection
- **Hierarchical Display**: Nested items, sections, and formatted output
- **Log Levels**: Control output verbosity (quiet, normal, verbose)
- **Path Formatting**: Syntax highlighting for file paths
- **Error Formatting**: Contextual error messages with helpful suggestions

## Installation

### Swift Package Manager

Add Prompt to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/Prompt.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Prompt", package: "Prompt")
    ]
)
```

## Usage

```swift
import Prompt

let prompt = PromptService()

// Display banner
prompt.banner()

// Status messages
prompt.success("Operation completed!")
prompt.error("Something went wrong")
prompt.warning("This is a warning")
prompt.info("FYI: Some information")

// Interactive prompts
let name = prompt.prompt("What's your name?", default: "User")
let confirmed = prompt.confirm("Continue?", default: true)

// Multi-select menu
let selected = prompt.multiSelect(
    "Choose platforms:",
    options: ["iOS", "macOS", "tvOS", "watchOS"]
)

// Spinner for long operations
let spinner = prompt.spinner("Loading...")
spinner.start()
// ... do work ...
spinner.stop(success: true)

// Or use withSpinner for automatic handling
prompt.withSpinner("Processing") {
    // ... do work ...
}

// Tables and panels
prompt.table(
    headers: ["Name", "Value"],
    rows: [
        ["Setting 1", "Value 1"],
        ["Setting 2", "Value 2"]
    ]
)

prompt.panel("Configuration", items: [
    ("Platform", "macOS"),
    ("Version", "1.0.0")
])

// Hierarchical output
prompt.header("Main Section")
prompt.item("First item")
prompt.itemSuccess("Completed task")
prompt.itemError("Failed task")
prompt.itemWarning("Warning message")
```

## Components

### PromptService

The main service for all terminal UI operations.

### Symbols

Consistent symbols used throughout the interface:
- `✓` Success (green)
- `✗` Error (red)
- `!` Warning (yellow)
- `i` Info (blue)
- `→` Arrow (navigation)
- `•` Bullet point
- `◉` Checked (multi-select)
- `○` Unchecked (multi-select)

### BoxStyle

Three box drawing styles:
- `.single` - Single line borders
- `.double` - Double line borders
- `.rounded` - Rounded corner borders

### LogLevel

Control output verbosity:
- `.quiet` - Minimal output
- `.normal` - Standard output
- `.verbose` - Detailed output

## Requirements

- Swift 5.9+
- macOS 13.0+

## Dependencies

- [Rainbow](https://github.com/onevcat/Rainbow) - Terminal string styling with ANSI colors

## License

MIT License - See LICENSE file for details

## Author

Created for use with tccc and other CLI tools.
