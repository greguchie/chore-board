import Foundation
import SwiftData

// Offline copies of API data. These are a separate layer from the API
// models, so networking code never depends on persistence.

@Model
final class CachedBoard {
    var serverId: UUID
    var name: String
    var details: String?
    var ownerId: UUID
    var role: String
    var createdAt: Date
    var updatedAt: Date
    var position: Int

    init(_ board: Board, position: Int) {
        serverId = board.id
        name = board.name
        details = board.description
        ownerId = board.ownerId
        role = board.myRole.rawValue
        createdAt = board.createdAt
        updatedAt = board.updatedAt
        self.position = position
    }

    var board: Board? {
        guard let myRole = BoardRole(rawValue: role) else { return nil }
        return Board(id: serverId, name: name, description: details, ownerId: ownerId,
                     createdAt: createdAt, updatedAt: updatedAt, myRole: myRole)
    }
}

@Model
final class CachedTask {
    var serverId: UUID
    var boardId: UUID
    var title: String
    var details: String?
    var status: String
    var assigneeId: UUID?
    var dueDate: String?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var position: Int

    init(_ task: BoardTask, boardId: UUID, position: Int) {
        serverId = task.id
        self.boardId = boardId   // the board we're caching for decides where it's filed
        title = task.title
        details = task.description
        status = task.status.rawValue
        assigneeId = task.assigneeId
        dueDate = task.dueDate
        completedAt = task.completedAt
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        self.position = position
    }

    var task: BoardTask? {
        guard let taskStatus = TaskStatus(rawValue: status) else { return nil }
        return BoardTask(id: serverId, boardId: boardId, title: title, description: details,
                         status: taskStatus, assigneeId: assigneeId, dueDate: dueDate,
                         completedAt: completedAt, createdAt: createdAt, updatedAt: updatedAt)
    }
}

@Model
final class CachedMember {
    var serverId: UUID
    var boardId: UUID
    var userId: UUID
    var role: String
    var joinedAt: Date
    var displayName: String?
    var email: String?
    var position: Int

    init(_ member: Member, boardId: UUID, position: Int) {
        serverId = member.id
        self.boardId = boardId
        userId = member.userId
        role = member.role.rawValue
        joinedAt = member.joinedAt
        displayName = member.displayName
        email = member.email
        self.position = position
    }

    var member: Member? {
        guard let memberRole = BoardRole(rawValue: role) else { return nil }
        return Member(id: serverId, userId: userId, role: memberRole, joinedAt: joinedAt,
                      displayName: displayName, email: email)
    }
}

/// When each piece of data was last saved. Also lets an empty list
/// count as "cached" (zero boards) rather than "never loaded".
@Model
final class CacheStamp {
    var key: String
    var savedAt: Date

    init(key: String, savedAt: Date) {
        self.key = key
        self.savedAt = savedAt
    }
}
