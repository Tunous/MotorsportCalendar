//
//  Series.swift
//  
//
//  Created by Łukasz Rutkowski on 26/02/2024.
//

import Foundation

public enum Series: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case formula1
    case wrc
    case wec

    public var id: Self { self }
}
