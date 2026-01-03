# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TweakKit is a Swift library for iOS/macOS that enables runtime tweaking of app values through a web-based terminal interface. It allows developers to modify configuration values in a running app without recompiling.

## Architecture

The library consists of three modules:

- **TweakKitCore**: The foundation - typed `Tweak<T>` values that self-register into a global O(1) registry, in-memory override storage, change events, and history tracking (last tweak + ring buffer)
- **TweakKitServer**: Embedded HTTP server serving a terminal-style web UI, WebSocket endpoint for command I/O (`list`, `get`, `set`, `reset`, `last`, `history`, `watch`)
- **TweakKitSwiftUI**: `@TweakValue` property wrapper that triggers SwiftUI updates on tweak changes

## Key Concepts

- `Tweak<T>` holds a default value, optional override, and constraints (min/max/step)
- `AnyTweakable` protocol provides type-erased storage with `setFromString(_:)` for WebSocket commands
- `TweakRegistry.shared` is the central dictionary storing all registered tweaks
- Server requires token auth (generated at startup, printed to console) for security
- Server defaults to localhost-only binding; LAN mode optional

## Build Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Run a single test
swift test --filter <TestClassName>/<testMethodName>
```

## Implementation Notes

- Server code should be gated with `#if DEBUG` by default
- Use Telegraph library for HTTP/WebSocket server (Swift, iOS-focused, SPM compatible)
- Terminal UI is a single HTML file served at `GET /`
- WebSocket commands use simple line-based protocol with quoted string support
