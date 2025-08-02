import Foundation
import CoreData
import CloudKit
import Combine

@MainActor
class ICloudSyncStatusProvider: ObservableObject {
    @Published var detailedSyncStatus: DetailedCloudKitSyncStatus = .uncertain

    private var lastSyncDate: Date?
    private var lastSyncError: String?
    private var internalSyncStatus: CloudKitSyncStatus = .notSyncing
    
    private var syncTimeoutTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let container: NSPersistentCloudKitContainer
    private let cloudKitService: CloudKitService

    init(container: NSPersistentCloudKitContainer, cloudKitService: CloudKitService) {
        self.container = container
        self.cloudKitService = cloudKitService
        
        startStatusObservers()
        monitorCloudKitEvents()
        
        // Initial check
        updateDetailedSyncStatus()
    }

    func triggerCloudKitSync() {
        print("ICloudSyncStatusProvider: Manually triggering sync...")
        syncTimeoutTimer?.invalidate()

        self.internalSyncStatus = .syncing
        self.lastSyncError = nil
        updateDetailedSyncStatus()

        do {
            try container.initializeCloudKitSchema()
        } catch {
            print("ICloudSyncStatusProvider: Error trying to poke container for sync: \(error)")
        }

        syncTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            if self.internalSyncStatus == .syncing {
                print("ICloudSyncStatusProvider: Sync timeout reached. No event received, resetting status.")
                self.internalSyncStatus = .synced
                self.updateDetailedSyncStatus()
            }
        }
    }

    private func monitorCloudKitEvents() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                    return
                }

                switch event.type {
                case .setup:
                    self.internalSyncStatus = .notSyncing
                    self.syncTimeoutTimer?.invalidate()
                case .import, .export:
                    if event.endDate != nil {
                        self.syncTimeoutTimer?.invalidate()
                        self.lastSyncDate = Date()
                        if let error = event.error {
                            self.lastSyncError = error.localizedDescription
                            self.internalSyncStatus = .error
                        } else {
                            self.lastSyncError = nil
                            self.internalSyncStatus = .synced
                        }
                    } else {
                        self.internalSyncStatus = .syncing
                    }
                @unknown default:
                    break
                }
                self.updateDetailedSyncStatus()
            }
            .store(in: &cancellables)
    }

    private func startStatusObservers() {
        // Observe network status
        NetworkReachability.shared.$isOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateDetailedSyncStatus() }
            .store(in: &cancellables)

        // Observe CloudKit account status
        cloudKitService.$accountStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateDetailedSyncStatus() }
            .store(in: &cancellables)
    }

    func updateDetailedSyncStatus() {
        if !NetworkReachability.shared.isOnline {
            detailedSyncStatus = .networkUnavailable
            return
        }

        switch cloudKitService.accountStatus {
        case .noAccount:
            detailedSyncStatus = .noAccount
            return
        case .restricted:
            detailedSyncStatus = .icloudRestricted
            return
        case .temporarilyUnavailable:
            detailedSyncStatus = .temporarilyUnavailable
            return
        case .couldNotDetermine:
            detailedSyncStatus = .uncertain
            return
        default:
            break
        }

        switch internalSyncStatus {
        case .syncing:
            detailedSyncStatus = .syncing
            return
        case .error:
            detailedSyncStatus = .error(lastSyncError ?? "An unknown error occurred.")
            return
        case .synced, .notSyncing:
            break
        }
        
        if internalSyncStatus == .synced || lastSyncDate != nil {
             detailedSyncStatus = .successfullySynced(lastSyncDate)
        } else {
            detailedSyncStatus = .idle
        }
    }
}

// Enums to represent the detailed sync status
private enum CloudKitSyncStatus {
    case notSyncing, syncing, synced, error
}

enum DetailedCloudKitSyncStatus: Equatable {
    case idle
    case syncing
    case successfullySynced(Date?)
    case error(String)
    case noAccount
    case networkUnavailable
    case icloudRestricted
    case temporarilyUnavailable
    case notPermitted
    case uncertain

    var userDescription: String {
        switch self {
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing with iCloud..."
        case .successfullySynced(let date):
            if let date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return "Up to Date (last sync: \(formatter.string(from: date)))"
            } else {
                return "Up to Date"
            }
        case .error(let message):
            return "Sync Error: \(message)"
        case .noAccount:
            return "Not signed into iCloud"
        case .networkUnavailable:
            return "No Internet Connection"
        case .icloudRestricted:
            return "iCloud access restricted"
        case .temporarilyUnavailable:
            return "iCloud temporarily unavailable"
        case .notPermitted:
            return "App lacks CloudKit permissions"
        case .uncertain:
            return "Sync status unavailable"
        }
    }

    var isSyncing: Bool {
        self == .syncing
    }

    var canSyncNow: Bool {
        switch self {
        case .noAccount, .networkUnavailable, .icloudRestricted, .notPermitted, .syncing:
            return false
        default:
            return true
        }
    }
}