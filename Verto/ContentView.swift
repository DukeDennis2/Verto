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

// MARK: - PricesViewModel (pagination & refresh)
class PricesViewModel: ObservableObject {
    @Published var coins: [Coin] = []
    @Published var sortOption: SortOption = .marketCap
    @Published var isLoading = false
    @Published var isRefreshing = false
    private var cancellables = Set<AnyCancellable>()
    private var currentPage = 1
    private let perPage = 50
    private var canLoadMore = true
    
    enum SortOption: String, CaseIterable, Identifiable {
        case marketCap = "Market Cap"
        case price = "Price"
        case percentChange = "% Change"
        var id: String { self.rawValue }
    }
    
    init() {
        fetchCoins(reset: true)
    }
    
    func fetchCoins(reset: Bool = false) {
        if isLoading { return }
        isLoading = true
        if reset {
            currentPage = 1
            canLoadMore = true
        }
        CoinGeckoService.shared.fetchCoins(page: currentPage, perPage: perPage)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                self?.isRefreshing = false
            }, receiveValue: { [weak self] newCoins in
                guard let self = self else { return }
                if reset {
                    self.coins = newCoins
                } else {
                    self.coins.append(contentsOf: newCoins)
                }
                self.canLoadMore = newCoins.count == self.perPage
                self.sortCoins()
                if self.canLoadMore { self.currentPage += 1 }
            })
            .store(in: &cancellables)
    }
    
    func loadMoreIfNeeded(currentCoin: Coin) {
        guard canLoadMore, !isLoading else { return }
        let thresholdIndex = coins.index(coins.endIndex, offsetBy: -10)
        if coins.firstIndex(where: { $0.id == currentCoin.id }) == thresholdIndex {
            fetchCoins()
        }
    }
    
    func refresh() {
        isRefreshing = true
        fetchCoins(reset: true)
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

// MARK: - CoinGeckoService (pagination support)
extension CoinGeckoService {
    func fetchCoins(page: Int, perPage: Int) -> AnyPublisher<[Coin], Error> {
        let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=\(perPage)&page=\(page)&sparkline=false&price_change_percentage=24h")!
        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [Coin].self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
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

// MARK: - CoinDetailViewModel (default to 'All' interval)
class CoinDetailViewModel: ObservableObject {
    @Published var history: [CoinHistoryPoint] = []
    @Published var isLoading = false
    @Published var selectedInterval: CoinHistoryService.Interval = .all
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

// MARK: - CoinDetailView (default to 'All' interval)
struct CoinDetailView: View {
    let coin: Coin
    @StateObject private var viewModel = CoinDetailViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
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
                            Text(coin.symbol.uppercased())
                                .font(.subheadline)
                        }
                        Spacer()
                    }
                    .padding(.top)
                    // Summary Card
                    HStack(spacing: 24) {
                        VStack {
                            Text("Current Price")
                                .font(.caption)
                            Text("$\(String(format: "%.2f", coin.price))")
                                .font(.title2).bold()
                        }
                        VStack {
                            Text("24h Change")
                                .font(.caption)
                            Text("\(String(format: "%+.2f", coin.percentChange))%")
                                .font(.title2).bold()
                                .foregroundColor(coin.percentChange >= 0 ? .green : .red)
                        }
                        VStack {
                            Text("Market Cap")
                                .font(.caption)
                            Text(coin.market_cap != nil ? "$\(Int(coin.market_cap!))" : "-")
                                .font(.title3)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.95))
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
                    .onChange(of: viewModel.selectedInterval) { _, newInterval in
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
                                    Spacer()
                                    Text(selected.date, style: .date)
                                    Text(selected.date, style: .time)
                                }
                                .padding(.vertical, 4)
                            }
                        } else {
                            Text("No chart data available.")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.95))
                            .shadow(radius: 4)
                    )
                }
                .padding()
            }
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            viewModel.selectedInterval = .all
            viewModel.fetchHistory(for: coin.id, interval: .all)
        }
    }
}

// MARK: - PricesView (infinite scroll & pull-to-refresh)
struct PricesView: View {
    @StateObject private var viewModel = PricesViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white
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
                            .fill(Color.white.opacity(0.95))
                            .shadow(radius: 2)
                    )
                    .padding(.horizontal)
                    
                    if viewModel.isLoading && viewModel.coins.isEmpty {
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
                                            .onAppear {
                                                viewModel.loadMoreIfNeeded(currentCoin: coin)
                                            }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                if viewModel.isLoading && !viewModel.coins.isEmpty {
                                    ProgressView()
                                        .padding()
                                }
                            }
                            .padding(.vertical)
                            .refreshable {
                                viewModel.refresh()
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .navigationTitle("Crypto Prices")
                .foregroundColor(.primary)
            }
        }
        .onChange(of: viewModel.sortOption) { _, _ in
            viewModel.sortCoins()
        }
    }
}

