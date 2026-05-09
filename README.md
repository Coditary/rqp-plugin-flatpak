# reqpack-plugin-flatpak

ReqPack wrapper plugin for Flatpak.

Plugin manages user-scope Flatpak apps and runtimes through `flatpak` CLI.

## Scope

- installs remote refs with `flatpak install --user`
- installs local `.flatpak` and `.flatpakref` artifacts
- removes and updates installed user Flatpaks
- lists installed apps and runtimes
- searches remote apps and runtimes
- shows installed package info
- reports outdated refs from configured remotes

Package identity is app ID or Flatpak ref first.
Wrapper does not do fuzzy name resolution for install/remove.

## Files

- `metadata.json`: bundle metadata and plugin id
- `reqpack.lua`: bundle manifest
- `run.lua`: Flatpak wrapper implementation
- `scripts/install.lua`: required bundle hook stub
- `scripts/remove.lua`: required bundle hook stub
- `.reqpack-test/core/*.lua`: hermetic plugin tests
- `API.md`: ReqPack Lua plugin API quick reference

## Usage Notes

- wrapper defaults to `--user`
- local install accepts `.flatpak` and `.flatpakref`
- `info()` targets installed refs only in first version
- `getMissingPackages()` checks installed and updateable refs to improve planning
- `resolvePackage()` resolves exact version and normalizes security identity as `kind.arch.branch/<app-id>`

## Running Tests

Run plugin conformance tests from repo root:

```bash
rqp test-plugin --plugin ./run.lua --preset core
```

Run one case directly:

```bash
rqp test-plugin --plugin ./run.lua --case ./.reqpack-test/core/info.lua
```

Current ReqPack runtime in CI resolves plugin directories incorrectly for this bundle layout.
Use explicit script path `run.lua` for hermetic test runs.
