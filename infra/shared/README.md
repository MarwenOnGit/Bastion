# infra/shared

`bootstrap.json` is written here by `infra/bootstrap` (`terraform apply`). It holds
non-secret IDs only: tenant, subscription, client IDs of the CI identities, the state
account name, the policy identity and the management group IDs.

Commit it after the first bootstrap apply so the docs and reviewers can see what exists.
It is not read by Terraform: the other stacks derive names from the subscription ID, and
the workflows read GitHub repository variables.
