//
//  APIEnvelope.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let result: T?
    let error: APIErrorPayload?
    let metadata: APIMetadata?
}

struct APIErrorPayload: Decodable {
    let code: String?
    let message: String?
    let details: AnyDecodable?
}

struct APIMetadata: Decodable {
    let apiVersion: String?
    let pagination: PaginationMetadata?
}

struct PaginationMetadata: Decodable {
    let nextCursor: String?
    let limit: Int?
    let hasMore: Bool?
}

struct EmptyAPIResult: Decodable {}

struct AnyDecodable: Decodable {}
