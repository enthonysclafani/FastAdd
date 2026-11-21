# FastAdd

Aggiunge **Nuovo elemento** al menu del tasto destro del Finder. Un clic crea un file vuoto "Senza titolo" e ti mette subito in rinomina: scrivi nome ed estensione (es. `index.html`) e premi Invio.

Funziona nella tua home e nei volumi esterni (`/Volumes`). Clic destro su una cartella → il file viene creato dentro quella cartella.

## Installazione
```bash
xcode-select --install   # solo se non hai i Command Line Tools
./build.sh
```
Alla fine FastAdd si apre: concedi **Accessibilità** (Impostazioni di Sistema → Privacy e sicurezza → Accessibilità → FastAdd). Senza, il file viene solo selezionato.

- FastAdd resta attivo in background (niente icona nel Dock) e si avvia al login.
- Lo script disattiva l'avviso del Finder "Confermi di voler aggiungere l'estensione…" (impostazione globale).
- Se avevi la vecchia versione *NuovoElemento*, lo script la rimuove.
- A ogni nuova build il permesso di Accessibilità va riconcesso (la firma ad-hoc cambia).

## Disinstallare
```bash
./uninstall.sh
```

## Diagnostica
```bash
log show --last 5m --style compact --predicate 'subsystem == "com.enthonysclafani.fastadd"'
```

## Struttura
| File | Ruolo |
|---|---|
| `Extension/FinderSync.swift` | Estensione Finder (sandboxed): voce di menu e creazione atomica del file |
| `App/main.swift` | App in background: valida la richiesta, seleziona il file, avvia la rinomina |
| `config.sh` | Nomi, bundle id e funzioni comuni agli script |
