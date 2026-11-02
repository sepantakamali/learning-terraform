# Terraform practice guide

Implementation notes for `learning-terraform`: what was built, why it is configured this way, and how to repeat the operations or diagnose the same problems.

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

## 1. Provision a network and virtual machine

**Practice:** declare a compartment, VCN, internet gateway, route table, security list, subnet, and Ubuntu instance; inspect a plan, apply it, and connect with SSH.

**Why:** provisioning means creating and configuring infrastructure through a provider API. Resource references express dependencies; the order of `.tf` files does not control creation order.

**What happened:** initial Ampere A1 attempts failed, including through the cloud interface. Some AD shape queries were empty; possibly unavailable. Selecting a shape did not guarantee successful allocation. We ultimately used `VM.Standard.E2.1.Micro` with an x86 Ubuntu image.

**Key distinctions:** the image must support the instance’s CPU architecture. Oracle assigns each instance an OCID when it is created; Terraform records this identifier in state to associate its resource address with the actual OCI instance. The resource label, such as web, forms part of the Terraform address and is separate from the OCI display name. Existing resources already have their OCIDs before import.

## 2. SSH, source addresses, and Linux basics

**Practice:** connect as `ubuntu`, inspect `whoami`, `uname -m`, and `free -h`; update the allowed SSH source CIDR when the source's public IP (e.g. your computer's public IP) changed.

**Why:** the subnet’s OCI security list allows SSH connections to TCP port 22 only from the address specified by ssh_source_cidr. If the client’s public IP changes, update that input and apply the Terraform plan to update the security list in OCI. Editing the local file alone does not change the active rule. Once an SSH connection is established, the VM sends replies back over that connection to the client. The stateful security rule allows this return traffic. A client’s public IP can change independently of restarting its computer.

