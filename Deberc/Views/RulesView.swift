import SwiftUI
import DebercKit

/// Правила — собираются из текущих настроек.
struct RulesView: View {
    @Environment(\.dismiss) private var dismiss
    let rules: RuleSet

    var body: some View {
        NavigationStack {
            List {
                ForEach(RulesText.sections(for: rules), id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items, id: \.self) { item in
                            Text(item)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 2)
                        }
                    }
                }
                Section {
                    Text("Любой пункт можно поменять в «Настройках» — изменения действуют с новой партии.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Правила")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
