//
//  ContentView.swift
//  Verto
//
//  Created by miguel corachea on 15/07/2025.
//

import SwiftUI
import Combine
import Charts
import MapKit

// MARK: - Coin Model (updated for CoinGecko API)
struct Coin: Identifiable, Decodable {
    let id: String
    let symbol: String
    let name: String
    let image: String?
    let current_price: Double
    let market_cap: Double?
    let price_change_percentage_24h: Double?
    
    var percentChange: Double { price_change_percentage_24h ?? 0 }
    var price: Double { current_price }
}

// MARK: - CoinGecko Service
class CoinGeckoService {
    static let shared = CoinGeckoService()
    private let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=50&page=1&sparkline=false&price_change_percentage=24h")!
    
    func fetchCoins() -> AnyPublisher<[Coin], Error> {
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [Coin].self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// MARK: - PricesViewModel
class PricesViewModel: ObservableObject {
    @Published var coins: [Coin] = []
    @Published var sortOption: SortOption = .marketCap
    @Published var isLoading = false
    private var cancellables = Set<AnyCancellable>()
    
    enum SortOption: String, CaseIterable, Identifiable {
        case marketCap = "Market Cap"
        case price = "Price"
        case percentChange = "% Change"
        var id: String { self.rawValue }
    }
    
    init() {
        fetchCoins()
    }
    
    func fetchCoins() {
        isLoading = true
        CoinGeckoService.shared.fetchCoins()
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
            }, receiveValue: { [weak self] coins in
                self?.coins = coins
                self?.sortCoins()
            })
            .store(in: &cancellables)
    }
    
    func sortCoins() {
        switch sortOption {
        case .marketCap:
            coins.sort { ($0.market_cap ?? 0) > ($1.market_cap ?? 0) }
        case .price:
            coins.sort { $0.price > $1.price }
        case .percentChange:
            coins.sort { $0.percentChange > $1.percentChange }
        }
    }
}

// MARK: - CoinHistory Model
struct CoinHistoryPoint: Decodable, Identifiable {
    let id = UUID()
    let price: Double
    let date: Date
    
    init(from array: [Double]) {
        self.date = Date(timeIntervalSince1970: array[0] / 1000)
        self.price = array[1]
    }
}

// MARK: - CoinHistoryService
class CoinHistoryService {}

// MARK: - CoinHistoryService (with interval support)
extension CoinHistoryService {
    enum Interval: String, CaseIterable, Identifiable {
        case day = "1D"
        case week = "7D"
        case month = "1M"
        case threeMonth = "3M"
        case year = "1Y"
        case all = "All"
        var id: String { self.rawValue }
        var daysParam: String {
            switch self {
            case .day: return "1"
            case .week: return "7"
            case .month: return "30"
            case .threeMonth: return "90"
            case .year: return "365"
            case .all: return "max"
            }
        }
    }
    static func fetchHistory(for coinId: String, interval: Interval) -> AnyPublisher<[CoinHistoryPoint], Error> {
        let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart?vs_currency=usd&days=\(interval.daysParam)")!
        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [String: [[Double]]].self, decoder: JSONDecoder())
            .map { dict in
                (dict["prices"] ?? []).map { CoinHistoryPoint(from: $0) }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// MARK: - CoinDetailViewModel (with interval)
class CoinDetailViewModel: ObservableObject {
    @Published var history: [CoinHistoryPoint] = []
    @Published var isLoading = false
    @Published var selectedInterval: CoinHistoryService.Interval = .week
    @Published var selectedPoint: CoinHistoryPoint? = nil
    private var cancellables = Set<AnyCancellable>()
    var coinId: String = ""
    
    func fetchHistory(for coinId: String, interval: CoinHistoryService.Interval? = nil) {
        self.coinId = coinId
        let intervalToUse = interval ?? selectedInterval
        isLoading = true
        CoinHistoryService.fetchHistory(for: coinId, interval: intervalToUse)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isLoading = false
            }, receiveValue: { [weak self] points in
                self?.history = points
                self?.selectedPoint = nil
            })
            .store(in: &cancellables)
    }
}

