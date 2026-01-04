import Foundation

public typealias TweakKey = String

public enum TweakEventSource: String, Sendable {
    case web
    case ui
    case code
}

public struct TweakEvent: Sendable {
    public let key: TweakKey
    public let oldValueString: String
    public let newValueString: String
    public let timestamp: Date
    public let source: TweakEventSource

    public init(
        key: TweakKey,
        oldValueString: String,
        newValueString: String,
        timestamp: Date = Date(),
        source: TweakEventSource
    ) {
        self.key = key
        self.oldValueString = oldValueString
        self.newValueString = newValueString
        self.timestamp = timestamp
        self.source = source
    }
}