The [connection and verification commands](vm-and-bootstrap-guide.md#connect-and-verify) cover SSH access, the login user, CPU architecture, and memory usage. Each command is explained alongside its use.

**SSH timeout case:** the website remained reachable, but SSH timed out before authentication. The allowed source IP had been edited locally without applying it. Configuration files describe the desired rule; OCI continues enforcing the old rule until apply updates it. Review the security-list diff before applying, then retry SSH.

## 3. Bootstrap with cloud-init, Docker, and Nginx

**Practice:** replace the VM with one that installs and starts the application automatically through cloud-init. Verify with:

```bash
sudo cloud-init status --wait
sudo docker ps
curl -i http://localhost
```

**Why:** bootstrapping performs initial setup so a new server becomes usable without manual installation. Terraform creates the VM and supplies user data; cloud-init runs inside the VM. VM creation finishing does not necessarily mean bootstrap has finished.

Cloud-init installs Docker on the Ubuntu VM, creates `/opt/learning-app/index.html`, and starts the Nginx container. Docker mounts the VM’s `/opt/learning-app` directory at `/usr/share/nginx/html` inside the container, allowing Nginx to serve the HTML file.

In this exercise, we replaced the existing VM to verify that setup could run automatically. Cloud-init also runs during the initial setup of a newly created VM; replacement is not a prerequisite. See the [bootstrap code](vm-and-bootstrap-guide.md#bootstrap-install-docker-and-start-nginx) and [verification commands](vm-and-bootstrap-guide.md#connect-and-verify) for the command explanations.

## 4. Configuration, state, and drift

**Practice:** change a tag outside Terraform, compare normal and refresh-only plans, restore the desired value, and verify no changes.

**Why:** configuration describes the desired values. State records which real resource belongs to each Terraform address and its recorded attributes. A normal plan reads OCI and proposes changes to make the resources match the configuration. Refresh-only apply updates state to match OCI without changing the resources or editing `.tf` files.

For example, if a tag is `learning` in the configuration but was manually changed to `production` in OCI, a normal plan proposes restoring `learning`. Refresh-only apply records `production` in state, but the next normal plan still proposes restoring `learning`. To keep `production`, edit the configuration too.

An ordinary plan reads current values without saving them into the backend state. Apply saves state updates; it does not rewrite the configuration.

Tags classify resources for ownership, environment, or cleanup policies. A tag such as `cleanup = "eligible"` does not automatically delete anything.

## 5. Resource renaming and module extraction

**Practice:** rename `oci_core_instance.application` to `oci_core_instance.web`, then move it into `module.web_server.oci_core_instance.web` using `moved` blocks.

**Why:** without the address mapping, Terraform can interpret a rename as one resource removed and another added. `moved` preserves the binding to the existing OCID. Applying a pure move updates state without modifying the VM; it is not a provider in-place update.

Module variables are the module's input interface. The root supplies values in the module block; a child module does not automatically inherit root variables. Module outputs expose selected values to callers. Terraform reads all `.tf` files in a directory together: `variables.tf`, `main.tf`, and `outputs.tf` are conventions, not special execution phases.

Keep the `moved` blocks to document the address changes and let older states follow the same migration without replacing resources.

## 6. Central remote state and separate environments

**Practice:** create a private, versioned OCI Object Storage bucket separately, configure backend `oci`, back up local state, and run `terraform init -migrate-state`. Confirm state addresses remain present and plan reports no changes.

**Why:** The OCI remote backend lets local Terraform commands and GitHub Actions use the same stored state. It also locks that state during operations to prevent simultaneous conflicting updates. Each environment’s state has its own lock. The backend tells Terraform how to store state; declaring it does not create the bucket. `terraform { backend "oci" { ... } }` configures Terraform itself. The OCI provider separately manages infrastructure.

Development and production use the same bucket but separate state objects:

| Directory | State object key | Compartment |
|---|---|---|
| `environment-lab/dev` | `environment-lab/dev/terraform.tfstate` | `learning-env-dev` |
| `environment-lab/prod` | `environment-lab/prod/terraform.tfstate` | `learning-env-prod` |

The backend key selects the state, not the directory name. Each state associates the same Terraform resource address with a different compartment OCID. If both directories used the same bucket and key, they would share one state.

**Promotion** means testing a configuration change in development, then applying that change to production's own resources. For example:

1. Change the description in the shared compartment module.
2. Plan and apply in `dev`; only the development compartment changes.
3. Verify the development result.
4. Plan in `prod`, using production's inputs and state.
5. Review and apply the production plan.

The shared module edit is visible to both environments' future plans immediately, but each environment changes only when its own plan is applied. Each keeps its own state and resource IDs. Neither development's state nor its saved plan is copied to production.

Other clouds have similar backends: `azurerm` stores state in Azure Blob Storage, `s3` in AWS S3, and `gcs` in Google Cloud Storage. The backend stores state; the provider manages resources. They do not have to use the same cloud.

## 7. Imports and removal from management

**Practice:** manually create `learning-import-practice`, write its resource declaration, then import its OCID into `oci_identity_compartment.import_practice` using an `import` block. The initial plan also proposed a description capitalization change and the provider's `enable_delete` setting.

**Why:** importing records which existing OCI compartment belongs to the Terraform resource declaration. Terraform also compares the settings written in that declaration with the compartment’s current settings in OCI. For example, our configuration used `Compartment for practicing Terraform import`, while OCI had `compartment for practicing Terraform import` (lowercase 'c'). The plan therefore proposed importing the existing compartment and updating its description. Review both the import and any proposed updates before applying.

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

**Result:** Terraform stopped managing the compartment while OCI retained it. Omitting the explicit `destroy = false` would not express that intention. Restoring the resource and import declarations and applying an import plan reconnects the same OCID. Merely restoring the file does not restore the state binding.

**Re-import case:** the plan showed `1 to import, 0 to add, 1 to change, 0 to destroy`. The extra change was `+ enable_delete = true`: a provider-side setting reconstructed from configuration, not a request to delete the compartment. Inspect the individual diff rather than assuming every import has an import-only summary.

The removed entry really was deleted from the current state. Re-import reconstructed an entry by reading the same existing OCI compartment; it did not recover the old entry from backup. Other state entries were unaffected. Historical snapshots may remain under bucket versioning.

`git restore --source=HEAD -- import-practice.tf` restored the committed resource and import blocks in the working file. `HEAD` identifies the checked-out commit (normally through the current branch). That Git command changes the file only; it does not restore Terraform state. The subsequent reviewed import apply re-established the binding.

## 8. Collections, expressions, and lifecycle

**Practice:** create alpha and beta with `for_each`, update one description, rename beta to gamma, use a moved mapping to preserve identity, and test `prevent_destroy` and `ignore_changes` behavior.

**Why:** `for_each` map keys become part of each resource address, such as `practice["alpha"]`. Changing a key normally proposes removing the old resource and creating a new one. A `moved` block records the address change while keeping the existing resource. `prevent_destroy` blocks plans that would destroy it; it does not perform the rename. To allow an intentional destruction, remove `prevent_destroy` or set it to `false`, then review the plan. Removing the entire resource declaration also removes this protection, so it is not a permanent safeguard.

Current collection input is `map(object({ description = string, enabled = bool, purpose = string }))`. The expression `for key, settings in var.practice_compartments : key => settings if settings.enabled` constructs a map containing only enabled entries. `key => settings` specifies each resulting key and value. Filtering an existing key out can propose destruction.

Validation permits purpose `temporary` or `retained`. A condition chooses the cleanup tag. We also practised explicit variable files and corrected `variable.practice_compartments` to `var.practice_compartments`.

**`ignore_changes` example:** inside `oci_identity_compartment.practice`, the lifecycle block could be written as follows. This is an example for the exercise; the current `collections.tf` keeps only `prevent_destroy`.

```hcl
lifecycle {
  prevent_destroy = true
  ignore_changes  = [description]
}
```

The configured description is used when creating each compartment. After creation, Terraform ignores description differences when planning updates. For example, if alpha's description is changed in OCI from `First practice compartment` to `Description managed outside Terraform`, a normal plan will not propose changing it back while this rule is present.

Editing the configured description also will not update an existing compartment while it is ignored. Other attributes, such as tags, are still managed normally. This block applies to every instance of the `practice` resource, including alpha and gamma.

Remove `ignore_changes = [description]` to manage the description through Terraform again. The next normal plan proposes making it match the configuration. `ignore_changes` neither edits the `.tf` files nor prevents deletion; `prevent_destroy` is the separate protection against destruction.

## 9. Locks, cancellation, stale plans, and partial failure

**Practice:** hold an interactive apply open, attempt another operation on the same state, observe OCI's lock error, cancel the first operation, and retry. Later, apply another state-changing operation before attempting an older saved plan; Terraform rejected the stale plan.

**Why:** locking protects state from concurrent writers. `-lock-timeout=60s` waits up to that duration to acquire a lock; it is not an overall apply timeout. It does not lock the entire bucket or other states.

For this OCI backend, Terraform attempts to create an object named after the state key with `.lock` appended. The creation request uses `If-None-Match: *`, meaning it must succeed only if that object does not already exist. This atomic condition lets one operation acquire the lock; another cannot overwrite it. Our second terminal received HTTP 412 while the first held it. Normal completion or cancellation releases the lock. [OCI backend locking](https://developer.hashicorp.com/terraform/language/backend/oci)

The lock coordinates Terraform operations on that state. It does not stop the VM, block console edits, or lock other environment state keys.

GitHub workflow concurrency is a separate scheduling control. 

A lock left by an interrupted process requires checking that the original operation has stopped before considering `force-unlock`.

An apply waiting for input can retain a lock. Ctrl-Z suspends a process rather than finishing it; use `jobs`, then `fg` and an appropriate cancellation to stop a suspended command. Do not force-unlock a live operation or use `-lock=false` to bypass a real conflict.

Terraform does not guarantee transaction-wide rollback after a partial failure. Successfully created objects can remain. Inspect the error, state, and fresh plan before retrying. A stale plan needs regeneration and renewed review, not forced application.

## 10. Provider versions, aliases, and checksums

**Practice:** add an OCI provider configuration named `london`, select it for a module, and upgrade the development provider from 9.9.0 to 9.10.0.

**Provider aliases:** an alias lets us name an additional configuration for the same provider. `oci.london` means the OCI provider configuration with `alias = "london"`. The name `london` does not select a region by itself; the provider's `region` setting does that.

In the module call:

```hcl
providers = {
  oci = oci.london
}
```

This tells the module to use the caller's `oci.london` configuration for its OCI resources. The two configurations can use the same credentials with different regions, or different credentials if needed. A credential profile identifies the user making requests; it does not select a compartment.

**Version constraints:** these control which provider versions Terraform may install:

| Constraint | Allowed versions |
|---|---|
| `~> 9.2` | 9.2.0 or newer, but below 10.0.0 |
| `~> 9.2.0` | 9.2.0 or newer, but below 9.3.0 |
| `= 9.9.0` | Only 9.9.0 |

`terraform init` normally reuses the version recorded in the lockfile. `terraform init -upgrade` selects a newer version if one is available within the allowed range. It cannot upgrade an exact `= 9.9.0` constraint to 9.10.0. Upgrading the OCI provider does not upgrade the Terraform command-line program itself.

**Provider lockfile:** `.terraform.lock.hcl` records the selected provider version and checksums used to verify its downloaded packages. A checksum is a fingerprint of a package's contents. A mismatch means Terraform cannot verify that package against the recorded checksums.

Several checksums can belong to the same provider version because packages differ between operating systems and CPU architectures, and Terraform supports different checksum formats. They are not previous versions or previous applies. Git history preserves earlier revisions of the lockfile.

**CI checksum case:** local work used macOS on ARM, while GitHub Actions used Linux on AMD64. We added checksums for both platforms:

```bash
terraform providers lock \
  -platform=darwin_arm64 \
  -platform=linux_amd64
```

Run this in the intended Terraform root, review the lockfile changes, and commit them. CI uses `terraform init -lockfile=readonly` so initialization cannot change the committed provider selections or checksums.

## 11. Tests and credential-free CI

**Practice:** validate invalid tag input, deliberately break formatting, observe CI failure, fix it, and add module tests using a mocked OCI provider.

**Why:** `fmt` checks formatting; `validate` checks configuration consistency; mock `terraform test` checks expressions and assertions without deploying real infrastructure. These tests do not establish real OCI authorization, capacity, or network reachability. Mock IDs need to satisfy whatever validation is actually exercised; realistic-looking strings are not proof of real resource existence.

The `Terraform checks` workflow initializes and validates oci-lab, dev, and prod with `-backend=false`, then runs the compartment module's naming and owner-input tests. The compartment module is used by dev and prod. Job label `validate` covers all these steps.

## 12. Git, pull requests, and branch protection

**Practice:** authenticate the GitHub CLI (`gh`), create the repository, push a branch, open a pull request, review its changes and checks, then merge it and delete the completed branch.

**Pull requests:** a PR proposes adding one branch's changes to another branch, usually `main`. Our GitHub Actions workflow runs checks, and repository rules require specified checks to pass before merging. Merging updates the repository code; our separate development deployment workflow must still be started and approved to change OCI.

`origin` is the local nickname for the GitHub repository. `main` is a branch name. `origin/main` is the local record of that remote branch as last fetched.

**Fast-forward:** if the remote branch has new commits and the local branch has no separate commits, Git can move the local branch forward to include those commits:

```text
Local main:   A → B
Remote main:  A → B → C → D
After pull:   A → B → C → D
```

```bash
git pull --ff-only
```

This fetches remote changes and updates the current branch only if it can do so without combining separate lines of development. If local and remote both have commits the other lacks, it stops instead:

```text
Local main:   A → B → X
Remote main:  A → B → C → D
```

Neither branch contains the other's full history. Decide how to combine the changes before continuing.

**Merge and rebase:** merge keeps the existing commits and can add a merge commit joining the two histories. Rebase takes the local changes and reapplies them after the other branch's commits, creating new commit IDs. In the example, rebasing local `X` onto the remote branch produces `A → B → C → D → X′`. Either approach can require resolving conflicts.

```bash
gh pr merge --merge --delete-branch
```

Here, `merge` is the action, `--merge` selects the merge-commit method, and `--delete-branch` requests deletion of the PR branch after merging. Other methods are `--squash`, which combines the PR changes into one commit, and `--rebase`, which adds its commits without a merge commit.

**Review commands:**

```bash
git diff -- path/to/file
git diff --cached
git diff --check
git status --short
```

- `-- path/to/file` identifies the file to inspect, separating it from command options or revision names.
- `--cached` shows staged changes that will be included in the next commit.
- `--check` checks whitespace errors and introduced conflict markers; it does not validate Terraform or YAML.
- In short status output, `??` means untracked and `M` means modified. The two status columns distinguish staged changes from unstaged changes.

**Delayed checks:** PR #9 initially showed an older commit than the remote branch, then showed the current commit on a later query. For PR #10, validation remained pending for an unusually long time; rerunning it completed successfully and allowed merging. The cause of the delay was not established. Check the PR's current commit and individual job results before retrying or changing code.

## 13. Restricted automation credentials

**Practice:** create a dedicated OCI user and group, generate an API-signing PEM key, grant scoped dev compartment/state permissions, verify access using OCI CLI, and store the private key as a GitHub environment secret.

**Why:** CI should not use the human administrator's credentials. PEM is a text encoding/container format for cryptographic material. An unattended process needs access to its key without a human entering a passphrase; that increases the importance of scoped permissions, protected secret access, rotation, and temporary files. A console password and an API-signing key are separate credentials.

The restricted identity can update the existing dev compartment, read foundation state, and handle dev state/lock objects. It is not intended to create arbitrary infrastructure or manage prod. Reading a remote-state output requires access to the underlying state snapshot; output selection is not an access-control boundary.

The workflow selects `GITHUB_TERRAFORM_DEV`. The OCI provider uses `OCI_CONFIG_FILE_PROFILE`; the backend selection uses `OCI_config_file_profile`. GitHub env mappings rejected both case variants together, so the lowercase form is assigned immediately before shell commands that need it. Local OCI-lab work uses `LEARNING_TERRAFORM`.

## 14. Approved saved-plan deployment

**Practice:** manually dispatch the main-branch workflow, approve plan access, inspect the plan, approve apply, then change only development's description through a PR and the workflow. This exercised both a no-change run and deployment of an actual description update.

**Why:** the apply job consumes the exact saved plan instead of generating a different unreviewed plan. Both jobs use the protected development environment, giving two approval gates. GitHub calls these deployments even when the first job only plans.

Each job has a separate hosted runner. The plan job writes `dev.tfplan`, encrypts it with GPG and `TF_PLAN_PASSWORD`, uploads only `dev.tfplan.gpg`, and removes local files. The apply job checks out the workflow commit, initializes matching providers, downloads, decrypts, and applies the plan. The artifact expires after three days. Rerun all jobs with this implementation because artifact names include `github.run_attempt`.

Encryption protects the stored artifact's contents, not a compromised runner that has both plaintext and the password. Terraform must access plaintext during creation/application. Secrets marked sensitive can still be present in saved plans/state; hiding console output is not encryption.

`checkout` obtains repository files; its GitHub token is separate from OCI credentials. `persist-credentials: false` avoids persisting checkout authentication for later Git commands. `terraform_wrapper: false` disables setup-terraform's output-capturing wrapper. `-no-color` removes ANSI formatting. `needs: plan` orders jobs; it does not itself grant approval.

File permissions: the plan-creation step does not yet set `umask 077`; encryption and decryption steps do. Adding it before plan creation would also restrict the initial plaintext file permissions.

## State recovery considerations

The state bucket has versioning enabled. Recovery begins by stopping competing writers, backing up the current state, identifying the correct state key and historical version, and comparing that snapshot with actual infrastructure. Restoring an older state does not roll back cloud resources; it changes Terraform's records. A subsequent plan can propose unexpected actions if records and reality differ.

For one accidentally forgotten resource, a reviewed import is often more focused than restoring a whole old snapshot. Do not casually overwrite remote state or use forced state push.

## 15. Optional owner tags and module tests

The compartment module accepts an optional `owner` string. Omitted or null means no owner tag; any nonblank string is accepted and preserved; an empty or whitespace-only string fails validation. `platform-team` is the development caller's value, not a required literal.

The checked-in suite has two naming tests and three owner tests: supplied, omitted, and invalid whitespace. With `mock_provider "oci" {}`, a test's `command = apply` uses mock operations rather than creating a cloud compartment.

**Problem encountered:** changing the omitted-owner test to `command = plan` produced `Unknown condition value`. The module passes null for the optional/computed tag map, so its result can be unknown during planning. Mock apply resolves that value. Test absence with a key-presence assertion after resolution; `try` catches expression errors but cannot turn an unknown value into a known one.

```bash
# From the repository root:
terraform -chdir=environment-lab/modules/compartment init -backend=false -input=false
terraform -chdir=environment-lab/modules/compartment test
terraform -chdir=environment-lab/dev plan
terraform -chdir=environment-lab/prod plan
```

The owner change produced a dev plan adding only the tag and a prod plan with no changes. This demonstrates separate environment inputs and state despite shared module code. See the [cheat sheet](repository-cheat-sheet.md#module-test-design-optional-owner-input) for the implementation snippets, assertions, and an optional expanded test suite.

## Project glossary

| Term | Meaning in this project |
|---|---|
| AD — Availability Domain | One or more isolated data centres within an OCI region; determines VM placement. It is separate from a compartment or a dev/prod environment. |
| OCID | Oracle's identifier for a cloud resource. |
| Object key | An object's name within a bucket, such as `environment-lab/dev/terraform.tfstate`; it is not an OCID. |
| Reference example | A code example to look up and adapt later. Expanded examples are labelled separately from checked-in implementation. |
| Terraform reference | An expression such as `oci_core_subnet.application.id` that reads another value and can establish a dependency. |
| State lock | Temporary exclusive access to a particular Terraform state during an operation. |
| Provider lockfile | `.terraform.lock.hcl`: selected provider versions and checksums; unrelated to the temporary state lock. |

An AD has separate power, cooling, and internal networking from other ADs in its region. Placing one VM in an AD does not make the application highly available. [OCI regions and availability domains](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm)

## Official references

- [Terraform removed blocks](https://developer.hashicorp.com/terraform/language/block/removed)
- [Terraform plan and saved-plan behavior](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [Provider lock checksums](https://developer.hashicorp.com/terraform/cli/commands/providers/lock)
- [OCI backend](https://developer.hashicorp.com/terraform/language/backend/oci)
- [Artifact upload](https://github.com/actions/upload-artifact) and [download](https://github.com/actions/download-artifact)
- [GPG password-input flags](https://www.gnupg.org/documentation/manuals/gnupg/GPG-Esoteric-Options.html)
