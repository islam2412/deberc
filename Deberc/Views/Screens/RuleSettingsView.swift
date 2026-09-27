import SwiftUI
import DebercKit

/// «Правила партии»: все переключатели правил с понятными подписями.
/// Зависимые пункты прячутся, когда не имеют смысла (размер штрафа при «Нет штрафа» и т. п.).
/// Изменения действуют с новой партии — об этом плашка сверху.
struct RuleSettingsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var confirmReset = false

    private var rules: RuleSet { store.settings.rules }

    var body: some View {
        // В iOS 16 ViewBuilder принимает не больше 10 детей — разделы собраны в группы,
        // чтобы новый раздел не ломал сборку.
        Form {
            Group {
                noticeSection
                matchSection
                dealSection
                sevensSection
                meldsSection
            }
            Group {
                playSection
                scoringSection
                threePlayersSection
                penaltiesSection
                resetSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(SheetBackground())
        .navigationTitle("Правила партии")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Вернуть наши правила?", isPresented: $confirmReset) {
            Button("Вернуть", role: .destructive) { store.settings.rules = .house }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все пункты станут такими, как в своде домашних правил. Действует с новой партии.")
        }
    }

    // MARK: - Разделы

    private var noticeSection: some View {
        Section {
            Label {
                Text(noticeText)
                    .foregroundStyle(Theme.tableText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.gold)
            }
        }
        .listRowBackground(Theme.gold.opacity(0.14))
    }

    private var noticeText: String {
        if let match = store.match, !match.isOver, match.rules != rules {
            return "Идущая партия доигрывается по прежним правилам. Эти начнут действовать с новой партии."
        }
        return "Изменения действуют с новой партии: идущую партию доигрывают по её правилам."
    }

    private var matchSection: some View {
        Section {
            Picker("Играем до", selection: $store.settings.rules.targetScore) {
                ForEach([301, 501, 701, 1001], id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
        } header: {
            Text("Партия").formHeaderStyle()
        }
        .screenRow()
    }

    private var dealSection: some View {
        Section {
            Picker("Обязы", selection: $store.settings.rules.forcedDealAfterRedeals) {
                Text("Нет").tag(0)
                Text("После 1 пересдачи").tag(1)
                Text("После 2 пересдач подряд").tag(2)
                Text("После 3 пересдач подряд").tag(3)
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
            Picker("Следующим сдаёт", selection: $store.settings.rules.dealerRotation) {
                Text("Следующий по кругу").tag(RuleSet.DealerRotation.nextPlayer)
                Text("Выигравший сдачу").tag(RuleSet.DealerRotation.dealWinner)
            }
            Picker("Нижняя карта колоды", selection: $store.settings.rules.bottomCard) {
                Text("Открыть после прикупа").tag(RuleSet.BottomCard.afterPrikup)
                Text("Открыть сразу").tag(RuleSet.BottomCard.afterDeal)
                Text("Не показывать").tag(RuleSet.BottomCard.hidden)
            }
        } header: {
            Text("Раздача и торговля").formHeaderStyle()
        } footer: {
            Text("Обязы: после нескольких пересдач подряд торговли нет — сдающий играет сам на масть открытой карты.")
                .formHeaderStyle()
        }
        .screenRow()
    }

    private var sevensSection: some View {
        Section {
            Picker("Четыре семёрки на руках", selection: $store.settings.rules.fourSevens) {
                Text("+\(rules.fourSevensBonus) и пересдача").tag(RuleSet.FourSevens.bonusAndRedeal)
                Text("Только пересдача").tag(RuleSet.FourSevens.redeal)
                Text("Ничего").tag(RuleSet.FourSevens.off)
            }
            if rules.fourSevens != .off {
                Toggle(isOn: $store.settings.rules.fourSevensAfterPrikup) {
                    SettingLabel(title: "Считаются и после прикупа", detail: "Четыре семёрки собрались после добора — тоже пересдача")
                }
                if rules.forcedDealAfterRedeals > 0 {
                    Toggle(isOn: $store.settings.rules.fourSevensKeepsForcedStreak) {
                        SettingLabel(title: "Не сбрасывают счёт до обязов",
                                     detail: "Если это были обязы, следующая сдача — снова обязы, у нового сдающего")
                    }
                }
            }
        } header: {
            Text("Четыре семёрки").formHeaderStyle()
        }
        .screenRow()
    }

    private var meldsSection: some View {
        Section {
            Toggle(isOn: $store.settings.rules.hundredForFive) {
                SettingLabel(title: "Пять подряд — сотня (100)", detail: "Выключено — это тоже полтинник")
            }
            Toggle(isOn: $store.settings.rules.bellaInMelds) {
                SettingLabel(title: "Король и дама бэлы — и в терце", detail: "Могут одновременно входить в терц или полтинник")
            }
            Picker("Какая комбинация старше", selection: $store.settings.rules.meldOrder) {
                Text("Длиннее, потом по старшей карте").tag(RuleSet.MeldOrder.longerFirst)
                Text("Дороже, потом по старшей карте").tag(RuleSet.MeldOrder.valueThenTopCard)
            }
            Picker("Без единой взятки", selection: $store.settings.rules.combosNeedTrick) {
                Text("Комбинации не пишутся").tag(RuleSet.CombosNeedTrick.all)
                Text("Не пишется только бэла").tag(RuleSet.CombosNeedTrick.bellaOnly)
                Text("Всё равно пишутся").tag(RuleSet.CombosNeedTrick.none)
            }
        } header: {
            Text("Комбинации").formHeaderStyle()
        }
        .screenRow()
    }

    private var playSection: some View {
        Section {
            Toggle(isOn: $store.settings.rules.mustTrump) {
                SettingLabel(title: "Нет масти — обязательно козырять")
            }
            if rules.mustTrump {
                Picker("Перебивать козырь старшим", selection: $store.settings.rules.overtrump) {
                    Text("Не обязательно").tag(RuleSet.Overtrump.never)
                    Text("Только на ход с козыря").tag(RuleSet.Overtrump.trumpLeadOnly)
                    Text("Всегда").tag(RuleSet.Overtrump.always)
                }
            }
        } header: {
            Text("Розыгрыш").formHeaderStyle()
        }
        .screenRow()
    }

    private var scoringSection: some View {
        Section {
            Picker("Байт: очки играющего", selection: $store.settings.rules.baitTransfer) {
                Text("Уходят сопернику").tag(RuleSet.BaitTransfer.toOpponent)
                Text("Сгорают").tag(RuleSet.BaitTransfer.burn)
            }
            Picker("Ничья с играющим", selection: $store.settings.rules.tieRule) {
                Text("Висячий байт").tag(RuleSet.TieRule.hangingBait)
                Text("Байт").tag(RuleSet.TieRule.bait)
                Text("Каждый пишет свои").tag(RuleSet.TieRule.eachKeeps)
            }
        } header: {
            Text("Подсчёт").formHeaderStyle()
        } footer: {
            Text("Висячий байт: очки играющего «висят» и достаются тому, кто наберёт больше всех в следующей сдаче.")
                .formHeaderStyle()
        }
        .screenRow()
    }

    private var threePlayersSection: some View {
        Section {
            if rules.baitTransfer == .toOpponent {
                Picker("Кому очки байта", selection: $store.settings.rules.baitRecipient) {
                    Text("Тому, у кого больше").tag(RuleSet.BaitRecipient.leadingOpponent)
                    Text("Обоим пополам").tag(RuleSet.BaitRecipient.splitHalf)
                }
            }
            Picker("Играющий должен набрать", selection: $store.settings.rules.bidderMustBeat) {
                Text("Больше каждого").tag(RuleSet.BidderMustBeat.eachOpponent)
                Text("Больше обоих вместе").tag(RuleSet.BidderMustBeat.opponentsCombined)
            }
        } header: {
            Text("Игра втроём").formHeaderStyle()
        }
        .screenRow()
    }

    private var penaltiesSection: some View {
        Section {
            Picker("Штраф за байты", selection: $store.settings.rules.baitPenaltyEvery) {
                Text("Нет").tag(0)
                Text("Каждый 2-й байт").tag(2)
                Text("Каждый 3-й байт").tag(3)
                Text("Каждый 4-й байт").tag(4)
            }
            if rules.baitPenaltyEvery > 0 {
                Stepper(value: $store.settings.rules.baitPenaltyPoints, in: 10...300, step: 10) {
                    SettingLabel(title: "Размер штрафа: \(Narrator.number(-rules.baitPenaltyPoints))")
                }
                Toggle(isOn: $store.settings.rules.hangingCountsAsBait) {
                    SettingLabel(title: "Висячий байт — тоже байт", detail: "Считается для штрафа")
                }
            }
            Picker("Голый (без взяток)", selection: $store.settings.rules.nakedPenaltyEvery) {
                Text("Без штрафа").tag(0)
                Text("Каждый раз").tag(1)
                Text("Каждый 2-й раз").tag(2)
                Text("Каждый 3-й раз").tag(3)
            }
            if rules.nakedPenaltyEvery > 0 {
                Stepper(value: $store.settings.rules.nakedPenaltyPoints, in: 10...300, step: 10) {
                    SettingLabel(title: "Штраф за голого: \(Narrator.number(-rules.nakedPenaltyPoints))")
                }
            }
        } header: {
            Text("Штрафы").formHeaderStyle()
        } footer: {
            Text("Счёт байтов и голых идёт за всю партию, не обязательно подряд.").formHeaderStyle()
        }
        .screenRow()
    }

    private var resetSection: some View {
        Section {
            Button("Вернуть наши правила", role: .destructive) { confirmReset = true }
                .disabled(rules == .house)
        }
        .screenRow()
    }
}
