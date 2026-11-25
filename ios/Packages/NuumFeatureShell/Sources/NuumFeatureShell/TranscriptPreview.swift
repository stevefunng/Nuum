import NuumContracts

func sidebarPreview(of event: TranscriptEvent) -> String? {
    switch event {
    case .user(let event):
        return nonEmpty(event.text)
    case .assistant(let event):
        let text = event.parts.compactMap { part -> String? in
            if case .text(let text) = part { return text.text }
            return nil
        }.last
        return text.flatMap(nonEmpty)
    case .message(let event):
        switch event.payload {
        case .text(let payload):
            return nonEmpty(payload.content)
        case .attachment(let payload):
            return payload.caption.flatMap(nonEmpty)
        case .widget, .legacyWidget:
            return nil
        }
    case .wake(let event):
        return nonEmpty(event.text)
    case .tool, .compact, .profile:
        return nil
    }
}

private func nonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
