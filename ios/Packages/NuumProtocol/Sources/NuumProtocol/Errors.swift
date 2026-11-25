import Foundation

/// Kernel codes from `packages/protocol/src/errors.ts`. 1001 is unused on purpose.
public enum KernelErrorCode {
    public static let `internal` = 1000
    public static let turnBusy = 1002
    public static let cancelled = 1003
    public static let model = 1004
    public static let tool = 1005
    public static let sandbox = 1006
    public static let invalid = 1007
}

/// Host codes. 2005–2007 are unused on purpose.
public enum HostErrorCode {
    public static let agentNotFound = 2001
    public static let agentBusy = 2002
    public static let noWorkspace = 2003
    public static let noAPIKey = 2004
    public static let kernelDown = 2008
    public static let dataDirLocked = 2009
    public static let workNotFound = 2010
    public static let workConflict = 2011
    public static let workForbidden = 2012
}

/// Desktop codes. `window` keeps the number only; window methods are not ported.
public enum DesktopErrorCode {
    public static let secretStore = 3001
    public static let folderPick = 3002
    public static let window = 3003
}

/// Numeric code plus a human message. Corresponds to Mac `RpcError`.
/// `message` must not contain key material.
public struct RpcError: Error, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}
