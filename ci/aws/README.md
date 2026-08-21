# ReaverOS AWS CI

ReaverOS owns the build semantics and job graph for its CI. Persistent AWS
resources, runner registration credentials, GitHub policy, and the reusable
runner-control actions are owned by the `reaver-project/infrastructure`
repository.

The workflows consume the contract and revision recorded in
`infrastructure-contract-version` and `infrastructure-revision`. Every shared
action use is pinned to that full revision. ReaverOS needs these non-secret
repository variables:

- `AWS_REGION`;
- `AWS_RUNNER_STACK_NAME`; and
- `AWS_RUNNER_ROLE_ARN`.

The infrastructure deployment publishes those variables through its
infrastructure GitHub App. `AWS_CI_TRUSTED_USERS` remains ReaverOS-owned and is
a comma-separated list of additional GitHub logins whose pull requests may use
AWS automatically.

## Authorization

`ci.yml` runs as `pull_request_target` so its authorization and provisioning
logic always comes from the protected default branch. It never executes pull
request code on a GitHub-hosted runner. The selected head SHA is passed into a
reusable workflow and checked out only on a newly provisioned, one-job AWS
runner.

Pushes and scheduled runs on the protected default branch are approved.
Same-repository branches, organization members, collaborators, and explicitly
listed trusted users are approved automatically. Other external revisions need
the `ci: aws-approved` label; `authorize` removes that label on every new head
revision so approval cannot carry across a force-push or update.

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

Per-run images are written to short-lived staging repositories. A successful
validation promotes their content-derived tag either to immutable candidate
repositories for pull requests or to mutable production repositories for the
protected branch. Production images are then copied to both the content tag
and `latest` in GHCR, for both pruned and unpruned variants.

`docker/toolchain-key` hashes tracked CMake, Docker, and toolchain inputs by
path, index mode, and content. This includes the local patch set, so a patched
tool cannot collide with its unpatched upstream version.

Run the local trust-boundary checks with:

```console
ci/aws/test-authorize
ci/aws/test-workflows
```

A breaking shared-action, stack-output, OIDC-trust, or ownership change must
increment the infrastructure contract and update both the pin and expected
version here in one reviewed change.
