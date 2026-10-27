# Repository cheat sheet

Companion: [Practice guide](terraform-practice-guide.md). Paths and commands below are relative to the repository root unless stated otherwise. Choose the intended root before running Terraform; do not run every example as a script.

## Where things live

| Path | Purpose |
|---|---|
| `oci-lab/` | Foundation: compartment, network, VM, collection/import exercises |
| `oci-lab/network.tf` | OCI networking and learning compartment |
| `oci-lab/compute.tf` | Web module call, moved addresses, IP outputs |
| `oci-lab/cloud-init.yaml` | VM's initial Docker/Nginx setup |
| `oci-lab/modules/web_server/` | Reusable VM definition and input validation |
| `oci-lab/collections.tf` | Map inputs, filtering, tags, lifecycle exercises |
| `oci-lab/import-practice.tf` | Import/removal exercise; inspect its current contents |
| `environment-lab/dev/` | Development root and separate remote state |
| `environment-lab/prod/` | Production root and separate remote state |
| `environment-lab/*/dependencies.tf` | Reads foundation state outputs |
| `environment-lab/modules/compartment/main.tf` | Shared compartment resource, variables, output |
| `environment-lab/modules/compartment/tests/` | Mock-provider naming tests |
| `.github/workflows/terraform.yml` | Formatting, initialization, validation, mock tests |
| `.github/workflows/terraform-dev.yml` | Manual authenticated plan and approved apply |

The three working roots use separate state keys in `learning-terraform-state`. The repository top level is not a wrapper that applies all roots. A child module directory is normally called by a root, not applied independently.

## Routine local checks

```bash
terraform fmt -check -diff -recursive
# To fix formatting deliberately:
terraform fmt -recursive

git diff --check
git status --short
```

Inside the chosen root (for example `cd oci-lab`):

```bash
terraform init
terraform validate
terraform plan -out=change.tfplan
terraform show change.tfplan
# Only after reviewing the plan:
terraform apply change.tfplan
terraform plan
terraform state list
terraform output
```

`terraform -chdir=oci-lab plan` is equivalent to changing directory first and running plan there. The saved-plan path is relative to that Terraform working directory. Do not use a saved plan after a state-changing operation; generate and review a fresh one.

## Identity selection for local work

For foundation work using the human profile:

```bash
export OCI_CONFIG_FILE_PROFILE=LEARNING_TERRAFORM
export OCI_config_file_profile=LEARNING_TERRAFORM
```

For deliberately testing the restricted dev identity, set both to `GITHUB_TERRAFORM_DEV`. Explicit provider/backend profile settings can override environment selection. Shell exports persist in the current shell. A profile selects identity; the backend key selects state; resource inputs select target resources.

Never commit private keys, credential files, state, variable files containing secrets, or saved plans. Lockfiles are committed. The current `.gitignore` does not ignore every possible secret filename: inspect staged filenames before committing.

## State decisions

| Intention | Mechanism |
|---|---|
| Rename/refactor an address, preserve resource | `moved` block |
| Adopt an existing resource | Resource declaration plus `import` block |
| Stop managing, keep the real resource | `removed` with `lifecycle { destroy = false }` |
| Record externally changed values in state only | Reviewed refresh-only plan/apply |
| Restore declared values after drift | Normal reviewed plan/apply |
| Prevent configured resources from destruction | `prevent_destroy`; not a permanent cloud-side guard |
| Select a different environment | Its root directory/backend state key |

State changes can matter even when the summary reports zero infrastructure additions, changes, and destruction. State is not a history of every apply. Bucket versions and Git history serve different recovery purposes.

## Provider maintenance

```bash
terraform version
terraform init -upgrade
# Review version/checksum changes; validate and plan afterwards.
git diff -- .terraform.lock.hcl

terraform providers lock \
  -platform=darwin_arm64 \
  -platform=linux_amd64
```

