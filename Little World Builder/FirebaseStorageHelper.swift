//
//  FirebaseStorageHelper.swift
//  AR Test
//
//  Created by Bryce on 11/09/21.
//

import Foundation
import Firebase

final class FirebaseStorageHelper {
    private static let cloudStorage = Storage.storage()
    
    static func asyncDownloadToFilesystem(relativePath: String, handler: @escaping (_ fileUrl: URL) -> Void) {
        // Create local filesystem URL
        guard let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Firebase Storage Error: Unable to locate the documents directory for \(relativePath).")
            return
        }

        let fileUrl = docsUrl.appendingPathComponent(relativePath)
        let destinationDirectory = fileUrl.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            print("Firebase Storage Error: Unable to create destination directory for \(relativePath): \(error.localizedDescription)")
            return
        }
        
        // Check if asset is already in the local filesystem
        // if it is, load that asset and return
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            handler(fileUrl)
            return
        }
        
        // Create a reference to the asset
        let storageRef = cloudStorage.reference(withPath: relativePath)
        
        // Download to the local filesystem
        storageRef.write(toFile: fileUrl) { url, error in
            guard let localUrl = url else {
                print("Firebase Storage Error: Unable to download \(relativePath): \(error?.localizedDescription ?? "No local URL returned.")")
                return
            }

            handler(localUrl)
        }.resume()
    }
}
