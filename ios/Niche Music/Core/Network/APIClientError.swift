//
//  APIClientError.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import Foundation

enum APIClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case decodingFailed(Error)
    case network(Error)
    case server(statusCode: Int, payload: APIErrorPayload?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .noData:
            return "No data in API response"
        case .decodingFailed:
            return "Failed to decode API response"
        case .network:
            return "Network request failed"
        case .server(let statusCode, let payload):
            return payload?.message ?? "Request failed with status \(statusCode)"
        }
    }
}
