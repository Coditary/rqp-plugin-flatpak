# Flatpak Wrapper Design

## Goal

Turn template bundle into ReqPack wrapper for Flatpak.
Wrapper stays thin and delegates real package work to `flatpak` CLI.

Chosen scope:

- default install scope is user-only via `--user`
- plugin manages Flatpak apps and runtimes
- package identity is app ID or full Flatpak ref first
- `installLocal()` supports `.flatpak` and `.flatpakref`

## Non-Goals

- no system-wide install mode in first version
- no automatic fuzzy name resolution for install/remove/info
- no advanced remote selection heuristics when multiple remotes offer same app
- no deep metadata or permissions export beyond what Flatpak reports cheaply
- no audit-specific `resolvePackage()` in first version

## Plugin Metadata

Bundle metadata changes:

- `metadata.json.name = "flatpak"`
- bundle summary and description describe Flatpak user-scope wrapper
- `plugin.getName()` returns stable display name such as `Flatpak`
- `plugin.getCategories()` returns categories aligned with desktop package management
- `plugin.fileExtensions = { ".flatpak", ".flatpakref" }`

`plugin.init()` checks `flatpak` binary with `command -v flatpak >/dev/null 2>&1`.
If binary missing, plugin load fails cleanly.

## Command Model

All action methods use `context.exec.run(...)`.
All mutating operations use non-interactive flags to fit ReqPack automation:

- `--user`
- `--noninteractive`
- `--assumeyes`

Thin-wrapper command mapping:

- install remote package: `flatpak install --user --noninteractive --assumeyes --or-update <id-or-ref>`
- install local `.flatpakref`: `flatpak install --user --noninteractive --assumeyes --from <path>`
- install local `.flatpak`: `flatpak install --user --noninteractive --assumeyes --bundle <path>`
- remove package: `flatpak uninstall --user --noninteractive --assumeyes <id-or-ref>`
- update selected packages: `flatpak update --user --noninteractive --assumeyes <id-or-ref>...`
- update all packages: `flatpak update --user --noninteractive --assumeyes`

Command strings are built from shell-quoted values only.

## Package Identity Rules

First version treats request package `name` as canonical identifier.

Accepted forms:

- Flatpak application ID such as `org.mozilla.firefox`
- full Flatpak ref such as `app/org.mozilla.firefox/x86_64/stable`
- runtime ref when request explicitly targets runtime ID or full runtime ref

Matching rules:

- if identifier contains `/`, treat it as full ref and compare against Flatpak `ref` column
- otherwise treat it as application/runtime ID and compare against `application` field

This avoids ambiguous search-time resolution and keeps wrapper deterministic.

## Data Sources And Parsing

### Installed State

Installed refs come from:

`flatpak list --user --columns=application,ref,version,branch,arch,origin,name,description`

Parser splits tab-delimited rows.
Each row maps to one PackageInfo entry.
Type inference uses `ref` prefix:

- `app/` => `packageType = "app"`
- `runtime/` => `packageType = "runtime"`

Returned fields include:

- `name`: Flatpak application/runtime ID from `application`
- `packageId`: full ref when available
- `version`
- `installed = true`
- `status = "installed"`
- `summary`: value from display name or description fallback
- `description`
- `architecture`
- `branch` in `extraFields.branch`
- `repository` from origin
- `packageType`

### Search

Remote search uses:

`flatpak search --user --columns=application,version,branch,remotes,name,description <prompt>`

Parser reads tab-delimited rows.
Because `search` output does not include full ref or explicit app/runtime type, wrapper returns best-effort package info:

- `name`: application ID
- `version`
- `summary`: display name
- `description`
- `repository`: first remote from `remotes`
- `extraFields.branch`
- `installed = false`

Search does not try to collapse duplicate application IDs from multiple remotes.
ReqPack receives rows as Flatpak reports them.

### Info

Installed package info uses:

- `flatpak info --user --show-ref --show-origin --show-runtime --show-sdk <id-or-ref>`

Parser reads line-oriented key/value output.
Wrapper extracts when present:

- ID or ref
- origin remote
- runtime
- sdk

Because `flatpak info` primarily targets installed refs, first version follows this rule:

- if package is installed, return rich installed info
- if package is not installed or command fails, return empty table rather than guessing via remote lookup

This keeps `info()` deterministic and avoids second remote query path in first version.

### Outdated

Available updates use:

`flatpak remote-ls --user --updates --columns=application,ref,version,branch,arch,origin,name,description`

Parser is same as `list()` plus:

- `latestVersion`: remote version
- `status = "outdated"`
- `installed = true`

Exact currently installed version may not be present from this command alone.
First version may leave `version` empty in outdated entries when current version is not cheaply available.

