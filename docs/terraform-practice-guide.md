# Terraform practice guide

This is the learning record for `learning-terraform`, reconstructed from our exercises and checked against the repository through 23 October 2026. Completed cloud actions below are based on reported command results; this document is not a fresh audit of OCI. Commands are examples to run deliberately, not a script to execute from top to bottom.

## Repository and dependency map

```text
OCI tenancy
├── state bucket (created separately; private, versioning enabled)
│   ├── oci-lab/terraform.tfstate
│   ├── environment-lab/dev/terraform.tfstate
│   └── environment-lab/prod/terraform.tfstate
└── learning compartment (managed by oci-lab)
    ├── VCN → internet gateway + route table + security list → subnet → VM
    ├── imported practice compartment
    ├── alpha and gamma collection practice compartments
    ├── development compartment (managed by dev state)
    └── production compartment (managed by prod state)
```

`oci-lab` exports its learning compartment ID. Development and production read that root output through `data.terraform_remote_state.foundation`, then pass it into the shared compartment module. The label `foundation` describes this dependency; it has no special Terraform meaning.

The VM uses `oci-lab/modules/web_server`. Development and production use `environment-lab/modules/compartment`. Shared module code does not mean shared resource ownership: each root's state maps its module address to a different OCI resource ID.

See the [VM and bootstrap guide](vm-and-bootstrap-guide.md) for the full code listings, architecture, flags, verification, and replacement procedure.

## 1. Provision a network and virtual machine

**Practice:** declare a compartment, VCN, internet gateway, route table, security list, subnet, and Ubuntu instance; inspect a plan, apply it, and connect with SSH.

**Why:** provisioning means creating and configuring infrastructure through a provider API. Resource references express dependencies; the order of `.tf` files does not control creation order.

**What happened:** initial Ampere A1 attempts failed, including through the console. Some AD shape queries were empty. Selecting a shape did not guarantee successful allocation. We ultimately used `VM.Standard.E2.1.Micro` with an x86 Ubuntu image. The historical errors alone do not prove every failure had the same cause.

**Key distinctions:** an image must match the CPU architecture. A subnet ID is a reference to a real resource. A Terraform resource label is a local address, not the OCI display name or OCID.

## 2. SSH, source addresses, and Linux basics

**Practice:** connect as `ubuntu`, inspect `whoami`, `uname -m`, and `free -h`; update the allowed SSH source CIDR when the Mac's public IP changed.

**Why:** the OCI ingress rule permits incoming connections from the specified public IP to TCP port 22. Terraform updates that cloud network rule; it does not tell the VM where to send a CLI session. Replies belong to the established connection. A dynamic public IP can change independently of restarting a computer.

SSH `-i` selects the private identity key. `-o IdentitiesOnly=yes` sets an SSH option that restricts offered identities. `known_hosts` records server identities; multiple entries can represent different host-key algorithms. `ssh-keygen -R IP` removes recorded keys for that host, not your login key.

`free -h`: `free` is unused RAM; `buff/cache` includes filesystem caches; `available` estimates memory usable by new work without swapping and includes reclaimable cache. MiB means mebibytes. Low free memory alone does not establish memory pressure. `tmpfs` is a memory-backed filesystem that can use swap when available; Docker can mount one for temporary container data.

## 3. Bootstrap with cloud-init, Docker, and Nginx

**Practice:** replace the VM with one that installs and starts the application automatically through cloud-init. Verify with:

```bash
sudo cloud-init status --wait
sudo docker ps
curl -i http://localhost
```

**Why:** bootstrapping performs initial setup so a new server becomes usable without manual installation. Terraform creates the VM and supplies user data; cloud-init runs inside the guest. VM creation finishing does not necessarily mean bootstrap has finished.

Docker runs containers; Nginx is the web server inside the container. `/opt/learning-app` is a host directory used for application files, not itself a container. Container filesystem paths are a separate namespace. `systemctl enable --now docker` enables startup on future boots and starts Docker immediately. `curl -i` includes response headers. `.yaml` and `.yml` are equivalent filename extensions.

