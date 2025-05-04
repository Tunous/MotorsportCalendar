//
//  Series.swift
//  
//
//  Created by Łukasz Rutkowski on 26/02/2024.
//

import Foundation

public enum Series: String, Codable, CaseIterable, Hashable, Sendable, Identifiable, Comparable {
    case formula1
    case wrc
    case wec

    public var id: Self { self }

    public static func < (lhs: Series, rhs: Series) -> Bool {
        Self.allCases.firstIndex(of: lhs)! < Self.allCases.firstIndex(of: rhs)!
    }
}
