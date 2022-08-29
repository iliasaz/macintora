//
//  BindVarInputView.swift
//  Macintora
//
//  Created by Ilia Sazonov on 7/2/22.
//

import SwiftUI
import SwiftOracle

enum BindVarInputType: String, Hashable {
    case text = "Text", int = "Integer", decimal = "Decimal", date = "Datetime", null = "Null"
}

struct BindVarModel: Identifiable, Equatable, CustomStringConvertible {
    var description: String {
        get {
            "id: \(id), name: \(name), type: \(type), textValue: \(textValue), dateValue: \(dateValue?.ISO8601Format()), intValue: \(intValue), decValue: \(decValue)"
        }
    }
    
    let id = UUID()
    var name: String
    var type: BindVarInputType
    var textValue: String = ""
    var dateValue: Date?
    var intValue: Int?
    var decValue: Double?
}

struct BindVarInputVM: CustomStringConvertible {
    var description: String {
        get {
            "bindVars: \(bindVars.map { $0.description }.joined(separator: ";"))"
        }
    }
    
    var bindVars = [BindVarModel]()
    
    init(preview: Bool = false) {
        log.debug("in BindVarInputVM.init with preview = \(preview)")
        if preview {
            bindVars = [
                BindVarModel(name: ":b1", type: .text),
                BindVarModel(name: ":b2", type: .decimal),
                BindVarModel(name: ":b3", type: .int),
                BindVarModel(name: ":b4", type: .date),
                BindVarModel(name: ":b5", type: .null)
            ]
        }
    }
    
    init(bindNames: Set<String>) {
        bindVars = bindNames.map { BindVarModel(name: $0, type: .text) }.sorted(by: {$0.name < $1.name})
    }
    
    // merge types and values from an existing instance if available
    init(from oldVM: BindVarInputVM, bindNames: Set<String>) {
        log.debug("BindVarInputVM.init: oldVM: \(oldVM), new bindNames: \(bindNames, privacy: .public)")
        bindVars = bindNames.map { BindVarModel(name: $0, type: .text) }.sorted(by: {$0.name < $1.name})
        for (i, bv) in bindVars.enumerated() {
            if let bvn = oldVM.bindVars.first(where: {$0.name == bv.name} ) {
                bindVars[i].textValue = bvn.textValue
                bindVars[i].intValue = bvn.intValue
                bindVars[i].decValue = bvn.decValue
                bindVars[i].dateValue = bvn.dateValue
                bindVars[i].type = bvn.type
            }
        }
        let debugBindVars = bindVars
        log.debug("BindVarInputVM.init: newVM: \(debugBindVars)")
    }
}


struct BindVarInputView: View {
    @Binding var bindVarVM: BindVarInputVM
    
    var runAction: () -> Void
    var cancelAction: () -> Void
    
    var body: some View {
        let _ = log.viewCycle.debug("Redrawing BindVarInputView body, bindVarVM: \(bindVarVM.bindVars)")
        VStack(alignment: .leading) {
            Text("Bind Variables").font(.title)
            List($bindVarVM.bindVars) { bindVar in
                BindVarField(bindVar: bindVar)
            }
            HStack {
                Button {
                    log.viewCycle.debug("in BindVarInputView Run Button; bindVars: \(bindVarVM.bindVars)")
//                    bindVarVM.showingBindVarInputView = false
                    runAction()
                } label: { Text("Run") }
                    .focusable()
                
                Button {
                    log.viewCycle.debug("in BindVarInputView Cancel Button")
//                    bindVarVM.showingBindVarInputView = false
                    cancelAction()
                } label: { Text("Cancel") }
                    .focusable()
            }
        }
        .padding()
    }
}

struct BindVarField: View {
    @Binding var bindVar: BindVarModel
    @State private var isValidDate = true
    
    private var dateFormatter: DateFormatter
    
    init(bindVar: Binding<BindVarModel>) {
        _bindVar = bindVar
        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
        dateFormatter.dateFormat = "yyyy-MM-dd' 'HH:mm:ss"
    }
    
    var body: some View {
        HStack {
            Text("\(bindVar.name)")
                .focusable(false)
            
            Picker("", selection: $bindVar.type) {
                Text(BindVarInputType.text.rawValue).tag(BindVarInputType.text)
                Text(BindVarInputType.decimal.rawValue).tag(BindVarInputType.decimal)
                Text(BindVarInputType.int.rawValue).tag(BindVarInputType.int)
                Text(BindVarInputType.date.rawValue).tag(BindVarInputType.date)
                Text(BindVarInputType.null.rawValue).tag(BindVarInputType.null)
            }
                .frame(width: 100)
            
            switch bindVar.type {
                case .decimal:
                    TextField("", value: $bindVar.decValue, format: .number, prompt: Text("#####.#####"))
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 150, maxWidth: .infinity)

                case .int:
                    TextField("", value: $bindVar.intValue, format: .number, prompt: Text("##########"))
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 150, maxWidth: .infinity)

                case .date:
//                    DatePicker("", selection: Binding(get: {bindVar.dateValue ?? Date()}, set: {bindVar.dateValue = $0}), displayedComponents: [.date, .hourAndMinute])
//                        .datePickerStyle(.field)
//                        .cornerRadius(10, antialiased: false)
//                        .frame(minWidth: 150, maxWidth: .infinity)
                    
                    TextField("", text: $bindVar.textValue, prompt: Text("YYYY-MM-DD HH:MI:SS"))
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 150, maxWidth: .infinity)
                        .onChange(of: $bindVar.textValue.wrappedValue, perform: { val in
                            log.viewCycle.debug("new value: \(val), converted date: \(dateFormatter.date(from: val)?.debugDescription ?? "---")")
                            
                            if let dt = dateFormatter.date(from: val) {
                                $bindVar.dateValue.wrappedValue = dt
                                isValidDate = true
                                log.viewCycle.debug("date is valid!!!")
                            } else {
                                isValidDate = false
                            }
                        })
                        .border(isValidDate ? Color.primary : .red, width: isValidDate ? 0 : 3)

                case .text:
                    TextField("", text: $bindVar.textValue)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 150, maxWidth: .infinity)

                default: EmptyView()
            }
        }
    }
}

//struct BindVarField_Previews: PreviewProvider {
//    static var previews: some View {
//        BindVarField(bindVar: .constant(BindVarInputVM(preview: true).bindVars[3]))
//    }
//}

//struct BindVarInputView_Previews: PreviewProvider {
//    static var previews: some View {
//        BindVarInputView(parentBindVarVM: BindVarInputVM(preview: true), parentRunAction: { _ in }, parentCancelAction: {}, testVar: testStruct() )
//    }
//}
