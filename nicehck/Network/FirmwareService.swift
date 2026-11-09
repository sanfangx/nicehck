import Foundation
import Combine

struct FirmwareInfo: Codable, Equatable {
    let id: Int?
    let deviceId: Int
    let deviceName: String
    let firmwareName: String
    let firmwareVersion: Int
    let firmwareDesc: String
    let downloadUrl: String
}

struct FirmwareVersionResponse: Codable {
    let code: Int
    let data: FirmwareInfo?
}

enum FirmwareUpdateState: Equatable {
    case checking
    case shouldUpdate(FirmwareInfo)
    case noUpdate(FirmwareInfo?)
    case downloading(FirmwareInfo)
    case downloadComplete(FirmwareInfo, Data)
    case failed(String)
    case networkFailed
}

/// Exact implementation of `FirmwareAPIService` (`0x100026088 .. 0x10002691c`)
final class FirmwareAPIService {
    static let shared = FirmwareAPIService()

    /// Exact endpoint from `0x1000260cc` & `0x100026208`
    private let baseURL = "https://nicehck.cn/api/app/firmware"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }

    func getLatestVersion(deviceId: Int) async throws -> FirmwareVersionResponse {
        guard let url = URL(string: "\(baseURL)/latestVersion?deviceId=\(deviceId)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(FirmwareVersionResponse.self, from: data)
    }

    func downloadFirmware(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw URLError(.cannotDecodeContentData)
        }
        return data
    }
}

/// Exact implementation of `FirmwareRepository` (`0x1000213cc .. 0x100021be8`)
@MainActor
final class FirmwareRepository: ObservableObject {
    @Published var updateState: FirmwareUpdateState = .checking

    func checkFirmwareUpdate(deviceId: Int, currentVersion: Int) async {
        updateState = .checking
        do {
            let response = try await FirmwareAPIService.shared.getLatestVersion(deviceId: deviceId)
            if response.code == 200, let info = response.data {
                if currentVersion > 0 && info.firmwareVersion > currentVersion {
                    updateState = .shouldUpdate(info)
                } else {
                    updateState = .noUpdate(info)
                }
            } else {
                updateState = .noUpdate(nil)
            }
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                updateState = .networkFailed
            default:
                updateState = .failed(urlError.localizedDescription)
            }
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func downloadFirmware(info: FirmwareInfo) async {
        updateState = .downloading(info)
        do {
            let data = try await FirmwareAPIService.shared.downloadFirmware(from: info.downloadUrl)
            updateState = .downloadComplete(info, data)
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }
}
