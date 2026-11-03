# ADR 0008: RBAC for actions that Azure Policy cannot block

Date: 2026-11-03. Status: accepted.

## Context

Azure Policy evaluates resource **properties** on create and update (PUT and PATCH). It
does not evaluate **actions** (POST to `.../action` endpoints). So Policy cannot stop:

| Fenrir | Action |
|---|---|
| X-08 | `Microsoft.Compute/virtualMachines/runCommand/action` |
| X-10 | `Microsoft.Web/sites/config/list/action` (publishing credentials) |
| X-13 | `Microsoft.Logic/workflows/triggers/listCallbackUrl/action` |
| X-14 | `Microsoft.ContainerInstance/containerGroups/containers/exec/action` |
| P-12 | `Microsoft.Storage/storageAccounts/listKeys/action` |
| P-13 | `Microsoft.ContainerRegistry/registries/listCredentials/action` |

For P-12, P-13 and X-10, Policy can make the **result** of the action useless (shared keys
disabled, ACR admin user disabled, basic auth disabled). For X-08, X-13 and X-14 only RBAC
can stop the action.

## Decision

1. The custom role **Bastion VM Operator** (created by the bootstrap, assignable at
   `bastion-spoke-app-rg` and `bastion-test-rg`) can read, start, stop, restart and
   deallocate VMs and container groups, and nothing else. It cannot run commands, exec into
   containers, install VM extensions (the Custom Script Extension is another way to run
   code), log in to VMs, list web app config, or assign managed identities.
2. No human or workload identity holds a standing Owner or Contributor on the workload
   groups. Fenrir's exploit stage only runs against resource groups where the caller holds
   one of a list of roles (Owner, Contributor, Virtual Machine Contributor, Website
   Contributor, and others). Bastion VM Operator is not on that list.
3. The CI apply identity holds Contributor on the hub and spoke groups, which does include
   Run Command. It can only be used from a job in the `bastion-apply` environment, which
   you approve. That is a time-boxed, approved use, not a standing one.

## What NotActions does and does not do

`NotActions` subtracts from **that role only**. It is not a deny. If the same principal
also has Contributor from another assignment, Run Command is allowed. Real deny needs Azure
deny assignments, which customers can only create through Azure Blueprints (being retired)
or deployment stacks with deny settings. Deployment stacks are a candidate for the roadmap.

## Gap

You are Owner of the subscription, permanently. Without Entra ID P1/P2 there is no PIM to
make that just-in-time. Huginn's `vm-runcommand-by-user` rule (validated 2026-11-03)
detects Run Command by any user, including you.
