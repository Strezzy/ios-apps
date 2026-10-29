// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import UniformTypeIdentifiers

enum GlintPaste {
    static func read(_ providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                let value: String? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                        let text: String?
                        if let url = item as? URL { text = url.absoluteString }
                        else if let string = item as? String { text = string }
                        else if let data = item as? Data { text = String(data: data, encoding: .utf8) }
                        else { text = nil }
                        continuation.resume(returning: text)
                    }
                }
                if let link = ClipboardLinkDetector.firstLink(in: value) { return link }
            }
        }
        return nil
    }
}
