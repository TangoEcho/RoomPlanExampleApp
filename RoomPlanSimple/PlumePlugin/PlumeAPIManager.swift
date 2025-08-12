import Foundation
import Combine

// MARK: - Plume API Manager

class PlumeAPIManager: ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var availableDevices: [PlumeDevice] = []
    @Published var currentConnection: PlumeConnection?
    @Published var lastError: PluginError?
    
    private let configuration: PlumePlugin.PlumeConfiguration
    private var session: URLSession
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - API Endpoints
    private enum Endpoint {
        case devices
        case connect(deviceId: String)
        case steer(deviceId: String, band: String)
        case status
        
        func url(baseURL: String) -> URL? {
            let base = URL(string: baseURL)
            switch self {
            case .devices:
                return base?.appendingPathComponent("devices")
            case .connect(let deviceId):
                return base?.appendingPathComponent("devices/\(deviceId)/connect")
            case .steer(let deviceId, let band):
                return base?.appendingPathComponent("devices/\(deviceId)/steer")
            case .status:
                return base?.appendingPathComponent("status")
            }
        }
    }
    
    init(configuration: PlumePlugin.PlumeConfiguration) {
        self.configuration = configuration
        
        // Configure URL session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        
        if let authToken = configuration.authToken {
            config.httpAdditionalHeaders = [
                "Authorization": "Bearer \(authToken)",
                "Content-Type": "application/json"
            ]
        }
        
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Connection Management
    
    func connect() async throws {
        await updateConnectionStatus(.connecting)
        
        do {
            // Discover available devices
            let devices = try await discoverDevices()
            
            await MainActor.run {
                self.availableDevices = devices
                self.connectionStatus = .connected
            }
            
            // Get current connection status
            if let currentConn = try await getCurrentConnectionStatus() {
                await MainActor.run {
                    self.currentConnection = currentConn
                }
            }
            
            print("🌐 Connected to Plume API - found \(devices.count) devices")
            
        } catch {
            await updateConnectionStatus(.error(error.localizedDescription))
            throw PluginError.apiError(error.localizedDescription)
        }
    }
    
    func disconnect() async {
        session.invalidateAndCancel()
        
        await MainActor.run {
            self.connectionStatus = .disconnected
            self.availableDevices = []
            self.currentConnection = nil
        }
        
        cancellables.removeAll()
    }
    
    @MainActor
    private func updateConnectionStatus(_ status: ConnectionStatus) {
        self.connectionStatus = status
    }
    
    // MARK: - Device Discovery
    
    private func discoverDevices() async throws -> [PlumeDevice] {
        guard let url = Endpoint.devices.url(baseURL: configuration.apiEndpoint) else {
            throw PluginError.apiError("Invalid endpoint URL")
        }
        
        let request = URLRequest(url: url)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PluginError.apiError("Invalid response type")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw PluginError.apiError("HTTP \(httpResponse.statusCode)")
            }
            
            let deviceResponse = try JSONDecoder().decode(DeviceListResponse.self, from: data)
            return deviceResponse.devices
            
        } catch {
            throw PluginError.apiError("Device discovery failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Connection Status
    
    private func getCurrentConnectionStatus() async throws -> PlumeConnection? {
        guard let url = Endpoint.status.url(baseURL: configuration.apiEndpoint) else {
            throw PluginError.apiError("Invalid status endpoint")
        }
        
        let request = URLRequest(url: url)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                return nil // No current connection
            }
            
            let statusResponse = try JSONDecoder().decode(ConnectionStatusResponse.self, from: data)
            return statusResponse.connection
            
        } catch {
            print("⚠️ Failed to get connection status: \(error)")
            return nil
        }
    }
    
    // MARK: - Device Steering
    
    func steerToDevice(_ device: PlumeDevice) async throws -> SteeringResult {
        guard let url = Endpoint.connect(deviceId: device.id).url(baseURL: configuration.apiEndpoint) else {
            throw PluginError.apiError("Invalid connect endpoint")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let connectRequest = ConnectRequest(
            deviceId: device.id,
            networkId: configuration.networkId ?? "default"
        )
        
        request.httpBody = try JSONEncoder().encode(connectRequest)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PluginError.apiError("Invalid response")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw PluginError.apiError("Steering failed: HTTP \(httpResponse.statusCode)")
            }
            
            let steeringResponse = try JSONDecoder().decode(SteeringResponse.self, from: data)
            
            // Update current connection
            await MainActor.run {
                self.currentConnection = steeringResponse.connection
            }
            
            return SteeringResult(
                success: steeringResponse.success,
                band: steeringResponse.connection?.band,
                device: device,
                signalStrength: steeringResponse.connection?.signalStrength ?? -70,
                stabilizationTime: steeringResponse.stabilizationTime,
                timestamp: Date()
            )
            
        } catch {
            throw PluginError.apiError("Device steering failed: \(error.localizedDescription)")
        }
    }
    
    func steerToBand(_ band: WiFiFrequencyBand, device: PlumeDevice) async throws -> SteeringResult {
        guard let url = Endpoint.steer(deviceId: device.id, band: band.rawValue).url(baseURL: configuration.apiEndpoint) else {
            throw PluginError.apiError("Invalid steer endpoint")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let steerRequest = BandSteeringRequest(
            band: band.rawValue,
            networkId: configuration.networkId ?? "default"
        )
        
        request.httpBody = try JSONEncoder().encode(steerRequest)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PluginError.apiError("Invalid response")
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw PluginError.apiError("Band steering failed: HTTP \(httpResponse.statusCode)")
            }
            
            let steeringResponse = try JSONDecoder().decode(SteeringResponse.self, from: data)
            
            // Update current connection
            await MainActor.run {
                self.currentConnection = steeringResponse.connection
            }
            
            return SteeringResult(
                success: steeringResponse.success,
                band: band,
                device: device,
                signalStrength: steeringResponse.connection?.signalStrength ?? -70,
                stabilizationTime: steeringResponse.stabilizationTime,
                timestamp: Date()
            )
            
        } catch {
            throw PluginError.apiError("Band steering failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - API Request/Response Models

private struct DeviceListResponse: Codable {
    let devices: [PlumeDevice]
    let networkId: String
    let timestamp: Date
}

private struct ConnectionStatusResponse: Codable {
    let connection: PlumeConnection?
    let networkId: String
    let timestamp: Date
}

private struct ConnectRequest: Codable {
    let deviceId: String
    let networkId: String
}

private struct BandSteeringRequest: Codable {
    let band: String
    let networkId: String
}

private struct SteeringResponse: Codable {
    let success: Bool
    let connection: PlumeConnection?
    let stabilizationTime: TimeInterval
    let message: String?
}