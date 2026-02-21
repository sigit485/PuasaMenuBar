import AppKit
import SwiftUI

struct PrayerTimes {
    let imsak: Date
    let subuh: Date
    let maghrib: Date
    let gregorianDate: Date
    let gregorianText: String
    let hijriText: String
    let timeZone: TimeZone
}

enum PrayerMethod: Int, CaseIterable, Identifiable, Codable {
    case karachi = 1
    case isna = 2
    case muslimWorldLeague = 3
    case ummAlQura = 4
    case egyptian = 5
    case tehran = 7
    case gulf = 8
    case kuwait = 9
    case qatar = 10
    case singapore = 11
    case turkeyDiyanet = 13
    case dubai = 16
    case jakim = 17
    case tunisia = 18
    case algeria = 19
    case kemenag = 20
    case morocco = 21
    case jordan = 23

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .karachi:
            return "Karachi"
        case .isna:
            return "ISNA"
        case .muslimWorldLeague:
            return "Muslim World League"
        case .ummAlQura:
            return "Umm Al-Qura"
        case .egyptian:
            return "Egyptian Survey"
        case .tehran:
            return "Tehran"
        case .gulf:
            return "Gulf"
        case .kuwait:
            return "Kuwait"
        case .qatar:
            return "Qatar"
        case .singapore:
            return "Singapore (MUIS)"
        case .turkeyDiyanet:
            return "Turkey (Diyanet)"
        case .dubai:
            return "Dubai"
        case .jakim:
            return "Malaysia (JAKIM)"
        case .tunisia:
            return "Tunisia"
        case .algeria:
            return "Algeria"
        case .kemenag:
            return "Indonesia (Kemenag)"
        case .morocco:
            return "Morocco"
        case .jordan:
            return "Jordan"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var city: String
    var country: String
    var method: PrayerMethod

    static let `default` = AppSettings(
        city: "Surabaya",
        country: "Indonesia",
        method: .kemenag
    )
}

private enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingField(String)
    case unableToParse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL API tidak valid."
        case .invalidResponse:
            return "Respons API tidak valid."
        case let .missingField(name):
            return "Field \(name) tidak ditemukan di respons API."
        case let .unableToParse(value):
            return "Gagal parse data waktu: \(value)."
        }
    }
}

private enum AladhanAPI {
    private struct ResponseEnvelope: Decodable {
        let code: Int
        let data: DataPayload
    }

    private struct DataPayload: Decodable {
        let timings: [String: String]
        let date: DatePayload
        let meta: MetaPayload
    }

    private struct DatePayload: Decodable {
        let gregorian: GregorianPayload
        let hijri: HijriPayload
    }

    private struct GregorianPayload: Decodable {
        let date: String
    }

    private struct HijriPayload: Decodable {
        let day: String
        let month: HijriMonthPayload
        let year: String
    }

    private struct HijriMonthPayload: Decodable {
        let en: String
    }

    private struct MetaPayload: Decodable {
        let timezone: String
    }

    static func fetchToday(settings: AppSettings) async throws -> PrayerTimes {
        let url = try buildURL(path: "timingsByCity", settings: settings, date: nil)
        return try await fetch(from: [url])
    }

    static func fetchForDate(
        settings: AppSettings,
        date: Date,
        timeZone: TimeZone
    ) async throws -> PrayerTimes {
        let dateString = apiDateFormatter(timeZone: timeZone).string(from: date)

        let pathVariant = try buildURL(path: "timingsByCity/\(dateString)", settings: settings, date: nil)
        let queryVariant = try buildURL(path: "timingsByCity", settings: settings, date: dateString)

        return try await fetch(from: [pathVariant, queryVariant])
    }

