//
//  SessionSettings.swift
//  AR Test
//
//  Created by Bryce on 24/07/21.
//

import Combine

final class SessionSettings: ObservableObject {
    @Published var isPeopleOcclusionEnabled: Bool = false
    @Published var isObjectOcclusionEnabled: Bool = false
    @Published var isLidarDebugEnabled: Bool = false
    @Published var isMultiuserEnabled: Bool = false
}
