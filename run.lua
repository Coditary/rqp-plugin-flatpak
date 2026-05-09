plugin = {}

local PLUGIN_NAME = "Flatpak"
local PLUGIN_VERSION = "0.1.0"
local REQUIRED_BINARY = "flatpak"
local READ_FLAGS = "--user"
local WRITE_FLAGS = "--user --noninteractive --assumeyes"
local LIST_COLUMNS = "application,ref,version,branch,arch,origin,name,description"
local SEARCH_COLUMNS = "application,version,branch,remotes,name,description"
local SIMPLE_COLUMNS = "application,ref"

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function is_blank(value)
    return trim(value) == ""
end

local function non_empty(value)
    local cleaned = trim(value)
    if cleaned == "" then
        return nil
    end
    return cleaned
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function lower(value)
    return tostring(value or ""):lower()
end

local function split_lines(value)
    local lines = {}
    for line in tostring(value or ""):gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

local function split_tsv(line)
    local fields = {}
    for field in (tostring(line or "") .. "\t"):gmatch("(.-)\t") do
        table.insert(fields, field)
    end
    return fields
end

local function split_words(line)
    local fields = {}
    for field in tostring(line or ""):gmatch("%S+") do
        table.insert(fields, field)
    end
    return fields
end

local function emit_event(context, name, payload)
    if context == nil or context.events == nil then
        return
    end

    local fn = context.events[name]
    if type(fn) == "function" then
        fn(payload)
    end
end

local function begin_step(context, label)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.begin_step
    if type(fn) == "function" then
        fn(label)
    end
end

local function tx_success(context)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.success
    if type(fn) == "function" then
        fn()
    end
end

local function tx_failed(context, message)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.failed
    if type(fn) == "function" then
        fn(message)
    end
end

local function log_warn(context, message)
    if context == nil or context.log == nil then
        return
    end

    local fn = context.log.warn
    if type(fn) == "function" then
        fn(message)
    end
end

local function command_exists(binary)
    return reqpack.exec.run("command -v " .. binary .. " >/dev/null 2>&1").success
end

local function normalize_ref(value)
    local cleaned = trim(value)
    if cleaned:match("^app/") or cleaned:match("^runtime/") then
        return cleaned:gsub("^[^/]+/", "", 1)
    end
    return cleaned
end

local function command_target(value)
    return normalize_ref(value)
end

local function is_ref_identifier(value)
    return trim(value):find("/", 1, true) ~= nil
end

local function parse_ref(ref)
    local cleaned = trim(ref)
    local parts = {}
    for part in cleaned:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    local kind = nil
    local name = nil
    local arch = nil
    local branch = nil

    if parts[1] == "app" or parts[1] == "runtime" then
        kind = parts[1]
        name = parts[2]
        arch = parts[3]
        branch = parts[4]
    else
        name = parts[1]
        arch = parts[2]
        branch = parts[3]
    end

    return {
        kind = kind,
        name = name,
        arch = arch,
        branch = branch,
    }
end

local function first_remote(remotes)
    local cleaned = trim(remotes)
    if cleaned == "" then
        return nil
    end

    local first = cleaned:match("^[^,]+")
    return non_empty(first)
end

local function maybe_set(target, key, value)
    if value ~= nil then
        target[key] = value
    end
end

local function canonical_package_id(item)
    if item == nil then
        return nil
    end

    local package_id = non_empty(item.packageId)
    if package_id == nil then
        return nil
    end
    if package_id:match("^app/") or package_id:match("^runtime/") then
        return package_id
    end

    local package_type = non_empty(item.packageType)
    if package_type == "app" or package_type == "runtime" then
        return package_type .. "/" .. package_id
    end
    return package_id
end

local function item_branch(item)
    if item == nil or type(item.extraFields) ~= "table" then
        return nil
    end
    return non_empty(item.extraFields.branch)
end

local function copy_extra_fields(extra_fields)
    if type(extra_fields) ~= "table" then
        return {}
    end

    local copy = {}
    for key, value in pairs(extra_fields) do
        copy[key] = value
    end
    return copy
end

