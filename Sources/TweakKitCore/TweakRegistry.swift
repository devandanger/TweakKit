import Foundation

public typealias TweakEventHandler = (TweakEvent) -> Void

public final class TweakRegistry {
    public static let shared = TweakRegistry()

    private let queue = DispatchQueue(label: "TweakKit.Registry")
    private var tweaks: [TweakKey: AnyTweakable] = [:]
    private var observers: [UUID: TweakEventHandler] = [:]
    private let historyCapacity = 100

    public private(set) var lastTweak: TweakEvent?
    public private(set) var history: [TweakEvent] = []

    private init() {}

    public func register(_ tweak: AnyTweakable) {
        queue.sync {
            tweaks[tweak.key] = tweak
        }
    }

    public func get(_ key: TweakKey) -> AnyTweakable? {
        queue.sync {
            tweaks[key]
        }
    }

    @discardableResult
    public func set(_ key: TweakKey, valueString: String, source: TweakEventSource) -> Result<Void, Error> {
        guard let tweak = get(key) else {
            return .failure(TweakError.invalidValue("Unknown key: \(key)"))
        }
        let oldValueString = tweak.currentValueString
        let result = tweak.setFromString(valueString)
        switch result {
        case .success:
            let newValueString = tweak.currentValueString
            if oldValueString != newValueString {
                let event = TweakEvent(
                    key: key,
                    oldValueString: oldValueString,
                    newValueString: newValueString,
                    source: source
                )
                record(event)
            }
            return .success(())
        case .failure:
            return result
        }
    }

    @discardableResult
    public func reset(_ key: TweakKey, source: TweakEventSource) -> Result<Void, Error> {
        guard let tweak = get(key) else {
            return .failure(TweakError.invalidValue("Unknown key: \(key)"))
        }
        let oldValueString = tweak.currentValueString
        let didReset = tweak.reset()
        guard didReset else {
            return .success(())
        }
        let newValueString = tweak.currentValueString
        if oldValueString != newValueString {
            let event = TweakEvent(
                key: key,
                oldValueString: oldValueString,
                newValueString: newValueString,
                source: source
            )
            record(event)
        }
        return .success(())
    }

    public func list(filter: String? = nil) -> [AnyTweakable] {
        let allTweaks = queue.sync {
            Array(tweaks.values)
        }
        let filtered = allTweaks.filter { tweak in
            guard let filter, !filter.isEmpty else {
                return true
            }
            return tweak.key.localizedCaseInsensitiveContains(filter)
        }
        return filtered.sorted { $0.key < $1.key }
    }

    public func addObserver(_ handler: @escaping TweakEventHandler) -> UUID {
        let id = UUID()
        queue.sync {
            observers[id] = handler
        }
        return id
    }

    public func removeObserver(_ id: UUID) {
        _ = queue.sync {
            observers.removeValue(forKey: id)
        }
    }

    func record(_ event: TweakEvent) {
        let handlers: [TweakEventHandler] = queue.sync {
            lastTweak = event
            history.append(event)
            if history.count > historyCapacity {
                history.removeFirst(history.count - historyCapacity)
            }
            return Array(observers.values)
        }
        handlers.forEach { $0(event) }
    }
}
