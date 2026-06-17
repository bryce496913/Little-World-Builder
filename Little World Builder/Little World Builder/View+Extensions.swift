//
//  View+Extensions.swift
//  AR Test
//
//  Created by Bryce on 18/07/21.
//

import SwiftUI

extension View {
    @ViewBuilder func hidden(_ shouldHide: Bool) -> some View {
        switch shouldHide {
        case true: self.hidden()
        case false: self
        }
    }
}
