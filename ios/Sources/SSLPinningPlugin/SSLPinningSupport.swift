import Capacitor
import Foundation
import Security

struct SSLPinningConfiguration {
    let certs: [String]
    let excludedDomains: [String]

    static let empty = SSLPinningConfiguration(certs: [], excludedDomains: [])

    var configured: Bool {
        !certs.isEmpty
    }

    var asJSObject: [String: Any] {
        [
            "configured": configured,
            "certs": certs,
            "excludedDomains": excludedDomains
        ]
    }

    static func from(_ pluginConfig: PluginConfig) -> SSLPinningConfiguration {
        let certs = (pluginConfig.getArray("certs") as? [String]) ?? []
        let excludedDomains = (pluginConfig.getArray("excludedDomains") as? [String]) ?? []
        return SSLPinningConfiguration(certs: certs, excludedDomains: excludedDomains)
    }
}

enum SSLPinningMatcher {
    static func isExcluded(url: URL, excludedDomains: [String]) -> Bool {
        for rawValue in excludedDomains where !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let excludedURL = URL(string: rawValue) else {
                if url.absoluteString.hasPrefix(rawValue) {
                    return true
                }
                continue
            }

            guard excludedURL.scheme?.caseInsensitiveCompare(url.scheme ?? "") == .orderedSame else {
                continue
            }
            guard excludedURL.host?.caseInsensitiveCompare(url.host ?? "") == .orderedSame else {
                continue
            }

            let excludedPort = excludedURL.port ?? excludedURL.defaultPort
            let requestPort = url.port ?? url.defaultPort
            guard excludedPort == requestPort else {
                continue
            }

            let excludedPath = excludedURL.path
            if excludedPath.isEmpty || excludedPath == "/" {
                return true
            }

            if url.path.hasPrefix(excludedPath) {
                return true
            }
        }

        return false
    }
}

final class SSLPinningCertificateStore {
    static let shared = SSLPinningCertificateStore()

    private var cachedPaths: [String] = []
    private var cachedCertificates: [SecCertificate] = []

    private init() {}

    func certificates(for configuredPaths: [String]) throws -> [SecCertificate] {
        if configuredPaths == cachedPaths {
            return cachedCertificates
        }

        let loadedCertificates = try configuredPaths.map(loadCertificate)
        cachedPaths = configuredPaths
        cachedCertificates = loadedCertificates
        return loadedCertificates
    }

    private func loadCertificate(from configuredPath: String) throws -> SecCertificate {
        let fileName = URL(fileURLWithPath: configuredPath).lastPathComponent
        let candidateFileNames = SSLPinningCertificateStore.candidateFileNames(for: fileName)

        guard let certificateData = SSLPinningCertificateStore.loadBundledCertificateData(candidateFileNames: candidateFileNames),
              let certificate = SecCertificateCreateWithData(nil, certificateData as CFData)
        else {
            throw NSError(
                domain: "SSLPinning",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing bundled certificate \(fileName)"]
            )
        }

        return certificate
    }

    private static func candidateFileNames(for fileName: String) -> [String] {
        var candidates = [fileName]
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension.lowercased()
        let base = url.deletingPathExtension().lastPathComponent

        if ext == "cer" {
            candidates.append("\(base).der")
        } else if ext == "der" {
            candidates.append("\(base).cer")
        }

        return candidates
    }

    private static func loadBundledCertificateData(candidateFileNames: [String]) -> Data? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        for fileName in candidateFileNames {
            let candidateURL = resourceURL.appendingPathComponent("public/certs/\(fileName)")
            guard let data = try? Data(contentsOf: candidateURL) else {
                continue
            }

            if let decoded = decodePEMCertificateIfNeeded(data) {
                return decoded
            }

            return data
        }

        return nil
    }

    private static func decodePEMCertificateIfNeeded(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8),
              text.contains("-----BEGIN CERTIFICATE-----")
        else {
            return nil
        }

        let beginMarker = "-----BEGIN CERTIFICATE-----"
        let endMarker = "-----END CERTIFICATE-----"

        guard let beginRange = text.range(of: beginMarker),
              let endRange = text.range(of: endMarker, range: beginRange.upperBound..<text.endIndex)
        else {
            return nil
        }

        let base64Body = text[beginRange.upperBound..<endRange.lowerBound]
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")

        guard let decoded = Data(base64Encoded: String(base64Body), options: [.ignoreUnknownCharacters]),
              !decoded.isEmpty
        else {
            return nil
        }

        return decoded
    }
}

enum SSLPinningTrustEvaluator {
    static func evaluate(
        challenge: URLAuthenticationChallenge,
        configuration: SSLPinningConfiguration
    ) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }

        if let url = url(from: challenge.protectionSpace),
           SSLPinningMatcher.isExcluded(url: url, excludedDomains: configuration.excludedDomains) {
            return (.performDefaultHandling, nil)
        }

        do {
            let certificates = try SSLPinningCertificateStore.shared.certificates(for: configuration.certs)
            SecTrustSetAnchorCertificates(trust, certificates as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)

            var evaluationError: CFError?
            if SecTrustEvaluateWithError(trust, &evaluationError) {
                return (.useCredential, URLCredential(trust: trust))
            }

            return (.cancelAuthenticationChallenge, nil)
        } catch {
            return (.cancelAuthenticationChallenge, nil)
        }
    }

    private static func url(from protectionSpace: URLProtectionSpace) -> URL? {
        guard let host = protectionSpace.host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            return nil
        }
        let scheme = (protectionSpace.protocol ?? "https").lowercased()
        let port = protectionSpace.port > 0 ? ":\(protectionSpace.port)" : ""
        return URL(string: "\(scheme)://\(host)\(port)")
    }
}