// MARK: - Accent Gradient
extension LinearGradient {
    static let accentGradient = LinearGradient(
        gradient: Gradient(colors: [Color.blue, Color.purple]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - CoinDetailView (chart visibility fix)
struct CoinDetailView: View {
    let coin: Coin
    @StateObject private var viewModel = CoinDetailViewModel()
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        if let imageUrl = coin.image, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                        }
                        VStack(alignment: .leading) {
                            Text(coin.name)
                                .font(.title2).bold()
                                .foregroundColor(.primary)
                            Text(coin.symbol.uppercased())
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top)
                    // Summary Card
                    HStack(spacing: 24) {
                        VStack {
                            Text("Current Price")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("$\(String(format: "%.2f", coin.price))")
                                .font(.title2).bold()
                                .foregroundColor(.primary)
                        }
                        VStack {
                            Text("24h Change")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%+.2f", coin.percentChange))%")
                                .font(.title2).bold()
                                .foregroundColor(coin.percentChange >= 0 ? .green : .red)
                        }
                        VStack {
                            Text("Market Cap")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(coin.market_cap != nil ? "$\(Int(coin.market_cap!))" : "-")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground).opacity(0.95))
                            .shadow(radius: 4)
                    )
                    // Interval Picker
                    Picker("Interval", selection: $viewModel.selectedInterval) {
                        ForEach(CoinHistoryService.Interval.allCases) { interval in
                            Text(interval.rawValue).tag(interval)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.bottom)
                    .onChange(of: viewModel.selectedInterval) { newInterval in
                        viewModel.fetchHistory(for: coin.id, interval: newInterval)
                    }
                    // Chart Card
                    VStack {
                        if viewModel.isLoading {
                            ProgressView("Loading chart...")
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if !viewModel.history.isEmpty {
                            Chart {
                                ForEach(viewModel.history) { point in
                                    LineMark(
                                        x: .value("Date", point.date),
                                        y: .value("Price", point.price)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(Color.blue)
                                    .accessibilityLabel("\(point.price)")
                                }
                                if let selected = viewModel.selectedPoint {
                                    PointMark(
                                        x: .value("Date", selected.date),
                                        y: .value("Price", selected.price)
                                    )
                                    .symbolSize(80)
                                    .foregroundStyle(.red)
                                }
                            }
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                                        .gesture(DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let location = value.location
                                                if let date: Date = proxy.value(atX: location.x) {
                                                    let closest = viewModel.history.min(by: { abs($0.date.timeIntervalSince1970 - date.timeIntervalSince1970) < abs($1.date.timeIntervalSince1970 - date.timeIntervalSince1970) })
                                                    viewModel.selectedPoint = closest
                                                }
                                            }
                                            .onEnded { _ in }
                                        )
                                }
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 250)
                            .padding(.vertical)
                            // Show marker info
                            if let selected = viewModel.selectedPoint {
                                HStack {
                                    Text("$\(String(format: "%.2f", selected.price))")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(selected.date, style: .date)
                                        .foregroundColor(.secondary)
                                    Text(selected.date, style: .time)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        } else {
                            Text("No chart data available.")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground).opacity(0.95))
                            .shadow(radius: 4)
                    )
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PricesView (improved readability)
struct PricesView: View {
    @StateObject private var viewModel = PricesViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
        VStack {
                    Picker("Sort by", selection: $viewModel.sortOption) {
                        ForEach(PricesViewModel.SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding([.top, .horizontal])
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemBackground).opacity(0.95))
                            .shadow(radius: 2)
                    )
                    .padding(.horizontal)
                    
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView("Loading prices...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(viewModel.coins) { coin in
                                    NavigationLink(destination: CoinDetailView(coin: coin)) {
                                        CoinRowView(coin: coin)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.vertical)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .navigationTitle("Crypto Prices")
                .foregroundColor(.primary)
            }
        }
        .onChange(of: viewModel.sortOption) { _ in
            viewModel.sortCoins()
        }
    }
}

