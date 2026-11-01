//
//  APIClient.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//

import Foundation

final class APIClient {
    static let shared = APIClient()

    var onEmailNotVerified: (@MainActor (String?) -> Void)?

    private static let queryParameterAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return allowed
    }()

    private var baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let camelCaseBodyEncoder = JSONEncoder()

    init(
        baseURL: URL = URL(string: "https://prefashioned-overtimorously-shay.ngrok-free.dev")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func setBaseURL(_ url: URL) {
        self.baseURL = url
    }

    var websocketURL: URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if components.scheme == "https" {
            components.scheme = "wss"
        } else if components.scheme == "http" {
            components.scheme = "ws"
        }
        components.path = "/ws"
        components.query = nil
        return components.url
    }

    var auxWebSocketURL: URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if components.scheme == "https" {
            components.scheme = "wss"
        } else if components.scheme == "http" {
            components.scheme = "ws"
        }
        components.path = "/ws/aux"
        components.query = nil
        return components.url
    }

    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        method: HTTPMethod = .get,
        query: [String: String?] = [:],
        body: Encodable? = nil,
        headers: [String: String] = [:],
        preserveBodyKeyNames: Bool = false
    ) async throws -> T {
        let request = try buildRequest(
            endpoint,
            method: method,
            query: query,
            body: body,
            headers: headers,
            preserveBodyKeyNames: preserveBodyKeyNames
        )

        let data: Data
        let response: URLResponse
        let startedAt = Date()
        APILogger.request(request, body: request.httpBody)

        do {
            (data, response) = try await session.data(for: request)
            APILogger.response(response, data: data, duration: Date().timeIntervalSince(startedAt))
        } catch {
            APILogger.error(request, error: error, duration: Date().timeIntervalSince(startedAt))
            throw APIClientError.network(error)
        }

        return try handleResponse(data: data, response: response)
    }

    func requestWithMetadata<T: Decodable>(
        _ endpoint: APIEndpoint,
        method: HTTPMethod = .get,
        query: [String: String?] = [:],
        body: Encodable? = nil,
        headers: [String: String] = [:]
    ) async throws -> (result: T, metadata: APIMetadata?) {
        let request = try buildRequest(
            endpoint,
            method: method,
            query: query,
            body: body,
            headers: headers
        )

        let data: Data
        let response: URLResponse
        let startedAt = Date()
        APILogger.request(request, body: request.httpBody)

        do {
            (data, response) = try await session.data(for: request)
            APILogger.response(response, data: data, duration: Date().timeIntervalSince(startedAt))
        } catch {
            APILogger.error(request, error: error, duration: Date().timeIntervalSince(startedAt))
            throw APIClientError.network(error)
        }

        return try handleResponseWithMetadata(data: data, response: response)
    }

    func requestVoid(
        _ endpoint: APIEndpoint,
        method: HTTPMethod = .post,
        query: [String: String?] = [:],
        body: Encodable? = nil,
        headers: [String: String] = [:],
        preserveBodyKeyNames: Bool = false
    ) async throws {
        let _: EmptyAPIResult = try await request(
            endpoint,
            method: method,
            query: query,
            body: body,
            headers: headers,
            preserveBodyKeyNames: preserveBodyKeyNames
        )
    }

    private func buildRequest(
        _ endpoint: APIEndpoint,
        method: HTTPMethod,
        query: [String: String?],
        body: Encodable?,
        headers: [String: String],
        preserveBodyKeyNames: Bool = false
    ) throws -> URLRequest {
        let cleanPath = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = baseURL.appending(path: cleanPath)

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidURL
        }

        let queryItems = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            let encodedName = key.addingPercentEncoding(withAllowedCharacters: Self.queryParameterAllowedCharacters) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: Self.queryParameterAllowedCharacters) ?? value
            return URLQueryItem(name: encodedName, value: encodedValue)
        }

        if !queryItems.isEmpty {
            components.percentEncodedQueryItems = queryItems
        }

        guard let finalURL = components.url else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encodeBody(body, preserveKeyNames: preserveBodyKeyNames)
        }

        return request
    }

    private func encodeBody(_ body: Encodable, preserveKeyNames: Bool = false) throws -> Data {
        do {
            let selectedEncoder = preserveKeyNames ? camelCaseBodyEncoder : self.encoder
            return try selectedEncoder.encode(AnyEncodable(body))
        } catch {
            throw APIClientError.network(error)
        }
    }

    private func handleResponse<T: Decodable>(
        data: Data,
        response: URLResponse
    ) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        let envelope = try decodeEnvelope(T.self, from: data, statusCode: http.statusCode)

        if (200...299).contains(http.statusCode) {
            if envelope.success {
                if let result = envelope.result {
                    return result
                }

                if T.self == EmptyAPIResult.self {
                    return EmptyAPIResult() as! T
                }

                throw APIClientError.noData
            }

            throw APIClientError.noData
        }

        notifyEmailNotVerifiedIfNeeded(statusCode: http.statusCode, payload: envelope.error)
        throw APIClientError.server(statusCode: http.statusCode, payload: envelope.error)
    }

    private func handleResponseWithMetadata<T: Decodable>(
        data: Data,
        response: URLResponse
    ) throws -> (result: T, metadata: APIMetadata?) {
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        let envelope = try decodeEnvelope(T.self, from: data, statusCode: http.statusCode)

        if (200...299).contains(http.statusCode) {
            if envelope.success {
                if let result = envelope.result {
                    return (result, envelope.metadata)
                }

                if T.self == EmptyAPIResult.self {
                    return (EmptyAPIResult() as! T, envelope.metadata)
                }

                throw APIClientError.noData
            }

            throw APIClientError.noData
        }

        notifyEmailNotVerifiedIfNeeded(statusCode: http.statusCode, payload: envelope.error)
        throw APIClientError.server(statusCode: http.statusCode, payload: envelope.error)
    }

    private func decodeEnvelope<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        statusCode: Int
    ) throws -> APIEnvelope<T> {
        if data.isEmpty {
            if (200...299).contains(statusCode) {
                return APIEnvelope(success: true, result: EmptyAPIResult() as? T, error: nil, metadata: nil)
            }

            return APIEnvelope(success: false, result: nil, error: nil, metadata: nil)
        }

        do {
            return try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            if (200...299).contains(statusCode) {
                throw APIClientError.decodingFailed(error)
            }

            return APIEnvelope(success: false, result: nil, error: nil, metadata: nil)
        }
    }

    private func notifyEmailNotVerifiedIfNeeded(statusCode: Int, payload: APIErrorPayload?) {
        guard statusCode == 403, payload?.code == "EMAIL_NOT_VERIFIED" else { return }
        Task { @MainActor in
            self.onEmailNotVerified?(nil)
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
