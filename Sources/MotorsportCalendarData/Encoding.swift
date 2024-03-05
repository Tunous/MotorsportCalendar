//
//  JSONDecoder.swift
//  
//
//  Created by Łukasz Rutkowski on 25/02/2024.
//

import Foundation

extension JSONEncoder {
    public static let motorsportCalendar: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    public static let motorsportCalendar: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension Series: CodingKeyRepresentable {
}
