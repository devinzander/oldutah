//
//  PhotoSaver.swift
//  The Data Center
//
//  Save a scan to the photo library with add-only access, and fetch the
//  full-resolution image once for display, saving and sharing.
//

import UIKit
import Photos

enum PhotoSaverError: LocalizedError {
    case denied
    var errorDescription: String? {
        "The Data Center isn't allowed to add to your photos. You can allow it in Settings › Privacy › Photos."
    }
}

enum PhotoSaver {
    /// Adds the image to the library. Asks for add-only permission the first time.
    static func save(_ image: UIImage) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { throw PhotoSaverError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    /// The image at `url`, through the shared URL cache.
    static func image(at url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

/// A brief confirmation that rises from the bottom edge — "Saved to Photos".
struct Toast: Equatable {
    let text: String
    let systemImage: String
}
