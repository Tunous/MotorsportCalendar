//
//  MotorsportEventStage.swift
//  
//
//  Created by Łukasz Rutkowski on 26/02/2024.
//

import Foundation

public struct MotorsportEventStage: Identifiable, Codable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
}