Replacement changed IPs and host keys. Persistent application data would need a separate preservation plan before replacement.

## 4. Configuration, state, and drift

**Practice:** change a tag outside Terraform, compare normal and refresh-only plans, restore the desired value, and verify no changes.

**Why:** configuration expresses desired values; state records resource bindings and known attributes; refresh reads current provider data. A normal plan compares refreshed reality with configuration. Refresh-only apply records observed changes in state without changing the remote resource or rewriting `.tf` files.

`terraform plan` previews; a normal plan is not a command to permanently accept drift into stored state. `terraform apply` does not rewrite your source configuration. A no-change plan is evidence of agreement for the attributes Terraform manages at that moment.

Tags classify resources for ownership, environment, or cleanup policies. A tag such as `cleanup = "eligible"` does not automatically delete anything.

## 5. Resource renaming and module extraction

**Practice:** rename `oci_core_instance.application` to `oci_core_instance.web`, then move it into `module.web_server.oci_core_instance.web` using `moved` blocks.

**Why:** without the address mapping, Terraform can interpret a rename as one resource removed and another added. `moved` preserves the binding to the existing OCID. Applying a pure move updates state without modifying the VM; it is not a provider in-place update.

Module variables are the module's input interface. The root supplies values in the module block; a child module does not automatically inherit root variables. Module outputs expose selected values to callers. Terraform reads all `.tf` files in a directory together: `variables.tf`, `main.tf`, and `outputs.tf` are conventions, not special execution phases.

Keep useful `moved` history for older states that have not yet applied the migration.

## 6. Central remote state and separate environments

**Practice:** create a private, versioned OCI Object Storage bucket separately, configure backend `oci`, back up local state, and run `terraform init -migrate-state`. Confirm state addresses remain present and plan reports no changes.

**Why:** a remote backend provides shared state access and, for this backend, locking. The backend tells Terraform how to store state; declaring it does not create the bucket. `terraform { backend "oci" { ... } }` configures Terraform itself. The OCI provider separately manages infrastructure.

Development and production use the same bucket but different object keys. Their identical `module.compartment.oci_identity_compartment.compartment` addresses live in different states and refer to different compartments. Separation is established by backend state selection, not by the filename alone.

Promotion means applying a reviewed configuration version to another environment. Copying dev state over prod state is not promotion. A shared module edit can affect both future plans, but applying dev does not apply prod.

Other platforms offer analogous backends, such as `azurerm` for Azure Blob Storage, `s3` for AWS S3, and `gcs` for Google Cloud Storage. Backend choice need not match the cloud managed by providers.

## 7. Imports and removal from management

**Practice:** manually create `learning-import-practice`, write its resource declaration, then import its OCID into `oci_identity_compartment.import_practice` using an `import` block. The initial plan also proposed a description capitalization change and the provider's `enable_delete` setting.

**Why:** importing connects an existing object to a Terraform address. It does not create another compartment, nor does it guarantee the handwritten configuration matches every observed value. Review accompanying changes before applying.

`enable_delete` is an OCI-provider compartment option; it is distinct from Terraform's `prevent_destroy` lifecycle rule and from IAM permission.

Later we replaced the resource and import blocks with:

```hcl
removed {
  from = oci_identity_compartment.import_practice
  lifecycle {
    destroy = false
  }
}
```

**Result reported:** Terraform stopped managing the compartment while OCI retained it. Omitting the explicit `destroy = false` would not express that intention. Restoring the resource and import declarations and applying an import plan reconnects the same OCID. Merely restoring the file does not restore the state binding.

**Completed checkpoint:** the learner reported successful re-import and verification. The re-import plan showed `1 to import, 0 to add, 1 to change, 0 to destroy`, rather than the initially predicted import-only summary. The additional diff was `+ enable_delete = true`: a provider-side setting reconstructed from configuration, not a deletion request. The learner correctly stopped to investigate the unexpected change before applying.

The removed entry really was deleted from the current state. Re-import reconstructed an entry by reading the same existing OCI compartment; it did not recover the old entry from backup. Other state entries were unaffected. Historical snapshots may remain under bucket versioning.