// MARK: - CoinRowView (improved readability)
struct CoinRowView: View {
    let coin: Coin
    @Environment(\.colorScheme) var colorScheme
    
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
                Text(coin.symbol.uppercased())
                    .font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(String(format: "%.2f", coin.price))")
                    .font(.headline)
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
                .fill(Color.white.opacity(0.95))
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
                    .fill(Color.white.opacity(0.95))
                    .shadow(radius: 4)
            )
            .padding()
        }
        .navigationTitle("Crypto Map")
    }
}

// MARK: - Portfolio Models
struct PortfolioPosition: Identifiable {
    let id = UUID()
    let coin: String
    let symbol: String
    let amount: Double
    let buyPrice: Double
    let currentPrice: Double
    var value: Double { amount * currentPrice }
    var cost: Double { amount * buyPrice }
    var profit: Double { value - cost }
    var percent: Double { (profit / cost) * 100 }
}

// MARK: - CoinListItem for Picker
struct CoinListItem: Identifiable, Decodable {
    let id: String
    let symbol: String
    let name: String
    let image: String?
    let current_price: Double
}

// MARK: - CoinGeckoService (all coins for picker)
extension CoinGeckoService {
    func fetchAllCoinsForPicker() -> AnyPublisher<[CoinListItem], Error> {
        let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=250&page=1&sparkline=false")!
        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [CoinListItem].self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// MARK: - Portfolio Sub-Views
struct PortfolioSummaryView: View {
    let totalValue: Double
    let totalProfit: Double
    let totalPercent: Double
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Total Portfolio Value")
                .font(.caption)
            Text("$\(String(format: "%.2f", totalValue))")
                .font(.title).bold()
            HStack(spacing: 24) {
                VStack {
                    Text("Unrealized P/L")
                        .font(.caption2)
                    Text("$\(String(format: "%.2f", totalProfit))")
                        .font(.headline)
                        .foregroundColor(totalProfit >= 0 ? .green : .red)
                }
                VStack {
                    Text("% Gain/Loss")
                        .font(.caption2)
                    Text("\(String(format: "%+.2f", totalPercent))%")
                        .font(.headline)
                        .foregroundColor(totalPercent >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.95))
                .shadow(radius: 4)
        )
    }
}

struct PositionRowView: View {
    let position: PortfolioPosition
    let onDelete: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text(position.coin)
                    .font(.headline)
                Text(position.symbol.uppercased())
                    .font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Holdings: \(position.amount, specifier: "%.4f")")
                    .font(.caption)
                Text("Buy: $\(position.buyPrice, specifier: "%.2f")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Now: $\(position.currentPrice, specifier: "%.2f")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .trailing) {
                Text("$\(position.value, specifier: "%.2f")")
                    .font(.headline)
                    .foregroundColor(colorScheme == .dark ? .black : .primary)
                Text("\(position.percent >= 0 ? "+" : "")\(position.percent, specifier: "%.2f")%")
                    .font(.caption)
                    .foregroundColor(position.percent >= 0 ? .green : .red)
            }
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.95))
                .shadow(radius: 2)
        )
    }
}

