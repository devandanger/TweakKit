import Foundation

public struct TweakConstraintInfo: Sendable {
    public let min: String?
    public let max: String?
    public let step: String?

    public init(min: String?, max: String?, step: String?) {
        self.min = min
        self.max = max
        self.step = step
    }
}

public protocol AnyTweakable: AnyObject {
    var key: TweakKey { get }
    var typeName: String { get }
    var defaultValueString: String { get }
    var currentValueString: String { get }
    var constraintsInfo: TweakConstraintInfo? { get }

    func setFromString(_ valueString: String) -> Result<Void, Error>
    func reset() -> Bool
}
