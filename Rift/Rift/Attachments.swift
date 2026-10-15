import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO
import PDFKit

struct ChatAttachment: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var imageFile: String?
    var text: String?
    var isImage: Bool { imageFile != nil }
}

struct AttachmentStore: Sendable {
    let directory: URL
    init(storage: LocalStorage) throws {
        directory = storage.root.appendingPathComponent("Attachments", isDirectory: true)
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
    }
    func imageURL(_ attachment: ChatAttachment) -> URL? {
        guard let file = attachment.imageFile, file == attachment.id.uuidString + ".jpg" else { return nil }
        return directory.appendingPathComponent(file)
    }
    func remove(_ attachment: ChatAttachment) {
        if let url = imageURL(attachment) { try? FileManager.default.removeItem(at: url) }
    }
    func importFile(_ url: URL) throws -> ChatAttachment {
        try prepare()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var result: Result<ChatAttachment, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readable in
            result = Result { try read(readable) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw RiftFailure("This file could not be opened.") }
        return try result.get()
    }
    private func read(_ url: URL) throws -> ChatAttachment {
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentTypeKey])
        guard info.isRegularFile == true, let size = info.fileSize, size > 0, size <= 20 * 1_048_576 else {
            throw RiftFailure("Choose a file smaller than 20 MB.")
        }
        let id = UUID(), name = String(url.lastPathComponent.prefix(120))
        let type = info.contentType ?? UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 768,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary) else { throw RiftFailure("This image could not be read. Try JPEG, PNG or HEIC.") }
            let filename = id.uuidString + ".jpg", output = directory.appendingPathComponent(id.uuidString + ".jpg")
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw RiftFailure("The image could not be saved on this iPhone.")
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { try? FileManager.default.removeItem(at: output); throw RiftFailure("The image could not be prepared.") }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: output.path)
            return .init(id: id, name: name, imageFile: filename)
        }
        let text: String
        if type?.conforms(to: .pdf) == true {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw RiftFailure("Unlock this PDF before attaching it.") }
            guard pdf.pageCount <= 40 else { throw RiftFailure("Choose a PDF with 40 pages or fewer.") }
            var pages: [String] = []
            var count = 0
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                let page = pdf.page(at: index)?.string ?? ""
                count += page.count
                guard count <= 24_000 else { throw RiftFailure("This PDF contains too much text. Attach a shorter excerpt.") }
                pages.append(page)
            }
            text = pages.joined(separator: "\n\n")
        } else {
            guard type?.conforms(to: .text) == true || ["txt", "md", "csv", "json", "log", "yaml", "yml"].contains(url.pathExtension.lowercased()), size <= 256 * 1024 else {
                throw RiftFailure("Choose an image, a text-based PDF, or a small text, Markdown, CSV or JSON file.")
            }
            let data = try Data(contentsOf: url)
            guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw RiftFailure("This file’s text encoding is not supported. Save it as UTF-8 text.")
            }
            text = decoded
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RiftFailure("No readable text was found. For a scanned PDF, attach a page as an image with Qwen3.5 4B selected.") }
        guard trimmed.count <= 24_000, !trimmed.contains("\0") else { throw RiftFailure("Attach a shorter text excerpt (up to 24,000 characters).") }
        return .init(id: id, name: name, text: trimmed)
    }
}

@MainActor final class VisionDownload: ObservableObject {
    static let bytes: Int64 = 675_568_768
    static let checksum = "a1e32e86ea99aa7a56f3dcfe7e63c1d0be9439d31fd07087099f15bc0fda0f22"
    static let filename = "mmproj-Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-BF16.gguf"
    static let url = URL(string: "https://huggingface.co/HauhauCS/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive/resolve/c09cdbcdb1fefad6d335809d445621b5f5ba0c6e/" + filename)!
    static func supports(_ model: InstalledModel?) -> Bool {
        model?.sha256 == "79e28ecacf84e75b6056cf4059636d435aa9eb67795780f7b7dbc7d32a962741"
    }
    static func installedURL(storage: LocalStorage) -> URL? {
        let url = storage.models.appendingPathComponent(filename)
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(bytes) ? url : nil
    }
    @Published private(set) var progress = 0.0
    @Published private(set) var downloading = false
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var job: DownloadJob?
    func start(storage: LocalStorage, cellular: Bool) {
        guard !downloading else { return }
        downloading = true; progress = 0; error = nil
        let partial = storage.transfers.appendingPathComponent("qwen4b-vision.partial")
        let destination = storage.models.appendingPathComponent(Self.filename)
        let transfer = DownloadJob(destination: partial, expectedBytes: Self.bytes)
        job = transfer
        task = Task {
            defer { downloading = false; job = nil; task = nil; try? FileManager.default.removeItem(at: partial) }
            do {
                guard storage.freeSpace() > Self.bytes + 128 * 1_048_576 else { throw RiftFailure("Free up about 800 MB before downloading image support.") }
                for try await event in transfer.start(url: Self.url, cellular: cellular) {
                    try Task.checkCancellation()
                    switch event {
                    case .progress(let value): progress = value
                    case .file(let file):
                        let hash = try await Task.detached(priority: .utility) { try GGUFInspector.hash(file) }.value
                        try Task.checkCancellation()
                        guard hash == Self.checksum else { throw RiftFailure("The image-support download did not pass verification. Please retry.") }
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: file, to: destination)
                    }
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func cancel() { task?.cancel(); job?.cancel() }
}

struct AttachmentPreview: View {
    @EnvironmentObject private var model: AppModel
    @State private var image: UIImage?
    let attachment: ChatAttachment
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: attachment.isImage ? "photo" : "doc.text").font(.title2).foregroundStyle(RiftTheme.accent) }
        }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            .task(id: attachment.id) {
                guard let storage = model.storage, let files = try? AttachmentStore(storage: storage), let url = files.imageURL(attachment) else { return }
                image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
            }
    }
}
