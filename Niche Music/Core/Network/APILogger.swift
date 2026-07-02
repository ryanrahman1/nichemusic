//
//  APILogger.swift
//  nichemusic
//
//  Created by Ryan Rahman on 4/25/26.
//


import Foundation

enum APILogger {
    static var isEnabled = true
    static var logsResponses = true

    static func request(_ request: URLRequest, body: Data?) {
        guard isEnabled else { return }

        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "Invalid URL"

        print("""
        
        ┌──────── API REQUEST ────────
        │ \(method) \(url)
        └─────────────────────────────
        """)

        if let body, let pretty = prettyJSON(body) {
            print("""
            Body:
            \(pretty)
            """)
        }
    }

    static func response(_ response: URLResponse, data: Data, duration: TimeInterval) {
        guard isEnabled else { return }
        guard let http = response as? HTTPURLResponse else {
            print("API RESPONSE: Invalid response")
            return
        }

        let status = http.statusCode
        let emoji = (200...299).contains(status) ? "✅" : "❌"
        let timeMs = Int(duration * 1000)

        print("""
        
        ┌──────── API RESPONSE ───────
        │ \(emoji) \(status) • \(timeMs)ms
        └─────────────────────────────
        """)

        guard logsResponses else { return }

        if let pretty = prettyJSON(data) {
            print("""
            Response:
            \(pretty)
            """)
        } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            print("""
            Response:
            \(text)
            """)
        }
    }

    static func error(_ request: URLRequest, error: Error, duration: TimeInterval? = nil) {
        guard isEnabled else { return }

        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "Invalid URL"
        let time = duration.map { " • \(Int($0 * 1000))ms" } ?? ""

        print("""
        
        ┌──────── API ERROR ──────────
        │ ❌ \(method) \(url)\(time)
        │ \(error.localizedDescription)
        └─────────────────────────────
        """)
    }

    private static func prettyJSON(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            )

            return String(data: prettyData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