Run these in the intended root. `-upgrade` selects allowed dependency versions, not a new Terraform CLI. Do not delete a lockfile merely to silence checksum verification.

## Pull request sequence

```bash
git switch main
git pull --ff-only
git switch -c descriptive-branch-name
# Edit and check files, then stage only intended paths.
git add path/to/changed-file
git diff --cached
git commit -m "Describe the change"
git push -u origin descriptive-branch-name
gh pr create --base main
gh pr checks --watch
gh pr diff
# Once reviewed and required checks pass:
gh pr merge --merge --delete-branch
```

`q` exits the diff pager. `--ff-only` refuses divergent-history merges. `--` separates paths from revision/options in commands such as `git diff -- file`. `??` is untracked; `M` is modified. `--auto` requests merging after requirements pass if supported; `--admin` bypasses protections and is not the normal fix for blocked checks.

## Deploy development through GitHub

```bash
# Run once after merging the intended changes:
gh workflow run terraform-dev.yml --ref main
gh run list --workflow terraform-dev.yml --limit 5
# Substitute the actual numeric run ID:
gh run view RUN_ID
gh run watch RUN_ID
```

1. Approve the plan job's environment access.
2. Read the `Plan development changes` log.
3. Approve apply only if the saved plan matches your intention.
4. Confirm apply success. Starting another workflow is a new deployment run, not a way to watch the existing one.

If a duplicate was started accidentally: `gh run cancel RUN_ID`. A successful cancellation does not undo previously completed changes. Rerun all jobs for this artifact-name scheme rather than only apply.

## Common flags and symbols

| Item | Meaning |
|---|---|
| `-input=false` | Do not prompt for missing Terraform inputs |
| `-backend=false` on init | Skip backend initialization for offline configuration checks |
| `-lockfile=readonly` | Do not change provider selections/checksums during init |
| `-lock-timeout=60s` | Wait up to 60 seconds for state lock |
| `-no-color` | Plain output without ANSI color codes |
| `-out=NAME.tfplan` | Save an executable Terraform plan |
| `+`, `~`, `-/+` in plans | Create, update in place, destroy then recreate |
| `--limit 5` | Return at most five CLI results |
| `gh pr diff 10` | Diff pull request number 10 |
| `|` in shell | Pipe standard output into the next command's input |
| `\` at end of shell line | Continue the command on the next line |
| YAML `run: |` | Multiline script text; not a shell pipe |
| `umask 077` | Restrict permissions for subsequently created files in that shell |

## GPG plan handoff

`--batch`: no interactive questions. `--yes`: accept GPG confirmations such as overwrites. `--pinentry-mode loopback`: supply the password through the caller instead of an interactive Pinentry program. `--passphrase-fd 0`: read it from standard input. `--symmetric`: password-based encryption. `--cipher-algo AES256`: choose AES-256. `--output`: destination file. `--decrypt`: reverse encryption.

The plaintext plan exists on trusted runners. Only the encrypted file is uploaded. Deleting a file reduces its exposure but is not guaranteed forensic erasure. Never print the password or upload the whole Terraform directory.

## Quick diagnostics

- SSH timeout after public-IP change: check the permitted source CIDR, routing, and network/host rules; known-host entries do not cause a network timeout.
- `Saved plan is stale`: generate and review a new plan.
- Lock error: identify the active owner before considering stale-lock recovery.
- No checks reported: not the same as checks passed.
- Merge blocked: inspect required checks/reviews and current PR commit.
- Apparent long validation: inspect individual step timestamps; job labels can be stale.
- OCI checksum mismatch in CI: inspect initialization output and platform checksums.
- `-out=...: command not found`: check the preceding line's continuation backslash.
- YAML parser error: check indentation, context names, and duplicate keys; `git diff --check` is not a YAML validator.


## Case: adopt an existing OCI compartment

Use a real OCID obtained from OCI. Replace placeholders before planning; never infer IDs from names alone. Match the current parent, name, and description if the goal is adoption without cloud changes.

```hcl
resource "oci_identity_compartment" "example" {
  compartment_id = var.parent_compartment_id
  name           = "existing-compartment-name"
  description    = "Existing description"
  enable_delete  = true
}

