#!/usr/bin/env bash
# control: storage_public_network
# reference: storage-public-network
# Fenrir: D-01, D-02 (data access from the operator's machine). Non-compliant: publicNetworkAccess = Enabled.
BASTION_TEST_NAME="storage-public-network"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="stbtpna$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, kind: "StorageV2", sku: {name: "Standard_LRS"}, tags: $tags,
  properties: {
    allowSharedKeyAccess: false,
    publicNetworkAccess: "Enabled",
    minimumTlsVersion: "TLS1_2",
    allowBlobPublicAccess: false,
    supportsHttpsTrafficOnly: true
  }
}')"

expect_denied "Microsoft.Storage/storageAccounts" "$name" "2023-05-01" "$body" "storage-public-network"
