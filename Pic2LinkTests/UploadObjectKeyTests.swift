import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pic2Link

final class UploadObjectKeyTests: XCTestCase {
    @MainActor
    func testThreeUnnamedCaptionedScreenshotsUploadToDistinctObjects() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = ImageHostingService(config: profile(), urlSession: session)
        var links: [String] = []
        var bodies: [Data] = []
        for index in 0..<3 {
            let input = CaptionUploadPayload(data: try screenshot(index), fileName: nil, mimeType: "image/png")
            let captioned = try PhotoCaptionRenderer().compose(input, text: "Screenshot \(index)")
            XCTAssertEqual(captioned.fileName, "image-caption.png")
            bodies.append(captioned.data)
            links.append(try await service.uploadFile(captioned.data,
                fileName: try XCTUnwrap(captioned.fileName), mimeType: captioned.mimeType))
        }
        XCTAssertEqual(Set(bodies).count, 3)
        XCTAssertEqual(Set(links).count, 3)
        let requests = ObjectUploadProtocol.takeRequests()
        XCTAssertEqual(requests.count, 3)
        for (index, request) in requests.enumerated() {
            XCTAssertEqual(request.body, bodies[index])
            XCTAssertEqual(request.request.httpMethod, "PUT")
            XCTAssertEqual(request.request.value(forHTTPHeaderField: "Content-Type"), "image/png")
            XCTAssertEqual(request.request.url?.path, URL(string: links[index])?.path)
            XCTAssertTrue(links[index].contains("/uploads/wmblog/"))
            XCTAssertTrue(links[index].contains("/image-caption-"))
            XCTAssertTrue(links[index].hasSuffix(".png"))
        }
    }

    @MainActor
    func testSameNamesAndRepeatedBytesNeverReuseKeysAcrossProvidersAndPathStyles() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let providers: [ImageHostProvider] = [.alibabaOSS, .amazonS3, .cloudflareR2, .qiniu, .upyun, .webDAV]
        for provider in providers {
            for style in PathStyle.allCases {
                var config = profile(provider)
                config.pathStyle = style
                let service = ImageHostingService(config: config, urlSession: session)
                let bytes = Data("same file contents".utf8)
                var links: [String] = []
                for _ in 0..<2 {
                    links.append(try await service.uploadFile(bytes, fileName: "image-caption.png", mimeType: "image/png"))
                }
                XCTAssertNotEqual(links[0], links[1], "\(provider) / \(style)")
                let requests = ObjectUploadProtocol.takeRequests().filter { $0.request.httpMethod != "MKCOL" }
                XCTAssertEqual(requests.count, 2)
                for (index, request) in requests.enumerated() {
                    let key = try XCTUnwrap(URL(string: links[index])).path.dropFirst()
                    if provider == .qiniu {
                        let body = try XCTUnwrap(String(data: request.body, encoding: .utf8))
                        XCTAssertTrue(body.contains("name=\"key\"\r\n\r\n\(key)\r\n"))
                        XCTAssertTrue(body.contains("filename=\"image-caption.png\""))
                    } else {
                        XCTAssertTrue(request.request.url?.path.hasSuffix("/" + key) == true)
                        XCTAssertEqual(request.body, bytes)
                    }
                }
            }
        }
    }

    @MainActor
    func testUniqueRemoteNamesKeepExtensionsMimeTypesAndSourceBytes() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let service = ImageHostingService(config: profile(), urlSession: session)
        for (name, mime) in [("动画 图片.GIF", "image/gif"), ("vector.svg", "image/svg+xml"),
                             ("archive.tar.gz", "application/gzip"), ("README", "application/octet-stream")] {
            let bytes = Data("unchanged \(name)".utf8)
            let link = try await service.uploadFile(bytes, fileName: name, mimeType: mime)
            let remote = try XCTUnwrap(URL(string: link)).lastPathComponent as NSString
            let original = name as NSString
            XCTAssertEqual(remote.pathExtension, original.pathExtension)
            XCTAssertTrue((remote as String).hasPrefix(original.deletingPathExtension + "-"))
            let request = try XCTUnwrap(ObjectUploadProtocol.takeRequests().first)
            XCTAssertEqual(request.body, bytes)
            XCTAssertEqual(request.request.value(forHTTPHeaderField: "Content-Type"), mime)
        }
        let gif = try XCTUnwrap(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
        let first = try await service.uploadImage(gif)
        let second = try await service.uploadImage(gif)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasSuffix(".gif"))
        for request in ObjectUploadProtocol.takeRequests() {
            XCTAssertEqual(request.body, gif)
            XCTAssertEqual(request.request.value(forHTTPHeaderField: "Content-Type"), "image/gif")
        }
    }

    @MainActor
    private func makeSession() -> URLSession {
        _ = ObjectUploadProtocol.takeRequests()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ObjectUploadProtocol.self]
        return URLSession(configuration: configuration)
    }

    @MainActor
    private func profile(_ provider: ImageHostProvider = .alibabaOSS) -> ImageHostProfile {
        ImageHostProfile(provider: provider, bucketName: "test-bucket", accessKey: "test-key",
            secretKey: "test-secret", publicURL: "https://cdn.example.invalid", endpoint: "upload.example.invalid",
            region: "test-region", basePath: "uploads/wmblog", operatorName: "test", password: "test")
    }

    private func screenshot(_ index: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: CGFloat(index) * 0.3, green: 0.2, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class ObjectUploadProtocol: URLProtocol, @unchecked Sendable {
    struct RecordedRequest {
        let request: URLRequest
        let body: Data
    }
    private nonisolated static let lock = NSLock()
    private nonisolated(unsafe) static var recorded: [RecordedRequest] = []

    nonisolated static func takeRequests() -> [RecordedRequest] {
        lock.withLock {
            defer { recorded.removeAll() }
            return recorded
        }
    }

    override nonisolated class func canInit(with request: URLRequest) -> Bool { true }
    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override nonisolated func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.withLock { Self.recorded.append(RecordedRequest(request: request, body: body)) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override nonisolated func stopLoading() {}
}