import {
  to = oci_identity_compartment.example
  id = "REPLACE_WITH_EXISTING_COMPARTMENT_OCID"
}
```

```bash
terraform plan -out=import.tfplan
terraform show import.tfplan
# Apply only after reviewing imports AND accompanying changes.
terraform apply import.tfplan
terraform state show oci_identity_compartment.example
terraform plan
```

`enable_delete = true` permits the OCI provider to attempt deletion in a future destroy plan. Choose it intentionally. Our re-import showed this as an additional update because it is provider-side state/configuration, not an OCI attribute recovered through import. It did not delete the compartment.

## Case: stop management without deleting the object

Replace the resource and its import block with:

```hcl
removed {
  from = oci_identity_compartment.example
  lifecycle {
    destroy = false
  }
}
```

```bash
terraform plan -out=forget.tfplan
# Confirm explicitly: no longer managed, but not destroyed.
terraform apply forget.tfplan
terraform state list
```

Verify independently in the cloud console that the object still exists. The entry is deleted from current state; the real object remains. To restore management, restore the resource/import declarations and apply a reviewed import plan. This reconstructs the entry; it does not roll back infrastructure or retrieve old state history.

## Case: refactor an address without replacing a resource

Rename the resource declaration and references, then retain a mapping:

```hcl
moved {
  from = oci_identity_compartment.old_label
  to   = oci_identity_compartment.new_label
}
```

Review and apply a saved plan. A pure move should have zero cloud creates/updates/destroys. For collection keys use addresses such as `oci_identity_compartment.practice["beta"]` and `["gamma"]`. `prevent_destroy` is not a substitute for the mapping.

## Case: optional module input, preserve existing callers

```hcl
variable "description" {
  type    = string
  default = null
}