local function add_purl_fields(extra, item)
    if extra == nil then
        extra = {}
    end
    if item == nil then
        return extra
    end

    local package_id = canonical_package_id(item)
    local parsed = parse_ref(package_id or "")
    local package_type = non_empty(item.packageType) or non_empty(parsed.kind)
    local architecture = non_empty(item.architecture) or non_empty(parsed.arch)
    local branch = item_branch(item) or non_empty(parsed.branch)
    local package_name = non_empty(item.name) or non_empty(parsed.name)

    maybe_set(extra, "purl.name", package_name)
    maybe_set(extra, "purl.namespace", package_type)
    maybe_set(extra, "purl.qualifier.arch", architecture)
    maybe_set(extra, "purl.qualifier.branch", branch)
    return extra
end

local function enrich_item_with_purl_fields(item)
    if item == nil then
        return item
    end

    local extra = add_purl_fields(copy_extra_fields(item.extraFields), item)
    if next(extra) == nil then
        item.extraFields = nil
    else
        item.extraFields = extra
    end
    return item
end

local function make_extra_fields(branch, runtime_ref, sdk_ref)
    local extra = {}
    maybe_set(extra, "branch", non_empty(branch))
    maybe_set(extra, "runtime", non_empty(runtime_ref))
    maybe_set(extra, "sdk", non_empty(sdk_ref))
    if next(extra) == nil then
        return nil
    end
    return extra
end

local function security_package_name_for_item(item)
    if item == nil then
        return nil
    end

    local name = non_empty(item.name)
    if name == nil then
        return canonical_package_id(item)
    end

    local package_type = non_empty(item.packageType)
    local architecture = non_empty(item.architecture)
    local branch = item_branch(item)
    if package_type == nil or architecture == nil or branch == nil then
        local parsed = parse_ref(canonical_package_id(item) or "")
        package_type = package_type or non_empty(parsed.kind)
        architecture = architecture or non_empty(parsed.arch)
        branch = branch or non_empty(parsed.branch)
    end

    if package_type == nil or architecture == nil or branch == nil then
        return name
    end

    return package_type .. "." .. architecture .. "." .. branch .. "/" .. name
end

local function resolved_version_for_item(item, original_package)
    local version = non_empty(item and item.version) or non_empty(item and item.latestVersion)
    if version ~= nil then
        return version
    end

    if item ~= nil and non_empty(item.packageType) == "runtime" then
        version = item_branch(item)
        if version ~= nil then
            return version
        end

        local parsed = parse_ref(canonical_package_id(item) or "")
        version = non_empty(parsed.branch)
        if version ~= nil then
            return version
        end
    end

    return non_empty(original_package and original_package.version)
end

local function identifier_matches_item(identifier, item)
    local cleaned = trim(identifier)
    if cleaned == "" or item == nil then
        return false
    end

    local item_name = trim(item.name)
    local package_id = trim(canonical_package_id(item) or item.packageId)
    if is_ref_identifier(cleaned) then
        local normalized = normalize_ref(cleaned)
        return normalized ~= "" and (
            normalize_ref(package_id) == normalized or
            item_name == normalized
        )
    end

    return item_name == cleaned or package_id == cleaned or normalize_ref(package_id) == cleaned
end

local function find_item_by_identifier(items, identifier)
    for _, item in ipairs(items or {}) do
        if identifier_matches_item(identifier, item) then
            return item
        end
    end
    return nil
end

local function build_resolved_package(original_package, item)
    local version = resolved_version_for_item(item, original_package)
    if version == nil then
        return nil
    end

    local resolved = {
        action = original_package.action,
        system = original_package.system,
        name = security_package_name_for_item(item) or canonical_package_id(item) or non_empty(item.name) or trim(original_package.name),
        version = version,
        extraFields = add_purl_fields(copy_extra_fields(item and item.extraFields), item),
    }

    if non_empty(original_package.sourcePath) ~= nil then
        resolved.sourcePath = original_package.sourcePath
    end
    if original_package.localTarget == true then
        resolved.localTarget = true
    end
    if original_package.flags ~= nil and #original_package.flags > 0 then
        resolved.flags = original_package.flags
    end

    return resolved
end

