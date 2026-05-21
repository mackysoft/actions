# MackySoft Actions

Reusable GitHub Actions for MackySoft repositories.

This repository intentionally provides small CI primitives. Product-specific
verification policy, package layout checks, path classification, and release
semantics stay in each consuming repository.

## Actions

### `setup-dotnet-cache`

Sets up the .NET SDK, restores the NuGet package cache, optionally pins
`global.json`, and optionally runs a restore command.

```yaml
- uses: mackysoft/actions/setup-dotnet-cache@v1
  with:
    dotnet-version: 10.0.x
    dotnet-quality: ga
    cache-key-files: |
      *.slnx
      **/*.csproj
    pin-global-json: false
    restore-command: dotnet restore Ucli.slnx
```

`checkout` is intentionally not included. Call `actions/checkout` in the
workflow before this action.

### `dotnet-format`

Runs `dotnet format whitespace` and `dotnet format style` in `format` or
`verify` mode.

```yaml
- uses: mackysoft/actions/dotnet-format@v1
  with:
    solution: Ucli.slnx
    mode: verify
    diagnostics: |
      IDE0005
      IDE0011
      IDE0036
      IDE0048
      IDE0049
      IDE0062
      IDE1006
```

Diagnostics are repository policy and should be passed by the caller.

### `dotnet-test`

Runs `dotnet test` with predictable argument handling. `test-arguments` is
parsed as one argument per line.

```yaml
- uses: mackysoft/actions/dotnet-test@v1
  with:
    target: Ucli.slnx
    configuration: Release
    restore: false
    no-build: true
    test-arguments: |
      --logger
      trx;LogFileName=linux.trx
      --results-directory
      artifacts/test-results/linux
```

### `resolve-release-version`

Resolves a package version and release tag from a tag push or
`workflow_dispatch` input.

```yaml
- id: version
  uses: mackysoft/actions/resolve-release-version@v1
  with:
    event-name: ${{ github.event_name }}
    ref-name: ${{ github.ref_name }}
    dispatch-tag: ${{ inputs.release_tag }}
```

Outputs:

- `package-version`
- `tag-name`

### `validate-release-source`

Validates that a release tag points to the expected source and that the source
is reachable from the default branch.

```yaml
- id: source
  uses: mackysoft/actions/validate-release-source@v1
  with:
    tag-name: ${{ steps.version.outputs.tag-name }}
    default-branch: ${{ github.event.repository.default_branch }}
    require-ancestor: true
```

Output:

- `release-sha`

### `publish-nuget-package`

Publishes one or more `.nupkg` files to NuGet.org using Trusted Publishing.

```yaml
- uses: mackysoft/actions/publish-nuget-package@v1
  with:
    package-glob: artifacts/packages/*.nupkg
    nuget-user: ${{ vars.NUGET_USER }}
```

The caller job must grant `id-token: write`.

### `inspect-nuget-package-state`

Checks whether a set of package IDs already exists for one version on a NuGet
flat container feed.

```yaml
- id: nuget-state
  uses: mackysoft/actions/inspect-nuget-package-state@v1
  with:
    version: ${{ steps.version.outputs.package-version }}
    package-ids: |
      MackySoft.Ucli
      MackySoft.Ucli.Contracts
      MackySoft.Ucli.Infrastructure
```

Outputs:

- `all-packages-exist`
- `publish-required`
- `existing-package-ids`
- `missing-package-ids`

When some packages exist and others are missing, the action fails by default.

### `wait-nuget-packages`

Waits until package artifacts are available from a NuGet flat container feed.

```yaml
- uses: mackysoft/actions/wait-nuget-packages@v1
  with:
    version: ${{ steps.version.outputs.package-version }}
    package-ids: |
      MackySoft.Ucli
      MackySoft.Ucli.Contracts
    attempts: 30
    interval-seconds: 10
```

Use this after `publish-nuget-package` and before NuGet.org smoke tests or
release mirroring.

### `mirror-github-release-assets`

Creates or updates a GitHub Release and uploads matched assets.

```yaml
- uses: mackysoft/actions/mirror-github-release-assets@v1
  with:
    github-token: ${{ github.token }}
    repository: ${{ github.repository }}
    tag-name: ${{ github.ref_name }}
    title: ${{ github.ref_name }}
    notes: ""
    asset-glob: artifacts/packages/*.nupkg
```

The caller job must grant `contents: write`.

### `dotnet-tool-smoke-test`

Installs a .NET tool package in an isolated environment and verifies the
installed command can run basic version and help checks.

```yaml
- uses: mackysoft/actions/dotnet-tool-smoke-test@v1
  with:
    package-id: MackySoft.Dotmet
    package-version: ${{ steps.version.outputs.package-version }}
    command-name: dotmet
    source: artifacts/packages
    help-contains: Commands:
```

This action only checks that the package works as a .NET tool. Product-specific
checks such as schema files, bundled skills, or command contracts should remain
in the consuming repository.

## Release flow

A typical NuGet release workflow uses these primitives in this order:

```text
resolve-release-version
validate-release-source
inspect-nuget-package-state
publish-nuget-package
wait-nuget-packages
dotnet-tool-smoke-test
mirror-github-release-assets
```

## Validation

Run the repository validation locally:

```bash
bash tests/run.sh
```
