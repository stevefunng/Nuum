func parseAgentProfile(directoryName: String, text: String) -> AgentListEntry? {
    guard let node = JSONDocument.parse(text),
          JSONDocument.has(node, "name"),
          JSONDocument.has(node, "createdAt"),
          let id = JSONDocument.string(JSONDocument.field(node, "id")),
          !id.isEmpty,
          id == directoryName
    else { return nil }
    let createdAt = JSONDocument.int(JSONDocument.field(node, "createdAt")) ?? 0
    return AgentListEntry(
        id: id,
        name: JSONDocument.string(JSONDocument.field(node, "name")) ?? "",
        description: JSONDocument.string(JSONDocument.field(node, "description")) ?? "",
        createdAt: createdAt,
        tags: JSONDocument.stringList(JSONDocument.field(node, "tags")),
        avatarColor: JSONDocument.nullableString(node, "avatarColor"),
        avatarShape: JSONDocument.nullableString(node, "avatarShape"),
        avatarMaterial: JSONDocument.nullableString(node, "avatarMaterial"),
        hiddenFromSidebar: false,
        lastActivityAt: createdAt
    )
}

func parseHiddenFromSidebar(_ text: String) -> Bool {
    guard let node = JSONDocument.parse(text),
          case .bool(let hidden) = JSONDocument.field(node, "hiddenFromSidebar")
    else { return false }
    return hidden
}

func parseWorkProfile(directoryName: String, text: String) -> WorkListEntry? {
    guard let node = JSONDocument.parse(text),
          JSONDocument.has(node, "createdAt"),
          let id = JSONDocument.string(JSONDocument.field(node, "id")),
          !id.isEmpty,
          id == directoryName,
          let name = JSONDocument.string(JSONDocument.field(node, "name")),
          !name.isEmpty
    else { return nil }
    let createdAt = JSONDocument.int(JSONDocument.field(node, "createdAt")) ?? 0
    return WorkListEntry(
        id: id,
        name: name,
        description: JSONDocument.string(JSONDocument.field(node, "description")) ?? "",
        projectRoot: JSONDocument.nullableString(node, "projectRoot"),
        createdAt: createdAt,
        kind: JSONDocument.nullableString(node, "kind"),
        avatar: JSONDocument.nullableString(node, "avatar"),
        workspaceId: JSONDocument.nullableString(node, "workspaceId"),
        lastActivityAt: createdAt,
        preview: nil
    )
}
