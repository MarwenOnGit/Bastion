#!/usr/bin/env bash
# control: storage_min_tls
# reference: storage-min-tls
# Non-compliant: minimumTlsVersion = TLS1_0. Everything else compliant.
BASTION_TEST_NAME="storage-min-tls"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="stbttls$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, kind: "StorageV2", sku: {name: "Standard_LRS"}, tags: $tags,
  properties: {
    allowSharedKeyAccess: false,
    publicNetworkAccess: "Disabled",
    minimumTlsVersion: "TLS1_0",
    allowBlobPublicAccess: false,
    supportsHttpsTrafficOnly: true
  }
}')"

expect_denied "Microsoft.Storage/storageAccounts" "$name" "2023-05-01" "$body" "storage-min-tls"
