#!/usr/bin/env bash
# Create a localhost TLS certificate in infra/certs/ (gitignored).
#
#   scripts/certs.sh          # mkcert if installed (trusted locally), else openssl self-signed
#   scripts/certs.sh --force  # overwrite existing files
#
# Output: infra/certs/localhost.pem (cert) and infra/certs/localhost-key.pem (key),
# valid for localhost, 127.0.0.1 and ::1. Used by `api --tls` and nginx (Module 5).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/infra/certs"
CERT="$DIR/localhost.pem"
KEY="$DIR/localhost-key.pem"

if [ -e "$CERT" ] && [ "${1:-}" != "--force" ]; then
  echo "certs: $CERT exists (use --force to replace)"
  exit 0
fi
mkdir -p "$DIR"

if command -v mkcert >/dev/null 2>&1; then
  # Does not run `mkcert -install`: trusting a local CA is your decision.
  mkcert -cert-file "$CERT" -key-file "$KEY" localhost 127.0.0.1 ::1
  echo "certs: created with mkcert (run 'mkcert -install' once to trust its CA)"
else
  openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
    -keyout "$KEY" -out "$CERT" -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1" 2>/dev/null
  echo "certs: created self-signed with openssl (clients need --cacert $CERT or -k)"
fi
chmod 600 "$KEY"
openssl x509 -in "$CERT" -noout -subject -enddate