local function parse_collection_output(stdout, package_type, installed, status, latest_version)
    local items = {}

    for _, line in ipairs(split_lines(stdout)) do
        local fields = split_tsv(line)
        local application = non_empty(fields[1])
        if application ~= nil then
            local display_name = non_empty(fields[7])
            local description = non_empty(fields[8])
            local item = {
                name = application,
                packageId = non_empty(fields[2]),
                type = "package",
                installed = installed,
                status = status,
                packageType = package_type,
                summary = display_name or description,
                description = description,
                architecture = non_empty(fields[5]),
                repository = non_empty(fields[6]),
                extraFields = make_extra_fields(fields[4], nil, nil),
            }

            local version = non_empty(fields[3])
            maybe_set(item, "version", version)
            maybe_set(item, "latestVersion", latest_version and version or nil)
            table.insert(items, enrich_item_with_purl_fields(item))
        end
    end

    return items
end

local function parse_search_output(stdout)
    local items = {}

    for _, line in ipairs(split_lines(stdout)) do
        local fields = split_tsv(line)
        local application = non_empty(fields[1])
        if application ~= nil then
            local display_name = non_empty(fields[5])
            local description = non_empty(fields[6])
            local item = {
                name = application,
                type = "package",
                installed = false,
                summary = display_name or description,
                description = description,
                repository = first_remote(fields[4]),
                extraFields = make_extra_fields(fields[3], nil, nil),
            }

            maybe_set(item, "version", non_empty(fields[2]))
            table.insert(items, enrich_item_with_purl_fields(item))
        end
    end

    return items
end

local function parse_info_output(package_name, stdout)
    local first_line = split_lines(stdout)[1]
    if first_line == nil then
        return {}
    end

    local fields = split_words(first_line)
    local ref = non_empty(fields[1])
    if ref == nil then
        return {}
    end

    local parsed = parse_ref(ref)
    local package_type = parsed.kind
    local item = {
        name = non_empty(parsed.name) or non_empty(package_name),
        packageId = ref,
        type = "package",
        installed = true,
        status = "installed",
        packageType = package_type,
        architecture = non_empty(parsed.arch),
        repository = non_empty(fields[2]),
        extraFields = make_extra_fields(parsed.branch, fields[3], fields[4]),
    }

    return enrich_item_with_purl_fields(item)
end

local function collect_simple_set(command)
    local result = reqpack.exec.run(command)
    if not result.success then
        return nil
    end

    local seen = {}
    for _, line in ipairs(split_lines(result.stdout)) do
        local fields = split_tsv(line)
        local application = non_empty(fields[1])
        local ref = non_empty(fields[2])
        if application ~= nil then
            seen[application] = true
        end
        if ref ~= nil then
            seen[normalize_ref(ref)] = true
        end
    end

    return seen
end

local function package_action(pkg)
    local action = non_empty(pkg and pkg.action)
    if action ~= nil then
        return action
    end
    return "install"
end

local function package_identifier(pkg)
    return trim(pkg and pkg.name)
end

local function query_items(context, command, parser)
    local result = context.exec.run(command)
    if not result.success then
        return nil, result
    end
    return parser(result.stdout or ""), result
end

local function query_list_items(context)
    local items = {}
    local app_items = query_items(
        context,
        "flatpak list " .. READ_FLAGS .. " --app --columns=" .. LIST_COLUMNS,
        function(stdout)
            return parse_collection_output(stdout, "app", true, "installed", false)
        end
    )
    if app_items ~= nil then
        for _, item in ipairs(app_items) do
            table.insert(items, item)
        end
    end

    local runtime_items = query_items(
        context,
        "flatpak list " .. READ_FLAGS .. " --runtime --columns=" .. LIST_COLUMNS,
        function(stdout)
            return parse_collection_output(stdout, "runtime", true, "installed", false)
        end
    )
    if runtime_items ~= nil then
        for _, item in ipairs(runtime_items) do
            table.insert(items, item)
        end
    end

    return items
end

