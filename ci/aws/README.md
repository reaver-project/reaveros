# ReaverOS AWS CI

ReaverOS owns the build semantics and job graph for its CI. Persistent AWS
resources, runner registration credentials, GitHub policy, and the reusable
runner-control actions are owned by the `reaver-project/infrastructure`
repository.

The workflows consume the contract and revision recorded in
`infrastructure-contract-version` and `infrastructure-revision`. Every shared
action use is pinned to that full revision. ReaverOS needs these non-secret
repository variables:

- `AWS_INFRASTRUCTURE_CONTRACT_VERSION` records the version read back from the
  deployed stack;
- `AWS_INFRASTRUCTURE_REVISION` records the exact infrastructure commit whose
  reviewed change set was deployed;
- `AWS_REGION`;
- `AWS_RUNNER_STACK_NAME`;
- `AWS_RUNNER_ROLE_ARN`;
- `AWS_PRODUCTION_PROMOTION_ROLE_ARN` identifies the main-only role that writes
  production ECR images;
- `CI_GATE_APP_SLUG` identifies the App allowed to publish an admitted revision
  to a protected CI branch; and
- `MAINTENANCE_APP_SLUG` identifies the App allowed to publish automatic
  infrastructure updates.

The infrastructure deployment publishes these variables through its
infrastructure GitHub App. Its Maintenance App proposes a matching update to
the recorded contract and shared-action pins; repository rules still apply to
that pull request.

## Authorization

The CI Gate App receives pull-request and issue-comment webhooks. A PR from a
configured automatic actor is admitted only when every commit in the PR's
head-but-not-base history has a valid signature from that actor, including
merge commits. GitHub-signed commits also qualify when their author is verified
as that actor. Other revisions require an exact maintainer comment of the form
`/ok to test <abbreviated-sha>`, where the abbreviation contains at
least seven hexadecimal characters. The controller resolves that name through
GitHub and requires the resulting full object ID to equal the pull request's
current open, non-draft head.

An admission copies the full commit object to `pull-request/<number>`. Repository
rules reserve creation, update, and deletion of that namespace for the CI Gate
App. `ci.yml` runs on pushes to those branches. AWS OIDC trusts the protected
default branch and the CI Gate App-reserved branch namespace. The GitHub-hosted
preflight in the checked-in workflow checks out its policy from the default
branch, queries the pull request again, and rejects a copied SHA that has gone
stale before provisioning. The candidate is then checked out by full SHA from
this repository on each newly provisioned, one-job AWS runner.

Admission authorizes the entire commit, including workflow definitions. Changes
to permissions, OIDC-bearing jobs, or publication steps therefore require the
same scrutiny as the code those jobs execute. The checked-in preflight is
defense in depth, not a sandbox against an admitted workflow edit.

Before provisioning any runner, the trusted workflow validates the selected
revision as an infrastructure consumer. Ordinary revisions must retain the
default branch's recorded contract. A branch named
`maintenance/infrastructure/<revision>` must come from the published
Maintenance App identity and match the deployment-published revision and stack
version. The shared validator also proves that an automatic update changes no
files or workflow content beyond exact action-pin and contract substitutions.

Pushes and scheduled runs on the protected default branch are approved and may
publish caches. The checked-in copied-PR workflow promotes only candidate
caches. A separate production promotion role trusts only the main-branch
cache-promotion workflow; the PR-capable role cannot write production ECR images.
An admitted workflow edit can request GitHub package-write permission, so
approval must account for that capability. A new pull-request head
invalidates the old approval: the controller removes or replaces the copied
branch, and both checked-in preflight checks compare it with the current PR
before any AWS runner starts.

The ReaverOS workflow receives only a narrow OIDC role. It does not receive the
Runner App key. The infrastructure controller owns JIT registration, stores
the single-use configuration in an unguessable SecureString parameter, and
derives cleanup metadata from EC2 tags. Normal workflow cleanup and a scheduled
expiry reaper both remove the registration and terminate the instance.

## Jobs and caches

The medium preparation job first asks the existing build graph whether LLVM
would be rebuilt. It defers a full LLVM rebuild to the large runner; other
toolchain work remains on the medium runner. Once a candidate image is ready,
build-dependency checks, unit tests, image construction, and the boot smoke test
remain separate jobs with independent reporting.

Per-run image tags are written to staging repositories and expire after three
days. Successful validation promotes their content-derived tag to immutable
candidate repositories for pull requests, or production repositories for the
protected branch. A separate publisher in the infrastructure repository copies
images from successful main-branch CI runs to both content tags and `latest` in
GHCR. The ReaverOS workflow does not receive package-write permission.

Promotion waits for the ECR scan-on-push result for both variants. A missing or
failed scan and any critical-severity finding block promotion; high-severity
findings remain visible as workflow warnings without preventing cache reuse.

`docker/toolchain-key` hashes tracked CMake, Docker, and toolchain inputs by
path, index mode, and content. This includes the local patch set, so a patched
tool cannot collide with its unpatched upstream version.

Run the local trust-boundary checks with:

```console
ci/aws/test-authorize
ci/aws/test-workflows
```

A breaking shared-action, stack-output, OIDC-trust, or ownership change must
increment the infrastructure contract. The recorded infrastructure revision
and every shared-action pin must identify the same deployed change.
