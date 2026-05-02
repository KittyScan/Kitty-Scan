import SwiftUI
import MapKit
import CoreLocation
import UIKit

/// In-app sheet that shows vets nearest to the user's current location.
/// Uses CoreLocation for the fix + MKLocalSearch for "动物医院" / "animal hospital".
/// Tapping a row opens the chosen vet in Apple Maps with driving directions.
struct NearbyVetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang
    @Environment(ThemeProvider.self) private var themeProvider

    @State private var finder = VetsFinder()

    private var zh: Bool { lang.isChineseSelected }
    private var theme: CatTheme { themeProvider.theme }

    var body: some View {
        NavigationStack {
            Group {
                switch finder.state {
                case .idle, .loading:
                    loadingView
                case .ready:
                    readyView
                case .failed(let msg):
                    failedView(msg: msg)
                }
            }
            .navigationTitle(zh ? "附近兽医" : "Nearby vets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(zh ? "关闭" : "Close") { dismiss() }
                }
            }
        }
        .onAppear { if finder.state == .idle { finder.start(zh: zh) } }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(theme.deep)
            Text(zh ? "查找附近的宠物医院…" : "Finding nearby vets…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var readyView: some View {
        if finder.vets.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(zh ? "附近没找到宠物医院" : "No vets found nearby")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(zh ? "试试搜索范围更远的 Apple 地图" : "Try searching Apple Maps for a wider area")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    openMapsFallback()
                } label: {
                    Text(zh ? "打开 Apple 地图" : "Open Apple Maps")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Capsule().fill(theme.deep))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if let userCoord = finder.userLocation {
                    mapSection(userCoord: userCoord)
                        .frame(height: 220)
                }
                List {
                    ForEach(finder.vets) { vet in
                        vetRow(vet: vet)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func mapSection(userCoord: CLLocationCoordinate2D) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: userCoord,
            latitudinalMeters: 4000,
            longitudinalMeters: 4000
        ))) {
            UserAnnotation()
            ForEach(finder.vets.prefix(10)) { vet in
                Marker(vet.name, systemImage: "cross.case.fill",
                       coordinate: vet.coordinate)
                    .tint(theme.deep)
            }
        }
    }

    private func vetRow(vet: VetItem) -> some View {
        Button {
            vet.mapItem.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(theme.light.opacity(0.45))
                        .frame(width: 38, height: 38)
                    Image(systemName: "cross.case.fill")
                        .foregroundStyle(theme.deep)
                        .font(.system(size: 16, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(vet.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.deep)
                        .lineLimit(1)
                    if !vet.address.isEmpty {
                        Text(vet.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDistance(vet.distanceMeters))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.main)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func failedView(msg: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text(zh ? "无法获取定位" : "Can't get location")
                .font(.headline)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(zh ? "打开设置" : "Open Settings")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Capsule().fill(theme.deep))
                }
                Button {
                    openMapsFallback()
                } label: {
                    Text(zh ? "直接打开 Apple 地图" : "Open Apple Maps instead")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int(meters)) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    private func openMapsFallback() {
        let q = zh ? "宠物医院" : "animal hospital"
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// =========================================================
// VetsFinder — location + search state holder
// =========================================================
@Observable
@MainActor
final class VetsFinder {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    var state: LoadState = .idle
    var vets: [VetItem] = []
    var userLocation: CLLocationCoordinate2D?

    private var isChinese = true
    private let manager = CLLocationManager()
    private var delegate: LocationDelegate?

    func start(zh: Bool) {
        isChinese = zh
        state = .loading

        if delegate == nil {
            delegate = LocationDelegate(onAuth: { [weak self] s in
                Task { @MainActor in self?.handleAuth(s) }
            }, onLocation: { [weak self] c in
                Task { @MainActor in self?.handleLocation(c) }
            }, onError: { [weak self] e in
                Task { @MainActor in self?.handleError(e) }
            })
            manager.delegate = delegate
        }
        manager.desiredAccuracy = kCLLocationAccuracyKilometer

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            state = .failed(isChinese
                             ? "请在系统设置里允许 KittyScan 访问定位"
                             : "Please allow KittyScan to use Location in Settings")
        @unknown default:
            state = .failed("Unknown authorization status")
        }
    }

    private func handleAuth(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            state = .failed(isChinese
                             ? "请在系统设置里允许 KittyScan 访问定位"
                             : "Please allow KittyScan to use Location in Settings")
        default:
            break
        }
    }

    private func handleLocation(_ coord: CLLocationCoordinate2D) {
        userLocation = coord
        searchVets(near: coord)
    }

    private func handleError(_ error: Error) {
        state = .failed(error.localizedDescription)
    }

    private func searchVets(near coord: CLLocationCoordinate2D) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = isChinese ? "宠物医院" : "animal hospital"
        request.region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 25_000,
            longitudinalMeters: 25_000
        )
        let search = MKLocalSearch(request: request)
        let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

        Task { [weak self, isChinese] in
            guard let self else { return }
            do {
                let response = try await search.start()
                let items = response.mapItems.compactMap { mk -> VetItem? in
                    guard let loc = mk.placemark.location else { return nil }
                    let address = [mk.placemark.thoroughfare, mk.placemark.locality]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                    return VetItem(
                        name: mk.name ?? (isChinese ? "未命名" : "Unknown"),
                        address: address,
                        coordinate: loc.coordinate,
                        distanceMeters: origin.distance(from: loc),
                        mapItem: mk
                    )
                }.sorted { $0.distanceMeters < $1.distanceMeters }

                await MainActor.run {
                    self.vets = Array(items.prefix(15))
                    self.state = .ready
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }
}

struct VetItem: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    let mapItem: MKMapItem
}

// =========================================================
// CLLocationManager delegate shim (keeps VetsFinder @MainActor-clean)
// =========================================================
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    let onAuth: (CLAuthorizationStatus) -> Void
    let onLocation: (CLLocationCoordinate2D) -> Void
    let onError: (Error) -> Void

    init(onAuth: @escaping (CLAuthorizationStatus) -> Void,
         onLocation: @escaping (CLLocationCoordinate2D) -> Void,
         onError: @escaping (Error) -> Void) {
        self.onAuth = onAuth
        self.onLocation = onLocation
        self.onError = onError
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuth(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.first {
            onLocation(loc.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        onError(error)
    }
}
