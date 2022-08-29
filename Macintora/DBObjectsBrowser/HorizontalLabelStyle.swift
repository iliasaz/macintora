//
//  HorizontalLabelStyle.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/8/22.
//

import Foundation
import SwiftUI

struct HorizontalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

extension HorizontalAlignment {
    private struct CentreLine: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.center]
        }
    }
    
    static let centreLine = Self(CentreLine.self)
}
