import Foundation

class BackupService {
    private var timer: Timer?
    private let backupInterval: TimeInterval = 5 * 60 // 5 minutes
    private let maxBackups = 10
    
    private var persistentStoreURL: URL?
    private var backupsDirectoryURL: URL?

    init() {
        guard let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("BackupService: Could not find Application Support directory.")
            return
        }
        let promptBindDirectory = appSupportDirectory.appendingPathComponent("PromptBind")
        self.persistentStoreURL = promptBindDirectory.appendingPathComponent("PromptBind.sqlite")
        self.backupsDirectoryURL = promptBindDirectory.appendingPathComponent("Backups")

        if let backupsDir = self.backupsDirectoryURL, !FileManager.default.fileExists(atPath: backupsDir.path) {
            do {
                try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true, attributes: nil)
                print("BackupService: Created backups directory at \(backupsDir.path)")
            } catch {
                print("BackupService: Could not create Backups directory: \(error)")
                self.backupsDirectoryURL = nil 
            }
        }
    }

    func startAutomaticBackups() {
        guard persistentStoreURL != nil, backupsDirectoryURL != nil else {
            print("BackupService: Store URL or Backups directory URL is not set. Cannot start backups.")
            return
        }
        
        timer?.invalidate()
        performBackup() 
        
        timer = Timer.scheduledTimer(withTimeInterval: backupInterval, repeats: true) { [weak self] _ in
            self?.performBackup()
        }
        print("BackupService: Automatic backups started. Interval: \(backupInterval / 60) minutes.")
    }

    func stopAutomaticBackups() {
        timer?.invalidate()
        timer = nil
        print("BackupService: Automatic backups stopped.")
    }

    private func performBackup() {
        guard let storeURL = persistentStoreURL, let backupsDir = backupsDirectoryURL else {
            print("BackupService: Missing store URL or backups directory for performing backup.")
            return
        }
        
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            print("BackupService: SQLite store does not exist at \(storeURL.path). Skipping backup.")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let backupFileName = "PromptBind_Backup_\(timestamp).sqlite"
        let backupFileURL = backupsDir.appendingPathComponent(backupFileName)

        do {
            // For robust backups, consider WAL files (.sqlite-wal, .sqlite-shm) if WAL mode is enabled for Core Data.
            // A simple copy might be sufficient if WAL is not heavily used or if a slight risk is acceptable.
            try FileManager.default.copyItem(at: storeURL, to: backupFileURL)
            print("BackupService: Successfully created backup at \(backupFileURL.path)")
            
            cleanupOldBackups()
        } catch {
            print("BackupService: Failed to create backup: \(error)")
        }
    }

    private func cleanupOldBackups() {
        guard let backupsDir = backupsDirectoryURL else { return }

        do {
            let backupFiles = try FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            let sortedBackups = backupFiles.sorted {
                guard let date1 = try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      let date2 = try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    return false
                }
                return date1 < date2
            }

            if sortedBackups.count > maxBackups {
                let backupsToDelete = sortedBackups.prefix(sortedBackups.count - maxBackups)
                for backupFile in backupsToDelete {
                    try FileManager.default.removeItem(at: backupFile)
                    print("BackupService: Deleted old backup: \(backupFile.path)")
                }
            }
        } catch {
            print("BackupService: Error cleaning up old backups: \(error)")
        }
    }
    
    deinit {
        stopAutomaticBackups()
    }
}