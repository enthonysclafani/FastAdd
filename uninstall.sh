#!/bin/bash
# FastAdd — disinstalla app, estensione e permesso di Accessibilità.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

pluginkit -e ignore -i "$EXT_ID" 2>/dev/null || true
uninstall_current
remove_legacy

step "Riattivo l'avviso del Finder sul cambio estensione"
defaults delete com.apple.finder FXEnableExtensionChangeWarning 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "✓ FastAdd rimosso."