`git restore --source=HEAD -- import-practice.tf` restored the committed resource and import blocks in the working file. `HEAD` identifies the checked-out commit (normally through the current branch). That Git command changes the file only; it does not restore Terraform state. The subsequent reviewed import apply re-established the binding.

## 8. Collections, expressions, and lifecycle

**Practice:** create alpha and beta with `for_each`, update one description, rename beta to gamma, use a moved mapping to preserve identity, and test `prevent_destroy` and `ignore_changes` behavior.

**Why:** map keys form stable resource identities. Changing a key normally proposes remove/add; `prevent_destroy` blocks destruction but does not rename the binding. Use `moved` to preserve identity. Removing an entire resource declaration also removes its configuration-based lifecycle protection.

Current collection input is `map(object({ description = string, enabled = bool, purpose = string }))`. The expression `for key, settings in var.practice_compartments : key => settings if settings.enabled` constructs a map containing enabled entries. `key => settings` specifies each resulting key and value. Filtering an existing key out can propose destruction.

Validation permits purpose `temporary` or `retained`. A conditional chooses the cleanup tag. We also practised explicit variable files and corrected `variable.practice_compartments` to `var.practice_compartments`.

`ignore_changes` delegates selected ongoing attribute changes; it does not prevent resource deletion or mean Terraform adopts those values into source code.

## 9. Locks, cancellation, stale plans, and partial failure

**Practice:** hold an interactive apply open, attempt another operation on the same state, observe OCI's lock error, cancel the first operation, and retry. Later, apply another state-changing operation before attempting an older saved plan; Terraform rejected the stale plan.

**Why:** locking protects state from concurrent writers. `-lock-timeout=60s` waits up to that duration to acquire a lock; it is not an overall apply timeout. It does not lock the entire bucket or other states.

An apply waiting for input can retain a lock. Ctrl-Z suspends a process rather than finishing it; use `jobs`, then `fg` and an appropriate cancellation to stop a suspended command. Do not force-unlock a live operation or use `-lock=false` to bypass a real conflict.

Terraform does not guarantee transaction-wide rollback after a partial failure. Successfully created objects can remain. Inspect the error, state, and fresh plan before retrying. A stale plan needs regeneration and renewed review, not forced application.

## 10. Provider versions, aliases, and checksums

**Practice:** configure default OCI and aliased `oci.london`, pass it to a module with `providers = { oci = oci.london }`, and upgrade the dev provider from 9.9.0 to 9.10.0 within the constraint.

**Why:** aliases name provider configurations. They can differ in region, identity, or other settings. Different regions do not inherently require different identities. A profile name selects credentials; it is not the compartment being managed.

`~> 9.2` permits versions from 9.2 up to but excluding 10.0; `~> 9.2.0` limits upgrades to the 9.2 series. An exact pin cannot be upgraded outside its constraint by `init -upgrade`. Provider upgrades do not upgrade the Terraform CLI.

`.terraform.lock.hcl` records selected provider versions and accepted package checksums. It contains neither infrastructure history nor previous applies. Multiple hashes can describe platform packages/hash formats for the same selected version. Git preserves earlier lockfile revisions.

We repaired a Mac ARM/Linux AMD64 CI checksum problem by recording both platforms with `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64`, keeping CI `-lockfile=readonly`.

## 11. Tests and credential-free CI

**Practice:** validate invalid tag input, deliberately break formatting, observe CI failure, fix it, and add module tests using a mocked OCI provider.

**Why:** `fmt` checks formatting; `validate` checks configuration consistency; mock `terraform test` checks expressions and assertions without deploying real infrastructure. These tests do not establish real OCI authorization, capacity, or network reachability. Mock IDs need to satisfy whatever validation is actually exercised; realistic-looking strings are not proof of real resource existence.

The `Terraform checks` workflow initializes and validates oci-lab, dev, and prod with `-backend=false`, then runs the compartment module's naming tests. The compartment module is used by dev and prod, not by the unrelated web-server module. Job label `validate` covers all these steps; it is not the duration of the validate command alone.

## 12. Git, pull requests, and branch protection

