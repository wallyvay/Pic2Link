import Foundation
import CryptoKit
import Combine
import ImageIO
import UniformTypeIdentifiers

struct ImageFormatMetadata: Equatable {
    let filenameExtension: String
    let mimeType: String
}

enum ImageFormatResolver {
    static func metadata(for data: Data) -> ImageFormatMetadata {
        let contentType = detectedContentType(for: data) ?? .png
        return ImageFormatMetadata(
            filenameExtension: contentType.preferredFilenameExtension ?? "png",
            mimeType: contentType.preferredMIMEType ?? "image/png"
        )
    }

    private static func detectedContentType(for data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) else {
            return nil
        }
        return UTType(typeIdentifier as String)
    }
}

struct UploadProgress: Equatable {
    let completedBytes: Int64
    let totalBytes: Int64

    static let zero = UploadProgress(completedBytes: 0, totalBytes: 0)

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }

    var percentage: Int {
        Int((fractionCompleted * 100).rounded(.down))
    }

    var byteCountDescription: String {
        guard totalBytes > 0 else { return "" }
        let completed = ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(completed) / \(total)"
    }
}

/// 统一图床上传服务
class ImageHostingService: ObservableObject {
    @Published var isUploading = false
    @Published private(set) var uploadProgress = UploadProgress.zero

    private var config: ImageHostProfile
    private let urlSession: URLSession

    init(config: ImageHostProfile, urlSession: URLSession? = nil) {
        self.config = config

        let configuration = URLSessionConfiguration.default
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300

        self.urlSession = urlSession ?? URLSession(configuration: configuration)
    }

    func updateConfig(_ newConfig: ImageHostProfile) {
        self.config = newConfig
    }

    func validateConfig() async throws -> Bool {
        guard config.isConfigured else { return false }

        switch config.provider {
        case .alibabaOSS:
            return try await validateOSSConfig()
        case .synologyC2, .jdCloud, .baiduBOS, .amazonS3, .googleCloudStorage, .cloudflareR2, .backblazeB2, .genericS3Compatible, .tencentCOS:
            return try await validateS3CompatibleConfig()
        case .webDAV:
            return try await validateWebDAVConfig()
        case .imgur:
            return true
        case .qiniu, .upyun, .flickr:
            return true
        }
    }

    func uploadImage(_ imageData: Data, fileName: String? = nil) async throws -> String {
        let resolvedFileName: String
        let resolvedMimeType: String

        if let fileName {
            resolvedFileName = fileName
            resolvedMimeType = inferredMimeType(fileName: fileName)
        } else {
            let metadata = ImageFormatResolver.metadata(for: imageData)
            resolvedFileName = generateFileName(from: imageData, fileExtension: metadata.filenameExtension)
            resolvedMimeType = metadata.mimeType
        }

        return try await uploadFile(
            imageData,
            fileName: resolvedFileName,
            mimeType: resolvedMimeType
        )
    }

    func uploadFile(_ fileData: Data, fileName: String, mimeType: String) async throws -> String {
        isUploading = true
        uploadProgress = .zero

        defer {
            isUploading = false
        }

        guard config.provider.supportsArbitraryFiles || mimeType.hasPrefix("image/") else {
            throw UploadServiceError.unsupportedFileType(provider: config.provider.displayName, summary: config.provider.supportedFileSummary)
        }

        let objectKey = generateObjectKey(fileName: fileName)

        switch config.provider {
        case .alibabaOSS:
            return try await uploadToOSS(fileData, fileName: fileName, objectKey: objectKey, mimeType: mimeType)
        case .synologyC2, .jdCloud, .baiduBOS, .tencentCOS, .amazonS3, .googleCloudStorage, .cloudflareR2, .backblazeB2, .genericS3Compatible:
            return try await uploadToS3Compatible(fileData, fileName: fileName, objectKey: objectKey, mimeType: mimeType)
        case .qiniu:
            return try await uploadToQiniu(fileData, fileName: fileName, objectKey: objectKey, mimeType: mimeType)
        case .upyun:
            return try await uploadToUpyun(fileData, fileName: fileName, objectKey: objectKey, mimeType: mimeType)
        case .webDAV:
            return try await uploadToWebDAV(fileData, fileName: fileName, objectKey: objectKey, mimeType: mimeType)
        case .imgur:
            guard mimeType.hasPrefix("image/") else {
                throw UploadServiceError.unsupportedFileType(provider: config.provider.displayName, summary: config.provider.supportedFileSummary)
            }
            return try await uploadToImgur(fileData, fileName: fileName, mimeType: mimeType)
        case .flickr:
            guard mimeType.hasPrefix("image/") else {
                throw UploadServiceError.unsupportedFileType(provider: config.provider.displayName, summary: config.provider.supportedFileSummary)
            }
            return try await uploadToFlickr(fileData, fileName: fileName, mimeType: mimeType)
        }
    }