final class SSLPinningURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let configuration: SSLPinningConfiguration
    private let disableRedirects: Bool

    init(configuration: SSLPinningConfiguration, disableRedirects: Bool) {
        self.configuration = configuration
        self.disableRedirects = disableRedirects
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let result = SSLPinningTrustEvaluator.evaluate(challenge: challenge, configuration: configuration)
        completionHandler(result.0, result.1)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(disableRedirects ? nil : request)
    }
}

private extension URL {
    var defaultPort: Int? {
        switch scheme?.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }
}

private struct SSLPinningRequestOptions {
    let call: CAPPluginCall
    let configuration: SSLPinningConfiguration
    let config: InstanceConfiguration?
    let httpMethod: String?
    let urlString: String
    let method: String
    let params: [String: Any]
    let responseType: String
    let timeoutMs: Double
    let shouldEncodeUrlParams: Bool
    let dataType: String
    let disableRedirects: Bool
    let headers: [String: Any]

    static func make(
        from payload: NSDictionary
    ) throws -> SSLPinningRequestOptions? {
        guard let call = payload["call"] as? CAPPluginCall else {
            return nil
        }

        let httpMethod = payload["httpMethod"] as? String
        let config = payload["config"] as? InstanceConfiguration
        let configuration = config.map { SSLPinningConfiguration.from($0.getPluginConfig("SSLPinning")) } ?? .empty

        guard configuration.configured else {
            try HttpRequestHandler.request(call, httpMethod, config)
            return nil
        }

        guard var urlString = call.getString("url") else {
            throw URLError(.badURL)
        }
        if urlString == urlString.removingPercentEncoding {
            guard let encodedUrlString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                throw URLError(.badURL)
            }
            urlString = encodedUrlString
        }

        guard let rawURL = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        if SSLPinningMatcher.isExcluded(url: rawURL, excludedDomains: configuration.excludedDomains) {
            try HttpRequestHandler.request(call, httpMethod, config)
            return nil
        }

        var headers = (call.getObject("headers") ?? [:]) as [String: Any]
        if let userAgentString = config?.overridenUserAgentString,
           headers["User-Agent"] == nil,
           headers["user-agent"] == nil {
            headers["User-Agent"] = userAgentString
        }

        return SSLPinningRequestOptions(
            call: call,
            configuration: configuration,
            config: config,
            httpMethod: httpMethod,
            urlString: urlString,
            method: httpMethod ?? call.getString("method", "GET"),
            params: (call.getObject("params") ?? [:]) as [String: Any],
            responseType: call.getString("responseType") ?? "text",
            timeoutMs: call.getDouble("connectTimeout") ?? call.getDouble("readTimeout") ?? 600000.0,
            shouldEncodeUrlParams: call.getBool("shouldEncodeUrlParams", true),
            dataType: call.getString("dataType") ?? "any",
            disableRedirects: call.getBool("disableRedirects") ?? false,
            headers: headers
        )
    }
}

@objc(SSLPinningHttpRequestHandlerClass)
public final class SSLPinningHttpRequestHandlerClass: NSObject {
    @objc public static func request(_ payload: NSDictionary) {
        do {
            guard let options = try SSLPinningRequestOptions.make(from: payload) else {
                return
            }

            let requestBuilder = try buildRequest(options: options)
            let delegate = SSLPinningURLSessionDelegate(configuration: options.configuration, disableRedirects: options.disableRedirects)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: requestBuilder.getUrlRequest()) { data, response, error in
                session.invalidateAndCancel()

                if let error {
                    options.call.reject(error.localizedDescription, (error as NSError).domain, error, nil)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    options.call.reject("Missing HTTP response")
                    return
                }

                HttpRequestHandler.setCookiesFromResponse(httpResponse, options.config)
                let resolvedResponseType = ResponseType(rawValue: options.responseType) ?? .default
                options.call.resolve(HttpRequestHandler.buildResponse(data, httpResponse, responseType: resolvedResponseType))
            }

            task.resume()
        } catch {
            let call = payload["call"] as? CAPPluginCall
            call?.reject(error.localizedDescription, (error as NSError).domain, error, nil)
        }
    }

    private static func buildRequest(options: SSLPinningRequestOptions) throws -> CapacitorUrlRequest {
        let requestBuilder = try HttpRequestHandler.CapacitorHttpRequestBuilder()
            .setUrl(options.urlString)
            .setMethod(options.method)
            .setUrlParams(options.params, options.shouldEncodeUrlParams)
            .openConnection()
            .build()

        requestBuilder.setRequestHeaders(options.headers)
        requestBuilder.setTimeout(options.timeoutMs / 1000.0)

        if let data = options.call.options["data"] as? JSValue {
            try requestBuilder.setRequestBody(data, options.dataType)
        }

        return requestBuilder
    }
}
