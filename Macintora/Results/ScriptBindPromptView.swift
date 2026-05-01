//
//  ScriptBindPromptView.swift
//  Macintora
//
//  Sheet wrapper around `BindVarInputView` for the script runner. The runner
//  pauses on `needsBinds` until the user submits values (or cancels); this
//  view translates that into the existing `BindVarInputVM` UI and resolves
//  the pending request through `ResultsController.resolvePendingBinds`.
//

import SwiftUI

struct ScriptBindPromptView: View {
    let request: PendingBindRequest
    /// Pass `nil` to abort the script.
    var onSubmit: ([String: BindValue]?) -> Void

    @State private var bindVarVM: BindVarInputVM

    init(request: PendingBindRequest, onSubmit: @escaping ([String: BindValue]?) -> Void) {
        self.request = request
        self.onSubmit = onSubmit
        _bindVarVM = State(wrappedValue: BindVarInputVM(bindNames: request.names))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bind Variables — unit \(request.unitIndex + 1)")
                .font(.title3)
                .bold()
            Text("Provide typed values for the `:bind` variables in this statement.")
                .font(.callout)
                .foregroundStyle(.secondary)
            BindVarInputView(
                bindVarVM: $bindVarVM,
                runAction: { onSubmit(collectBinds()) },
                cancelAction: { onSubmit(nil) }
            )
        }
        .padding()
        .frame(minWidth: 460, idealWidth: 520, minHeight: 200)
    }

    private func collectBinds() -> [String: BindValue] {
        bindVarVM.bindVars.reduce(into: [:]) { partial, entry in
            switch entry.type {
            case .text:
                partial[entry.name] = .text(entry.textValue)
            case .null:
                partial[entry.name] = .null
            case .date:
                if let d = entry.dateValue { partial[entry.name] = .date(d) } else { partial[entry.name] = .null }
            case .int:
                if let i = entry.intValue { partial[entry.name] = .int(i) } else { partial[entry.name] = .null }
            case .decimal:
                if let d = entry.decValue { partial[entry.name] = .decimal(d) } else { partial[entry.name] = .null }
            }
        }
    }
}
