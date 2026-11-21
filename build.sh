#!/bin/bash
# FastAdd — compila, firma (ad-hoc), installa in ~/Applications e attiva l'estensione Finder.
# Requisiti: Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

ARCH="$(uname -m)"
readonly TARGET="$ARCH-apple-macos$MIN_OS"
readonly BUILD="build"
readonly APP="$BUILD/$APP_NAME.app"
readonly EXT="$APP/Contents/PlugIns/$EXT_NAME.appex"

command -v swiftc >/dev/null || die "swiftc non trovato: esegui 'xcode-select --install'"

# --- Compilazione ------------------------------------------------------------
step "Compilo ($TARGET)"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$EXT/Contents/MacOS"

swiftc -O -swift-version 5 -target "$TARGET" \
  -module-name "$EXT_NAME" -parse-as-library -application-extension \
  -framework Cocoa -framework FinderSync \
  -Xlinker -e -Xlinker _NSExtensionMain \
  Extension/FinderSync.swift \
  -o "$EXT/Contents/MacOS/$EXT_NAME"
cp Extension/Info.plist "$EXT/Contents/Info.plist"

swiftc -O -swift-version 5 -target "$TARGET" \
  -module-name "$APP_NAME" \
  -framework Cocoa -framework FinderSync -framework ServiceManagement \
  App/main.swift \
  -o "$APP/Contents/MacOS/$APP_NAME"
cp App/Info.plist "$APP/Contents/Info.plist"

# --- Firma (prima l'estensione, poi il contenitore) --------------------------
step "Firma ad-hoc"
codesign --force --sign - --timestamp=none --entitlements Extension/Extension.entitlements "$EXT"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

# --- Installazione -----------------------------------------------------------
remove_legacy
uninstall_current

step "Installo in $DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$APP" "$DEST"

step "Registro e attivo l'estensione"
"$LSREGISTER" -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/$EXT_NAME.appex"
pluginkit -e use -i "$EXT_ID"

step "Disattivo l'avviso del Finder sul cambio estensione (impostazione globale)"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
killall Finder 2>/dev/null || true

sleep 1
status="$(pluginkit -m -i "$EXT_ID" 2>/dev/null || true)"
if [[ "$status" =~ ^[[:space:]]*\+ ]]; then
  echo "✓ Estensione attiva."
else
  echo "! Estensione registrata ma non attiva: attivala da Impostazioni → Generali → Elementi login ed estensioni → Finder."
fi

step "Avvio FastAdd: concedi il permesso di Accessibilità quando richiesto"
open "$DEST"
