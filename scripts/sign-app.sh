#!/bin/bash
# Keep local builds recognizable to Keychain across source changes. This keychain
# holds only the app's signing key; it never changes Claude's credential or trust.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?Usage: sign-app.sh path/to/app}"

if [[ -n "${CLAUDE_MONITOR_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --sign "$CLAUDE_MONITOR_SIGNING_IDENTITY" \
        --identifier com.local.claudemonitor.bridge "$APP/Contents/Helpers/AgentMonitorBridge"
    codesign --force --sign "$CLAUDE_MONITOR_SIGNING_IDENTITY" \
        --identifier com.local.claudemonitor "$APP"
else
    umask 077
    SIGNING_DIR="$PWD/.local-signing"
    KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
    mkdir -p "$SIGNING_DIR"
    chmod 700 "$SIGNING_DIR"
    SIGNING_TEMP="$(mktemp -d)"
    ORIGINAL_KEYCHAINS=()
    while IFS= read -r line; do
        line="${line#*\"}"
        line="${line%\"*}"
        ORIGINAL_KEYCHAINS+=("$line")
    done < <(security list-keychains -d user)
    RESTORE_SEARCH_LIST=false
    INITIALIZING_KEYCHAIN=false
    cleanup() {
        security lock-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
        if [[ "$INITIALIZING_KEYCHAIN" == true ]]; then
            security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
        fi
        if [[ "$RESTORE_SEARCH_LIST" == true ]]; then
            security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"
        fi
        rm -rf "$SIGNING_TEMP"
    }
    trap cleanup EXIT

    if [[ ! -f "$KEYCHAIN" ]]; then
        echo "Creating a persistent local app-signing identity…"
        if [[ ! -f "$SIGNING_DIR/password" ]]; then
            openssl rand -hex 32 > "$SIGNING_DIR/password"
        fi
        KEYCHAIN_PASSWORD="$(cat "$SIGNING_DIR/password")"
        cat > "$SIGNING_TEMP/certificate.conf" <<'CONFIG'
[req]
distinguished_name = name
x509_extensions = extensions
prompt = no
[name]
CN = Agent Monitor Local Signing
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -config "$SIGNING_TEMP/certificate.conf" \
            -keyout "$SIGNING_TEMP/key.pem" -out "$SIGNING_TEMP/cert.pem" 2>/dev/null
        openssl pkcs12 -export -inkey "$SIGNING_TEMP/key.pem" \
            -in "$SIGNING_TEMP/cert.pem" -out "$SIGNING_TEMP/identity.p12" \
            -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
            -passout "file:$SIGNING_DIR/password"
        RESTORE_SEARCH_LIST=true
        security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
        INITIALIZING_KEYCHAIN=true
        security import "$SIGNING_TEMP/identity.p12" -k "$KEYCHAIN" \
            -P "$KEYCHAIN_PASSWORD" -x -T /usr/bin/codesign >/dev/null
        security set-key-partition-list -S apple-tool: -s \
            -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
        cp "$SIGNING_TEMP/cert.pem" "$SIGNING_DIR/cert.pem"
        INITIALIZING_KEYCHAIN=false
    fi

    KEYCHAIN_PASSWORD="$(cat "$SIGNING_DIR/password")"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    IDENTITY="$(openssl x509 -in "$SIGNING_DIR/cert.pem" -noout -fingerprint -sha1)"
    IDENTITY="${IDENTITY#*=}"
    IDENTITY="${IDENTITY//:/}"
    codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" \
        --identifier com.local.claudemonitor.bridge "$APP/Contents/Helpers/AgentMonitorBridge"
    codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" \
        --identifier com.local.claudemonitor "$APP"
fi

codesign --verify --strict --deep "$APP"
