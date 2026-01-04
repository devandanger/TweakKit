import Foundation

public protocol TweakValue: CustomStringConvertible {
    static func parse(_ value: String) -> Self?
}

extension TweakValue where Self: LosslessStringConvertible {
    public static func parse(_ value: String) -> Self? {
        Self(value)
    }
}

extension String: TweakValue {
    public static func parse(_ value: String) -> String? {
        value
    }
}

extension Bool: TweakValue {
    public static func parse(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "y", "on":
            return true
        case "false", "0", "no", "n", "off":
            return false
        default:
            return nil
        }
    }
}

public protocol TweakNumeric: Comparable {
    var asDouble: Double { get }
    static func fromDouble(_ value: Double) -> Self?
}

extension Double: TweakNumeric {
    public var asDouble: Double { self }

    public static func fromDouble(_ value: Double) -> Double? {
        value
    }
}

extension Int: TweakNumeric {
    public var asDouble: Double { Double(self) }

    public static func fromDouble(_ value: Double) -> Int? {
        let rounded = value.rounded()
        guard abs(value - rounded) < 0.000_000_1 else {
            return nil
        }
        return Int(rounded)
    }
}

public struct TweakConstraints<T> {
    public let min: T?
    public let max: T?
    public let step: T?

    public init(min: T? = nil, max: T? = nil, step: T? = nil) {
        self.min = min
        self.max = max
        self.step = step
    }
}

public enum TweakError: Error, CustomStringConvertible {
    case invalidValue(String)
    case outOfRange(min: String?, max: String?)
    case stepMismatch(step: String)

    public var description: String {
        switch self {
        case .invalidValue(let value):
            return "Invalid value: \(value)"
        case .outOfRange(let min, let max):
            return "Value out of range (min: \(min ?? "-") max: \(max ?? "-") )"
        case .stepMismatch(let step):
            return "Value must align to step \(step)"
        }
    }
}

public final class Tweak<T: TweakValue>: AnyTweakable {
    public let key: TweakKey
    public let defaultValue: T
    public let constraints: TweakConstraints<T>?
    public let typeName: String

    private let registry: TweakRegistry
    private var overrideValue: T?

    public var currentValue: T {
        overrideValue ?? defaultValue
    }

    public var defaultValueString: String {
        defaultValue.description
    }

    public var currentValueString: String {
        currentValue.description
    }

    public var constraintsInfo: TweakConstraintInfo? {
        guard let constraints else {
            return nil
        }
        return TweakConstraintInfo(
            min: constraints.min?.description,
            max: constraints.max?.description,
            step: constraints.step?.description
        )
    }

    public init(
        _ key: TweakKey,
        defaultValue: T,
        constraints: TweakConstraints<T>? = nil,
        registry: TweakRegistry = .shared
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.constraints = constraints
        self.registry = registry
        self.typeName = String(describing: T.self)

        registry.register(self)
    }

    @discardableResult
    public func set(_ value: T, source: TweakEventSource = .code) -> Result<Void, Error> {
        let oldValueString = currentValueString
        let result = validate(value)
        switch result {
        case .success:
            overrideValue = value
        case .failure:
            return result
        }

        let newValueString = currentValueString
        if oldValueString != newValueString {
            let event = TweakEvent(
                key: key,
                oldValueString: oldValueString,
                newValueString: newValueString,
                source: source
            )
            registry.record(event)
        }
        return .success(())
    }

    public func reset(source: TweakEventSource = .code) -> Bool {
        guard overrideValue != nil else {
            return false
        }
        let oldValueString = currentValueString
        overrideValue = nil
        let newValueString = currentValueString
        let event = TweakEvent(
            key: key,
            oldValueString: oldValueString,
            newValueString: newValueString,
            source: source
        )
        registry.record(event)
        return true
    }

    public func setFromString(_ valueString: String) -> Result<Void, Error> {
        guard let parsed = T.parse(valueString) else {
            return .failure(TweakError.invalidValue(valueString))
        }
        let result = validate(parsed)
        switch result {
        case .success:
            overrideValue = parsed
            return .success(())
        case .failure:
            return result
        }
    }

    public func reset() -> Bool {
        guard overrideValue != nil else {
            return false
        }
        overrideValue = nil
        return true
    }

    private func validate(_ value: T) -> Result<Void, Error> {
        guard let constraints else {
            return .success(())
        }
        if let rangeResult = validateRangeIfPossible(constraints, value), case .failure = rangeResult {
            return rangeResult
        }
        if let stepResult = validateStepIfPossible(constraints, value), case .failure = stepResult {
            return stepResult
        }
        return .success(())
    }

    private func validateRangeIfPossible(_ constraints: TweakConstraints<T>, _ value: T) -> Result<Void, Error>? {
        nil
    }

    private func validateStepIfPossible(_ constraints: TweakConstraints<T>, _ value: T) -> Result<Void, Error>? {
        nil
    }
}

private extension Tweak where T: Comparable {
    func validateRangeIfPossible(_ constraints: TweakConstraints<T>, _ value: T) -> Result<Void, Error>? {
        if let min = constraints.min, value < min {
            return .failure(TweakError.outOfRange(min: min.description, max: constraints.max?.description))
        }
        if let max = constraints.max, value > max {
            return .failure(TweakError.outOfRange(min: constraints.min?.description, max: max.description))
        }
        return .success(())
    }
}

private extension Tweak where T: TweakNumeric {
    func validateStepIfPossible(_ constraints: TweakConstraints<T>, _ value: T) -> Result<Void, Error>? {
        guard let step = constraints.step else {
            return .success(())
        }
        let base = constraints.min?.asDouble ?? 0
        let delta = value.asDouble - base
        let remainder = delta.truncatingRemainder(dividingBy: step.asDouble)
        let epsilon = 0.000_000_1
        let isAligned = abs(remainder) < epsilon || abs(remainder - step.asDouble) < epsilon
        if isAligned {
            return .success(())
        }
        return .failure(TweakError.stepMismatch(step: step.description))
    }
}
