import NuumContracts

/// Global `settings.json` is the non-secret document. Encoding writes only `Settings` fields,
/// so key material cannot round-trip through this file.
enum SettingsJSON {
    static func encode(_ settings: Settings) -> String {
        var fields: [(String, JSONNode)] = [
            ("defaultToolPermission", .string(settings.defaultToolPermission.rawValue)),
            (
                "defaultModel",
                .object([
                    ("provider", .string(settings.defaultModel.provider.rawValue)),
                    ("model", .string(settings.defaultModel.model)),
                ])
            ),
            ("theme", .string(settings.theme.rawValue)),
            ("language", .string(settings.language.rawValue)),
        ]
        if let sidebar = settings.sidebar {
            fields.append(("sidebar", encodeSidebar(sidebar)))
        }
        return JSONDocument.renderFields(fields) + "\n"
    }

    static func decode(_ text: String) -> Settings {
        guard let node = JSONDocument.parse(text) else { return defaultSettings }
        return fromObject(node)
    }

    /// Rewrites a global settings document to the schema. Invalid JSON is rejected without echoing it.
    static func canonical(_ text: String) throws -> String {
        let node = try JSONDocument.requireObject(text)
        return encode(fromObject(node))
    }

    /// Agent `settings.json` keeps its own shape. Secret-like keys are removed.
    /// A document that already has none is returned unchanged.
    static func stripSecretFields(_ text: String) throws -> String {
        let node = try JSONDocument.requireObject(text)
        let (cleaned, removed) = JSONDocument.removingSecretFields(node)
        if !removed { return text }
        return JSONDocument.render(cleaned) + "\n"
    }

    private static func fromObject(_ node: JSONNode) -> Settings {
        let permission = enumValue(ToolPermission.self, JSONDocument.string(JSONDocument.field(node, "defaultToolPermission")))
            ?? defaultSettings.defaultToolPermission
        let model = parseModel(JSONDocument.field(node, "defaultModel")) ?? defaultSettings.defaultModel
        let theme = enumValue(ThemePreference.self, JSONDocument.string(JSONDocument.field(node, "theme")))
            ?? defaultSettings.theme
        let language = enumValue(Language.self, JSONDocument.string(JSONDocument.field(node, "language")))
            ?? defaultSettings.language
        let sidebar: SidebarOrganization?
        if let value = JSONDocument.field(node, "sidebar"), !JSONDocument.isNull(value) {
            sidebar = parseSidebar(value)
        } else {
            sidebar = nil
        }
        return Settings(
            defaultToolPermission: permission,
            defaultModel: model,
            theme: theme,
            language: language,
            sidebar: sidebar
        )
    }

    private static func parseModel(_ node: JSONNode?) -> ModelRef? {
        guard let provider = enumValue(ProviderId.self, JSONDocument.string(JSONDocument.field(node, "provider"))),
              let model = JSONDocument.string(JSONDocument.field(node, "model")),
              !model.isEmpty
        else { return nil }
        return ModelRef(provider: provider, model: model)
    }

    private static func parseSidebar(_ node: JSONNode?) -> SidebarOrganization? {
        guard case .object = node else { return nil }
        let sectionsNode = JSONDocument.field(node, "sections")
        var sections: [SidebarSection] = []
        if let sectionsNode {
            guard case .array(let items) = sectionsNode else { return nil }
            for item in items {
                guard let id = JSONDocument.string(JSONDocument.field(item, "id")), !id.isEmpty else { return nil }
                guard let name = JSONDocument.string(JSONDocument.field(item, "name"))?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
                let collapsed = if case .bool(let value) = JSONDocument.field(item, "isCollapsed") { value } else { false }
                sections.append(SidebarSection(
                    id: id,
                    name: name,
                    agentIds: JSONDocument.stringList(JSONDocument.field(item, "agentIds")),
                    isCollapsed: collapsed
                ))
            }
        }
        return SidebarOrganization(
            pinnedAgentIds: JSONDocument.stringList(JSONDocument.field(node, "pinnedAgentIds")),
            sections: sections
        )
    }

    private static func encodeSidebar(_ sidebar: SidebarOrganization) -> JSONNode {
        let sections = sidebar.sections.map { section in
            JSONNode.object([
                ("id", .string(section.id)),
                ("name", .string(section.name)),
                ("agentIds", .array(section.agentIds.map { .string($0) })),
                ("isCollapsed", .bool(section.isCollapsed)),
            ])
        }
        return .object([
            ("pinnedAgentIds", .array(sidebar.pinnedAgentIds.map { .string($0) })),
            ("sections", .array(sections)),
        ])
    }

    private static func enumValue<T: RawRepresentable>(_ type: T.Type, _ raw: String?) -> T? where T.RawValue == String {
        guard let raw, !raw.isEmpty else { return nil }
        return T(rawValue: raw)
    }
}
