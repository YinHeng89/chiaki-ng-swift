#!/bin/zsh
set -eu
umask 077
project_dir="$(cd "$(dirname "$0")/../.." && pwd)"
signing_dir="$project_dir/.local-signing"
if [[ -f "$signing_dir/identity" ]]; then
    print "A signing identity is already configured. Leaving it unchanged."
    exit 0
fi
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
cat > "$work_dir/certificate.conf" <<'CONFIG'
[req]
distinguished_name = identity
x509_extensions = signing
prompt = no
[identity]
CN = Chiaki Native Local Development
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650     -config "$work_dir/certificate.conf" -keyout "$work_dir/key.pem"     -out "$work_dir/certificate.pem" 2>"$work_dir/generation.log"
/usr/bin/openssl pkcs12 -export -inkey "$work_dir/key.pem" -in "$work_dir/certificate.pem"     -out "$work_dir/identity.p12" -passout pass:chiaki-local-import
security import "$work_dir/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db"     -f pkcs12 -P "chiaki-local-import" -x -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign     -k "$HOME/Library/Keychains/login.keychain-db" "$work_dir/certificate.pem"
identity_hash="$(/usr/bin/openssl x509 -in "$work_dir/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
mkdir -p "$signing_dir"
cp "$work_dir/certificate.pem" "$signing_dir/certificate.pem"
printf '%s\n' "$identity_hash" > "$signing_dir/identity"
print "Local signing identity configured. Subsequent builds will reuse it."