local function query_remote_items(context)
    local items = {}
    local app_items = query_items(
        context,
        "flatpak remote-ls " .. READ_FLAGS .. " --app --columns=" .. LIST_COLUMNS,
        function(stdout)
            return parse_collection_output(stdout, "app", false, nil, false)
        end
    )
    if app_items ~= nil then
        for _, item in ipairs(app_items) do
            table.insert(items, item)
        end
    end

    local runtime_items = query_items(
        context,
        "flatpak remote-ls " .. READ_FLAGS .. " --runtime --columns=" .. LIST_COLUMNS,
        function(stdout)
            return parse_collection_output(stdout, "runtime", false, nil, false)
        end
    )
    if runtime_items ~= nil then
        for _, item in ipairs(runtime_items) do
            table.insert(items, item)
        end
    end

    return items
end

local function query_outdated_items(context)
    local items = {}
    local app_items = query_items(
        context,
        "flatpak remote-ls " .. READ_FLAGS .. " --updates --app --columns=" .. LIST_COLUMNS,
        function(stdout)
            return parse_collection_output(stdout, "app", true, "outdated", true)
        end
    )
    if app_items ~= nil then
        for _, item in ipairs(app_items) do
            table.insert(items, item)
        end
    end

    local runtime_items = query_items(
        context,
        "flatpak remote-ls " .. READ_FLAGS .. " --updates --runtime --columns=" .. LIST_COLUMNS,
        function(stdout)
            return parse_collection_output(stdout, "runtime", true, "outdated", true)
        end
    )
    if runtime_items ~= nil then
        for _, item in ipairs(runtime_items) do
            table.insert(items, item)
        end
    end

    return items
end

local function run_package_commands(context, step_label, packages, command_builder, success_event)
    if packages == nil or #packages == 0 then
        return true
    end

    begin_step(context, step_label)
    for _, pkg in ipairs(packages) do
        local identifier = package_identifier(pkg)
        if identifier == "" then
            tx_failed(context, "flatpak package identifier missing")
            return false
        end

        local result = context.exec.run(command_builder(identifier))
        if not result.success then
            tx_failed(context, "flatpak command failed")
            return false
        end
    end

    emit_event(context, success_event, packages)
    tx_success(context)
    return true
end

plugin.fileExtensions = { ".flatpak", ".flatpakref" }

function plugin.getName()
    return PLUGIN_NAME
end

function plugin.getVersion()
    return PLUGIN_VERSION
end

function plugin.getRequirements()
    return {}
end

function plugin.getCategories()
    return { "Desktop", "Package Manager" }
end

function plugin.getMissingPackages(packages)
    if packages == nil or #packages == 0 then
        return {}
    end

    local installed = collect_simple_set("flatpak list " .. READ_FLAGS .. " --columns=" .. SIMPLE_COLUMNS)
    if installed == nil then
        return packages
    end

    local needs_update = false
    for _, pkg in ipairs(packages) do
        if package_action(pkg) == "update" then
            needs_update = true
            break
        end
    end

    local updateable = nil
    if needs_update then
        updateable = collect_simple_set("flatpak remote-ls " .. READ_FLAGS .. " --updates --columns=" .. SIMPLE_COLUMNS)
        if updateable == nil then
            return packages
        end
    end

    local filtered = {}
    for _, pkg in ipairs(packages) do
        local identifier = package_identifier(pkg)
        local key = is_ref_identifier(identifier) and normalize_ref(identifier) or identifier
        local action = package_action(pkg)
        local is_installed = installed[key] == true
        local has_update = updateable ~= nil and updateable[key] == true

        if action == "remove" then
            if is_installed then
                table.insert(filtered, pkg)
            end
        elseif action == "update" then
            if has_update then
                table.insert(filtered, pkg)
            end
        elseif not is_installed then
            table.insert(filtered, pkg)
        end
    end

    return filtered
end

function plugin.install(context, packages)
    return run_package_commands(
        context,
        "install flatpak packages",
        packages,
        function(identifier)
            return "flatpak install " .. WRITE_FLAGS .. " --or-update " .. shell_quote(command_target(identifier))
        end,
        "installed"
    )
end