struct CoinPickerSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedCoin: CoinListItem?
    @Binding var searchText: String
    let coins: [CoinListItem]
    let isLoading: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var filteredCoins: [CoinListItem] {
        if searchText.isEmpty { return coins }
        return coins.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.symbol.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                if isLoading {
                    ProgressView()
                } else {
                    List(filteredCoins, id: \.id) { coin in
                        Button(action: {
                            selectedCoin = coin
                            isPresented = false
                        }) {
                            HStack(spacing: 12) {
                                if let url = coin.image.flatMap(URL.init) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        Color.gray.opacity(0.2)
                                    }
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                                }
                                VStack(alignment: .leading) {
                                    Text(coin.name)
                                        .font(.body)
                                    Text(coin.symbol.uppercased())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("$\(String(format: "%.2f", coin.current_price))")
                                    .font(.subheadline)
                                    .foregroundColor(colorScheme == .dark ? .black : .primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Coin")
            .toolbar { 
                ToolbarItem(placement: .cancellationAction) { 
                    Button("Cancel") { isPresented = false } 
                } 
            }
        }
    }
}

// MARK: - PortfolioView (simplified)
struct PortfolioView: View {
    @State private var positions: [PortfolioPosition] = [
        PortfolioPosition(coin: "Bitcoin", symbol: "BTC", amount: 0.5, buyPrice: 40000, currentPrice: 67000),
        PortfolioPosition(coin: "Ethereum", symbol: "ETH", amount: 2, buyPrice: 2000, currentPrice: 3500)
    ]
    @State private var showAdd = false
    @State private var showCoinPicker = false
    @State private var coinSearch = ""
    @State private var allCoins: [CoinListItem] = []
    @State private var isLoadingCoins = false
    @State private var newCoin: CoinListItem? = nil
    @State private var newAmount = ""
    @State private var newBuyPrice = ""
    @State private var cancellables = Set<AnyCancellable>()
    @Environment(\.colorScheme) var colorScheme
    
    var totalValue: Double { positions.reduce(0) { $0 + $1.value } }
    var totalCost: Double { positions.reduce(0) { $0 + $1.cost } }
    var totalProfit: Double { totalValue - totalCost }
    var totalPercent: Double { totalCost > 0 ? (totalProfit / totalCost) * 100 : 0 }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                PortfolioSummaryView(
                    totalValue: totalValue,
                    totalProfit: totalProfit,
                    totalPercent: totalPercent
                )
                
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(positions) { position in
                            PositionRowView(position: position) {
                                positions.removeAll { $0.id == position.id }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .padding(.horizontal, 8)
                
                Button(action: {
                    showAdd = true
                    if allCoins.isEmpty {
                        loadCoins()
                    }
                }) {
                    Label("Add Position", systemImage: "plus")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Portfolio")
            .sheet(isPresented: $showAdd) {
                AddPositionSheet(
                    isPresented: $showAdd,
                    newCoin: $newCoin,
                    newAmount: $newAmount,
                    newBuyPrice: $newBuyPrice,
                    showCoinPicker: $showCoinPicker,
                    onAdd: addPosition
                )
            }
            .sheet(isPresented: $showCoinPicker) {
                CoinPickerSheet(
                    isPresented: $showCoinPicker,
                    selectedCoin: $newCoin,
                    searchText: $coinSearch,
                    coins: allCoins,
                    isLoading: isLoadingCoins
                )
            }
        }
    }
    
    private func loadCoins() {
        isLoadingCoins = true
        CoinGeckoService.shared.fetchAllCoinsForPicker()
            .sink(receiveCompletion: { _ in isLoadingCoins = false }, receiveValue: { coins in
                allCoins = coins
            })
            .store(in: &cancellables)
    }
    
    private func addPosition() {
        if let coin = newCoin, let amt = Double(newAmount), let buy = Double(newBuyPrice) {
            positions.append(PortfolioPosition(coin: coin.name, symbol: coin.symbol, amount: amt, buyPrice: buy, currentPrice: coin.current_price))
            newCoin = nil
            newAmount = ""
            newBuyPrice = ""
            showAdd = false
        }
    }
}

struct AddPositionSheet: View {
    @Binding var isPresented: Bool
    @Binding var newCoin: CoinListItem?
    @Binding var newAmount: String
    @Binding var newBuyPrice: String
    @Binding var showCoinPicker: Bool
    let onAdd: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Position")
                .font(.title2).bold()
            
            Button(action: { showCoinPicker = true }) {
                HStack {
                    if let coin = newCoin, let url = coin.image.flatMap(URL.init) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    }
                    Text(newCoin?.name ?? "Select Coin")
                        .foregroundColor(colorScheme == .dark ? .black : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
            }
            
            if let coin = newCoin {
                HStack {
                    Text("Symbol: ")
                    Text(coin.symbol.uppercased())
                        .bold()
                }
                HStack {
                    Text("Current Price: ")
                    Text("$\(String(format: "%.2f", coin.current_price))")
                        .bold()
                }
            }
            
#if os(iOS)
            TextField("Amount", text: $newAmount)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Buy Price", text: $newBuyPrice)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
#else
            TextField("Amount", text: $newAmount)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Buy Price", text: $newBuyPrice)
                .textFieldStyle(RoundedBorderTextFieldStyle())
#endif
            
            Button("Add", action: onAdd)
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            
            Button("Cancel") { isPresented = false }
                .foregroundColor(.red)
                .padding(.top, 4)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - WatchlistView (basic)
struct WatchlistView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
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
    @Environment(\.colorScheme) var colorScheme
    
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
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    var body: some View {
        MainTabView()
            .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}

#Preview {
    ContentView()
}
