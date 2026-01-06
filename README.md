# TweakKit

![CI](https://github.com/devandanger/TweakKit/actions/workflows/ci.yml/badge.svg)

Swift library for runtime tweaking of app values through a web-based terminal interface.

## Install

Add the package in Swift Package Manager:

- URL: `https://github.com/devandanger/TweakKit.git`
- Products: `TweakKitCore`, `TweakKitServer`

## Core usage

Create tweaks and update values programmatically:

```swift
import TweakKitCore

let cornerRadius = Tweak<Double>(
    "ui.cornerRadius",
    defaultValue: 12,
    constraints: TweakConstraints(min: 0, max: 40, step: 1)
)

_ = cornerRadius.set(18, source: .code)
print(cornerRadius.currentValue)
```

Listen for change events:

```swift
let id = TweakRegistry.shared.addObserver { event in
    print("\(event.key): \(event.oldValueString) -> \(event.newValueString)")
}

// Later when you are done
TweakRegistry.shared.removeObserver(id)
```

## Server usage

Start the embedded server and open the printed URL:

```swift
import TweakKitServer

let server = TweakKitServer()
try server.start(port: 8080, networkMode: .localhostOnly)
```

The server prints a URL with a `token` query parameter. Use that URL in your browser.

### Web commands

- `help`
- `list [filter]`
- `get <key>`
- `set <key> <value>`
- `reset <key>`
- `reset-all`
- `last`
- `history [n]`
- `watch [key]`

## SwiftUI integration

SwiftUI property wrapper support is planned in Phase 4.
