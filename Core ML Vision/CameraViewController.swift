/**
 * Copyright IBM Corporation 2017, 2018
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import UIKit
import AVFoundation
import Photos
import VisualRecognitionV3

struct ListItem {
    var id: String
    var name: String
}

class CameraViewController: UIViewController {

    // MARK: - IBOutlets
    
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var heatmapView: UIImageView!
    @IBOutlet weak var outlineView: UIImageView!
    @IBOutlet weak var focusView: UIImageView!
    @IBOutlet weak var simulatorTextView: UITextView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var updateModelButton: UIButton!
    @IBOutlet weak var choosePhotoButton: UIButton!
    @IBOutlet weak var flashButton: UIButton!
    @IBOutlet weak var flipButton: UIButton!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var alphaSlider: UISlider!
    @IBOutlet weak var boundingBoxView: UIView!
    @IBOutlet weak var checkStatusIndicatorView: UIActivityIndicatorView! {
        didSet {
            checkStatusIndicatorView.hidesWhenStopped = true
        }
    }
    @IBOutlet weak var pickerView: AKPickerView!
    
    // MARK: - Variable Declarations
    
    let visualRecognition: VisualRecognition = {
        guard let path = Bundle.main.path(forResource: "Credentials", ofType: "plist"), let apiKey = NSDictionary(contentsOfFile: path)?["apiKey"] as? String else {
            // Please create a Credentials.plist file with your Visual Recognition credentials.
            fatalError()
        }
        if apiKey == "YOUR_API_KEY" {
            // No Visual Recognition API key found. Make sure you add your API key to the Credentials.plist file.
            fatalError()
        }
        return VisualRecognition(version: VisualRecognitionConstants.version, apiKey: apiKey)
    }()
    
    let photoOutput = AVCapturePhotoOutput()
    lazy var captureSession: AVCaptureSession? = {
        guard let backCamera = { () -> AVCaptureDevice? in
            if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                return device
            } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                return device
            } else {
                return nil
            }
        }(), let input = try? AVCaptureDeviceInput(device: backCamera) else {
            return nil
        }
        
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        captureSession.addInput(input)
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = CGRect(x: view.bounds.minX, y: view.bounds.minY, width: view.bounds.width, height: view.bounds.height)
            // `.resize` allows the camera to fill the screen on the iPhone X.
            previewLayer.videoGravity = .resize
            previewLayer.connection?.videoOrientation = .portrait
            cameraView.layer.addSublayer(previewLayer)
            return captureSession
        }
        return nil
    }()
    
    let defaultClassifiers = [
        ListItem(id: "default", name: "general"),
        ListItem(id: "detect_faces", name: "faces"),
        ListItem(id: "explicit", name: "explicit"),
        ListItem(id: "food", name: "food")
    ]
    
    var originalConfs = [ClassResult]()
    var heatmaps = [String: VisualRecognition.Heatmap]()
    var selectionIndex = 0
    var classifiers = [ListItem]()
    var isLoading = false
    var back = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pickerView.delegate = self
        pickerView.dataSource = self
        isLoading = true
        pickerView.reloadData()
        resetUI()
        
        // Only show a max of 20 bounding boxes.
        for _ in 0 ..< 20 {
            let box = UIBoundingBox()
            box.addToLayer(boundingBoxView.layer)
            boundingBoxes.append(box)
        }
        
        // Start capture session after UI setup.
        captureSession?.startRunning()
        
        var modelList = [ListItem]()
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        visualRecognition.listClassifiers() { response, error in
            defer { dispatchGroup.leave() }
            guard var classifiers = response?.result?.classifiers else {
                return
            }
            classifiers = classifiers.filter { $0.status == "ready" }
            for classifier in classifiers {
                modelList.append(ListItem(id: classifier.classifierID, name: classifier.name))
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            self.classifiers = modelList
            self.isLoading = false
            self.pickerView.reloadData()
            self.pickerView.selectItem(self.selectionIndex)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let drawer = pulleyViewController?.drawerContentViewController as? ResultsTableViewController else {
            return
        }
        drawer.delegate = self
    }
    
    // MARK: - Image Classification
    
    var boundingBoxes: [UIBoundingBox] = []
    func classifyImage(_ image: UIImage, localThreshold: Double = 0.0) {
        guard let croppedImage = image.cropToCenter(targetSize: CGSize(width: 224, height: 224)) else {
            return
        }
        
        showResultsUI(for: image)
        
        guard let classifierId = UserDefaults.standard.string(forKey: "classifier_id") else {
            return
        }
        
        if classifierId == "detect_faces" {
            visualRecognition.detectFaces(image: image) { response, error in
                DispatchQueue.main.async {
                    guard let faces = response?.result?.images.first?.faces else {
                        return
                    }
                    
                    let imageWidth = image.size.width
                    let imageHeight = image.size.height
                    let viewWidth = self.boundingBoxView.layer.frame.width
                    let viewHeight = self.boundingBoxView.layer.frame.height
                    
                    let imageAspectRatio = imageWidth / imageHeight
                    let viewAspectRatio = viewWidth / viewHeight
                    
                    var scale: CGFloat = 0.0
                    var xOffset: CGFloat = 0.0
                    var yOffset: CGFloat = 0.0
                    if imageAspectRatio > viewAspectRatio {
                        // image is wider than view
                        let scaledImageWidth = viewHeight * imageAspectRatio
                        scale = viewHeight / imageHeight
                        xOffset = (scaledImageWidth - viewWidth) / 2
                        yOffset = 0.0
                    } else {
                        // image is taller than view
                        let scaledImageHeight = viewWidth / imageAspectRatio
                        scale = viewWidth / imageWidth
                        xOffset = 0.0
                        yOffset = (scaledImageHeight - viewHeight) / 2
                    }
                    
                    let topKFaces = faces.prefix(self.boundingBoxes.count)
                    for (index, face) in topKFaces.enumerated() {
                        guard let faceBox = face.faceLocation else {
                            return
                        }
                        
                        let label = "\(face.gender?.genderLabel ?? "") \(face.age?.min ?? 0) - \(face.age?.max ?? 99)"
                        
                        let rect = CGRect(x: faceBox.left, y: faceBox.top, width: faceBox.width, height: faceBox.height)
                        
                        let transform = CGAffineTransform(translationX: -xOffset, y: -yOffset)
                        let scale = CGAffineTransform(scaleX: scale, y: scale)
                        let scaledRect = rect.applying(scale).applying(transform)
                        
                        let color = UIColor(red: 36/255, green: 101/255, blue: 255/255, alpha: 1.0)
                        self.boundingBoxes[index].show(frame: scaledRect, label: label, color: color)
                    }
                    for index in topKFaces.count ..< 20 {
                        self.boundingBoxes[index].hide()
                    }
                }
            }
            return
        }
        
        do {
            let _ = try visualRecognition.getLocalModel(classifierID: classifierId)
            visualRecognition.classifyWithLocalModel(image: croppedImage, classifierIDs: [classifierId], threshold: localThreshold) { classifiedImages, error in
                DispatchQueue.main.async {
                    // Make sure that an image was successfully classified.
                    guard let classifications = classifiedImages?.images.first?.classifiers.first?.classes else {
                        return
                    }
                    self.push(results: classifications)
                    self.originalConfs = classifications
                }
            }
        } catch {
            visualRecognition.classify(image: croppedImage, threshold: localThreshold, classifierIDs: [classifierId]) { response, error in
                DispatchQueue.main.async {
                    // Make sure that an image was successfully classified.
                    guard let classifications = response?.result?.images.first?.classifiers.first?.classes else {
                        return
                    }
                    self.push(results: classifications)
                    self.originalConfs = classifications
                }
            }
        }
    }
    
    func dismissResults() {
        push(results: [], position: .closed)
    }
    
    func push(results: [ClassResult], position: PulleyPosition = .partiallyRevealed) {
        guard let drawer = pulleyViewController?.drawerContentViewController as? ResultsTableViewController else {
            return
        }
        drawer.classifications = results
        pulleyViewController?.setDrawerPosition(position: position, animated: true)
        drawer.tableView.reloadData()
    }
    
    func showResultsUI(for image: UIImage) {
        imageView.image = image
        pickerView.isHidden = true
        imageView.isHidden = false
        simulatorTextView.isHidden = true
        closeButton.isHidden = false
        captureButton.isHidden = true
        choosePhotoButton.isHidden = true
        updateModelButton.isHidden = true
        focusView.isHidden = true
        flashButton.isHidden = true
        flipButton.isHidden = true
        checkStatusIndicatorView.stopAnimating()
    }
    
    func resetUI() {
        heatmaps = [String: VisualRecognition.Heatmap]()
        if captureSession != nil {
            simulatorTextView.isHidden = true
            imageView.isHidden = true
            captureButton.isHidden = false
            focusView.isHidden = false
        } else {
            imageView.image = UIImage(named: "Background")
            simulatorTextView.isHidden = false
            imageView.isHidden = false
            captureButton.isHidden = true
            focusView.isHidden = true
        }
        heatmapView.isHidden = true
        outlineView.isHidden = true
        alphaSlider.isHidden = true
        closeButton.isHidden = true
        pickerView.isHidden = false
        choosePhotoButton.isHidden = false
        updateModelButton.isHidden = false
        flashButton.isHidden = false
        flipButton.isHidden = false
        dismissResults()
        invalidateStatus()
        for boundingBox in boundingBoxes {
            boundingBox.hide()
        }
    }
    
    func invalidateStatus() {
        checkStatusIndicatorView.stopAnimating()
        updateModelButton.isEnabled = false
        
        if isLoading {
            choosePhotoButton.isEnabled = false
            captureButton.isEnabled = false
            return
        } else {
            choosePhotoButton.isEnabled = true
            captureButton.isEnabled = true
        }
        
        guard let classifierId = UserDefaults.standard.string(forKey: "classifier_id") else {
            return
        }
        if defaultClassifiers.contains(where: { $0.id == classifierId }) {
            updateModelButton.isHidden = true
        } else {
            updateModelButton.isEnabled = true
            do {
                let _ = try visualRecognition.getLocalModel(classifierID: classifierId)
                updateModelButton.isHidden = true
                checkStatusIndicatorView.startAnimating()
                visualRecognition.checkLocalModelStatus(classifierID: classifierId) { modelUpToDate in
                    self.checkStatusIndicatorView.stopAnimating()
                    if !modelUpToDate {
                        self.updateModelButton.isHidden = false
                    }
                }
            } catch {
                updateModelButton.isHidden = false
            }
        }
    }
    
    // MARK: - IBActions
    
    @IBAction func sliderValueChanged(_ sender: UISlider) {
        let currentValue = CGFloat(sender.value)
        self.heatmapView.alpha = currentValue
    }
    
    @IBAction func checkUpdates() {
        guard let modelId = UserDefaults.standard.string(forKey: "classifier_id") else {
            return
        }
        visualRecognition.checkLocalModelStatus(classifierID: modelId) { modelUpToDate in
            if !modelUpToDate {
                SwiftSpinner.show("Compiling model...")
                self.visualRecognition.updateLocalModel(classifierID: modelId) { response, error in
                    DispatchQueue.main.async {
                        defer { SwiftSpinner.hide() }
                        
                        guard let error = error else {
                            self.updateModelButton.isHidden = true
                            return
                        }
                        self.modelUpdateFail(modelId: modelId, error: error)
                    }
                }
            }
        }
    }
    
    @IBAction func flipPhoto() {
        guard let input = captureSession?.inputs.first else {
            return
        }
        captureSession?.removeInput(input)
        
        back = !back
        
        let device = { () -> AVCaptureDevice? in
            if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: back ? .back : .front) {
                return device
            } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: back ? .back : .front) {
                return device
            } else {
                return nil
            }
        }()
        
        guard let sdevice = device, let newInput = try? AVCaptureDeviceInput(device: sdevice) else {
            return
        }
        captureSession?.addInput(newInput)
    }
    
    @IBAction func capturePhoto() {
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
    
    @IBAction func presentPhotoPicker() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        present(picker, animated: true)
    }
    
    @IBAction func reset() {
        resetUI()
    }
}

// MARK: - Error Handling

extension CameraViewController {
    func showAlert(_ alertTitle: String, alertMessage: String) {
        let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func modelUpdateFail(modelId: String, error: Error) {
        let error = error as NSError
        var errorMessage = ""
        
        // 0 = probably wrong api key
        // 404 = probably no model
        // -1009 = probably no internet
        
        switch error.code {
        case 0:
            errorMessage = "Please check your Visual Recognition API key in `Credentials.plist` and try again."
        case 404:
            errorMessage = "We couldn't find a classifier with ID: \"\(modelId)\""
        case 500:
            errorMessage = "Internal server error. Please try again."
        case -1009:
            errorMessage = "Please check your internet connection."
        default:
            errorMessage = "Please try again."
        }
        
        // TODO: Do some more checks, does the model exist? is it still training? etc.
        // The service's response is pretty generic and just guesses.
        
        showAlert("Unable to download model", alertMessage: errorMessage)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension CameraViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        guard let image = info[.originalImage] as? UIImage else {
            return
        }
        
        classifyImage(image)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            return
        }
        guard let photoData = photo.fileDataRepresentation(),
            let image = UIImage(data: photoData) else {
            return
        }
        
        classifyImage(image)
    }
}

// MARK: - TableViewControllerSelectionDelegate

extension CameraViewController: TableViewControllerSelectionDelegate {
    func didSelectItem(_ name: String) {
        if let heatmap = heatmaps[name] {
            heatmapView.image = heatmap.heatmap
            outlineView.image = heatmap.outline
            return
        }

        guard let classifierId = UserDefaults.standard.string(forKey: "classifier_id") else {
            return
        }
        do {
            let _ = try visualRecognition.getLocalModel(classifierID: classifierId)
            guard let image = imageView.image else {
                return
            }
            SwiftSpinner.show("analyzing")
            visualRecognition.generateHeatmap(image: image, classifierId: classifierId, className: name) { heatmap in
                DispatchQueue.main.async {
                    SwiftSpinner.hide()
                    self.heatmaps[name] = heatmap
                    
                    self.heatmapView.image = heatmap.heatmap
                    self.outlineView.image = heatmap.outline
                    self.heatmapView.alpha = CGFloat(self.alphaSlider.value)
                    
                    self.heatmapView.isHidden = false
                    self.outlineView.isHidden = false
                    self.alphaSlider.isHidden = false
                }
            }
        } catch {
            return
        }
    }
}

// MARK: - AKPickerViewDataSource

extension CameraViewController: AKPickerViewDataSource {
    func numberOfItemsInPickerView(_ pickerView: AKPickerView) -> Int {
        return (isLoading ? 1 : defaultClassifiers.count + classifiers.count)
    }
    
    func pickerView(_ pickerView: AKPickerView, titleForItem item: Int) -> String {
        if isLoading {
            return "Loading..."
        } else {
            if item < defaultClassifiers.count {
                if defaultClassifiers[item].id == UserDefaults.standard.string(forKey: "classifier_id") {
                    selectionIndex = item
                }
                return defaultClassifiers[item].name.uppercased().truncate(to: 20)
            }
            
            let scaledItem = item - defaultClassifiers.count
            
            if classifiers[scaledItem].id == UserDefaults.standard.string(forKey: "classifier_id") {
                selectionIndex = item
            }
            return classifiers[scaledItem].name.uppercased().truncate(to: 20)
        }
    }
}

// MARK: - AKPickerViewDelegate

extension CameraViewController: AKPickerViewDelegate {
    func pickerView(_ pickerView: AKPickerView, didSelectItem item: Int) {
        if item < defaultClassifiers.count {
            let classifierId = defaultClassifiers[item].id
            UserDefaults.standard.set(classifierId, forKey: "classifier_id")
        } else {
            let classifierId = classifiers[item - defaultClassifiers.count].id
            UserDefaults.standard.set(classifierId, forKey: "classifier_id")
        }
        invalidateStatus()
    }
}
