# Verto – iOS Crypto Portfolio & Market App

Verto is a modern, real-time cryptocurrency portfolio and market tracking app for iOS, built with SwiftUI. It provides live prices, interactive charts, a global crypto activity map, portfolio management, and more—all with a beautiful, user-friendly interface.

---

## 🚀 Features

- **Live Crypto Prices:**
  - Real-time prices, market cap, and 24h change for all major cryptocurrencies (powered by CoinGecko API).
  - Infinite scrolling and pull-to-refresh for the full market list.
  - Sort by market cap, price, or % change.

- **Interactive Price Charts:**
  - Tap any coin to view its full price history (from origin to present) with interactive, zoomable charts.
  - Select time intervals (1D, 7D, 1M, 3M, 1Y, All).
  - Touch and hold to see exact price and date at any point.

- **Global Crypto Map:**
  - Interactive world map with pins for major trading cities.
  - Tap pins to view trading activity (demo data, ready for real integration).

- **Portfolio Tracking:**
  - Add your own positions (buy price, amount) and track profit/loss (feature in progress).

- **Watchlist:**
  - Save favorite coins for quick access (feature in progress).

- **Comprehensive Settings:**
  - Dark/light mode toggle, currency selection, data refresh rate, security, notifications, and more.

- **Modern UI:**
  - Clean, card-based design with gradients, glassmorphism, and smooth navigation.

---

## 📱 Screenshots
*Add screenshots here to showcase the app UI.*

---

## 🛠️ Getting Started

### Prerequisites
- Xcode 14+
- iOS 16+
- Swift 5.7+

### Setup
1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/verto-ios.git
   cd verto-ios
   ```
2. **Open in Xcode:**
   - Open `Verto.xcodeproj`.
3. **Build & Run:**
   - Select a simulator or your device and hit Run (▶️).

### Dependencies
- [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- [Charts](https://developer.apple.com/documentation/charts) (Apple)
- [MapKit](https://developer.apple.com/documentation/mapkit)
- [Combine](https://developer.apple.com/documentation/combine)
- [CoinGecko API](https://www.coingecko.com/en/api)

All dependencies are native or fetched via Swift Package Manager.

---

## 🏗️ Architecture
- **MVVM:** Each major view has a ViewModel for business logic and data fetching.
- **Services:**
  - `CoinGeckoService` for all market data.
  - `CoinHistoryService` for historical price charts.
- **SwiftUI Views:** Modular, reusable, and adaptive for dark/light mode.

---

## 🔒 Security & Privacy
- No user data is sent to any server except for public API requests (CoinGecko).
- Optional Face ID/Touch ID for portfolio protection (in progress).

---

## 🤝 Contributing
1. Fork the repo and create your branch: `git checkout -b feature/your-feature`
2. Commit your changes: `git commit -am 'Add new feature'`
3. Push to the branch: `git push origin feature/your-feature`
4. Open a Pull Request

---

## 📧 Feedback & Support
- Email: support@verto.app
- Issues: [GitHub Issues](https://github.com/yourusername/verto-ios/issues)

---

## 📄 License
MIT License. See [LICENSE](LICENSE) for details. 