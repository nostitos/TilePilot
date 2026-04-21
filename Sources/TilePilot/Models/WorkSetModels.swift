import Foundation

struct WorkSetScopeKey: Codable, Hashable, Sendable, Identifiable {
    let displayID: Int
    let spaceIndex: Int

    var id: String {
        "display-\(displayID)-space-\(spaceIndex)"
    }
}

struct WorkSetMember: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let appName: String
    let windowTitle: String
    let role: String
    let subrole: String
    let lastSeenWindowID: Int?
    let lastSeenPID: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case appName
        case windowTitle
        case role
        case subrole
        case lastSeenWindowID
        case lastSeenPID
    }

    init(
        id: UUID = UUID(),
        appName: String,
        windowTitle: String,
        role: String,
        subrole: String,
        lastSeenWindowID: Int? = nil,
        lastSeenPID: Int? = nil
    ) {
        self.id = id
        self.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.windowTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subrole = subrole.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastSeenWindowID = lastSeenWindowID
        self.lastSeenPID = lastSeenPID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appName = try container.decode(String.self, forKey: .appName).trimmingCharacters(in: .whitespacesAndNewlines)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        subrole = try container.decodeIfPresent(String.self, forKey: .subrole)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lastSeenWindowID = try container.decodeIfPresent(Int.self, forKey: .lastSeenWindowID)
        lastSeenPID = try container.decodeIfPresent(Int.self, forKey: .lastSeenPID)
    }

    init(window: WindowState) {
        self.init(
            appName: window.app,
            windowTitle: window.title,
            role: window.role,
            subrole: window.subrole,
            lastSeenWindowID: window.id,
            lastSeenPID: window.pid
        )
    }

    func with(
        appName: String? = nil,
        windowTitle: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        lastSeenWindowID: Int?? = nil,
        lastSeenPID: Int?? = nil
    ) -> WorkSetMember {
        WorkSetMember(
            id: id,
            appName: appName ?? self.appName,
            windowTitle: windowTitle ?? self.windowTitle,
            role: role ?? self.role,
            subrole: subrole ?? self.subrole,
            lastSeenWindowID: lastSeenWindowID ?? self.lastSeenWindowID,
            lastSeenPID: lastSeenPID ?? self.lastSeenPID
        )
    }
}

struct WorkSet: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let sourceDisplayName: String
    let scopeKey: WorkSetScopeKey
    let members: [WorkSetMember]
    let backdropEnabled: Bool
    let backdropColor: OverlayAccentColor

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceDisplayName
        case scopeKey
        case members
        case backdropEnabled
        case backdropColor
    }

    init(
        id: UUID = UUID(),
        name: String,
        sourceDisplayName: String,
        scopeKey: WorkSetScopeKey,
        members: [WorkSetMember],
        backdropEnabled: Bool = false,
        backdropColor: OverlayAccentColor = .workSetBackdropDefault
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceDisplayName = sourceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scopeKey = scopeKey
        self.members = members
        self.backdropEnabled = backdropEnabled
        self.backdropColor = backdropColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name).trimmingCharacters(in: .whitespacesAndNewlines)
        sourceDisplayName = try container.decodeIfPresent(String.self, forKey: .sourceDisplayName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Current Display"
        scopeKey = try container.decode(WorkSetScopeKey.self, forKey: .scopeKey)
        members = try container.decodeIfPresent([WorkSetMember].self, forKey: .members) ?? []
        backdropEnabled = try container.decodeIfPresent(Bool.self, forKey: .backdropEnabled) ?? false
        backdropColor = try container.decodeIfPresent(OverlayAccentColor.self, forKey: .backdropColor) ?? .workSetBackdropDefault
    }

    func with(
        name: String? = nil,
        sourceDisplayName: String? = nil,
        scopeKey: WorkSetScopeKey? = nil,
        members: [WorkSetMember]? = nil,
        backdropEnabled: Bool? = nil,
        backdropColor: OverlayAccentColor? = nil
    ) -> WorkSet {
        WorkSet(
            id: id,
            name: name ?? self.name,
            sourceDisplayName: sourceDisplayName ?? self.sourceDisplayName,
            scopeKey: scopeKey ?? self.scopeKey,
            members: members ?? self.members,
            backdropEnabled: backdropEnabled ?? self.backdropEnabled,
            backdropColor: backdropColor ?? self.backdropColor
        )
    }
}

