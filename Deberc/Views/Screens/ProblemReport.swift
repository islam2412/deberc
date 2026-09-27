import SwiftUI
import UIKit
import DebercKit

/// «Что-то не так?» — файл с партией для разработчика.
///
/// В файле: версия приложения, модель устройства и версия iOS, настройки и партия целиком
/// (вместе с текущей или только что сыгранной сдачей: руки, взятки, колода) — по нему
/// спорную сдачу можно воспроизвести. Больше ничего: имя игрока — только то, что он сам вписал.
struct ProblemReport: Encodable {
    var kind = "deberc-problem-report"
    var format = 1
    var createdAt: Date
    var app: String
    var device: String
    var system: String
    var settings: AppSettings
    var opponentIDs: [String]
    var match: Match?
    var comment = "Опишите, что пошло не так:"

    @MainActor
    init(store: GameStore) {
        createdAt = Date()
        app = AppInfo.version
        device = ProblemReport.machine()
        system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        settings = store.settings
        opponentIDs = store.opponents.map(\.id)
        match = store.match
    }

    /// Записать отчёт во временный файл. nil — не получилось (тогда кнопку не показываем).
    @MainActor
    static func write(store: GameStore) -> URL? {
        let report = ProblemReport(store: store)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return nil }
        // Один файл на всё: ссылка есть в каждом окне итогов, и файлы не должны копиться.
        // Время отчёта — внутри (createdAt); вся история партии — тоже.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deberc-report.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Модель устройства вида «iPhone10,4».
    @MainActor
    private static func machine() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let bytes = mirror.children.compactMap { $0.value as? Int8 }.prefix { $0 != 0 }
        let name = String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? UIDevice.current.model : name
    }
}

/// Ссылка «Отправить разработчику»: файл готовится, когда ссылка появляется на экране.
struct ProblemReportLink: View {
    @EnvironmentObject private var store: GameStore
    var title = "Сообщить о проблеме"
    var systemImage = "exclamationmark.bubble"
    /// Тема письма/сообщения.
    var subject = "Деберц: что-то не так"

    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                ShareLink(item: url,
                          subject: Text(subject),
                          message: Text("Что-то пошло не так — в файле вся партия, её можно воспроизвести.")) {
                    Label(title, systemImage: systemImage)
                }
            } else {
                Label(title, systemImage: systemImage)
                    .opacity(0.5)
            }
        }
        .onAppear {
            if url == nil { url = ProblemReport.write(store: store) }
        }
        .accessibilityHint("Отправить файл с партией разработчику")
    }
}
