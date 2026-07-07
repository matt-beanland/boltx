#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generates a throwaway local CA and a Neo4j bolt server certificate for the
# TLS integration tests (test/bolty/tls_test.exs) and the TLS-enabled
# neo4j-bolt5 compose service. NOT for production use. Output lands in
# test/tls/certs/ and is git-ignored — regenerate with `./test/tls/gen_certs.sh`.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/certs"
mkdir -p "$DIR"
cd "$DIR"

# 1. Local CA (the test trusts this via ssl_opts: [cacertfile: "ca.crt"]).
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout ca.key -out ca.crt -days 3650 \
  -subj "/CN=bolty-test-ca" 2>/dev/null

# 2. Server key + CSR.
openssl req -newkey rsa:2048 -nodes \
  -keyout server.key -out server.csr \
  -subj "/CN=localhost" 2>/dev/null

# 3. Sign the server cert, with SANs so hostname verification passes whether the
#    client connects to "localhost" or "127.0.0.1".
openssl x509 -req -in server.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 825 \
  -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth") \
  2>/dev/null

rm -f server.csr ca.srl
echo "TLS test certs written to $DIR (ca.crt, server.crt, server.key)"
