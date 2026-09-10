import Foundation

struct ChatResponse: Decodable {
    var reply: String?
    var audio: String?
    var error: String?
}

struct ImageResponse: Decodable {
    var image: String?
    var error: String?
}

struct VoicesResponse: Decodable {
    struct V: Decodable { var id: String; var name: String }
    var voices: [V]
    var `default`: String?
}

struct ModelsResponse: Decodable { var models: [String] }

final class JarvisAPI {
    var base: String

    init(base: String) { self.base = base }

    private func url(_ path: String) -> URL? {
        URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any],
                                    timeout: TimeInterval = 180) async throws -> T {
        guard let u = url(path) else { throw URLError(.badURL) }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func models() async throws -> [String] {
        guard let u = url("/api/models") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: u)
        return try JSONDecoder().decode(ModelsResponse.self, from: data).models
    }

    func voices() async throws -> VoicesResponse {
        guard let u = url("/api/voices") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: u)
        return try JSONDecoder().decode(VoicesResponse.self, from: data)
    }

    func chat(text: String, model: String?, voice: String, speed: Double,
              key: String) async throws -> ChatResponse {
        try await post("/api/chat", body: [
            "text": text, "model": model ?? "", "voice": voice,
            "speed": speed, "key": key, "images": [] as [String],
        ])
    }

    func image(prompt: String) async throws -> ImageResponse {
        try await post("/api/image", body: ["prompt": prompt], timeout: 400)
    }
}
