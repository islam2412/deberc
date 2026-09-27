import SwiftUI
import DebercKit

/// Настройки игры и все правила.
struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                gameSection
                namesSection
                partySection
                biddingSection
                meldsSection
                playSection
                scoringSection
                penaltiesSection
                Section {
                    Button("Вернуть наши правила", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Изменения правил действуют с новой партии.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .confirmationDialog("Вернуть правила по умолчанию?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Вернуть", role: .destructive) { store.settings.rules = .house }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    // MARK: - Разделы

    private var gameSection: some View {
        Section("Игра") {
            Picker("Сложность", selection: $store.settings.botLevel) {
                ForEach(BotLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Скорость", selection: $store.settings.speed) {
                ForEach(GameSpeed.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Ходить двойным касанием", isOn: $store.settings.confirmCardTap)
        }
    }

    private var namesSection: some View {
        Section {
            TextField("Ваше имя", text: $store.settings.playerName)
            TextField("Соперник 1", text: $store.settings.botNames[0])
            TextField("Соперник 2", text: $store.settings.botNames[1])
        } header: {
            Text("Имена")
        } footer: {
            Text("Второй соперник играет, когда вы выбираете игру втроём.")
        }
    }

    private var partySection: some View {
        Section("Партия") {
            Picker("До скольки очков", selection: $store.settings.rules.targetScore) {
                ForEach([301, 501, 701, 1001], id: \.self) { Text("\($0)").tag($0) }
            }
        }
    }

    private var biddingSection: some View {
        Section("Раздача и козырь") {
            Picker("Обязы", selection: $store.settings.rules.forcedDealAfterRedeals) {
                Text("Нет").tag(0)
                Text("После 1 пересдачи").tag(1)
                Text("После 2 пересдач").tag(2)
                Text("После 3 пересдач").tag(3)
            }
            Picker("Обмен козырной семёрки", selection: $store.settings.rules.sevenExchange) {
                Text("Любой игрок").tag(RuleSet.SevenExchange.anyPlayer)
                Text("Только играющий").tag(RuleSet.SevenExchange.bidderOnly)
                Text("Нельзя").tag(RuleSet.SevenExchange.off)
            }
            Picker("Первый ход", selection: $store.settings.rules.firstLead) {
                Text("Следующий после сдающего").tag(RuleSet.FirstLead.afterDealer)
                Text("Играющий").tag(RuleSet.FirstLead.bidder)
            }
            Picker("Кто сдаёт", selection: $store.settings.rules.dealerRotation) {
                Text("По кругу").tag(RuleSet.DealerRotation.nextPlayer)
                Text("Выигравший сдачу").tag(RuleSet.DealerRotation.dealWinner)
            }
            Picker("Четыре семёрки", selection: $store.settings.rules.fourSevens) {
                Text("+\(store.settings.rules.fourSevensBonus) и пересдача").tag(RuleSet.FourSevens.bonusAndRedeal)
                Text("Пересдача").tag(RuleSet.FourSevens.redeal)
                Text("Ничего").tag(RuleSet.FourSevens.off)
            }
            Toggle("Семёрки считаются и после прикупа", isOn: $store.settings.rules.fourSevensAfterPrikup)
            Picker("Нижняя карта", selection: $store.settings.rules.bottomCard) {
                Text("Открыть после прикупа").tag(RuleSet.BottomCard.afterPrikup)
                Text("Открыть сразу").tag(RuleSet.BottomCard.afterDeal)
                Text("Не показывать").tag(RuleSet.BottomCard.hidden)
            }
        }
    }

    private var meldsSection: some View {
        Section("Комбинации") {
            Toggle("5 подряд — сотня (100)", isOn: $store.settings.rules.hundredForFive)
            Picker("Какая старше", selection: $store.settings.rules.meldOrder) {
                Text("Длиннее, потом по старшей карте").tag(RuleSet.MeldOrder.longerFirst)
                Text("По стоимости, потом по старшей карте").tag(RuleSet.MeldOrder.valueThenTopCard)
            }
            Picker("Нужна взятка", selection: $store.settings.rules.combosNeedTrick) {
                Text("Для всех комбинаций").tag(RuleSet.CombosNeedTrick.all)
                Text("Только для бэлы").tag(RuleSet.CombosNeedTrick.bellaOnly)
                Text("Не нужна").tag(RuleSet.CombosNeedTrick.none)
            }
        }
    }

    private var playSection: some View {
        Section("Розыгрыш") {
            Toggle("Нет масти — обязан козырять", isOn: $store.settings.rules.mustTrump)
            Picker("Перебивать козырь", selection: $store.settings.rules.overtrump) {
                Text("Не обязательно").tag(RuleSet.Overtrump.never)
                Text("Только на ход с козыря").tag(RuleSet.Overtrump.trumpLeadOnly)
                Text("Всегда").tag(RuleSet.Overtrump.always)
            }
        }
    }

    private var scoringSection: some View {
        Section("Подсчёт") {
            Picker("Байт", selection: $store.settings.rules.baitTransfer) {
                Text("Очки уходят сопернику").tag(RuleSet.BaitTransfer.toOpponent)
                Text("Очки сгорают").tag(RuleSet.BaitTransfer.burn)
            }
            Picker("Байт втроём", selection: $store.settings.rules.baitRecipient) {
                Text("Тому, у кого больше").tag(RuleSet.BaitRecipient.leadingOpponent)
                Text("Пополам").tag(RuleSet.BaitRecipient.splitHalf)
            }
            Picker("Втроём играющий должен", selection: $store.settings.rules.bidderMustBeat) {
                Text("Обойти каждого").tag(RuleSet.BidderMustBeat.eachOpponent)
                Text("Обойти обоих вместе").tag(RuleSet.BidderMustBeat.opponentsCombined)
            }
            Picker("Ничья", selection: $store.settings.rules.tieRule) {
                Text("Висячий байт").tag(RuleSet.TieRule.hangingBait)
                Text("Байт").tag(RuleSet.TieRule.bait)
                Text("Каждый пишет свои").tag(RuleSet.TieRule.eachKeeps)
            }
        }
    }

    private var penaltiesSection: some View {
        Section("Штрафы") {
            Picker("За байты", selection: $store.settings.rules.baitPenaltyEvery) {
                Text("Нет").tag(0)
                Text("Каждый 2-й байт").tag(2)
                Text("Каждый 3-й байт").tag(3)
                Text("Каждый 4-й байт").tag(4)
            }
            Stepper("Штраф за байты: \(store.settings.rules.baitPenaltyPoints)",
                    value: $store.settings.rules.baitPenaltyPoints, in: 10...300, step: 10)
            Toggle("Висячий байт считается", isOn: $store.settings.rules.hangingCountsAsBait)
            Picker("Голый (без взяток)", selection: $store.settings.rules.nakedPenaltyEvery) {
                Text("Без штрафа").tag(0)
                Text("Каждый раз").tag(1)
                Text("Каждый 2-й раз").tag(2)
                Text("Каждый 3-й раз").tag(3)
            }
            Stepper("Штраф за голого: \(store.settings.rules.nakedPenaltyPoints)",
                    value: $store.settings.rules.nakedPenaltyPoints, in: 10...300, step: 10)
        }
    }
}
