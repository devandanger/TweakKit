Recommended architecture (what you’re building)

TweakKit = Core + (optional) Server + (optional) SwiftUI integration
	•	TweakKitCore
	•	Typed Tweak<T> that self-registers into a global O(1) registry
	•	Override values live in-memory (no UserDefaults)
	•	Emits change events
	•	Keeps lastTweak + a small ring buffer history
	•	TweakKitServer
	•	Embedded HTTP server:
	•	GET / serves a terminal-looking page (monospace, black background)
	•	WebSocket endpoint /ws for command I/O
	•	Implements a simple command language (list, get, set, last, history, watch)
	•	TweakKitSwiftUI (optional but high ROI)
	•	@TweakValue property wrapper (or @Tweak)
	•	SwiftUI updates on change

⸻

Implementation plan (step-by-step)

Phase 4 — SwiftUI integration (optional, but makes it pop)
	12.	Property wrapper

	•	@TweakValue("ui.cornerRadius", default: 12, min: 0, max: 40, step: 1) var cornerRadius: Double
	•	Wrapper subscribes to registry events and triggers SwiftUI updates

	13.	Example app

	•	A “Tweak Playground” view with visible changes:
	•	spacing, corner radius, animation duration, feature toggle
	•	Print “Open terminal at …” on launch

✅ Milestone: demoable in 30 seconds.