    private static func fetch(from urls: [URL]) async throws -> PrayerTimes {
        var lastError: Error?

        for url in urls {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ... 299).contains(httpResponse.statusCode)
                else {
                    throw APIError.invalidResponse
                }

                let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
                return try parse(decoded)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    private static func parse(_ envelope: ResponseEnvelope) throws -> PrayerTimes {
        guard envelope.code == 200 else {
            throw APIError.invalidResponse
        }

        let payload = envelope.data

        let timeZone = TimeZone(identifier: payload.meta.timezone) ?? .current
        let (year, month, day) = try parseGregorianDate(payload.date.gregorian.date)

        let imsak = try makeDate(
            year: year,
            month: month,
            day: day,
            clock: payload.timings["Imsak"],
            timeZone: timeZone
        )

        let subuh = try makeDate(
            year: year,
            month: month,
            day: day,
            clock: payload.timings["Fajr"],
            timeZone: timeZone
        )

        let maghrib = try makeDate(
            year: year,
            month: month,
            day: day,
            clock: payload.timings["Maghrib"],
            timeZone: timeZone
        )

        let gregorianDate = try makeDate(
            year: year,
            month: month,
            day: day,
            clock: "12:00",
            timeZone: timeZone
        )

        let gregorianText = displayGregorianDateFormatter(timeZone: timeZone).string(from: gregorianDate)
        let hijriText = "\(payload.date.hijri.day) \(payload.date.hijri.month.en) \(payload.date.hijri.year)"

        return PrayerTimes(
            imsak: imsak,
            subuh: subuh,
            maghrib: maghrib,
            gregorianDate: gregorianDate,
            gregorianText: gregorianText,
            hijriText: hijriText,
            timeZone: timeZone
        )
    }

    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        clock: String?,
        timeZone: TimeZone
    ) throws -> Date {
        guard let rawClock = clock else {
            throw APIError.missingField("clock")
        }

        let (hour, minute) = try parseClock(rawClock)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let date = calendar.date(from: components) else {
            throw APIError.unableToParse(rawClock)
        }

        return date
    }

    private static func parseClock(_ raw: String) throws -> (Int, Int) {
        guard let match = raw.range(of: #"^(\d{1,2}):(\d{2})"#, options: .regularExpression) else {
            throw APIError.unableToParse(raw)
        }

        let timePart = raw[match]
        let pieces = timePart.split(separator: ":")

        guard pieces.count == 2,
              let hour = Int(pieces[0]),
              let minute = Int(pieces[1])
        else {
            throw APIError.unableToParse(raw)
        }

        return (hour, minute)
    }

    private static func parseGregorianDate(_ raw: String) throws -> (Int, Int, Int) {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let day = Int(parts[0]),
              let month = Int(parts[1]),
              let year = Int(parts[2])
        else {
            throw APIError.unableToParse(raw)
        }

        return (year, month, day)
    }

    private static func buildURL(path: String, settings: AppSettings, date: String?) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.aladhan.com"
        components.path = "/v1/\(path)"

        var queryItems = [
            URLQueryItem(name: "city", value: settings.city),
            URLQueryItem(name: "country", value: settings.country),
            URLQueryItem(name: "method", value: "\(settings.method.rawValue)"),
        ]

        if let date {
            queryItems.append(URLQueryItem(name: "date", value: date))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        return url
    }

    private static func apiDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }

    private static func displayGregorianDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }
}

@MainActor
final class PuasaViewModel: ObservableObject {
    enum PrayerSlot {
        case imsak
        case subuh
        case maghrib
    }

    enum Status {
        case loading
        case waitingSubuh(until: Date)
        case fasting(until: Date)
        case afterMaghrib(until: Date)
    }

    @Published private(set) var now = Date()
    @Published private(set) var prayerTimes: PrayerTimes?
    @Published private(set) var tomorrowImsak: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    @Published var cityInput: String
    @Published var countryInput: String
    @Published var methodInput: PrayerMethod

    private var settings: AppSettings
    private var tickerTask: Task<Void, Never>?
    private var lastFetchDayKey: String?
    private let deviceClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private enum StorageKey {
        static let settings = "puasa_menu_bar_settings_v1"
    }

    init() {
        let savedSettings = Self.loadSettings()
        settings = savedSettings

        cityInput = savedSettings.city
        countryInput = savedSettings.country
        methodInput = savedSettings.method

        startTicker()

        Task {
            await refreshFromAPI(force: true)
        }
    }

    var cityName: String {
        "\(settings.city), \(settings.country)"
    }

    var dateLine: String {
        if let prayerTimes {
            return "\(prayerTimes.gregorianText) / \(prayerTimes.hijriText)"
        }

        let gregorian = displayDateFormatter.string(from: now)
        let hijri = hijriDateFormatter.string(from: now)
        return "\(gregorian) / \(hijri)"
    }

    var imsakText: String {
        formatTime(prayerTimes?.imsak)
    }

    var subuhText: String {
        formatTime(prayerTimes?.subuh)
    }

