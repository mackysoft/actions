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

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `dotnet-version` | Yes | None | .NET SDK version passed to `actions/setup-dotnet@v5`. |
| `dotnet-quality` | No | `""` | Optional .NET SDK quality passed to `actions/setup-dotnet@v5`. |
| `cache` | No | `true` | Whether to restore and save `~/.nuget/packages` with `actions/cache@v5`. |
| `cache-key-files` | No | `*.sln`, `*.slnx`, `**/*.csproj`, `**/*.fsproj`, `**/*.vbproj`, `Directory.Build.props`, `Directory.Build.targets`, `Directory.Packages.props`, `NuGet.config`, `global.json` | Newline-separated git pathspecs used to compute the NuGet cache key. |
| `cache-key-prefix` | No | `nuget` | Prefix used after the runner OS in the generated cache key. |
| `pin-global-json` | No | `false` | Whether to overwrite `global.json` with the SDK version installed by `actions/setup-dotnet`. |
| `restore-command` | No | `""` | Optional restore command run after setup and cache restore. |

Outputs:

| Name | Description |
| --- | --- |
| `cache-key` | Generated NuGet cache key. |

### `dotnet-format`

Runs `dotnet format whitespace` and `dotnet format style` in `format` or
`verify` mode.

```yaml
- uses: mackysoft/actions/dotnet-format@v1
  with:
    solution: Ucli.slnx
    mode: verify
```

Analyzer severities and formatting policy come from the consuming repository,
including `.editorconfig`.

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `solution` | Yes | None | Solution or project path passed to `dotnet format`. |
| `mode` | No | `verify` | Either `format` or `verify`. |
| `restore` | No | `false` | Whether to run `dotnet restore` before formatting. |
| `include` | No | `""` | Optional newline-separated paths passed to `dotnet format --include`. |

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

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `target` | No | `""` | Optional solution, project, or directory passed to `dotnet test`. |
| `configuration` | No | `Release` | Build configuration passed to `dotnet test`. |
| `restore` | No | `false` | Whether `dotnet test` should restore packages. |
| `no-build` | No | `false` | Whether to pass `--no-build` to `dotnet test`. |
| `test-arguments` | No | `""` | Optional newline-separated arguments appended to `dotnet test`. |

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

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `event-name` | Yes | None | GitHub event name. |
| `ref-name` | No | `""` | GitHub ref name used for tag push releases. |
| `dispatch-tag` | No | `""` | Release tag input used for `workflow_dispatch` releases. |
| `allow-prerelease` | No | `false` | Whether prerelease SemVer tags are accepted. |

Outputs:

| Name | Description |
| --- | --- |
| `package-version` | Resolved package version. |
| `tag-name` | Resolved release tag name. |

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

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `tag-name` | Yes | None | Release tag name. |
| `release-sha` | No | `""` | Optional expected release commit SHA. |
| `default-branch` | Yes | None | Default branch name used for reachability validation. |
| `remote` | No | `origin` | Git remote name. |
| `require-tag` | No | `true` | Whether the release tag must exist and be fetched. |
| `require-head-match` | No | `false` | Whether the current `HEAD` must match the resolved release SHA. |
| `require-ancestor` | No | `true` | Whether the resolved release SHA must be reachable from the default branch. |

Output:

| Name | Description |
| --- | --- |
| `release-sha` | Resolved release commit SHA. |

### `publish-nuget-package`

Publishes one or more `.nupkg` files to NuGet.org using Trusted Publishing.

```yaml
- uses: mackysoft/actions/publish-nuget-package@v1
  with:
    package-glob: artifacts/packages/*.nupkg
    nuget-user: ${{ vars.NUGET_USER }}
```

The caller job must grant `id-token: write`.

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `package-glob` | Yes | None | Glob or path for NuGet package artifacts. |
| `nuget-user` | Yes | None | NuGet.org account name configured for Trusted Publishing. |
| `source` | No | `https://api.nuget.org/v3/index.json` | NuGet package source URL. |
| `skip-duplicate` | No | `true` | Whether to pass `--skip-duplicate` to `dotnet nuget push`. |

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

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `version` | Yes | None | Package version to inspect. |
| `package-ids` | Yes | None | Newline-separated package IDs. |
| `source-base-url` | No | `https://api.nuget.org/v3-flatcontainer` | NuGet flat container base URL. |
| `fail-on-partial` | No | `true` | Whether to fail when some packages exist and others are missing. |

Outputs:

| Name | Description |
| --- | --- |
| `all-packages-exist` | `true` when every package exists. |
| `publish-required` | `true` when packages should be published. |
| `existing-package-ids` | Newline-separated existing package IDs. |
| `missing-package-ids` | Newline-separated missing package IDs. |

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

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `version` | Yes | None | Package version to wait for. |
| `package-ids` | Yes | None | Newline-separated package IDs. |
| `attempts` | No | `30` | Number of availability attempts. |
| `interval-seconds` | No | `10` | Seconds to sleep between attempts. |
| `source-base-url` | No | `https://api.nuget.org/v3-flatcontainer` | NuGet flat container base URL. |

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

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `github-token` | Yes | None | GitHub token used by `gh`. |
| `repository` | Yes | None | Repository in `owner/name` form. |
| `tag-name` | Yes | None | Release tag name. |
| `asset-glob` | Yes | None | Glob or path for assets to upload. |
| `title` | Yes | None | Release title. |
| `notes` | No | `""` | Release notes. |
| `clobber` | No | `true` | Whether to overwrite existing assets. |
| `verify-tag` | No | `true` | Whether `gh release create` should verify the tag. |
| `update-existing-release` | No | `true` | Whether to update title and notes when the release already exists. |

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

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `package-id` | Yes | None | NuGet package ID. |
| `package-version` | Yes | None | NuGet package version. |
| `command-name` | Yes | None | Installed command name. |
| `source` | No | `https://api.nuget.org/v3/index.json` | NuGet feed URL or local package directory. |
| `retry-timeout-seconds` | No | `600` | Maximum install retry duration. |
| `retry-interval-seconds` | No | `30` | Seconds to sleep between install attempts. |
| `assert-version` | No | `true` | Whether to assert command version output equals `package-version`. |
| `version-argument` | No | `--version` | Command argument used for version assertion. |
| `assert-help` | No | `true` | Whether to run the command help check. |
| `help-argument` | No | `--help` | Command argument used for help assertion. |
| `help-contains` | No | `""` | Optional text expected in help output. |

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
