#!/usr/bin/env bash
# Read-only compliance report for bastion-baseline, as Markdown on stdout.
#
# This is the input for Phase 6 (Audit to Deny): a control can move to its target
# effect when it has no non-compliant resources that should stay, or when each one
# has been fixed or exempted. Needs Reader on the Bastion groups (az login first).
#
#   tests/policy/compliance-report.sh                     all Bastion groups
#   tests/policy/compliance-report.sh bastion-spoke-app-rg
#   tests/policy/compliance-report.sh --scan              trigger a scan first (needs write; skip in CI)
set -euo pipefail

assignment="bastion-baseline"
groups=(bastion-hub-rg bastion-spoke-app-rg bastion-test-rg)
scan=false

args=()
for a in "$@"; do
  if [[ "$a" == "--scan" ]]; then scan=true; else args+=("$a"); fi
done
if [[ ${#args[@]} -gt 0 ]]; then groups=("${args[@]}"); fi

for rg in "${groups[@]}"; do
  if [[ "$rg" != bastion-* ]]; then
    echo "refusing $rg: this report only reads Bastion resource groups" >&2
    exit 2
  fi
done

if [[ "$scan" == true ]]; then
  for rg in "${groups[@]}"; do
    echo "triggering a compliance scan in $rg (this can take several minutes)" >&2
    az policy state trigger-scan --resource-group "$rg" --only-show-errors
  done
fi

echo "## bastion-baseline compliance"
echo
echo "Generated $(date -u +%Y-%m-%dT%H:%MZ). Compliance data is refreshed by Azure about every 24 hours, and within minutes for new or changed resources."
echo

for rg in "${groups[@]}"; do
  echo "### $rg"
  echo
  summary="$(az policy state summarize --resource-group "$rg" --policy-assignment "$assignment" -o json --only-show-errors 2>/dev/null || echo '{}')"
  rows="$(jq -r '
    [.policyAssignments[]?.policyDefinitions[]?
      | {ref: .policyDefinitionReferenceId, nc: (.results.nonCompliantResources // 0)}]
    | sort_by(-.nc, .ref)
    | .[] | "| `\(.ref)` | \(.nc) |"' <<<"$summary")"
  if [[ -z "$rows" ]]; then
    echo "No compliance data yet for $assignment in this group (not assigned, or not evaluated yet)."
    echo
    continue
  fi
  echo "| Policy reference | Non-compliant resources |"
  echo "|---|---|"
  echo "$rows"
  echo

  details="$(az policy state list --resource-group "$rg" \
    --filter "complianceState eq 'NonCompliant' and policyAssignmentName eq '$assignment'" \
    --query "[].{ref:policyDefinitionReferenceId, id:resourceId}" -o json --only-show-errors 2>/dev/null || echo '[]')"
  if [[ "$(jq 'length' <<<"$details")" -gt 0 ]]; then
    echo "<details><summary>Non-compliant resources</summary>"
    echo
    echo "| Policy reference | Resource |"
    echo "|---|---|"
    jq -r 'sort_by(.ref) | .[] | "| `\(.ref)` | `\(.id | split("/") | .[-2:] | join("/"))` |"' <<<"$details"
    echo
    echo "</details>"
    echo
  fi
done
