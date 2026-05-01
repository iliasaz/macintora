//
//  SubstitutionInputView.swift
//  Macintora
//
//  Modal that collects values for SQL*Plus substitution variables (`&name`,
//  `&&name`) before a script run. Modeled on `BindVarInputView`. `&&` names
//  are flagged as "session-sticky" so the user knows their value will be
//  remembered for the rest of the document's lifetime.
//

import SwiftUI

struct PendingSubstitutionRequest: Identifiable, Equatable {
    let id: UUID
    let names: [String]
    let stickyNames: Set<String>
    let prefilled: [String: String]

    init(names: [String], stickyNames: Set<String>, prefilled: [String: String] = [:]) {
        self.id = UUID()
        self.names = names
        self.stickyNames = stickyNames
        self.prefilled = prefilled
    }
}

struct SubstitutionInputView: View {
    let request: PendingSubstitutionRequest
    /// `nil` = user cancelled.
    var onSubmit: ([String: String]?) -> Void

    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Substitution Variables")
                .font(.title3)
                .bold()
            Text("Provide values for the script's `&` and `&&` substitution variables. `&&` values stick for the rest of this document's session.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(request.names, id: \.self) { name in
                        SubstitutionField(
                            name: name,
                            isSticky: request.stickyNames.contains(name),
                            value: Binding(
                                get: { values[name] ?? "" },
                                set: { values[name] = $0 }
                            )
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 80, idealHeight: 200, maxHeight: 360)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onSubmit(nil)
                }
                .keyboardShortcut(.cancelAction)
                Button("Run") {
                    onSubmit(values)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 420, idealWidth: 480)
        .onAppear {
            // Seed any prefilled defaults exactly once.
            for (k, v) in request.prefilled where values[k] == nil {
                values[k] = v
            }
        }
    }
}

private struct SubstitutionField: View {
    let name: String
    let isSticky: Bool
    @Binding var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 100, alignment: .leading)
            if isSticky {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
                    .help("This value will stick for the rest of the session (&&).")
            }
            TextField("value", text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }
}

#Preview {
    SubstitutionInputView(
        request: .init(
            names: ["OWNER", "SCHEMA", "BATCH_ID"],
            stickyNames: ["OWNER"],
            prefilled: ["BATCH_ID": "42"]
        ),
        onSubmit: { _ in }
    )
}
