# ADR 0005: GitHub Actions authenticates with OIDC and ID-based subjects

Date: 2026-11-03. Status: accepted.

## Decision

1. No client secret, certificate or storage key exists anywhere. GitHub Actions gets a
   short-lived Entra ID token through workload identity federation (OIDC).
2. Federated credentials use the ID-based subject format that GitHub issues for this
   account:

   ```
   repo:MarwenOnGit@183097322/Bastion@1444942400:<context>
   ```

   Name-only subjects (`repo:MarwenOnGit/Bastion:...`) are rejected for these repositories
   with AADSTS700213. ID-based subjects have a second benefit: if the repository is
   deleted and a new one is created with the same name, the old trust does not carry over.
3. Each identity trusts the narrowest contexts it needs:

   | Identity | Trusted subjects |
   |---|---|
   | `bastion-github-plan` | `ref:refs/heads/bastion-dev`, `ref:refs/heads/main`, `pull_request` |
   | `bastion-github-apply` | `environment:bastion-apply` only |
   | `bastion-policy-tester` | `environment:bastion-policy-tests` only |

   A job that names an environment gets the environment subject, not the branch subject,
   so the apply identity cannot be used by any job that has not passed the environment's
   protection rules (required reviewer, main branch only).
4. `pull_request` trust is safe for the plan identity because it is read-only, and because
   GitHub does not give OIDC tokens to workflows triggered by pull requests from forks.
5. The repository ID was read from the GitHub API on 2026-11-03 (`1444942400`, owner
   `183097322`). `tests/static/test_oidc.py` fails if the subject format changes.

## Consequences

- Renaming the repository or the owner breaks the trust until the bootstrap is re-applied
  with the new names. The numeric IDs do not change on rename.