    private func validateOSSConfig() async throws -> Bool {
        let dateString = rfc1123Date()
        let stringToSign = "GET\n\n\n\(dateString)\n/\(config.bucketName)/"
        let signature = hmacSHA1Base64(string: stringToSign, key: config.secretKey)

        var request = URLRequest(url: URL(string: "https://\(config.bucketName).\(normalizedHost(config.endpoint))/?max-keys=1")!)
        request.httpMethod = "GET"
        request.setValue("OSS \(config.accessKey):\(signature)", forHTTPHeaderField: "Authorization")
        request.setValue(dateString, forHTTPHeaderField: "Date")

        let (_, response) = try await urlSession.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func uploadToOSS(_ fileData: Data, fileName: String, objectKey: String, mimeType: String) async throws -> String {
        let contentMD5 = md5Base64(data: fileData)
        let contentType = mimeType
        let dateString = rfc1123Date()
        let stringToSign = "PUT\n\(contentMD5)\n\(contentType)\n\(dateString)\n/\(config.bucketName)/\(objectKey)"
        let signature = hmacSHA1Base64(string: stringToSign, key: config.secretKey)

        var request = URLRequest(url: URL(string: "https://\(config.bucketName).\(normalizedHost(config.endpoint))/\(escapedPath(objectKey))")!)
        request.httpMethod = "PUT"
        request.setValue("OSS \(config.accessKey):\(signature)", forHTTPHeaderField: "Authorization")
        request.setValue(dateString, forHTTPHeaderField: "Date")
        request.setValue(contentMD5, forHTTPHeaderField: "Content-MD5")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await uploadWithProgress(request: request, bodyData: fileData)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? L10n.tr("error.unknownServer")
            throw UploadServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return makePublicURL(for: objectKey)
    }

    private func validateS3CompatibleConfig() async throws -> Bool {
        let request = try makeS3SignedRequest(method: "HEAD", objectKey: nil, body: Data(), contentType: nil)
        let (_, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (200...399).contains(statusCode)
    }

    private func uploadToS3Compatible(_ fileData: Data, fileName: String, objectKey: String, mimeType: String) async throws -> String {
        let request = try makeS3SignedRequest(method: "PUT", objectKey: objectKey, body: fileData, contentType: mimeType)
        let (data, response) = try await uploadWithProgress(request: request, bodyData: fileData)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? L10n.tr("error.unknownServer")
            throw UploadServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return makePublicURL(for: objectKey)
    }

    private func validateWebDAVConfig() async throws -> Bool {
        let request = try makeWebDAVRequest(method: "PROPFIND", objectKey: nil, body: nil, contentType: nil, depth: "0")
        let (_, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 207, 301, 302].contains(statusCode)
    }

    private func uploadToWebDAV(_ fileData: Data, fileName: String, objectKey: String, mimeType: String) async throws -> String {
        try await ensureWebDAVDirectories(for: objectKey)
        let request = try makeWebDAVRequest(method: "PUT", objectKey: objectKey, body: fileData, contentType: mimeType, depth: nil)
        let (data, response) = try await uploadWithProgress(request: request, bodyData: fileData)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 201 || httpResponse.statusCode == 204 else {
            let message = String(data: data, encoding: .utf8) ?? L10n.tr("error.unknownServer")
            throw UploadServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return makePublicURL(for: objectKey)
    }

    private func ensureWebDAVDirectories(for objectKey: String) async throws {
        let parts = objectKey.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return }

        var current: [String] = []
        for segment in parts.dropLast() {
            current.append(segment)
            let path = current.joined(separator: "/")
            let request = try makeWebDAVRequest(method: "MKCOL", objectKey: path, body: nil, contentType: nil, depth: nil)
            let (_, response) = try await urlSession.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard [200, 201, 204, 301, 302, 405].contains(statusCode) else {
                throw UploadServiceError.uploadFailed(statusCode: statusCode, message: L10n.tr("error.webDAVDirectory", path))
            }
        }
    }

    private func uploadToQiniu(_ fileData: Data, fileName: String, objectKey: String, mimeType: String) async throws -> String {
        let deadline = Int(Date().timeIntervalSince1970) + 3600
        let putPolicy = """
        {"scope":"\(config.bucketName):\(objectKey)","deadline":\(deadline)}
        """

        let encodedPolicy = urlSafeBase64(Data(putPolicy.utf8))
        let signedPolicy = urlSafeBase64(hmacSHA1Data(message: Data(encodedPolicy.utf8), key: config.secretKey))
        let uploadToken = "\(config.accessKey):\(signedPolicy):\(encodedPolicy)"

        let boundary = "Pic2LinkBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: normalizedURLString(config.endpoint))!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipartField(named: "token", value: uploadToken, boundary: boundary)
        body.appendMultipartField(named: "key", value: objectKey, boundary: boundary)
        body.appendMultipartFile(named: "file", fileName: fileName, mimeType: mimeType, fileData: fileData, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")

        let (data, response) = try await uploadWithProgress(request: request, bodyData: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? L10n.tr("error.unknownServer")
            throw UploadServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return makePublicURL(for: objectKey)
    }

    private func uploadToUpyun(_ fileData: Data, fileName: String, objectKey: String, mimeType: String) async throws -> String {
        let host = normalizedHost(config.endpoint)
        let passwordHash = md5Hex(Data(config.password.utf8))
        let credentials = "\(config.operatorName):\(passwordHash)"
        let authorization = Data(credentials.utf8).base64EncodedString()
        let urlString = "https://\(host)/\(config.bucketName)/\(escapedPath(objectKey))"

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "PUT"
        request.setValue("Basic \(authorization)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await uploadWithProgress(request: request, bodyData: fileData)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? L10n.tr("error.unknownServer")
            throw UploadServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return makePublicURL(for: objectKey)
    }

    private func uploadToImgur(_ fileData: Data, fileName: String, mimeType: String) async throws -> String {
        let boundary = "Pic2LinkBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.imgur.com/3/image")!)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(config.clientID)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipartField(named: "type", value: "file", boundary: boundary)
        body.appendMultipartFile(named: "image", fileName: fileName, mimeType: mimeType, fileData: fileData, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")

        let (data, response) = try await uploadWithProgress(request: request, bodyData: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? L10n.tr("error.unknownServer")
            throw UploadServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = json["data"] as? [String: Any],
            let link = payload["link"] as? String
        else {
            throw UploadServiceError.invalidResponse
        }

        return link
    }

    private func uploadToFlickr(_ fileData: Data, fileName: String, mimeType: String) async throws -> String {
        let endpoint = "https://up.flickr.com/services/upload/"
        let params = [
            "api_key": config.apiKey,
            "auth_token": config.authToken,
            "title": fileName
        ]
        let apiSig = flickrAPISignature(params: params, secret: config.sharedSecret)
        let boundary = "Pic2LinkBoundary-\(UUID().uuidString)"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipartField(named: "api_key", value: config.apiKey, boundary: boundary)
        body.appendMultipartField(named: "auth_token", value: config.authToken, boundary: boundary)
        body.appendMultipartField(named: "title", value: fileName, boundary: boundary)
        body.appendMultipartField(named: "api_sig", value: apiSig, boundary: boundary)
        body.appendMultipartFile(named: "photo", fileName: fileName, mimeType: mimeType, fileData: fileData, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")

        let (data, response) = try await uploadWithProgress(request: request, bodyData: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? L10n.tr("error.unknownServer")
            throw UploadServiceError.uploadFailed(statusCode: httpResponse.statusCode, message: message)
        }

        guard let responseText = String(data: data, encoding: .utf8),
              let photoID = responseText.captureGroup(for: "<photoid>(.*?)</photoid>") else {
            throw UploadServiceError.invalidResponse
        }

        return "https://www.flickr.com/photo.gne?id=\(photoID)"
    }

    private func makeS3SignedRequest(method: String, objectKey: String?, body: Data, contentType: String?) throws -> URLRequest {
        let endpointHost = normalizedHost(config.endpoint)
        let usePathStyle = config.provider == .cloudflareR2 || config.provider == .backblazeB2
        let requestHost = usePathStyle ? endpointHost : "\(config.bucketName).\(endpointHost)"
        let uriObjectKey = objectKey.map(escapedPath) ?? ""
        let canonicalURI = usePathStyle
            ? "/\(config.bucketName)" + (uriObjectKey.isEmpty ? "/" : "/\(uriObjectKey)")
            : (uriObjectKey.isEmpty ? "/" : "/\(uriObjectKey)")
        let requestURL = "https://\(requestHost)\(canonicalURI)"

        let amzDate = awsTimestamp()
        let dateStamp = awsDateStamp()
        let region = config.region.isEmpty ? "auto" : config.region
        let payloadHash = sha256Hex(body)

        var headers: [(String, String)] = [
            ("host", requestHost),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", amzDate)
        ]

        if let contentType {
            headers.append(("content-type", contentType))
        }

        let sortedHeaders = headers.sorted { $0.0 < $1.0 }
        let canonicalHeaders = sortedHeaders.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = sortedHeaders.map(\.0).joined(separator: ";")
        let canonicalRequest = "\(method)\n\(canonicalURI)\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = """
        AWS4-HMAC-SHA256
        \(amzDate)
        \(credentialScope)
        \(sha256Hex(Data(canonicalRequest.utf8)))
        """
        let signingKey = awsSigningKey(secretKey: config.secretKey, dateStamp: dateStamp, region: region, service: "s3")
        let signature = hmacSHA256Hex(data: Data(stringToSign.utf8), key: signingKey)
        let authorization = """
        AWS4-HMAC-SHA256 Credential=\(config.accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)
        """

        var request = URLRequest(url: URL(string: requestURL)!)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(requestHost, forHTTPHeaderField: "Host")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func uploadWithProgress(request: URLRequest, bodyData: Data) async throws -> (Data, URLResponse) {
        var mutableRequest = request
        mutableRequest.setValue("\(bodyData.count)", forHTTPHeaderField: "Content-Length")

        let totalBytes = Int64(bodyData.count)
        uploadProgress = UploadProgress(completedBytes: 0, totalBytes: totalBytes)

        let progressDelegate = UploadProgressDelegate(expectedBytes: totalBytes) { [weak self] completedBytes, expectedBytes in
            self?.uploadProgress = UploadProgress(
                completedBytes: completedBytes,
                totalBytes: expectedBytes
            )
        }

        let (data, response) = try await urlSession.upload(
            for: mutableRequest,
            from: bodyData,
            delegate: progressDelegate
        )
        uploadProgress = UploadProgress(completedBytes: totalBytes, totalBytes: totalBytes)
        return (data, response)
    }

    private func generateFileName(from data: Data, fileExtension: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let hash = md5Hex(data).prefix(8)
        return "\(timestamp)_\(hash).\(fileExtension)"
    }

    private func generateObjectKey(fileName: String) -> String {
        var components: [String] = []
        if !config.resolvedBasePath.isEmpty {
            components.append(config.resolvedBasePath)
        }

        if config.provider.supportsPathStyle, config.pathStyle == .dateFolder {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            components.append(formatter.string(from: Date()))
        }

        // Display/source names are not object identities (clipboard captions all
        // use image-caption.png). Allocate once per upload, before signing, so
        // every provider and the returned public URL use the same unique key.
        let name = fileName as NSString
        let ext = name.pathExtension
        let stem = ext.isEmpty ? fileName : name.deletingPathExtension
        let uniqueName = "\(stem)-\(UUID().uuidString.lowercased())"
        components.append(ext.isEmpty ? uniqueName : "\(uniqueName).\(ext)")
        return components.joined(separator: "/")
    }

    private func inferredMimeType(fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    private func makePublicURL(for objectKey: String) -> String {
        guard !config.publicURL.isEmpty else {
            return "https://\(normalizedHost(config.endpoint))/\(escapedPath(objectKey))"
        }

        return "\(normalizedBaseURL(config.publicURL))/\(escapedPath(objectKey))"
    }

    private func normalizedBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        return withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func normalizedURLString(_ value: String) -> String {
        normalizedBaseURL(value)
    }

    private func normalizedHost(_ value: String) -> String {
        normalizedBaseURL(value)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func makeWebDAVRequest(method: String, objectKey: String?, body: Data?, contentType: String?, depth: String?) throws -> URLRequest {
        let root = normalizedBaseURL(config.endpoint)
        let basePath = [config.bucketName, objectKey]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        let target = basePath.isEmpty ? root : "\(root)/\(escapedPath(basePath))"

        var request = URLRequest(url: URL(string: target)!)
        request.httpMethod = method
        request.setValue(webDAVAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let depth {
            request.setValue(depth, forHTTPHeaderField: "Depth")
        }
        if let body {
            request.httpBody = body
        }
        return request
    }

    private func webDAVAuthorizationHeader() -> String {
        let credential = "\(config.accessKey):\(config.secretKey)"
        let encoded = Data(credential.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func escapedPath(_ path: String) -> String {
        path
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }
}

extension ImageHostingService {
    private func hmacSHA1Base64(string: String, key: String) -> String {
        let signature = hmacSHA1Data(message: Data(string.utf8), key: key)
        return signature.base64EncodedString()
    }

    private func hmacSHA1Data(message: Data, key: String) -> Data {
        let key = SymmetricKey(data: Data(key.utf8))
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key)
        return Data(hmac)
    }

    private func hmacSHA256Hex(data: Data, key: SymmetricKey) -> String {
        let digest = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(digest).map { String(format: "%02x", $0) }.joined()
    }

    private func md5Base64(data: Data) -> String {
        let hash = Insecure.MD5.hash(data: data)
        return Data(hash).base64EncodedString()
    }

    private func md5Hex(_ data: Data) -> String {
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func awsSigningKey(secretKey: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        let kDate = hmacSHA256(data: Data(dateStamp.utf8), key: SymmetricKey(data: Data(("AWS4" + secretKey).utf8)))
        let kRegion = hmacSHA256(data: Data(region.utf8), key: SymmetricKey(data: kDate))
        let kService = hmacSHA256(data: Data(service.utf8), key: SymmetricKey(data: kRegion))
        let kSigning = hmacSHA256(data: Data("aws4_request".utf8), key: SymmetricKey(data: kService))
        return SymmetricKey(data: kSigning)
    }

    private func hmacSHA256(data: Data, key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private func awsTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func awsDateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func rfc1123Date() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    private func urlSafeBase64(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func flickrAPISignature(params: [String: String], secret: String) -> String {
        let canonical = params
            .sorted { $0.key < $1.key }
            .reduce(secret) { partial, item in
                partial + item.key + item.value
            }
        return md5Hex(Data(canonical.utf8))
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private nonisolated let expectedBytes: Int64
    private nonisolated let onProgress: @MainActor @Sendable (Int64, Int64) -> Void

    nonisolated init(
        expectedBytes: Int64,
        onProgress: @escaping @MainActor @Sendable (Int64, Int64) -> Void
    ) {
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
        super.init()
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let total = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : expectedBytes
        let completed = min(max(totalBytesSent, 0), total)
        Task { @MainActor [onProgress] in
            onProgress(completed, total)
        }
    }
}

enum UploadServiceError: Error, LocalizedError {
    case uploadFailed(statusCode: Int, message: String)
    case invalidResponse
    case invalidConfig
    case unsupportedFileType(provider: String, summary: String)
    case directoryUploadUnsupported

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let statusCode, let message):
            return L10n.tr("error.uploadFailed", statusCode, message)
        case .invalidResponse:
            return L10n.tr("error.invalidResponse")
        case .invalidConfig:
            return L10n.tr("error.invalidConfig")
        case .unsupportedFileType(let provider, let summary):
            return L10n.tr("error.unsupportedFileType", provider, summary)
        case .directoryUploadUnsupported:
            return L10n.tr("error.directoryUnsupported")
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(named name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(named name: String, fileName: String, mimeType: String, fileData: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}

private extension String {
    func captureGroup(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let outputRange = Range(match.range(at: 1), in: self) else {
            return nil
        }

        return String(self[outputRange])
    }
}
