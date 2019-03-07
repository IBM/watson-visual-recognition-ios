//
//  String+truncate.swift
//  Core ML Vision
//
//  Created by Nicholas Bourdakos on 3/7/19.
//

import Foundation

extension String {
    func truncate(to length: Int) -> String {
        if self.count > length {
            var newString = self
            let range = NSRange(location: length / 2, length: self.count - length)
            newString.replaceSubrange(Range(range, in: newString)!, with: "...")
            return newString
        } else {
            return self
        }
    }
}