# Inside the resource:
# description = var.description != null ? var.description : "Terraform-managed ${var.environment} environment"
```

Pass `description = "New description"` in only the intended root's module call. Plan both roots to verify isolation. An input default should preserve existing behavior when evolving a shared module.

## Case: drift—restore desired configuration or accept reality

```bash
terraform plan
terraform plan -refresh-only
```

These are alternative questions: normal plan asks how to reach the declared configuration; refresh-only asks how state records differ from reality. To accept an intentional external change permanently, also update the configuration. Refresh-only apply alone does not rewrite `.tf` files and a later normal plan can still propose undoing the drift.

## Case: inspect/back up state before recovery work

Run from the correct root and keep the resulting file outside the repository:

```bash
mkdir -p "$HOME/terraform-state-backups"
chmod 700 "$HOME/terraform-state-backups"
(umask 077; terraform state pull > "$HOME/terraform-state-backups/oci-lab-$(date +%Y%m%d-%H%M%S).tfstate")
```

Use a filename matching the actual root. `state pull` reads the current state from the selected backend. Parentheses limit the `umask` change to a subshell; `$(date ...)` supplies a timestamp. Check command success before treating the file as a valid backup. State can contain secrets.

For bucket-version recovery: stop writers, preserve the current snapshot, inspect historical versions of the exact state key, compare with reality, and plan a controlled restoration. This is a recovery checklist, not authorization to overwrite state. Re-import is usually more focused for one forgotten object. Never restore dev state over prod.

## Git HEAD and file restoration

`HEAD` identifies the currently checked-out commit, normally via its branch. `git restore --source=HEAD -- path/to/file` replaces a working file with that committed version and discards its uncommitted edits. It does not change Terraform's remote state. `git show HEAD:path/to/file` reads the committed version without modifying files.

## Case: diagnose blocked PRs before retrying

```bash
gh pr view PR_NUMBER --json headRefOid,mergeStateStatus,reviewDecision,statusCheckRollup
git log -1 --oneline
git ls-remote origin refs/heads/BRANCH_NAME
gh run view RUN_ID --json status,jobs
gh run view RUN_ID --log-failed
```

Substitute the actual IDs and branch. Compare local, remote-branch, and PR commit IDs. Our earlier stale PR head resolved after GitHub updated its metadata. In another incident all step timestamps showed quick completion despite stale job status; rerunning the check allowed the PR to merge. Neither incident justified force-pushing or bypassing rules.


## Module test design: optional owner input

| Input | Expected result | Test mechanism |
|---|---|---|
| `"platform-team"` | Matching owner tag | Assert tag value |
| Another name such as `"application-team"` | Also accepted, preserved | Separate assertion; catches accidental hardcoding |
| Omitted or explicit null | No owner tag | Assert absence of the key once map is known |
| `""` or `"   "` | Input rejected | `expect_failures = [var.owner]` |

`assert` checks a result of an otherwise successful run. `expect_failures` names the validation/check expected to fail: the test passes when the expected diagnostic occurs, and fails when the invalid input is accepted. It does not mean any arbitrary execution error counts as success.

With `mock_provider "oci" {}`, `command = apply` uses mocked provider operations, not live OCI resources. It can resolve values unknown during plan. Tests do not establish live IAM access. `try(map["owner"], null) == null` accepts both a missing key and a null value; use a key-presence check when absence itself is the requirement. Passing tests prove their assertions, not all input cases.

## Owner input code and optional expanded tests

The following snippets explain the module's owner input and its `null` fallback for `freeform_tags`. The six-run test file below is an optional expanded example to adapt; the repository's owner test file contains three runs.

Input declaration in the shared module:

```hcl
variable "owner" {
  description = "Optional owner; any nonblank string is accepted."
  type        = string
  default     = null

  validation {
    condition     = var.owner == null ? true : trimspace(var.owner) != ""
    error_message = "Owner must be null or a nonblank string."
  }
}
```

Inside the compartment resource:

```hcl
freeform_tags = var.owner != null ? { owner = var.owner } : null
```

Inside development's module call:

```hcl
owner = "platform-team"
```

`platform-team` is example data, not a required literal. Omitted/null is allowed; empty string/whitespace is rejected. The condition checks trimmed content but preserves the supplied nonblank string as the tag value.

Optional expanded `tests/owner-tag.tftest.hcl` (six cases):

```hcl
mock_provider "oci" {}

variables {
  parent_compartment_id = "ocid1.compartment.oc1..test"
  environment           = "dev"
}

run "owner_supplied" {
  command = plan
  variables {
    owner = "platform-team"
  }
  assert {
    condition     = oci_identity_compartment.compartment.freeform_tags["owner"] == "platform-team"
    error_message = "The supplied owner must be preserved as the owner tag."
  }
}

run "different_owner_supplied" {
  command = plan
  variables {
    owner = "application-team"
  }
  assert {
    condition     = oci_identity_compartment.compartment.freeform_tags["owner"] == "application-team"
    error_message = "Any nonblank owner must be accepted, not just platform-team."
  }
}

run "owner_omitted" {
  command = apply
  assert {
    condition     = !contains(keys(coalesce(oci_identity_compartment.compartment.freeform_tags, {})), "owner")
    error_message = "Omitting owner must not produce an owner tag."
  }
}

run "owner_explicit_null" {
  command = apply
  variables {
    owner = null
  }
  assert {
    condition     = !contains(keys(coalesce(oci_identity_compartment.compartment.freeform_tags, {})), "owner")
    error_message = "A null owner must not produce an owner tag."
  }
}

run "owner_empty" {
  command = plan
  variables {
    owner = ""
  }
  expect_failures = [var.owner]
}

