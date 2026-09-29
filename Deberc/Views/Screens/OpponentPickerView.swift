import SwiftUI
import DebercKit

/// Выбор соперника для места за столом (новой партии): все персонажи по уровням —
/// аватар, имя, манера, пара слов о характере и ваш личный счёт с ним.
struct OpponentPickerView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    /// Место соперника: 0 — первый (он играет и вдвоём), 1 — второй (только втроём).
    let slot: Int

    private var ids: [String] { store.settings.opponentIDs }
    private var currentID: String? { ids.indices.contains(slot) ? ids[slot] : nil }
    /// Другой соперник за столом (только втроём).
    private var otherID: String? {
        guard store.settings.playerCount == 3 else { return nil }
        let other = slot == 0 ? 1 : 0
        return ids.indices.contains(other) ? ids[other] : nil
    }

    private var title: String {
        if store.settings.playerCount == 2 { return "Соперник" }
        return slot == 0 ? "Первый соперник" : "Второй соперник"
    }

    var body: some View {
        SheetContainer(title: title, sizing: .page) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Уровень показывает, насколько сильно играет соперник, манера — как он торгуется. Выбор действует с новой партии.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.tableSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(BotLevel.allCases, id: \.self) { level in
                            levelSection(level)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                // Выбран соперник посильнее — список сразу на нём, а не на «Новичках» в начале.
                .task {
                    guard let currentID, let current = Persona.byID(currentID),
                          current.level != .novice else { return }
                    proxy.scrollTo(currentID, anchor: .center)
                }
            }
        }
    }

    private func levelSection(_ level: BotLevel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(level.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.gold)
                LevelStarsView(level: level, size: 13)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(level.subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.tableSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Persona.all.filter { $0.level == level }) { persona in
                personaButton(persona)
            }
        }
    }

    private func personaButton(_ persona: Persona) -> some View {
        let isCurrent = persona.id == currentID
        let isOther = persona.id == otherID
        return Button {
            choose(persona)
        } label: {
            PersonaCard(persona: persona,
                        record: store.stats.byPersona[persona.id],
                        isSelected: isCurrent,
                        note: isOther ? "Уже за столом — поменяются местами" : nil)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .id(persona.id)
    }

    private func choose(_ persona: Persona) {
        var updated = ids
        while updated.count < 2 {
            updated.append(AppSettings.defaultOpponentIDs(for: store.settings.difficulty)[updated.count])
        }
        if let index = updated.firstIndex(of: persona.id), index != slot {
            updated.swapAt(index, slot)
        } else {
            updated[slot] = persona.id
        }
        if updated != store.settings.opponentIDs {
            store.settings.opponentIDs = updated
        }
        dismiss()
    }
}

/// Карточка персонажа: аватар, имя, уровень звёздами, манера, характер и ваш счёт с ним.
struct PersonaCard: View {
    let persona: Persona
    let record: PlayerStats.Record?
    var isSelected = false
    var note: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PersonaAvatarView(persona: persona, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(persona.name)
                        .font(.headline)
                        .foregroundStyle(Theme.tableText)
                    Spacer(minLength: 6)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.gold)
                            .accessibilityHidden(true)
                    }
                }
                Text("\(persona.level.title) · \(persona.style.title(feminine: persona.feminine))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                Text(persona.bio)
                    .font(.subheadline)
                    .foregroundStyle(Theme.tableText)
                    .fixedSize(horizontal: false, vertical: true)
                if let record, record.played > 0 {
                    Text("Ваш счёт: \(record.won) : \(max(0, record.played - record.won))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.tableSecondaryText)
                }
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.tableSecondaryText)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tableSurface(cornerRadius: 18, interactive: true, highlighted: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
