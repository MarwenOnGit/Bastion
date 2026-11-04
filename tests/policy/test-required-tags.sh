#!/usr/bin/env bash
# control: required_tags
# reference: require-tag-owner
# Non-compliant: an empty NSG (free) with every required tag except owner.
# It keeps bastion-test=true so cleanup.sh can find it if it is wrongly created.
BASTION_TEST_NAME="required-tags"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="nsg-bt-tag-$(random_suffix)"
tags="$(bastion_test_tags | jq -c 'del(.owner)')"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$tags" '{location: $loc, tags: $tags, properties: {}}')"

expect_denied "Microsoft.Network/networkSecurityGroups" "$name" "2024-05-01" "$body" "require-tag-owner"
