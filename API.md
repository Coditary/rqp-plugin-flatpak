# ReqPack Lua Plugin API Quick Reference

Short reference for wrapper authors.
Source of truth is ReqPack wiki page `Extending-Writing-Lua-Plugins` from this project.

## Recommended Workflow

If you are turning this template into real plugin, use this order:

1. Read this file once front to back.
2. Read `metadata.json`, `reqpack.lua`, `run.lua`, and `.reqpack-test/core/*.lua`.
3. Edit `metadata.json` so `name` matches your plugin id.
4. Replace all `template` placeholders with real plugin id, system name, and binary name.
5. Put package-manager existence check in `plugin.init()`.
6. Implement methods in this order:
   - `getMissingPackages`
   - `install`
   - `installLocal`
   - `remove`
   - `update`
   - `list`
   - `search`
   - `info`
   - `outdated`
7. Update `.reqpack-test/core/*.lua`.
8. Run `rqp test-plugin --plugin . --preset core` from plugin root.

For most wrappers, this repository already covers file layout, method names, and test-case format.
Open full ReqPack wiki only when a runtime detail is still unclear.

## Files You Usually Edit

- `metadata.json`: plugin id and bundle metadata
- `reqpack.lua`: bundle manifest with `apiVersion` and `depends`
- `run.lua`: main wrapper implementation
- `scripts/install.lua` and `scripts/remove.lua`: required bundle hook stubs
- `.reqpack-test/core/*.lua`: hermetic plugin tests
- `README.md`: rename example commands if needed

## Plugin Layout

Expected layout:

```text
<plugin-id>/
  metadata.json
  reqpack.lua
  run.lua
  scripts/
    install.lua
    remove.lua
  .reqpack-test/
    core/
```

Important:

- main script must expose global `plugin` table
- `metadata.json.name` is plugin id used for discovery
- wrapper logic lives in `run.lua`
- `scripts/install.lua` and `scripts/remove.lua` must exist even if they only return `true`

## Required Methods

ReqPack expects these methods on `plugin`:

```lua
function plugin.getName() end
function plugin.getVersion() end
function plugin.getRequirements() end
function plugin.getCategories() end
function plugin.getMissingPackages(packages) end
function plugin.install(context, packages) end
function plugin.installLocal(context, path) end
function plugin.remove(context, packages) end
function plugin.update(context, packages) end
function plugin.list(context) end
function plugin.search(context, prompt) end
function plugin.info(context, packageName) end
```

Useful optional methods:

```lua
function plugin.init() end
function plugin.shutdown() end
function plugin.outdated(context) end
function plugin.resolvePackage(context, package) end
function plugin.resolveProxyRequest(context, request) end
function plugin.getSecurityMetadata() end
```

Optional metadata:

```lua
plugin.fileExtensions = { ".rpm", ".deb" }
```

## Where To Put "tool exists" Checks

For most wrapper plugins, binary checks belong in `plugin.init()`.

Generic example:

```lua
function plugin.init()
  return reqpack.exec.run("command -v your-binary >/dev/null 2>&1").success
end
```

If `init()` runs shell commands, remember that `rqp test-plugin` must be able to fake those commands too.
Add matching `fakeExec` rules in your test cases when needed.

## `context` Object

ReqPack passes `context` into action methods.

### Metadata

```lua
context.plugin.id
context.plugin.dir
context.plugin.script
context.flags
context.host
context.proxy
context.repositories
```

### Logging

```lua
context.log.debug("...")
context.log.info("...")
context.log.warn("...")
context.log.error("...")
```

### Transaction helpers

```lua
context.tx.status(42)
context.tx.progress(50)
context.tx.begin_step("install packages")
context.tx.commit()
context.tx.success()
context.tx.failed("install failed")
```

### Domain events

Use these to tell ReqPack what happened:

```lua
context.events.installed(payload)
context.events.deleted(payload)
context.events.updated(payload)
context.events.listed(payload)
context.events.searched(payload)
context.events.informed(payload)
context.events.outdated(payload)
context.events.unavailable(payload)
```