## getMissingPackages Behavior

`getMissingPackages(packages)` improves planning by checking current state before executor runs.

Implementation strategy:

1. collect installed set from `flatpak list --user --columns=application,ref`
2. collect updateable set from `flatpak remote-ls --user --updates --columns=application,ref` when any request action is `update`
3. filter each requested package by action

Rules:

- install: keep only packages not already installed
- remove: keep only packages already installed
- update: keep only packages present in updateable set
- unknown action: pass through unchanged

Matching prefers full ref when request name contains `/`, otherwise application/runtime ID.

If helper command fails, function falls back to returning original package list so wrapper remains usable.

## Action Method Behavior

### install(context, packages)

- if package list empty, return `true`
- begin transaction step `install flatpak packages`
- run one install command per package to keep failures attributable to one item
- on first command failure: call `context.tx.failed("flatpak install failed")` and return `false`
- on success: emit `context.events.installed(packages)` and `context.tx.success()`

Using per-package install is slightly slower than one bulk command, but simpler for deterministic tests and clearer failure handling.

### installLocal(context, path)

- detect extension from path
- `.flatpakref` => `flatpak install --user --noninteractive --assumeyes --from <path>`
- `.flatpak` => `flatpak install --user --noninteractive --assumeyes --bundle <path>`
- other extension => fail with explicit message
- on success emit installed payload `{ path = path, localTarget = true }`

### remove(context, packages)

- if empty, return `true`
- begin step `remove flatpak packages`
- run one uninstall command per package
- emit `context.events.deleted(packages)` on full success

### update(context, packages)

- if request contains packages, update only those identifiers
- if request empty or nil, update all user-scope Flatpaks
- begin step `update flatpak packages`
- emit `context.events.updated(packages or {})` on success

### list(context)

- query installed refs
- return parsed PackageInfo array
- emit `context.events.listed(items)`

### search(context, prompt)

- if prompt blank, return empty array and emit `searched`
- otherwise query Flatpak search and return parsed rows
- emit `context.events.searched(items)`

### info(context, packageName)

- if package name blank, return empty table
- query installed info for exact identifier
- return one PackageInfo table on success, empty table on failure
- emit `context.events.informed(item)` even when item empty so ReqPack gets explicit result

### outdated(context)

- query updates list
- return parsed rows
- emit `context.events.outdated(items)`

## Error Handling

Wrapper should keep failures simple and visible.

Rules:

- mutating command failure => `context.tx.failed(<message>)` and `false`
- read/query failure for `list/search/outdated` => return empty array after optional warning log
- `info` failure => return empty table
- unsupported local file extension => fail with explicit message mentioning supported extensions

No retry logic in first version.

## Security Metadata

First version implements `getSecurityMetadata()` with thin-wrapper scope:

- `role = "package-manager"`
- `capabilities = { "exec" }`
- `ecosystemScopes = { "flatpak" }`
- `writeScopes = { { kind = "user-home-subpath", value = ".local/share/flatpak" } }`
- `privilegeLevel = "user"`
- `purlType = "generic"` or omitted if ReqPack expects more specific mapping later

Network scopes are omitted because wrapper delegates network behavior to Flatpak and does not call `context.net` directly.

## Tests

Template tests will be replaced with hermetic Flatpak-specific cases under `.reqpack-test/core/`.

Required cases:

- `install.lua`: installs remote package with expected command and installed event
- `install-local-flatpakref.lua` or updated local case: installs `.flatpakref` via `--from`
- `install-local-flatpak.lua` or second local case: installs `.flatpak` via `--bundle`
- `remove.lua`: uninstalls package
- `update.lua`: updates package
- `list.lua`: parses tab-delimited installed output
- `search.lua`: parses tab-delimited search output
- `info.lua`: parses line-oriented info output
- `outdated.lua`: parses update listing
- one failure case for unsupported local file extension or command failure

If `plugin.init()` is covered in test harness flow, fake command for `command -v flatpak >/dev/null 2>&1` must be added.

## Implementation Notes

Keep helpers small and local to `run.lua`:

- trim
- shell quoting
- tab-row split
- line parser for `info`
- identifier matching helper for app ID vs ref
- thin transaction/event wrappers already present in template can stay if still useful

Avoid introducing broad abstraction layers.
Single-file wrapper is appropriate for first version.

## Open Follow-Ups

Potential later improvements, intentionally out of first version scope:

- optional system scope through request flags
- `resolvePackage()` for exact refs and better audit/SBOM data
- remote info fallback for non-installed `info()`
- duplicate-result collapsing or remote preference rules
- richer metadata such as homepage, license, and runtime dependencies when Flatpak provides them cheaply
