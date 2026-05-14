//
//  ImagePickerView.swift
//  SmartTutor
//
//  PHPickerViewController wrapper for SwiftUI.
//  Used by the Dashboard search bar camera button to let students
//  photograph a textbook question.
//
//  Usage:
//    .sheet(isPresented: $showCameraPicker) {
//        ImagePickerView { image in pickedImage = image }
//    }
//

import os
import PhotosUI
import SwiftUI

struct ImagePickerView: UIViewControllerRepresentable {

    /// Called on the main thread when the user confirms a picked image.
    let onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        // Prefer high-res original so any embedded text is legible
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        AppLogger.camera.info("ImagePickerView: presented PHPickerViewController")
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: ImagePickerView

        init(_ parent: ImagePickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()

            guard let result = results.first else {
                AppLogger.camera.info("ImagePickerView: user cancelled — no selection")
                return
            }

            AppLogger.camera.info("ImagePickerView: loading selected asset  id=\(result.assetIdentifier ?? "unknown")")

            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let error {
                    AppLogger.camera.error("ImagePickerView: load failed  error=\(error.localizedDescription)")
                    return
                }
                guard let image = object as? UIImage else {
                    AppLogger.camera.error("ImagePickerView: cast to UIImage failed")
                    return
                }
                AppLogger.camera.info("ImagePickerView: loaded  size=\(image.size.width)×\(image.size.height)  scale=\(image.scale)")
                DispatchQueue.main.async { self?.parent.onImage(image) }
            }
        }
    }
}
