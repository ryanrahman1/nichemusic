//
//  ReportModels.swift
//  Niche Music
//

import Foundation

enum ReportTargetType: String, Encodable {
    case user
    case post
    case comment
    case message
    case group
    case track
    case album
    case artist
    case other
}

struct CreateReportBody: Encodable {
    let targetType: String
    let targetId: String
    let reason: String
    let reportedUserId: String?
    let content: [String: String]

    init(
        targetType: ReportTargetType,
        targetId: String,
        reason: String,
        reportedUserId: String? = nil,
        content: [String: String] = [:]
    ) {
        self.targetType = targetType.rawValue
        self.targetId = targetId
        self.reason = reason
        self.reportedUserId = reportedUserId
        self.content = content
    }
}

struct CreateReportResponse: Decodable {
    let report: ReportRow?
}

struct ReportRow: Decodable {
    let id: String?
}

enum ReportsService {
    static func submit(
        targetType: ReportTargetType,
        targetId: String,
        message: String,
        reportedUserId: String? = nil,
        content: [String: String] = [:]
    ) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let reason = String(trimmed.prefix(2000))

        let _: CreateReportResponse = try await APIClient.shared.request(
            Endpoints.createReport,
            method: .post,
            body: CreateReportBody(
                targetType: targetType,
                targetId: targetId,
                reason: reason,
                reportedUserId: reportedUserId,
                content: content
            ),
            preserveBodyKeyNames: true
        )
    }
}
