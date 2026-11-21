import Cocoa
import FinderSync
import ApplicationServices
import ServiceManagement
import os

/// FastAdd — app contenitore, sempre attiva in background (senza Dock, avvio al login).
///
/// Riceve `fastadd://rename?path=…` dall'estensione, seleziona il file nel Finder e,
/// appena il Finder lo mostra selezionato, simula Invio per entrare in rinomina.
/// Richiede il permesso di Accessibilità.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private enum Config {
        static let finderID = "com.apple.finder"
        static let baseName = "Senza titolo"
        /// L'URL è pubblico: accettiamo solo file appena creati dall'estensione.
        static let maxFileAge: TimeInterval = 10
        static let pollInterval: TimeInterval = 0.02
        static let maxAttempts = 50          // ~1 s
        static let reselectAttempt = 10      // ~200 ms
        static let axTimeout: Float = 0.1    // evita blocchi se il Finder non risponde
    }

    private let log = Logger(subsystem: "com.enthonysclafani.fastadd", category: "app")
    private var renameToken = 0
    private var didPromptAccessibility = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLoginItem()
        if !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showSetup() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Ogni clic genera un solo URL: se ne arrivano più insieme vale l'ultimo valido.
        guard let file = urls.reversed().lazy.compactMap({ self.validatedNewFile(from: $0) }).first else {
            log.notice("URL ignorato: non è un file appena creato da FastAdd")
            return
        }
        startRename(file)
    }

    private func registerLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        // Non ri-registrare se l'utente l'ha disattivato o è in attesa di approvazione.
        guard service.status == .notRegistered else { return }
        do { try service.register() } catch {
            log.error("Registrazione avvio al login fallita: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Validazione input

    /// Accetta solo `fastadd://rename?path=<assoluto>` che punti a un file regolare, vuoto,
    /// chiamato "Senza titolo[ N]" e creato da pochi secondi. Così un URL esterno
    /// non può far premere Invio su file arbitrari.
    private func validatedNewFile(from url: URL) -> URL? {
        guard url.scheme == "fastadd", url.host == "rename",
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/") else { return nil }

        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard file.path == path, isUntitledName(file.lastPathComponent),
              let values = try? file.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]),
              values.isRegularFile == true, values.fileSize == 0,
              // Alcuni volumi (es. SMB) non hanno la data di creazione.
              let created = values.creationDate ?? values.contentModificationDate,
              abs(created.timeIntervalSinceNow) < Config.maxFileAge else { return nil }
        return file
    }

    private func isUntitledName(_ name: String) -> Bool {
        if name == Config.baseName { return true }
        let prefix = Config.baseName + " "
        guard name.hasPrefix(prefix) else { return false }
        let suffix = name.dropFirst(prefix.count)
        return (1...3).contains(suffix.count) && suffix.allSatisfy(\.isASCII) && suffix.allSatisfy(\.isNumber)
    }

    // MARK: - Rinomina

    private func startRename(_ file: URL) {
        renameToken += 1
        let token = renameToken

        notifyFinder(folder: file.deletingLastPathComponent())
        NSWorkspace.shared.activateFileViewerSelecting([file])

        guard AXIsProcessTrusted() else {
            log.notice("Permesso Accessibilità mancante: file solo selezionato")
            promptAccessibilityOnce()
            return
        }
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: Config.finderID).first
        else { return }

        let axFinder = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(axFinder, Config.axTimeout)
        poll(file: file, axFinder: axFinder, token: token, attempt: 0)
    }

    /// Fa aggiornare subito la cartella al Finder invece di attendere FSEvents.
    private func notifyFinder(folder: URL) {
        folder.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            let directoryModified: FNMessage = 1   // kFNDirectoryModifiedMessage
            _ = FNNotifyByPath(UnsafeRawPointer(path).assumingMemoryBound(to: UInt8.self),
                               directoryModified, 0)
        }
    }

    /// Ogni 20 ms: se il file è selezionato nel Finder in primo piano, preme Invio.
    private func poll(file: URL, axFinder: AXUIElement, token: Int, attempt: Int) {
        guard token == renameToken else { return }   // superata da un clic più recente

        let finderFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Config.finderID
        if finderFront {
            let focused = axElement(axFinder, kAXFocusedUIElementAttribute)
            // Rinomina già attiva (es. l'utente ha premuto Invio): non interferire.
            if let focused, isTextInput(focused) { return }
            if let focused, selection(of: focused, contains: file.lastPathComponent) {
                pressReturn()
                return
            }
        }

        if attempt >= Config.maxAttempts {
            // Selezione non confermata (es. viste non riconosciute): Invio solo se il Finder
            // è ancora in primo piano, mai verso un'altra app.
            if finderFront { pressReturn() }
            else { log.notice("Finder non in primo piano: rinomina annullata") }
            return
        }
        if attempt == Config.reselectAttempt {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.pollInterval) { [weak self] in
            self?.poll(file: file, axFinder: axFinder, token: token, attempt: attempt + 1)
        }
    }

    private func pressReturn() {
        let source = CGEventSource(stateID: .hidSystemState)
        let returnKey: CGKeyCode = 0x24
        CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)?.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility helpers

    private func isTextInput(_ element: AXUIElement) -> Bool {
        let role = axString(element, kAXRoleAttribute)
        return role == kAXTextFieldRole || role == kAXTextAreaRole
    }

    private func selection(of container: AXUIElement, contains name: String) -> Bool {
        var selected = axElements(container, kAXSelectedRowsAttribute)
        if selected.isEmpty { selected = axElements(container, kAXSelectedChildrenAttribute) }
        return selected.contains { element($0, contains: name, depth: 3) }
    }

    private func element(_ el: AXUIElement, contains name: String, depth: Int) -> Bool {
        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
        where axString(el, attribute) == name {
            return true
        }
        guard depth > 0 else { return false }
        return axElements(el, kAXChildrenAttribute).contains { element($0, contains: name, depth: depth - 1) }
    }

    private func axValue(_ el: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func axElement(_ el: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axValue(el, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)   // tipo verificato sopra
    }

    private func axElements(_ el: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let value = axValue(el, attribute), CFGetTypeID(value) == CFArrayGetTypeID(),
              let array = value as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    private func axString(_ el: AXUIElement, _ attribute: String) -> String? {
        axValue(el, attribute) as? String
    }

    // MARK: - Configurazione

    private func promptAccessibilityOnce() {
        guard !didPromptAccessibility else { return }
        didPromptAccessibility = true
        requestAccessibility()
    }

    private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func showSetup() {
        NSApp.activate(ignoringOtherApps: true)
        let trusted = AXIsProcessTrusted()
        let alert = NSAlert()
        alert.messageText = "FastAdd"
        alert.informativeText = trusted
            ? "Tutto pronto. Clic destro in una cartella del Finder → Nuovo elemento."
            : """
            Per entrare subito in rinomina serve il permesso di Accessibilità:
            Impostazioni di Sistema → Privacy e sicurezza → Accessibilità → attiva "FastAdd".

            Se "Nuovo elemento" non compare nel Finder, attiva l'estensione in \
            Generali → Elementi login ed estensioni → Finder.
            """
        if !trusted { alert.addButton(withTitle: "Concedi Accessibilità") }
        alert.addButton(withTitle: "Impostazioni estensioni")
        alert.addButton(withTitle: "Chiudi")

        switch (trusted, alert.runModal()) {
        case (false, .alertFirstButtonReturn):
            requestAccessibility()
        case (false, .alertSecondButtonReturn), (true, .alertFirstButtonReturn):
            FIFinderSyncController.showExtensionManagementInterface()
        default:
            break
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