    var maghribText: String {
        formatTime(prayerTimes?.maghrib)
    }

    var menuBarTitle: String {
        deviceClockFormatter.string(from: now)
    }

    var statusTitle: String {
        switch currentStatus {
        case .loading:
            return "Memuat Jadwal"
        case .waitingSubuh:
            return "Menunggu Sahur"
        case .fasting:
            return "Sedang Berpuasa"
        case .afterMaghrib:
            return "Sudah Berbuka"
        }
    }

    var statusColor: Color {
        switch currentStatus {
        case .loading:
            return Color(red: 0.46, green: 0.62, blue: 0.56)
        case .waitingSubuh:
            return Color(red: 0.24, green: 0.66, blue: 0.56)
        case .fasting:
            return Color(red: 0.14, green: 0.60, blue: 0.47)
        case .afterMaghrib:
            return Color(red: 0.29, green: 0.71, blue: 0.59)
        }
    }

    var statusCountdownText: String {
        switch currentStatus {
        case .loading:
            return isLoading ? "Memuat..." : "--"
        case let .waitingSubuh(until):
            return remainingText(until: until)
        case let .fasting(until):
            return remainingText(until: until)
        case let .afterMaghrib(until):
            return remainingText(until: until)
        }
    }

    var heroCountdownText: String {
        deviceClockFormatter.string(from: now)
    }

    var heroHeadlineText: String {
        switch currentStatus {
        case .loading:
            return "Sinkronisasi Jadwal"
        case .waitingSubuh:
            return "Menuju Subuh"
        case .fasting:
            return "Menuju Berbuka"
        case .afterMaghrib:
            return "Menuju Imsak Besok"
        }
    }

    var heroTargetText: String {
        guard let targetDate = statusTargetDate else {
            return cityName
        }
        return "\(cityName) • Target \(formatTime(targetDate))"
    }

    var highlightedPrayer: PrayerSlot? {
        switch currentStatus {
        case .loading:
            return nil
        case .waitingSubuh:
            return .subuh
        case .fasting:
            return .maghrib
        case .afterMaghrib:
            return .imsak
        }
    }

    var methodSummary: String {
        "Metode: \(settings.method.title)"
    }

    var saveButtonEnabled: Bool {
        let city = cityInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !city.isEmpty && !country.isEmpty && !isLoading
    }

    func refresh() {
        Task {
            await refreshFromAPI(force: true)
        }
    }

    func saveSettings() {
        let city = cityInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !city.isEmpty, !country.isEmpty else {
            errorMessage = "Kota dan negara wajib diisi."
            return
        }

        let newSettings = AppSettings(city: city, country: country, method: methodInput)
        settings = newSettings
        cityInput = city
        countryInput = country

        persistSettings(newSettings)

        Task {
            await refreshFromAPI(force: true)
        }
    }

    private var displayTimeZone: TimeZone {
        prayerTimes?.timeZone ?? TimeZone.current
    }

    private var statusTargetDate: Date? {
        switch currentStatus {
        case .loading:
            return nil
        case let .waitingSubuh(until):
            return until
        case let .fasting(until):
            return until
        case let .afterMaghrib(until):
            return until
        }
    }

    private var currentStatus: Status {
        guard let prayerTimes else {
            return .loading
        }

        if now < prayerTimes.subuh {
            return .waitingSubuh(until: prayerTimes.subuh)
        }

        if now < prayerTimes.maghrib {
            return .fasting(until: prayerTimes.maghrib)
        }

        if let tomorrowImsak {
            return .afterMaghrib(until: tomorrowImsak)
        }

        let fallback = prayerTimes.imsak.addingTimeInterval(24 * 3600)
        return .afterMaghrib(until: fallback)
    }

