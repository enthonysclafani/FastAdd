import Cocoa
import FinderSync
import os

/// FastAdd — Finder Sync extension.
///
/// Aggiunge "Nuovo elemento" al menu contestuale del Finder. Il clic crea un file vuoto
/// "Senza titolo" e chiede all'app FastAdd (non sandboxed) di avviarne la rinomina.
@objc(FAFinderSync)
final class FAFinderSync: FIFinderSync {

    private static let baseName = "Senza titolo"
    private static let maxCopies = 999
    private let log = Logger(subsystem: "com.enthonysclafani.fastadd", category: "extension")

    override init() {
        super.init()
        // Solo dove la sandbox permette di scrivere (vedi Extension.entitlements):
        // così la voce non compare in cartelle in cui fallirebbe.
        // In sandbox NSHomeDirectory() punta al container: serve la home reale.
        var folders: Set<URL> = [URL(fileURLWithPath: "/Volumes", isDirectory: true)]
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            folders.insert(URL(fileURLWithPath: String(cString: dir), isDirectory: true))
        }
        FIFinderSyncController.default().directoryURLs = folders
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForContainer:
            break
        case .contextualMenuForItems:
            guard selectedFolder() != nil else { return nil }
        default:
            return nil
        }
        let menu = NSMenu(title: "")
        menu.addItem(NSMenuItem(title: "Nuovo elemento", action: #selector(createFile(_:)), keyEquivalent: ""))
        return menu
    }

    @IBAction func createFile(_ sender: AnyObject?) {
        guard let folder = selectedFolder() ?? FIFinderSyncController.default().targetedURL(),
              let file = createUniqueEmptyFile(in: folder) else { return }

        var components = URLComponents()
        components.scheme = "fastadd"
        components.host = "rename"
        components.queryItems = [URLQueryItem(name: "path", value: file.path)]

        if let link = components.url, NSWorkspace.shared.open(link) { return }
        log.error("App FastAdd non raggiungibile: seleziono solo il file")
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    // MARK: - Helpers

    /// La cartella selezionata, se la selezione è esattamente una cartella (non un bundle).
    private func selectedFolder() -> URL? {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              items.count == 1 else { return nil }
        let url = items[0]
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true ? url : nil
    }

    /// Crea "Senza titolo", "Senza titolo 2", … in modo atomico (O_EXCL):
    /// non sovrascrive mai un file esistente, nemmeno in caso di race.
    private func createUniqueEmptyFile(in folder: URL) -> URL? {
        for n in 1...Self.maxCopies {
            let name = n == 1 ? Self.baseName : "\(Self.baseName) \(n)"
            let url = folder.appendingPathComponent(name, isDirectory: false)

            var error: Int32 = 0
            let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { error = EINVAL; return -1 }
                let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
                if fd < 0 { error = errno }
                return fd
            }
            if fd >= 0 {
                close(fd)
                return url
            }
            if error != EEXIST {
                log.error("Creazione file fallita (errno \(error, privacy: .public)): \(url.path, privacy: .private)")
                return nil
            }
        }
        log.error("Troppi file \"Senza titolo\" nella cartella")
        return nil
    }
}
