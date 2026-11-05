#!/usr/bin/env bash
set -euo pipefail

# The RSA-4096 root key is created once by the operator and is never generated
# during image builds. Only the stable public CA certificate ships in the OS.
cert=/usr/share/kiyan/kiyan-os-root-ca.pem
test -s "$cert"
openssl x509 -in "$cert" -noout -subject >/dev/null
openssl x509 -in "$cert" -noout -ext basicConstraints | grep -q 'CA:TRUE'
openssl x509 -in "$cert" -pubkey -noout \
  | openssl pkey -pubin -text -noout \
  | grep -q 'Public-Key: (4096 bit)'