    private var displayTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = displayTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private var displayDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = displayTimeZone
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }

    private var hijriDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = displayTimeZone
        formatter.calendar = Calendar(identifier: .islamicUmmAlQura)
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }

    private func startTicker() {
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else {
                    return
                }

                self.now = Date()
                await self.refreshIfDateChanged()
            }
        }
    }

    private func refreshIfDateChanged() async {
        guard !isLoading, prayerTimes != nil else {
            return
        }

        let currentKey = dayKey(for: now, timeZone: displayTimeZone)
        if currentKey != lastFetchDayKey {
            await refreshFromAPI(force: false)
        }
    }

    private func refreshFromAPI(force: Bool) async {
        if isLoading {
            return
        }

        if !force,
           let prayerTimes,
           dayKey(for: now, timeZone: prayerTimes.timeZone) == lastFetchDayKey
        {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let today = try await AladhanAPI.fetchToday(settings: settings)

            let tomorrowReference = tomorrowReferenceDate(from: today)
            let tomorrow: PrayerTimes?

            do {
                tomorrow = try await AladhanAPI.fetchForDate(
                    settings: settings,
                    date: tomorrowReference,
                    timeZone: today.timeZone
                )
            } catch {
                tomorrow = nil
            }

            prayerTimes = today
            tomorrowImsak = tomorrow?.imsak
            lastFetchDayKey = dayKey(for: now, timeZone: today.timeZone)
            errorMessage = nil
        } catch {
            if prayerTimes == nil {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Gagal refresh. Menampilkan jadwal terakhir."
            }
        }
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else {
            return "--:--"
        }
        return displayTimeFormatter.string(from: date)
    }

    private func remainingText(until targetDate: Date) -> String {
        let remaining = max(0, Int(targetDate.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60

        if hours > 0 {
            return "\(hours)j \(minutes)m lagi"
        }

        return "\(minutes)m lagi"
    }

    private func dayKey(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func tomorrowReferenceDate(from prayerTimes: PrayerTimes) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prayerTimes.timeZone

        return calendar.date(byAdding: .day, value: 1, to: prayerTimes.gregorianDate) ?? prayerTimes.gregorianDate.addingTimeInterval(24 * 3600)
    }

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.settings) else {
            return .default
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return .default
        }
    }

    private func persistSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: StorageKey.settings)
    }
}

@main
struct PuasaMenuBarApp: App {
    @StateObject private var viewModel = PuasaViewModel()

