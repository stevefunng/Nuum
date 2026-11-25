import Foundation

public let maxAttachmentBytes = 10 * 1024 * 1024
public let maxAttachments = 5

/// Mac inlines this 20 MiB ceiling in host and ui. The client keeps one named constant.
public let maxAttachmentTotalBytes = 20 * 1024 * 1024

/// `ceil(maxAttachmentBytes / 3) * 4`, the Zod max on the base64 `data` string.
public let maxAttachmentBase64Chars = ((maxAttachmentBytes + 2) / 3) * 4

public let attachmentCountMessage = "At most 5 attachments per message."
public let attachmentSizeMessage = "Each attachment must be 10 MB or smaller."
public let attachmentTotalMessage = "Attachments must total 20 MB or less."

public let imageMIMETypes: Set<String> = [
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
]

/// Wire shape of an upload. Field name is `data` (base64), matching `packages/protocol/src/attachments.ts`.
public struct AttachmentUpload: WireRepresentable, Sendable, Equatable {
    public var name: String
    public var mimeType: String
    public var data: String

    public init(name: String, mimeType: String, data: String) {
        self.name = name
        self.mimeType = mimeType
        self.data = data
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        name = try object.string("name")
        mimeType = try object.string("mimeType")
        data = try object.string("data")
        try validateAttachmentUpload(self)
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("name", name)
        fields.add("mimeType", mimeType)
        fields.add("data", data)
        return fields.json
    }
}

public struct UserAttachment: WireRepresentable, Sendable, Equatable {
    public var name: String
    public var path: String
    public var mimeType: String
    public var size: Int
    public var text: String?

    public init(name: String, path: String, mimeType: String, size: Int, text: String? = nil) {
        self.name = name
        self.path = path
        self.mimeType = mimeType
        self.size = size
        self.text = text
    }

    public init(protocolJSON: JSONValue) throws {
        let object = try JSONObject(protocolJSON)
        name = try object.string("name")
        path = try object.string("path")
        mimeType = try object.string("mimeType")
        size = try object.int("size")
        if size < 0 {
            throw ProtocolParseException(["size"], "Number must be greater than or equal to 0")
        }
        text = try object.optionalString("text")
    }

    public var protocolJSON: JSONValue {
        var fields = JSONFieldList()
        fields.add("name", name)
        fields.add("path", path)
        fields.add("mimeType", mimeType)
        fields.add("size", size)
        fields.addIfPresent("text", text)
        return fields.json
    }
}

public func validateAttachmentUpload(_ upload: AttachmentUpload) throws {
    var issues: [ProtocolIssue] = []
    if upload.name.isEmpty {
        issues.append(ProtocolIssue(path: ["name"], message: "String must contain at least 1 character(s)"))
    } else if upload.name.count > 255 {
        issues.append(ProtocolIssue(path: ["name"], message: "String must contain at most 255 character(s)"))
    }
    if upload.mimeType.count > 120 {
        issues.append(ProtocolIssue(path: ["mimeType"], message: "String must contain at most 120 character(s)"))
    }
    let data = upload.data
    let matches = wholeMatch(#"^[A-Za-z0-9+/]*={0,2}$"#, data)
    if !matches || data.count > maxAttachmentBase64Chars {
        issues.append(ProtocolIssue(path: ["data"], message: "Invalid"))
    } else if data.count % 4 != 0 {
        issues.append(ProtocolIssue(path: ["data"], message: "Invalid base64 length"))
    }
    if !issues.isEmpty { throw ProtocolParseException(issues) }
}

/// Count, then per-file, then total. Messages match the Mac host and the attachment screen.
/// `sizes` are decoded byte lengths, not base64 lengths.
public func attachmentLimitError(_ sizes: [Int64]) -> String? {
    if sizes.count > maxAttachments { return attachmentCountMessage }
    if sizes.contains(where: { $0 > Int64(maxAttachmentBytes) }) { return attachmentSizeMessage }
    if sizes.reduce(0, +) > Int64(maxAttachmentTotalBytes) { return attachmentTotalMessage }
    return nil
}

public func requireAttachmentLimits(_ sizes: [Int64]) throws {
    if let error = attachmentLimitError(sizes) {
        throw ProtocolParseException([], error)
    }
}

/// Conservative defaults for manually entered model ids. Unknown ids use file tools.
public func supportsImageInput(_ model: ModelRef) -> Bool {
    if model.provider == .deepseek { return false }
    if model.provider == .anthropic {
        return wholeMatch(#"^claude-(?:3|sonnet-4|opus-4|haiku-4)"#, model.model, caseInsensitive: true)
    }
    return wholeMatch(
        #"^(?:gpt-4o|gpt-4\.1|gpt-4-turbo|gpt-5|o1(?!-mini|-preview)|o3(?!-mini)|o4)"#,
        model.model,
        caseInsensitive: true
    )
}

func wholeMatch(_ pattern: String, _ text: String, caseInsensitive: Bool = false) -> Bool {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
    let range = NSRange(text.startIndex..., in: text)
    return regex.firstMatch(in: text, range: range) != nil
}