run "owner_whitespace" {
  command = plan
  variables {
    owner = "   "
  }
  expect_failures = [var.owner]
}
```

The file-level `variables` block supplies shared inputs to every run; each run overrides or adds its own inputs. A run's owner override does not become the next run's default. The omitted/null runs use mocked apply to resolve computed provider values, not to deploy OCI resources. With a real provider, test apply can create real resources: always inspect the provider configuration before reusing a test.

Why the absence assertion works: `coalesce(tags, {})` substitutes an empty map for a known null map; `keys` returns its keys; `contains` tests for the owner key; `!` negates that result. A present `owner = null` would still have that key and would fail this strict absence check. `coalesce` does not resolve an unknown value before apply.

Commands from repository root:

```bash
terraform fmt -recursive environment-lab/modules/compartment
terraform -chdir=environment-lab/modules/compartment init -backend=false -input=false
terraform -chdir=environment-lab/modules/compartment validate
terraform -chdir=environment-lab/modules/compartment test
# Run only this test file:
terraform -chdir=environment-lab/modules/compartment test -filter=tests/owner-tag.tftest.hcl
```

Equivalent from `environment-lab/dev`:

```bash
terraform -chdir=../modules/compartment test
terraform -chdir=../modules/compartment test -filter=tests/owner-tag.tftest.hcl
```

`-filter` selects a test file, not a run-block name. `init -backend=false` initializes dependencies without connecting to a backend; the mocked provider, not this flag, is what prevents OCI API operations in these tests.

### Case solved: Unknown condition value in omitted-owner test

With `owner` omitted, the module passes null for the whole optional/computed tag map. Its resulting value is unknown during a fresh plan. Unknown is neither empty nor null. Comparing an unknown indexed value to null also yields unknown, which cannot establish a passing assertion.

Mock providers normally generate computed values during apply. For this test, keep `command = apply` and assert key absence after resolution. Directly indexing an absent key can instead produce an invalid-index error after apply, so do not use `tags["owner"] == null` to test absence.

`try` handles expression errors (such as an absent key), not unknown values. It does not turn a valid but unknown expression into its fallback. An alternative for other tests is `mock_provider "oci" { override_during = plan }`, which generates mock values during planning; choose it intentionally. Avoid overriding the owner result itself merely to force an assertion to pass.

Reference: https://developer.hashicorp.com/terraform/language/tests/mocking


## Case solved: local validation passes but CI says unsupported module argument

During PR #11, only the development caller's `owner` argument was committed. The shared module's new `variable "owner"`, its resource change, tests, and documentation remained uncommitted. Local checks saw working-tree files; GitHub checked out the commit and saw the old module interface.

Diagnose before changing working code:

```bash
git status --short
git show HEAD:environment-lab/modules/compartment/main.tf
git log -1 --stat
git diff --cached --stat
```

Stage the caller and module implementation together, along with tests and intended documentation, then review the staged diff, commit, and push. `git push` sends commits, not uncommitted local files. An `M` in the working-tree column and `??` files are not included merely because local tests passed.


## VM operations quick reference

Full code and explanations: [VM and bootstrap guide](vm-and-bootstrap-guide.md).

On the Mac, from `oci-lab`:

```bash
terraform output application_public_ip
VM_IP=$(terraform output -raw application_public_ip)
ssh -i ~/.ssh/oci_learning -o IdentitiesOnly=yes "ubuntu@$VM_IP"
# After exiting SSH, verify external HTTP:
curl -i "http://$VM_IP"
```

On the VM:

```bash
sudo cloud-init status --wait
sudo docker ps -a
sudo docker logs --tail 100 learning-web
sudo systemctl status docker --no-pager
sudo tail -n 100 /var/log/cloud-init-output.log
curl -i http://localhost
free -h
df -h /
```

Connection order: permitted source IP → OCI routing/ingress → guest service → Docker published port → Nginx content. SSH timeout, key rejection, and host-identity mismatch are different errors. `localhost` checks the VM from inside; public-IP HTTP checks the external path. Never assume Terraform apply success means bootstrap is complete.
