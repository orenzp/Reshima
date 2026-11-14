import Foundation

/// The user-editable columns of `list_items`. Only changed fields are sent to the server,
/// so two phones editing different fields of the same item do not overwrite each other.
public enum ItemField: String, Codable, CaseIterable, Hashable, Sendable {
    case categoryId
    case name
    case quantity
    case unit
    case notes
    case photoPath
    case isChecked
}

public extension ListItem {
    /// Fields whose value differs from `old`.
    func changedFields(from old: ListItem) -> Set<ItemField> {
        var fields: Set<ItemField> = []
        if categoryId != old.categoryId { fields.insert(.categoryId) }
        if name != old.name { fields.insert(.name) }
        if quantity != old.quantity { fields.insert(.quantity) }
        if unit != old.unit { fields.insert(.unit) }
        if notes != old.notes { fields.insert(.notes) }
        if photoPath != old.photoPath { fields.insert(.photoPath) }
        if isChecked != old.isChecked { fields.insert(.isChecked) }
        return fields
    }
}

/// Body of a partial update (HTTP PATCH): encodes only the listed fields, with explicit `null`s.
public struct ItemPatch: Encodable, Sendable {
    public let item: ListItem
    public let fields: Set<ItemField>

    public init(item: ListItem, fields: Set<ItemField>) {
        self.item = item
        self.fields = fields
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ListItem.CodingKeys.self)
        for field in fields {
            switch field {
            case .categoryId: try container.encode(item.categoryId, forKey: .categoryId)
            case .name: try container.encode(item.name, forKey: .name)
            case .quantity: try container.encode(item.quantity, forKey: .quantity)
            case .unit: try container.encode(item.unit, forKey: .unit)
            case .notes: try container.encode(item.notes, forKey: .notes)
            case .photoPath: try container.encode(item.photoPath, forKey: .photoPath)
            case .isChecked: try container.encode(item.isChecked, forKey: .isChecked)
            }
        }
    }
}

/// One not-yet-confirmed local change to a list item. Values are read from the local item at send time;
/// the queue only remembers *what* changed.
public struct PendingItemChange: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case insert
        case update
        case delete
    }

    public var itemId: UUID
    public var kind: Kind
    public var fields: Set<ItemField>
    /// Bumped whenever the change is modified, so a send that started earlier cannot confirm newer edits.
    public var revision: Int
    /// Number of send attempts started. Greater than zero means the server may already have seen it.
    public var attempts: Int
    /// Times the server refused this change (as opposed to the network failing).
    public var rejections: Int

    public init(itemId: UUID, kind: Kind, fields: Set<ItemField> = [], revision: Int = 0, attempts: Int = 0, rejections: Int = 0) {
        self.itemId = itemId
        self.kind = kind
        self.fields = fields
        self.revision = revision
        self.attempts = attempts
        self.rejections = rejections
    }
}

/// A not-yet-confirmed change to a catalog (autocomplete) entry, keyed by normalized name.
public struct PendingCatalogChange: Codable, Equatable, Sendable {
    /// How many times the product was added since the last successful sync.
    public var usageDelta: Int
    public var revision: Int

    public init(usageDelta: Int = 0, revision: Int = 0) {
        self.usageDelta = usageDelta
        self.revision = revision
    }
}

/// Ordered outbox of local item changes, at most one entry per item. Persisted so offline edits survive restarts.
public struct PendingItemQueue: Codable, Equatable, Sendable {
    public private(set) var changes: [PendingItemChange] = []

    public init() {}

    public var isEmpty: Bool { changes.isEmpty }
    public var count: Int { changes.count }

    public func change(for itemId: UUID) -> PendingItemChange? {
        changes.first { $0.itemId == itemId }
    }

    public mutating func recordInsert(_ itemId: UUID) {
        if let index = index(of: itemId) {
            changes[index].kind = .insert
            changes[index].revision += 1
        } else {
            changes.append(PendingItemChange(itemId: itemId, kind: .insert))
        }
    }

    public mutating func recordUpdate(_ itemId: UUID, fields: Set<ItemField>) {
        guard !fields.isEmpty else { return }
        if let index = index(of: itemId) {
            switch changes[index].kind {
            case .insert:
                changes[index].revision += 1 // the whole item is re-sent anyway
            case .update:
                changes[index].fields.formUnion(fields)
                changes[index].revision += 1
            case .delete:
                break // deleted locally; nothing to update
            }
        } else {
            changes.append(PendingItemChange(itemId: itemId, kind: .update, fields: fields))
        }
    }

    public mutating func recordDelete(_ itemId: UUID) {
        if let index = index(of: itemId) {
            if changes[index].kind == .insert && changes[index].attempts == 0 {
                // Never left the phone: nothing to delete on the server.
                changes.remove(at: index)
            } else {
                changes[index].kind = .delete
                changes[index].fields = []
                changes[index].revision += 1
            }
        } else {
            changes.append(PendingItemChange(itemId: itemId, kind: .delete))
        }
    }