struct WorkSetBackdropPresentation: Equatable, Sendable {
    let workSetID: UUID
    let scopeKey: WorkSetScopeKey
    let display: DisplayState
    let color: OverlayAccentColor
    let anchorWindow: WindowState?
}

enum WorkSetMemberMatchStatus: String, Sendable {
    case exact
    case sameApp
    case missing

    var label: String {
        switch self {
        case .exact:
            return "Exact"
        case .sameApp:
            return "Same App"
        case .missing:
            return "Missing"
        }
    }
}

struct WorkSetResolvedMember: Identifiable, Sendable {
    let member: WorkSetMember
    let matchedWindow: WindowState?
    let status: WorkSetMemberMatchStatus

    var id: UUID { member.id }
}

enum WorkSetDropPayload: Sendable {
    case member(sourceWorkSetID: UUID, memberID: UUID)
    case window(WorkSetMember)
}

func nextWorkSetToCycle(in workSets: [WorkSet], activeWorkSetID: UUID?) -> WorkSet? {
    guard !workSets.isEmpty else { return nil }
    guard let activeWorkSetID,
          let activeIndex = workSets.firstIndex(where: { $0.id == activeWorkSetID }) else {
        return workSets.first
    }
    let nextIndex = (activeIndex + 1) % workSets.count
    return workSets[nextIndex]
}

func resolveWorkSetMembers(_ members: [WorkSetMember], in windows: [WindowState]) -> [WorkSetResolvedMember] {
    var usedWindowIDs = Set<Int>()
    var resolved: [WorkSetResolvedMember] = []

    for member in members {
        if let exactMatch = windows.first(where: { window in
            !usedWindowIDs.contains(window.id) && workSetMember(member, exactlyMatches: window)
        }) {
            usedWindowIDs.insert(exactMatch.id)
            resolved.append(WorkSetResolvedMember(member: member, matchedWindow: exactMatch, status: .exact))
            continue
        }

        if let titleRoleMatch = windows.first(where: { window in
            !usedWindowIDs.contains(window.id) && workSetMember(member, titleRoleMatches: window)
        }) {
            usedWindowIDs.insert(titleRoleMatch.id)
            resolved.append(WorkSetResolvedMember(member: member, matchedWindow: titleRoleMatch, status: .sameApp))
            continue
        }

        if let sameAppMatch = windows.first(where: { window in
            !usedWindowIDs.contains(window.id) && workSetMember(member, appMatches: window)
        }) {
            usedWindowIDs.insert(sameAppMatch.id)
            resolved.append(WorkSetResolvedMember(member: member, matchedWindow: sameAppMatch, status: .sameApp))
            continue
        }

        resolved.append(WorkSetResolvedMember(member: member, matchedWindow: nil, status: .missing))
    }

    return resolved
}

private func workSetMember(_ member: WorkSetMember, appMatches window: WindowState) -> Bool {
    normalizedAppRuleKey(member.appName) == normalizedAppRuleKey(window.app)
}

private func workSetMember(_ member: WorkSetMember, exactlyMatches window: WindowState) -> Bool {
    guard let lastSeenWindowID = member.lastSeenWindowID,
          let lastSeenPID = member.lastSeenPID else {
        return false
    }
    return window.id == lastSeenWindowID && window.pid == lastSeenPID
}

private func workSetMember(_ member: WorkSetMember, titleRoleMatches window: WindowState) -> Bool {
    guard workSetMember(member, appMatches: window) else { return false }
    return normalizedWorkSetMetadata(member.windowTitle) == normalizedWorkSetMetadata(window.title)
        && normalizedWorkSetMetadata(member.role) == normalizedWorkSetMetadata(window.role)
        && normalizedWorkSetMetadata(member.subrole) == normalizedWorkSetMetadata(window.subrole)
}

private func normalizedWorkSetMetadata(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
}
