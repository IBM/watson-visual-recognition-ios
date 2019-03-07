//
//  VisualRecognition+Helpers.swift
//  Core ML Vision
//
//  Created by Nicholas Bourdakos on 3/4/19.
//

import VisualRecognitionV3
import CoreML

extension VisualRecognition {
    /// Helper function for checking if a model needs to be updated.
    func checkLocalModelStatus(classifierID: String, modelUpToDate: @escaping (Bool) -> Void) {
        // setup date formatter '2017-12-04T19:44:27.419Z'
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        
        // load model from disk
        guard let model = try? getLocalModel(classifierID: classifierID) else {
            // There is no local model so it can't be up to date.
            modelUpToDate(false)
            return
        }
        
        // parse the date on which the local model was last updated
        let description = model.modelDescription
        let metadata = description.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String] ?? [:]
        guard let updated = metadata["retrained"] ?? metadata["created"], let modelDate = dateFormatter.date(from: updated) else {
            modelUpToDate(false)
            return
        }
        
        // parse the date on which the classifier was last updated
        getClassifier(classifierID: classifierID) { response, error in
            guard let classifier = response?.result else {
                return
            }
            
            guard let classifierDate = classifier.retrained ?? classifier.created else {
                DispatchQueue.main.async {
                    modelUpToDate(false)
                }
                return
            }
            
            if classifierDate > modelDate && classifier.status == "ready" {
                DispatchQueue.main.async {
                    modelUpToDate(false)
                }
            } else {
                DispatchQueue.main.async {
                    modelUpToDate(true)
                }
            }
        }
    }
}