    /// Call right before sending. Returns the snapshot to pass to `confirm` afterwards.
    public mutating func beginAttempt(_ itemId: UUID) -> PendingItemChange? {
        guard let index = index(of: itemId) else { return nil }
        changes[index].attempts += 1
        return changes[index]
    }

    /// Removes the change after the server accepted `sent`, unless it was modified while in flight.
    public mutating func confirm(_ sent: PendingItemChange) {
        guard let index = index(of: sent.itemId) else { return }
        if changes[index].revision == sent.revision {
            changes.remove(at: index)
        }
    }

    /// Call when the server refused the change. Gives up (returns true) after `maxRejections`,
    /// so one bad change cannot block the outbox forever.
    @discardableResult
    public mutating func recordRejection(_ itemId: UUID, maxRejections: Int = SyncMerge.maxRejectedAttempts) -> Bool {
        guard let index = index(of: itemId) else { return true }
        changes[index].rejections += 1
        if changes[index].rejections >= maxRejections {
            changes.remove(at: index)
            return true
        }
        return false
    }

    public mutating func drop(_ itemId: UUID) {
        changes.removeAll { $0.itemId == itemId }
    }

    private func index(of itemId: UUID) -> Int? {
        changes.firstIndex { $0.itemId == itemId }
    }
}

public enum SyncMerge {
    /// Maximum times a change rejected by the server (not a network failure) is retried before being discarded.
    public static let maxRejectedAttempts = 5

    /// Combines a fresh server snapshot with local state: the server wins, except where a local change is still pending.
    public static func mergeItems(remote: [ListItem], local: [ListItem], pending: PendingItemQueue) -> [ListItem] {
        let localById = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var remoteIds = Set<UUID>()
        var result: [ListItem] = []

        for remoteItem in remote {
            guard remoteIds.insert(remoteItem.id).inserted else { continue }
            guard let change = pending.change(for: remoteItem.id) else {
                result.append(remoteItem)
                continue
            }
            switch change.kind {
            case .delete:
                continue
            case .insert:
                result.append(localById[remoteItem.id] ?? remoteItem)
            case .update:
                if let localItem = localById[remoteItem.id] {
                    result.append(overlay(remote: remoteItem, local: localItem, fields: change.fields))
                } else {
                    result.append(remoteItem)
                }
            }
        }

        // Items created locally that the server has not seen yet.
        for change in pending.changes where change.kind == .insert && !remoteIds.contains(change.itemId) {
            if let localItem = localById[change.itemId] {
                result.append(localItem)
            }
        }
        return result
    }

    /// The server row with the locally edited `fields` applied on top.
    public static func overlay(remote: ListItem, local: ListItem, fields: Set<ItemField>) -> ListItem {
        var merged = remote
        for field in fields {
            switch field {
            case .categoryId: merged.categoryId = local.categoryId
            case .name: merged.name = local.name
            case .quantity: merged.quantity = local.quantity
            case .unit: merged.unit = local.unit
            case .notes: merged.notes = local.notes
            case .photoPath: merged.photoPath = local.photoPath
            case .isChecked:
                merged.isChecked = local.isChecked
                merged.checkedAt = local.checkedAt
            }
        }
        return merged
    }

    /// Drops pending updates for items that were deleted on the server (the delete wins).
    public static func pruneOrphanedUpdates(_ pending: inout PendingItemQueue, remote: [ListItem]) {
        let remoteIds = Set(remote.map(\.id))
        for change in pending.changes where change.kind == .update && !remoteIds.contains(change.itemId) {
            pending.drop(change.itemId)
        }
    }

    /// Server catalog wins, except entries (keyed by normalized name) with a pending local change.
    public static func mergeCatalog(remote: [CatalogItem], local: [CatalogItem], pendingNames: Set<String>) -> [CatalogItem] {
        guard !pendingNames.isEmpty else { return remote }
        let localByName = Dictionary(local.map { ($0.normalizedName, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [CatalogItem] = []
        for remoteItem in remote {
            seen.insert(remoteItem.normalizedName)
            if pendingNames.contains(remoteItem.normalizedName), let localItem = localByName[remoteItem.normalizedName] {
                result.append(localItem)
            } else {
                result.append(remoteItem)
            }
        }
        for name in pendingNames.sorted() where !seen.contains(name) {
            if let localItem = localByName[name] {
                result.append(localItem)
            }
        }
        return result
    }

    /// Maps ids of categories that disappear in `new` to the category of the same `kind` in `new`.
    /// Needed when locally seeded aisles (random ids) are replaced by the household's real ones.
    public static func categoryIdRemap(old: [Category], new: [Category]) -> [UUID: UUID] {
        let newIds = Set(new.map(\.id))
        var newIdByKind: [String: UUID] = [:]
        for category in new {
            if let kind = category.kind, newIdByKind[kind] == nil {
                newIdByKind[kind] = category.id
            }
        }
        var remap: [UUID: UUID] = [:]
        for category in old where !newIds.contains(category.id) {
            if let kind = category.kind, let replacement = newIdByKind[kind] {
                remap[category.id] = replacement
            }
        }
        return remap
    }
}
