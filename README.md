# MackySoft Actions

Small GitHub Actions for CI-only external boundaries.

This repository only keeps actions that behave as single-purpose modules:

- one action owns one external operation
- repository verification policy stays in the consuming repository
- local scripts stay the source of truth for build, test, format, package, and smoke checks
- duplicate publish policy, release note policy, and package contract checks stay in each repository

## Actions

### `nuget-trusted-publish`

Publishes one or more `.nupkg` files to NuGet.org using NuGet Trusted Publishing.

```yaml
permissions:
  contents: read
  id-token: write

steps:
  - name: Publish to NuGet.org
    uses: mackysoft/actions/nuget-trusted-publish@v1
    with:
      package-glob: artifacts/packages/*.nupkg
      nuget-user: ${{ vars.NUGET_USER }}
```

The caller job must grant `id-token: write`.

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `package-glob` | Yes | None | Glob or path for NuGet package artifacts. Matched files are pushed in sorted order. |
| `nuget-user` | Yes | None | NuGet.org account name configured for Trusted Publishing. |
| `source` | No | `https://api.nuget.org/v3/index.json` | NuGet package source URL passed to `dotnet nuget push`. |

This action only performs Trusted Publishing login and `dotnet nuget push`.
It does not decide whether publishing is required, and it does not pass
`--skip-duplicate`.

### `nuget-package-state`

Inspects or waits for NuGet package availability through the NuGet flat
container feed.

Inspect before publishing:

```yaml
- name: Inspect NuGet package state
  id: package-state
  uses: mackysoft/actions/nuget-package-state@v1
  with:
    mode: inspect
    package-version: ${{ needs.prepare-release.outputs.package_version }}
    package-ids: |
      MackySoft.Ucli
      MackySoft.Ucli.Contracts
```

Wait after publishing:

```yaml
- name: Wait for NuGet package availability
  uses: mackysoft/actions/nuget-package-state@v1
  with:
    mode: wait
    package-version: ${{ needs.prepare-release.outputs.package_version }}
    package-ids: |
      MackySoft.Ucli
      MackySoft.Ucli.Contracts
    max-attempts: 30
    interval-seconds: 10
```

Inputs:

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `mode` | No | `inspect` | Operation mode. Use `inspect` to classify publication state, or `wait` to block until every package exists. |
| `package-version` | Yes | None | NuGet package version to inspect. |
| `package-ids` | Yes | None | Newline-separated NuGet package IDs. |
| `flat-container-base-url` | No | `https://api.nuget.org/v3-flatcontainer` | NuGet flat container base URL. |
| `max-attempts` | No | `30` | Maximum number of checks in `wait` mode. |
| `interval-seconds` | No | `10` | Seconds to wait between checks in `wait` mode. |

Outputs:

| Name | Description |
| --- | --- |
| `all-packages-exist` | `true` when every requested package exists. |
| `publish-required` | `true` when none of the requested packages exist and publishing should proceed. |
| `existing-package-ids-json` | JSON array of package IDs that already exist. |
| `missing-package-ids-json` | JSON array of package IDs that do not exist. |

In `inspect` mode, partial publication state fails closed. That means all
packages existing is safe to skip, all packages missing is safe to publish, and
mixed existing/missing state fails.

## Non-Goals

These responsibilities intentionally stay out of this repository:

- .NET SDK setup, restore, build, test, and format
- repository verification policy
- package version resolution
- release source validation, until release flows converge enough to justify a module
- package content or command contract smoke tests
- GitHub Release asset policy
- path-based verification scope detection

## Validation

Run the repository validation locally:

```bash
bash tests/run.sh
```
