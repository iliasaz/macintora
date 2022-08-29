//
//  Logo.swift
//  MacOra
//
//  Created by Ilia on 2/18/22.
//

import SwiftUI

extension View {
    func glow(color: Color = .red, radius: CGFloat = 20) -> some View {
        self
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
    }
}

struct Logo: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.red)
                .frame(width: 220, height: 120, alignment: .center)
            Capsule()
                .fill(Color.white)
                .frame(width: 160, height: 80, alignment: .center)
            Text("MacOra")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(Color(NSColor.darkGray))
                .glow(color: Color(NSColor.lightGray), radius: 5.0)
                .lineLimit(1)
        }
    }
}

struct Logo_Previews: PreviewProvider {
    static var previews: some View {
        Logo()
    }
}
