#!/usr/bin/env bash
set -euo pipefail

SIGNING_IDENTITY="${OPENNOTE_BATCH_SIGNING_IDENTITY:-OpenNote Batch Development}"
login_keychain="$(security login-keychain | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"

if security find-certificate -c "$SIGNING_IDENTITY" "$login_keychain" >/dev/null 2>&1 \
    && security find-key -l "$SIGNING_IDENTITY" -t private "$login_keychain" >/dev/null 2>&1; then
    echo "Signing identity already available: $SIGNING_IDENTITY"
    exit 0
fi

temp_root="$(mktemp -d -t OpenNoteBatch-signing)"
trap 'rm -f "$temp_root/key.pem" "$temp_root/certificate.pem" "$temp_root/identity.p12"' EXIT

p12_password="$(openssl rand -hex 32)"

openssl req \
    -new \
    -x509 \
    -newkey rsa:3072 \
    -nodes \
    -keyout "$temp_root/key.pem" \
    -out "$temp_root/certificate.pem" \
    -days 3650 \
    -subj "/CN=$SIGNING_IDENTITY/O=OpenNote Batch/OU=Local Development" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    >/dev/null 2>&1

openssl pkcs12 \
    -export \
    -out "$temp_root/identity.p12" \
    -inkey "$temp_root/key.pem" \
    -in "$temp_root/certificate.pem" \
    -name "$SIGNING_IDENTITY" \
    -passout "pass:$p12_password" \
    >/dev/null 2>&1

security import "$temp_root/identity.p12" \
    -k "$login_keychain" \
    -P "$p12_password" \
    -T /usr/bin/codesign \
    >/dev/null

if ! security find-certificate -c "$SIGNING_IDENTITY" "$login_keychain" >/dev/null 2>&1 \
    || ! security find-key -l "$SIGNING_IDENTITY" -t private "$login_keychain" >/dev/null 2>&1; then
    echo "The signing identity was imported but is not available to codesign." >&2
    exit 1
fi

echo "Created stable local signing identity: $SIGNING_IDENTITY"
echo "The private key is stored in: $login_keychain"
