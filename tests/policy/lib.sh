#!/usr/bin/env bash
# Shared helpers for Bastion policy tests.
#
# Every test tries to create ONE non-compliant resource in bastion-test-rg with a
# direct ARM PUT (az rest), so no client-side validation hides the policy result.
# A test passes only if Azure answers RequestDisallowedByPolicy and the answer
# names the expected bastion-baseline policy reference. If the PUT unexpectedly
# succeeds, the test fails and a trap deletes the resource.
#
# Sourced by tests/policy/test-*.sh. Needs: az (logged in), jq.

set -euo pipefail

readonly BASTION_TEST_RG="bastion-test-rg"
readonly BASTION_ASSIGNMENT="bastion-baseline"
BASTION_LOCATION="${BASTION_LOCATION:-francecentral}"

# Tags every test resource carries. bastion-test=true is what cleanup.sh looks for.
# The governance tags are present so that only the control under test can deny.
bastion_test_tags() {
  jq -nc '{owner: "bastion-policy-tests", env: "test", project: "bastion", "bastion-test": "true"}'
}

log() { printf '[%s] %s\n' "${BASTION_TEST_NAME:-policy-test}" "$*" >&2; }

die() {
  log "ERROR: $*"
  exit 2
}

require_test_rg() {
  local rg="$1"
  if [[ "$rg" != "$BASTION_TEST_RG" ]]; then
    die "refusing to touch resource group '$rg'; policy tests only run in $BASTION_TEST_RG"
  fi
}

subscription_id() {
  if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    printf '%s' "$AZURE_SUBSCRIPTION_ID"
  else
    az account show --query id -o tsv
  fi
}

random_suffix() {
  od -An -N4 -tx1 /dev/urandom | tr -d ' \n'
}

tenant_id() {
  if [[ -n "${AZURE_TENANT_ID:-}" ]]; then
    printf '%s' "$AZURE_TENANT_ID"
  else
    az account show --query tenantId -o tsv
  fi
}

# Resource URL the trap must delete if a PUT is accepted.
__bastion_created_url=""

__bastion_cleanup_trap() {
  if [[ -n "$__bastion_created_url" ]]; then
    log "deleting unexpectedly created resource: $__bastion_created_url"
    local i
    for i in 1 2 3 4 5; do
      if az rest --method delete --url "$__bastion_created_url" --only-show-errors >/dev/null 2>&1; then
        __bastion_created_url=""
        return 0
      fi
      sleep $((i * 10))
    done
    log "could not delete it; the cleanup job will retry (tag bastion-test=true)"
  fi
}

trap __bastion_cleanup_trap EXIT

# expect_denied <provider/type> <name> <api-version> <json-body> <expected-reference-id>
expect_denied() {
  local type="$1" name="$2" api="$3" body="$4" expected_ref="$5"
  local sub url out rc

  require_test_rg "$BASTION_TEST_RG"
  sub="$(subscription_id)"
  url="https://management.azure.com/subscriptions/${sub}/resourceGroups/${BASTION_TEST_RG}/providers/${type}/${name}?api-version=${api}"

  log "PUT ${type}/${name} (expect deny by ${BASTION_ASSIGNMENT}/${expected_ref})"
  set +e
  out="$(az rest --method put --url "$url" --body "$body" --only-show-errors 2>&1)"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    __bastion_created_url="$url"
    log "FAIL: Azure accepted the non-compliant resource. Is the control in Deny and applied?"
    return 1
  fi

  if ! grep -q "RequestDisallowedByPolicy" <<<"$out"; then
    log "FAIL: request failed, but not because of policy:"
    printf '%s\n' "$out" >&2
    return 1
  fi

  local lower
  lower="$(tr '[:upper:]' '[:lower:]' <<<"$out")"
  if ! grep -q "$expected_ref" <<<"$lower" || ! grep -q "$BASTION_ASSIGNMENT" <<<"$lower"; then
    log "FAIL: denied by policy, but not by ${BASTION_ASSIGNMENT}/${expected_ref}:"
    printf '%s\n' "$out" >&2
    return 1
  fi

  log "PASS: RequestDisallowedByPolicy from ${BASTION_ASSIGNMENT}/${expected_ref}"
  return 0
}
