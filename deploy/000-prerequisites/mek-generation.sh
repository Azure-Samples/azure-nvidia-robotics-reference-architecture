#!/usr/bin/env bash
# Generate MEK for OSMO

# Generate random 32-byte key
RANDOM_KEY="$(openssl rand -base64 32 | tr -d '\n')"

# Create JWK
JWK_JSON="{\"k\":\"$RANDOM_KEY\",\"kid\":\"key1\",\"kty\":\"oct\"}"

# Base64 encode the JWK
ENCODED_JWK="$(echo -n "$JWK_JSON" | base64 | tr -d '\n')"

mkdir -p ./out

cat > ./out/mek-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: mek-config
data:
  mek.yaml: |
    currentMek: key1
    meks:
      key1: $ENCODED_JWK
EOF

echo "ConfigMap written to ./out/mek-config.yaml"