**Practice:** authenticate `gh`, create the public repository, push branches, inspect diffs, open PRs, wait for checks, merge, and delete completed branches.

**Why:** a PR (pull request) proposes integrating a branch into another branch with review and checks. `origin` is a remote nickname; `main` is a branch name. The command `gh pr merge --merge` has a verb and a separate merge-method flag. Alternatives include squash and rebase.

Fast-forward advances a branch pointer without a merge commit; `git pull --ff-only` refuses divergent histories requiring a merge. Rebase replays commits onto another base and changes their identities; merge can combine diverged histories with a merge commit.

`git diff -- path` uses `--` to separate revisions/options from paths. `git diff --check` checks whitespace problems and conflict markers, not Terraform or workflow semantics. `??` means untracked. Exit the diff pager with `q`, not Ctrl-Z. Commit-message imperative wording is a convention.

We encountered delayed GitHub PR/check status reporting: step timestamps showed execution had finished while a job still appeared running. Inspect evidence rather than assuming Terraform is slow. Do not bypass required checks merely because a status looks stale.

## 13. Restricted automation credentials

**Practice:** create a dedicated OCI user and group, generate an API-signing PEM key, grant scoped dev compartment/state permissions, verify access using OCI CLI, and store the private key as a GitHub environment secret.

**Why:** CI should not use the human administrator's credentials. PEM is a text encoding/container format for cryptographic material. An unattended process needs access to its key without a human entering a passphrase; that increases the importance of scoped permissions, protected secret access, rotation, and temporary files. A console password and an API-signing key are separate credentials.

The restricted identity can update the existing dev compartment, read foundation state, and handle dev state/lock objects. It is not intended to create arbitrary infrastructure or manage prod. Reading a remote-state output requires access to the underlying state snapshot; output selection is not an access-control boundary.

The workflow selects `GITHUB_TERRAFORM_DEV`. The OCI provider uses `OCI_CONFIG_FILE_PROFILE`; the backend selection uses `OCI_config_file_profile`. GitHub env mappings rejected both case variants together, so the lowercase form is assigned immediately before shell commands that need it. Local OCI-lab work uses `LEARNING_TERRAFORM`.

## 14. Approved saved-plan deployment

**Practice:** manually dispatch the main-branch workflow, approve plan access, inspect the plan, approve apply, then change only development's description through a PR and the workflow. Both the no-change run and actual description deployment were reported successful.

**Why:** the apply job consumes the exact saved plan instead of generating a different unreviewed plan. Both jobs use the protected development environment, giving two approval gates. GitHub calls these deployments even when the first job only plans.

Each job has a separate hosted runner. The plan job writes `dev.tfplan`, encrypts it with GPG and `TF_PLAN_PASSWORD`, uploads only `dev.tfplan.gpg`, and removes local files. The apply job checks out the workflow commit, initializes matching providers, downloads, decrypts, and applies the plan. The artifact expires after three days. Rerun all jobs with this implementation because artifact names include `github.run_attempt`.

Encryption protects the stored artifact's contents, not a compromised runner that has both plaintext and the password. Terraform must access plaintext during creation/application. Secrets marked sensitive can still be present in saved plans/state; hiding console output is not encryption.

`checkout` obtains repository files; its GitHub token is separate from OCI credentials. `persist-credentials: false` avoids persisting checkout authentication for later Git commands. `terraform_wrapper: false` disables setup-terraform's output-capturing wrapper. `-no-color` removes ANSI formatting. `needs: plan` orders jobs; it does not itself grant approval.

Current implementation note from file inspection: the plan-creation step does not yet set `umask 077`; encryption and decryption steps do. Adding it before plan creation would also restrict the initial plaintext file permissions. Documentation creation did not alter the workflow.

## Recovery principles — explanation, not an executed recovery drill

The state bucket has versioning enabled. Recovery begins by stopping competing writers, backing up the current state, identifying the correct state key and historical version, and comparing that snapshot with actual infrastructure. Restoring an older state does not roll back cloud resources; it changes Terraform's records. A subsequent plan can propose unexpected actions if records and reality differ.

