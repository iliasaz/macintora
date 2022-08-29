//
//  FormField.swift
//  DBObjectsBrowser
//
//  Created by Ilia on 6/8/22.
//

import SwiftUI

struct FormField<Control: View>: View {
    private let label: String
    private let control: Control
    init(label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }
    var body: some View {
        HStack {
            Text(label).alignmentGuide(.centreLine) { $0[.trailing] }
            control.alignmentGuide(.centreLine) { $0[.leading] }
        }
    }
}