// MARK: - CoinRowView (improved readability)
struct CoinRowView: View {
    let coin: Coin
    var body: some View {
        HStack(spacing: 16) {
            if let imageUrl = coin.image, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .shadow(radius: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(coin.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(coin.symbol.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(String(format: "%.2f", coin.price))")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("\(String(format: "%+.2f", coin.percentChange))%")
                    .font(.caption)
                    .foregroundColor(coin.percentChange >= 0 ? .green : .red)
            }
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - CryptoCity for Map Annotations
struct CryptoCity: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let volume: String
}

// MARK: - CryptoMapView (basic interactive map)
struct CryptoMapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 180)
    )
    let exampleCities: [CryptoCity] = [
        CryptoCity(name: "New York", coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), volume: "$2.1B"),
        CryptoCity(name: "London", coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278), volume: "$1.7B"),
        CryptoCity(name: "Tokyo", coordinate: CLLocationCoordinate2D(latitude: 35.6895, longitude: 139.6917), volume: "$2.5B"),
        CryptoCity(name: "Singapore", coordinate: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198), volume: "$1.2B")
    ]
    @State private var selectedCity: CryptoCity? = nil
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Map(coordinateRegion: $region, annotationItems: exampleCities, annotationContent: { city in
                MapAnnotation(coordinate: city.coordinate) {
                    Button(action: {
                        selectedCity = city
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: "bitcoinsign.circle.fill")
                                .font(.title)
                                .foregroundColor(.orange)
                            Text(city.name)
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                    }
                }
            })
            .ignoresSafeArea()
            // Card overlay
            VStack {
                if let city = selectedCity {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(city.name)
                                .font(.headline)
                            Text("Trading Volume: \(city.volume)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Close") { selectedCity = nil }
                            .foregroundColor(.blue)
                    }
                    .padding()
                } else {
                    HStack {
                        Image(systemName: "map")
                            .foregroundColor(.blue)
                        Text("Tap a pin to see trading activity")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground).opacity(0.95))
                    .shadow(radius: 4)
            )
            .padding()
        }
        .navigationTitle("Crypto Map")
    }
}

struct PortfolioView: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack {
                Image(systemName: "chart.pie")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Portfolio")
            }
        }
    }
}

struct WatchlistView: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack {
                Image(systemName: "star")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Watchlist")
            }
        }
    }
}

// MARK: - SettingsView (comprehensive)
struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @State private var notificationsEnabled: Bool = true
    @State private var useBiometrics: Bool = false
    @State private var selectedCurrency: String = "USD"
    @State private var refreshRate: Double = 30
    @State private var showAbout = false
    @State private var showFeedback = false
    let currencies = ["USD", "EUR", "GBP", "JPY", "BTC", "ETH"]
    let refreshOptions: [Double] = [5, 15, 30, 60, 300]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Toggle(isOn: $isDarkMode) {
                        Label("Dark Mode", systemImage: "moon.fill")
                    }
                }
                Section(header: Text("Notifications")) {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Enable Notifications", systemImage: "bell.fill")
                    }
                    NavigationLink(destination: Text("Set price alerts and market notifications here.")) {
                        Label("Manage Alerts", systemImage: "exclamationmark.bubble.fill")
                    }
                }
                Section(header: Text("Security")) {
                    Toggle(isOn: $useBiometrics) {
                        Label("Use Face ID / Touch ID", systemImage: "faceid")
                    }
                    NavigationLink(destination: Text("Sign in with Apple coming soon.")) {
                        Label("Sign in with Apple", systemImage: "applelogo")
                    }
                }
                Section(header: Text("Currency")) {
                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                Section(header: Text("Data Refresh"), footer: Text("How often prices and portfolio update.")) {
                    Picker("Refresh Rate", selection: $refreshRate) {
                        ForEach(refreshOptions, id: \.self) { rate in
                            Text("Every \(Int(rate))s").tag(rate)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Section(header: Text("About")) {
                    Button(action: { showAbout = true }) {
                        Label("About Verto", systemImage: "info.circle.fill")
                    }
                    Button(action: { showFeedback = true }) {
                        Label("Send Feedback", systemImage: "envelope.fill")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAbout) {
                VStack(spacing: 16) {
                    Text("Verto Crypto App")
                        .font(.title)
                        .bold()
                    Text("Version 1.0.0")
                        .foregroundColor(.secondary)
                    Text("Built with ❤️ for crypto enthusiasts.\n\nThis app is for informational purposes only and does not constitute financial advice.")
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                    Button("Close") { showAbout = false }
                        .padding()
                }
                .padding()
            }
            .sheet(isPresented: $showFeedback) {
                VStack(spacing: 16) {
                    Text("Send Feedback")
                        .font(.title2)
                        .bold()
                    Text("We value your feedback! Please email us at support@verto.app or use the form below (coming soon).")
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                    Button("Close") { showFeedback = false }
                        .padding()
                }
                .padding()
            }
        }
    }
}

// Move MainTabView above ContentView so it's in scope
struct MainTabView: View {
    var body: some View {
        TabView {
            CryptoMapView()
                .tabItem { Label("Map", systemImage: "map") }
            PricesView()
                .tabItem { Label("Prices", systemImage: "bitcoinsign.circle") }
            PortfolioView()
                .tabItem { Label("Portfolio", systemImage: "chart.pie") }
            WatchlistView()
                .tabItem { Label("Watchlist", systemImage: "star") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
}