function plugin.installLocal(context, path)
    local cleaned_path = trim(path)
    begin_step(context, "install local flatpak artifact")

    local command = nil
    if lower(cleaned_path):match("%.flatpakref$") then
        command = "flatpak install " .. WRITE_FLAGS .. " --from " .. shell_quote(cleaned_path)
    elseif lower(cleaned_path):match("%.flatpak$") then
        command = "flatpak install " .. WRITE_FLAGS .. " --bundle " .. shell_quote(cleaned_path)
    else
        tx_failed(context, "unsupported local Flatpak artifact type")
        return false
    end

    local result = context.exec.run(command)
    if not result.success then
        tx_failed(context, "flatpak local install failed")
        return false
    end

    emit_event(context, "installed", { path = cleaned_path, localTarget = true })
    tx_success(context)
    return true
end

function plugin.remove(context, packages)
    return run_package_commands(
        context,
        "remove flatpak packages",
        packages,
        function(identifier)
            return "flatpak uninstall " .. WRITE_FLAGS .. " " .. shell_quote(command_target(identifier))
        end,
        "deleted"
    )
end

function plugin.update(context, packages)
    if packages == nil or #packages == 0 then
        begin_step(context, "update flatpak packages")
        local result = context.exec.run("flatpak update " .. WRITE_FLAGS)
        if not result.success then
            tx_failed(context, "flatpak update failed")
            return false
        end

        emit_event(context, "updated", {})
        tx_success(context)
        return true
    end

    return run_package_commands(
        context,
        "update flatpak packages",
        packages,
        function(identifier)
            return "flatpak update " .. WRITE_FLAGS .. " " .. shell_quote(command_target(identifier))
        end,
        "updated"
    )
end

function plugin.list(context)
    local items = query_list_items(context)
    if #items == 0 then
        log_warn(context, "flatpak list returned no user packages or query failed")
    end
    emit_event(context, "listed", items)
    return items
end

function plugin.outdated(context)
    local items = query_outdated_items(context)
    if #items == 0 then
        log_warn(context, "flatpak remote-ls returned no updates or query failed")
    end
    emit_event(context, "outdated", items)
    return items
end

function plugin.search(context, prompt)
    if is_blank(prompt) then
        local empty = {}
        emit_event(context, "searched", empty)
        return empty
    end

    local items, result = query_items(
        context,
        "flatpak search " .. READ_FLAGS .. " --columns=" .. SEARCH_COLUMNS .. " " .. shell_quote(trim(prompt)),
        parse_search_output
    )

    if items == nil then
        log_warn(context, "flatpak search failed")
        items = {}
    elseif result ~= nil and not result.success then
        items = {}
    end

    emit_event(context, "searched", items)
    return items
end

function plugin.info(context, name)
    if is_blank(name) then
        local empty = {}
        emit_event(context, "informed", empty)
        return empty
    end

    local result = context.exec.run(
        "flatpak info " .. READ_FLAGS .. " --show-ref --show-origin --show-runtime --show-sdk " .. shell_quote(command_target(name))
    )
    if not result.success then
        local empty = {}
        emit_event(context, "informed", empty)
        return empty
    end

    local item = parse_info_output(name, result.stdout)
    emit_event(context, "informed", item)
    return item
end

function plugin.resolvePackage(context, package)
    if package == nil or package.localTarget == true or non_empty(package.sourcePath) ~= nil then
        return nil
    end

    local identifier = package_identifier(package)
    if identifier == "" then
        return nil
    end

    local installed_item = find_item_by_identifier(query_list_items(context), identifier)
    if installed_item ~= nil then
        return build_resolved_package(package, installed_item)
    end

    local remote_item = find_item_by_identifier(query_remote_items(context), identifier)
    if remote_item ~= nil then
        return build_resolved_package(package, remote_item)
    end

    return nil
end

function plugin.init()
    return command_exists(REQUIRED_BINARY)
end

function plugin.shutdown()
    return true
end

function plugin.getSecurityMetadata()
    return {
        role = "package-manager",
        capabilities = { "exec" },
        ecosystemScopes = { "flatpak" },
        writeScopes = {
            { kind = "user-home-subpath", value = ".local/share/flatpak" },
        },
        privilegeLevel = "user",
        osvEcosystem = "Generic",
        purlType = "generic",
        versionComparatorProfile = "lexicographic",
    }
end

return plugin