For one accidentally forgotten resource, a reviewed import is often more focused than restoring a whole old snapshot. Do not casually overwrite remote state or use forced state push. The lab has practised locks, stale plans, import, and removal, but has not deliberately corrupted state or demonstrated bucket-version restoration.

## Course completion and follow-through

1. Completed: remove the imported compartment from management and re-import the same OCI object.
2. Completed: owner-input assessment passed on 23 October 2026: five tests passed, dev planned only the owner-tag update, and prod planned no changes. Applying the tag through CI is a separate deployment follow-through, not an additional assessment requirement.
3. Keep this guide updated as the repository changes. Terraform is an ongoing tool, not a list of commands to memorize.

## Official references

- [Terraform removed blocks](https://developer.hashicorp.com/terraform/language/block/removed)
- [Terraform plan and saved-plan behavior](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [Provider lock checksums](https://developer.hashicorp.com/terraform/cli/commands/providers/lock)
- [OCI backend](https://developer.hashicorp.com/terraform/language/backend/oci)
- [Artifact upload](https://github.com/actions/upload-artifact) and [download](https://github.com/actions/download-artifact)
- [GPG password-input flags](https://www.gnupg.org/documentation/manuals/gnupg/GPG-Esoteric-Options.html)


## Final assessment checkpoint — 23 October 2026

The learner reported five passing mock tests: two naming tests and three owner cases (supplied, omitted, whitespace). This confirms those tested cases, not every possible valid owner. Review found validation additionally restricted the owner to `platform-team`, although any nonblank team name should be accepted. That restriction needs removal and another valid-name test should prevent regression. Deployment of this assessment is not yet recorded; the later assessment result below supersedes this intermediate code review.

The omitted test currently uses mock `command = apply` and `try(map["owner"], null) == null`. With the OCI provider mocked this does not create a real OCI compartment. It accepts either a missing owner key or a null-valued owner key, so it is broader than a strict absence assertion. The module currently assigns null to the whole optional tag map when the owner is omitted. This can leave the computed provider attribute unknown at plan time; a mock apply resolves it.

Clear acceptance criteria: omitted/null is valid and adds no owner tag; any nonblank string is valid and is preserved; empty or whitespace-only strings fail variable validation. `platform-team` is sample data, not an allowed-values list.

### Assessment clarification: expectations and unknown values

The original exercise explanation did not distinguish sufficiently clearly between omitted/null and an empty string, or between sample owner data and an allowed-values list. This was an instruction ambiguity, not evidence that the learner should have guessed a different specification. The agreed requirement is now explicit: any nonblank string is accepted; omitted/null adds no owner tag; empty/whitespace is rejected.

After correcting validation, the learner changed the omitted-owner test to a plan and saw `Unknown condition value`. This is not a requirement to supply an owner. With the current null fallback, the optional/computed tag map is unknown until mocked apply. The previous use of mock apply was appropriate. A strict absence assertion checks map keys after resolution, rather than comparing an indexed missing value to null. `try` does not resolve unknown values.

The cheat sheet now contains complete owner-input, resource-argument, caller-input, and six-run mock test examples, initialization/test/filter commands, and an explanation of assertions and unknown values. These are reference snippets, not automatic changes to the learner's implementation. At this historical checkpoint, successful execution of the revised suite and final deployment were unconfirmed. See the assessment result below for the subsequent verified tests and plans.


## Assessment result — passed, 23 October 2026

The learner supplied evidence of five passing tests (two naming and three owner tests), a development plan containing only `owner = "platform-team"` with 0 add / 1 change / 0 destroy, and a production plan reporting no changes. This satisfies the original implementation, three required test cases, and environment-isolation requirements. The exercise is passed. Additional example test cases in the cheat sheet are reference extensions, not retroactive pass requirements.

The assessment involved clarification and guided debugging; it should not be represented as an entirely unassisted implementation or as proof of mastery of every Terraform feature. Deployment of this particular owner tag has not yet been reported and is separate from the passed assessment. Earlier pending checkpoints above describe the historical progression and are superseded by this result.
