# shellcheck shell=bash disable=SC2034  # variabili usate dagli script che fanno source
# Configurazione condivisa da build.sh e uninstall.sh (non eseguire direttamente).

readonly APP_NAME="FastAdd"
readonly EXT_NAME="FastAddFinder"
readonly APP_ID="com.enthonysclafani.fastadd"
readonly EXT_ID="$APP_ID.finder"
readonly MIN_OS="12.0"
readonly DEST="$HOME/Applications/$APP_NAME.app"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

step() { printf '→ %s\n' "$*"; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

# Rimuove l'installazione attuale. La firma ad-hoc cambia a ogni build,
# quindi il vecchio permesso di Accessibilità non sarebbe più valido.
uninstall_current() {
  pkill -x "$APP_NAME" 2>/dev/null || true
  tccutil reset Accessibility "$APP_ID" >/dev/null 2>&1 || true
  [[ -d "$DEST" ]] || return 0
  step "Rimuovo l'installazione precedente"
  pluginkit -r "$DEST/Contents/PlugIns/$EXT_NAME.appex" 2>/dev/null || true
  "$LSREGISTER" -u "$DEST" 2>/dev/null || true
  rm -rf "$DEST"
}

# Rimuove la vecchia versione "NuovoElemento", se presente.
remove_legacy() {
  local old="$HOME/Applications/NuovoElemento.app"
  [[ -d "$old" ]] || return 0
  step "Rimuovo la vecchia versione NuovoElemento"
  pkill -x NuovoElemento 2>/dev/null || true
  pluginkit -e ignore -i com.enthonysclafani.nuovoelemento.finder 2>/dev/null || true
  pluginkit -r "$old/Contents/PlugIns/NuovoElementoFinder.appex" 2>/dev/null || true
  "$LSREGISTER" -u "$old" 2>/dev/null || true
  rm -rf "$old"
  tccutil reset Accessibility com.enthonysclafani.nuovoelemento >/dev/null 2>&1 || true
}