### Helpers

```lua
local result = context.exec.run("your-command --flag")
local tmpDir = context.fs.get_tmp_dir()
local ok = context.net.download(url, destination)
context.artifacts.register({ type = "file", path = "/tmp/out" })
```

Global helper also exists:

```lua
local result = reqpack.exec.run("command -v your-tool >/dev/null 2>&1")
local host = reqpack.host
```

Use `context.exec.run(...)` inside action methods when possible.

## Data You Usually Return

### `getMissingPackages(packages)`

Return only packages that still need work.

Examples:

- install: package not yet installed
- remove: package currently installed
- update: package has newer version available

Lazy `return packages` works, but planning quality gets worse.

Common wrapper pattern:

```lua
function plugin.getMissingPackages(packages)
  local missing = {}
  for _, pkg in ipairs(packages or {}) do
    local installed = false -- replace with real check
    if pkg.action == "remove" then
      if installed then
        table.insert(missing, pkg)
      end
    elseif pkg.action == "update" then
      local hasUpdate = false -- replace with real check
      if hasUpdate then
        table.insert(missing, pkg)
      end
    elseif not installed then
      table.insert(missing, pkg)
    end
  end
  return missing
end
```

### `list`, `search`, `outdated`

Return array of package info tables.

Common fields:

```lua
{
  name = "curl",
  version = "8.0.1",
  latestVersion = "8.1.0",
  type = "package",
  summary = "Transfer tool",
  description = "Longer description",
  architecture = "x86_64",
}
```

### `info`

Return one package info table.

## Typical Wrapper Pattern

Thin wrappers usually do this:

1. check installed state in `getMissingPackages()`
2. build shell command
3. run command with `context.exec.run(...)`
4. emit `context.tx.*` and `context.events.*`
5. return `true` or parsed package info

Example:

```lua
function plugin.install(context, packages)
    if #packages == 0 then
        return true
    end

    context.tx.begin_step("install packages")
    local result = context.exec.run("example-pm install ...")
    if not result.success then
        context.tx.failed("install failed")
        return false
    end

    context.events.installed(packages)
    context.tx.success()
    return true
end
```

`installLocal(context, path)` is same pattern, but request uses `localPath` instead of `packages`.

## Testing

ReqPack has hermetic plugin tests.

```bash
rqp test-plugin --plugin . --preset core
rqp test-plugin --plugin . --case ./.reqpack-test/core/info.lua
```

Case files are Lua tables with:

- `request`
- `fakeExec`
- `expect`

Template already ships example cases.

### Case File Anatomy

Minimal install case:

```lua
return {
  name = "install success",
  request = {
    action = "install",
    system = "demo",
    packages = {
      { name = "delta", version = "1.0.0" }
    }
  },
  fakeExec = {
    {
      match = "demo-pm install delta",
      exitCode = 0,
      stdout = "done\n",
      stderr = "",
      success = true,
    }
  },
  expect = {
    success = true,
    commands = { "demo-pm install delta" },
    stdout = { "done\n" },
    events = { "installed", "success" },
  }
}
```

To test `installLocal(context, path)`, use:

```lua
request = {
  action = "install",
  system = "demo",
  localPath = "/tmp/demo.tgz",
}
```

### Recommended Starter Test Matrix

Template ships starter cases for:

- `install`
- `installLocal`
- `remove`
- `update`
- `list`
- `search`
- `info`
- `outdated`

If your plugin cannot support one path yet, keep method and test explicit instead of silently dropping it.

## Best Practices

- Keep wrapper thin. Let real package manager do real work.
- Emit events for visible results.
- Add `installLocal()` if ecosystem supports local artifacts.
- Add `resolvePackage()` later if exact version lookup is possible.
- Keep command parsing deterministic.
- Start with template, then replace placeholders step by step.
- Use local template files as first reference, not external repos.

## Full Docs

Read full wiki pages for details when working inside ReqPack repo:

- `ReqPack.wiki/Extending-ReqPack.md`
- `ReqPack.wiki/Extending-Writing-Lua-Plugins.md`