    var body: some Scene {
        MenuBarExtra {
            PuasaPopover(viewModel: viewModel)
                .padding(12)
        } label: {
            Image(systemName: "moon.stars.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct PuasaPopover: View {
    @ObservedObject var viewModel: PuasaViewModel

    var body: some View {
        VStack(spacing: 12) {
            headerCard
            scheduleCard
            settingsCard
            footerBar
        }
        .padding(14)
        .frame(width: 396)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.98, blue: 0.96),
                    Color(red: 0.97, green: 1.00, blue: 0.99),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(viewModel.heroCountdownText)
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Button {
                    viewModel.refresh()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.24))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.32), lineWidth: 1)
                            )

                        Image(systemName: viewModel.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            Text(viewModel.heroHeadlineText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.98))

            Text(viewModel.heroTargetText)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(2)

            HStack(spacing: 8) {
                TagBadge(
                    icon: "dot.radiowaves.left.and.right",
                    text: viewModel.statusTitle,
                    tint: .white.opacity(0.22)
                )

                TagBadge(
                    icon: "timer",
                    text: viewModel.statusCountdownText,
                    tint: .white.opacity(0.16)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.56, blue: 0.45),
                            Color(red: 0.23, green: 0.72, blue: 0.58),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: Color(red: 0.12, green: 0.53, blue: 0.43).opacity(0.28), radius: 12, x: 0, y: 8)
    }

    private var scheduleCard: some View {
        WhiteCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text("Jadwal Hari Ini")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.15, green: 0.36, blue: 0.31))

                    Spacer()

                    TimePill(
                        text: viewModel.statusCountdownText,
                        tint: viewModel.statusColor,
                        highlighted: true
                    )
                }

                ScheduleRow(
                    icon: "moon.zzz.fill",
                    title: "Imsak",
                    subtitle: "Batas makan sahur",
                    time: viewModel.imsakText,
                    tint: Color(red: 0.45, green: 0.72, blue: 0.64),
                    highlighted: viewModel.highlightedPrayer == .imsak
                )

                ScheduleRow(
                    icon: "sunrise.fill",
                    title: "Sahur (Subuh)",
                    subtitle: "Mulai puasa",
                    time: viewModel.subuhText,
                    tint: Color(red: 0.20, green: 0.63, blue: 0.51),
                    highlighted: viewModel.highlightedPrayer == .subuh
                )

                ScheduleRow(
                    icon: "sunset.fill",
                    title: "Berbuka (Maghrib)",
                    subtitle: "Waktu berbuka",
                    time: viewModel.maghribText,
                    tint: Color(red: 0.16, green: 0.55, blue: 0.45),
                    highlighted: viewModel.highlightedPrayer == .maghrib
                )
            }
        }
    }

    private var settingsCard: some View {
        WhiteCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pengaturan")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.17, green: 0.38, blue: 0.33))

                SettingLine(label: "Kota") {
                    SettingInputShell {
                        TextField("Surabaya", text: $viewModel.cityInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.12, green: 0.28, blue: 0.24))
                            .tint(Color(red: 0.16, green: 0.53, blue: 0.43))
                    }
                }

                SettingLine(label: "Negara") {
                    SettingInputShell {
                        TextField("Indonesia", text: $viewModel.countryInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.12, green: 0.28, blue: 0.24))
                            .tint(Color(red: 0.16, green: 0.53, blue: 0.43))
                    }
                }

                SettingLine(label: "Metode") {
                    SettingInputShell {
                        Menu {
                            ForEach(PrayerMethod.allCases) { method in
                                Button {
                                    viewModel.methodInput = method
                                } label: {
                                    if method == viewModel.methodInput {
                                        Label(method.title, systemImage: "checkmark")
                                    } else {
                                        Text(method.title)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(viewModel.methodInput.title)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.12, green: 0.28, blue: 0.24))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.red.opacity(0.88))
                        .padding(.top, 2)
                }

                HStack {
                    Button("Simpan Perubahan") {
                        viewModel.saveSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.17, green: 0.60, blue: 0.48),
                                        Color(red: 0.24, green: 0.68, blue: 0.55),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .opacity(viewModel.saveButtonEnabled ? 1 : 0.45)
                    .disabled(!viewModel.saveButtonEnabled)

                    Spacer()

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(red: 0.19, green: 0.58, blue: 0.48))
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            FooterActionButton(
                title: "Refresh",
                icon: "arrow.clockwise",
                filled: true
            ) {
                viewModel.refresh()
            }

            FooterActionButton(
                title: "Quit",
                icon: "power",
                filled: false
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private struct ScheduleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let time: String
    let tint: Color
    let highlighted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((highlighted ? tint.opacity(0.18) : Color(red: 0.94, green: 0.98, blue: 0.96)))
                    .frame(width: 30, height: 30)

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(highlighted ? tint : Color(red: 0.33, green: 0.55, blue: 0.48))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.31, blue: 0.27))

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(red: 0.43, green: 0.55, blue: 0.51))
            }

            Spacer(minLength: 8)

            TimePill(text: time, tint: tint, highlighted: highlighted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(highlighted ? tint.opacity(0.10) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(highlighted ? tint.opacity(0.30) : Color.clear, lineWidth: 1)
                )
        )
    }
}

private struct TimePill: View {
    let text: String
    let tint: Color
    let highlighted: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(highlighted ? .white : Color(red: 0.34, green: 0.48, blue: 0.44))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(highlighted ? tint : Color(red: 0.91, green: 0.96, blue: 0.94))
                    .overlay(
                        Capsule()
                            .stroke(highlighted ? tint.opacity(0.35) : Color(red: 0.79, green: 0.89, blue: 0.85), lineWidth: 1)
                    )
            )
    }
}

private struct SettingLine<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(label):")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.27, green: 0.46, blue: 0.40))
                .frame(width: 56, alignment: .leading)

            content
        }
    }
}

private struct SettingInputShell<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.96, green: 0.99, blue: 0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(red: 0.76, green: 0.87, blue: 0.83), lineWidth: 1)
                )
        )
        .shadow(color: Color(red: 0.14, green: 0.54, blue: 0.43).opacity(0.08), radius: 3, x: 0, y: 1)
    }
}

private struct WhiteCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(red: 0.84, green: 0.93, blue: 0.89), lineWidth: 1)
                    )
            )
            .shadow(color: Color(red: 0.20, green: 0.58, blue: 0.47).opacity(0.10), radius: 8, x: 0, y: 4)
    }
}

private struct TagBadge: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tint)
        )
    }
}

private struct FooterActionButton: View {
    let title: String
    let icon: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? .white : Color(red: 0.18, green: 0.47, blue: 0.40))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        filled
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.16, green: 0.58, blue: 0.47),
                                        Color(red: 0.22, green: 0.66, blue: 0.54),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(red: 0.75, green: 0.87, blue: 0.83), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
