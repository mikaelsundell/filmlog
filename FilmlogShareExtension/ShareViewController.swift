// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

class ShareViewController: UIViewController {
    
    private var selectedImages: [UIImage] = []
    private let imageStackContainer = UIView()
    private let noteField = UITextView()
    private let nameField = UITextField()
    private let addButton = UIButton(type: .system)
    private let countBadge = UILabel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black
        setupUI()
        loadImages()
    }
    
    private func setupUI() {
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.systemBlue, for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        
        let titleLabel = UILabel()
        titleLabel.text = "Add to Filmlog Gallery"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let nameLabel = UILabel()
        nameLabel.text = "Name".uppercased()
        nameLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let noteLabel = UILabel()
        noteLabel.text = "Note".uppercased()
        noteLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        noteLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        
        imageStackContainer.translatesAutoresizingMaskIntoConstraints = false
        imageStackContainer.backgroundColor = UIColor.clear
        
        countBadge.backgroundColor = UIColor.systemBlue
        countBadge.textColor = .white
        countBadge.font = UIFont.boldSystemFont(ofSize: 14)
        countBadge.textAlignment = .center
        countBadge.layer.cornerRadius = 12
        countBadge.clipsToBounds = true
        countBadge.isHidden = true
        countBadge.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.barStyle = .default
        toolbar.tintColor = .systemBlue
        toolbar.items = [
            UIBarButtonItem.flexibleSpace(),
            UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        ]
        
        nameField.placeholder = "Name"
        nameField.attributedPlaceholder = NSAttributedString(
            string: "Name",
            attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.5)]
        )
        nameField.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        nameField.textColor = .white
        nameField.font = UIFont.systemFont(ofSize: 16)
        nameField.layer.cornerRadius = 8
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        nameField.leftViewMode = .always
        
        noteField.inputAccessoryView = toolbar
        noteField.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        noteField.textColor = .white
        noteField.font = UIFont.systemFont(ofSize: 16)
        noteField.layer.cornerRadius = 8
        noteField.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        noteField.translatesAutoresizingMaskIntoConstraints = false
        
        addButton.setTitle("Add image", for: .normal)
        addButton.setTitleColor(.white, for: .normal)
        addButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        addButton.backgroundColor = UIColor.systemBlue
        addButton.layer.cornerRadius = 8
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.addTarget(self, action: #selector(addToGallery), for: .touchUpInside)
        
        view.addSubview(cancelButton)
        view.addSubview(titleLabel)
        view.addSubview(imageStackContainer)
        view.addSubview(countBadge)
        view.addSubview(nameLabel)
        view.addSubview(nameField)
        view.addSubview(noteLabel)
        view.addSubview(noteField)
        view.addSubview(addButton)
        
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            imageStackContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageStackContainer.widthAnchor.constraint(equalToConstant: 240),
            imageStackContainer.heightAnchor.constraint(equalToConstant: 240),
            imageStackContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            
            countBadge.topAnchor.constraint(equalTo: imageStackContainer.topAnchor, constant: -8),
            countBadge.trailingAnchor.constraint(equalTo: imageStackContainer.trailingAnchor, constant: 8),
            countBadge.heightAnchor.constraint(equalToConstant: 24),
            countBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            
            nameLabel.topAnchor.constraint(equalTo: imageStackContainer.bottomAnchor, constant: 24),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            nameField.heightAnchor.constraint(equalToConstant: 44),
            
            noteLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 16),
            noteLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            noteField.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 6),
            noteField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            noteField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            noteField.heightAnchor.constraint(equalToConstant: 200),
            
            addButton.topAnchor.constraint(equalTo: noteField.bottomAnchor, constant: 20),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            addButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func loadImages() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else { return }
        
        var loadedCount = 0
        
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                    if let image = item as? UIImage {
                        DispatchQueue.main.async {
                            self?.addImagePreview(image)
                            loadedCount += 1
                        }
                    } else if let url = item as? URL, let image = UIImage(contentsOfFile: url.path) {
                        DispatchQueue.main.async {
                            self?.addImagePreview(image)
                            loadedCount += 1
                        }
                    } else if let error = error {
                        print("failed to load image: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func addImagePreview(_ image: UIImage) {
        selectedImages.append(image)
        imageStackContainer.subviews.forEach { $0.removeFromSuperview() }

        let count = min(selectedImages.count, 3)
        let imageSize: CGFloat = 180
        let offset: CGFloat = 10
        let totalWidth = imageSize + CGFloat(count - 1) * offset

        for (index, img) in selectedImages.prefix(3).enumerated() {
            let imageView = UIImageView(image: img)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 10
            imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
            imageView.layer.borderWidth = 1
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOpacity = 0.25
            imageView.layer.shadowRadius = 4
            imageView.layer.shadowOffset = CGSize(width: 1, height: 1)
            
            // Default (no rotation or offset)
            var rotationDegrees: CGFloat = 0
            var offsetXY: CGPoint = .zero

            // Apply random layout *only if more than one image*
            if selectedImages.count > 1 {
                switch index {
                case 0: rotationDegrees = -5; offsetXY = CGPoint(x: -8, y: 4)
                case 1: rotationDegrees = 3;  offsetXY = CGPoint(x: -2, y: -3)
                case 2: rotationDegrees = 1;  offsetXY = CGPoint(x: 4, y: 3)
                default: break
                }
            }

            let x = (imageStackContainer.bounds.width - totalWidth) / 2 + CGFloat(index) * offset + offsetXY.x
            let y = (imageStackContainer.bounds.height - imageSize) / 2 + CGFloat(index) * offset + offsetXY.y
            imageView.frame = CGRect(x: x, y: y, width: imageSize, height: imageSize)
            imageView.transform = CGAffineTransform(rotationAngle: rotationDegrees * (.pi / 180))
            
            imageStackContainer.addSubview(imageView)
        }

        if selectedImages.count > 3 {
            countBadge.text = "+\(selectedImages.count - 3)"
            countBadge.isHidden = false
        } else {
            countBadge.isHidden = true
        }

        addButton.setTitle(selectedImages.count == 1 ? "Add image" : "Add images", for: .normal)
    }
    
    @objc private func addToGallery() {
        for (index, image) in selectedImages.enumerated() {
            saveImageToAppGroup(image, name: nameField.text, note: noteField.text)
        }
        
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    @objc private func dismissKeyboard() {
        noteField.resignFirstResponder()
    }
    
    @objc private func cancelAction() {
        extensionContext?.cancelRequest(withError: NSError(domain: "com.filmlog.cancel", code: 0, userInfo: nil))
    }
    
    private func saveImageToAppGroup(_ image: UIImage, name: String?, note: String?) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            print("could not encode image JPEG data")
            return
        }

        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.mikaelsundell.filmlog") else {
            print("could not access shared container")
            return
        }
        let uuid = UUID().uuidString
        let baseName = "shared_\(uuid)"

        let imageFileName = "\(baseName).jpg"
        let imageFileURL = containerURL.appendingPathComponent(imageFileName)
        let metadataFileName = "\(baseName).json"
        let metadataFileURL = containerURL.appendingPathComponent(metadataFileName)

        do {
            try data.write(to: imageFileURL)

            var metadata: [String: Any] = [
                "fileName": imageFileName,
                "uuid": uuid,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "creator": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Unknown"
            ]

            if let name = name, !name.isEmpty {
                metadata["name"] = name
            }
            if let note = note, !note.isEmpty {
                metadata["note"] = note
            }

            let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted])
            try jsonData.write(to: metadataFileURL)
        } catch {
            print("failed to save image or metadata: \(error)")
        }
    }

}
