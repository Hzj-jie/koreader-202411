local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")

ffi.cdef[[
    int getpid(void);
]]

local parent_pid = ffi.C.getpid()
local original_os_exit = os.exit
local exit_code = 0

os.exit = function(code, close)
    local current_pid = ffi.C.getpid()
    if current_pid ~= parent_pid then
        -- We are inside a child process spawned via fork (e.g. util.runInSubProcess).
        -- We must exit immediately using the original os.exit to prevent the child
        -- from returning and leaking into the parent's test execution flow.
        original_os_exit(code or 0, false)
    else
        -- Parent process: Intercept Busted's exit call, record the exit code, and return.
        -- Busted will finish its execution flow and return to our script.
        exit_code = code or 0
    end
end

-- 1. Configure relative module search paths directly in Lua to avoid global env dependencies
package.path = "./luacov/?.lua;./luacov/?/init.lua;./base/spec/unit/?.lua;./spec/unit/?.lua;./?.lua;./common/?.lua;./frontend/?.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;" .. package.path
package.cpath = "./?.so;./common/?.so;./libs/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;;"

local test_env = require("test_helper")

-- WORKER PROCESS EXECUTION MODE
if os.getenv("KO_TEST_WORKER") == "1" then
    local test_file = arg[1]
    if test_file then
        local plugin = test_file:match("^plugins/([%w%.%-_]+)/")
        if plugin then
            package.path = string.format("./plugins/%s/?.lua;%s", plugin, package.path)
        end

        local is_settings_test = test_file:match("docsettings_spec%.lua$") or test_file:match("named_settings_spec%.lua$")
        if not is_settings_test then
            local ok, named_settings = pcall(require, "named_settings")
            if ok then
                named_settings.document_metadata_folder = function()
                    return "dir"
                end
            end

            local intercepting_docsettings = false
            table.insert(package.loaders, 1, function(modname)
                if intercepting_docsettings or modname ~= "docsettings" then
                    return nil
                end
                intercepting_docsettings = true
                local s_ok, res = pcall(require, modname)
                intercepting_docsettings = false
                if s_ok and type(res) == "table" and res.getSidecarDir then
                    local orig_getSidecarDir = res.getSidecarDir
                    res.getSidecarDir = function(self, doc_path, force_location)
                        local worker_dir = os.getenv("XDG_CONFIG_HOME") or os.getenv("TMPDIR")
                        if (force_location == nil or force_location == "doc") and worker_dir and type(doc_path) == "string" then
                            local test_subpath = doc_path:match("spec/[%w/]*unit/data/(.+)")
                                or doc_path:match("spec/[^/]+/data/(.+)")
                                or doc_path:match("base/[^/]+/data/(.+)")
                                or doc_path:match("[%/]test/(.+)")
                                or doc_path:match("^test/(.+)")
                            if test_subpath then
                                local sdr_parent = worker_dir .. "/sdr"
                                local base_name = test_subpath:match("(.*)%.") or test_subpath
                                local sdr_dir = sdr_parent .. "/" .. base_name .. ".sdr"
                                local u_ok, util = pcall(require, "util")
                                if u_ok and util and util.makePath then
                                    util.makePath(sdr_dir)
                                else
                                    local l_ok, lfs_mod = pcall(require, "libs/libkoreader-lfs")
                                    if l_ok and lfs_mod and lfs_mod.mkdir then
                                        lfs_mod.mkdir(sdr_parent)
                                    end
                                end
                                return sdr_dir
                            end
                        end
                        return orig_getSidecarDir(self, doc_path, force_location)
                    end
                end
                return function() return res end
            end)
        end
    end

    pcall(function()
        local runner = require("luacov.runner")
        if runner and runner.debug_hook then
            debug.sethook(runner.debug_hook, "l")
        end
    end)

    local ok, err = pcall(function()
        require("busted.runner")({ standalone = false })
    end)

    if not ok then
        io.stderr:write("RUNNER ERROR: " .. tostring(err) .. "\n")
        exit_code = 1
    end

    collectgarbage("collect")
    collectgarbage("collect")

    pcall(function()
        local runner = require("luacov.runner")
        if runner and runner.save_stats then
            runner.save_stats()
        end
    end)

    original_os_exit(exit_code, false)
end

-- ORCHESTRATOR PROCESS EXECUTION MODE
local is_brief = os.getenv("TEST_BRIEF") ~= nil
local test_file = arg[1]

local function print_verbose(...)
    if not is_brief then
        print(...)
    end
end

local function write_verbose(...)
    if not is_brief then
        io.write(...)
    end
end

print_verbose("=========================================================================")
print_verbose("[*] Test Runner: Orchestrating tests in worker process pool...")
print_verbose("=========================================================================")

-- List of spec files that must be exempted from environment isolation (KO_MULTIUSER)
local env_exemptions = {
    ["spec/unit/datastorage_spec.lua"] = true,
    ["spec/unit/screenshoter_spec.lua"] = true,
    ["spec/unit/readerhighlight_spec.lua"] = true,
    ["spec/unit/autosuspend_spec.lua"] = true,
    ["plugins/autosuspend.koplugin/spec/unit/autosuspend_spec.lua"] = true,
    ["plugins/autowarmth.koplugin/spec/unit/autowarmth_spec.lua"] = true,
    ["plugins/clock.koplugin/spec/unit/clock_spec.lua"] = true,
    ["spec/unit/device_spec.lua"] = true,
    ["spec/unit/eink_optimization_spec.lua"] = true,
    ["spec/unit/network_manager_spec.lua"] = true,
    ["spec/unit/readerfooter_spec.lua"] = true,
    ["spec/unit/readerthumbnail_spec.lua"] = true,
}

-- Collect spec files to execute
local spec_files = {}
if test_file then
    table.insert(spec_files, test_file)
else
    local function find_specs(dir)
        local attr = lfs.attributes(dir)
        if attr and attr.mode == "directory" then
            for file in lfs.dir(dir) do
                if file ~= "." and file ~= ".." then
                    local path = dir .. "/" .. file
                    local f_attr = lfs.attributes(path)
                    if f_attr then
                        if f_attr.mode == "directory" then
                            find_specs(path)
                        elseif f_attr.mode == "file" and file:match("_spec%.lua$") then
                            table.insert(spec_files, path)
                        end
                    end
                end
            end
        end
    end

    find_specs("base/spec/unit")
    find_specs("spec/unit")

    local plugins_dir = "plugins"
    local plugins_attr = lfs.attributes(plugins_dir)
    if plugins_attr and plugins_attr.mode == "directory" then
        for plugin in lfs.dir(plugins_dir) do
            if plugin ~= "." and plugin ~= ".." then
                find_specs(plugins_dir .. "/" .. plugin .. "/spec/unit")
            end
        end
    end

    table.sort(spec_files)
end

if #spec_files == 0 then
    io.stderr:write("[!] Error: No spec files found.\n")
    original_os_exit(1, false)
end

assert(test_env and test_env.max_jobs ~= nil, "test_helper must define max_jobs")
local max_jobs = test_env.max_jobs

local lua_flags = os.getenv("LUAFLAGS") or ""
print_verbose("[*] Running with parallelism limit: " .. max_jobs)
print_verbose("")

local active_jobs = {}
local failed_tests = {}
local failed_cases_details = {}
local total_tests = 0
local passed_tests = 0
local total_cases = 0
local passed_cases = 0
local failed_cases = 0
local next_spec_idx = 1

-- Helper to spawn a job with isolated environment
local function spawn_job(idx)
    local spec_path = spec_files[idx]
    local multi_user = (not env_exemptions[spec_path]) and "KO_MULTIUSER=1 " or ""
    local luacov_env = ""
    if lua_flags:find("luacov") then
        luacov_env = string.format("LUACOV_STATS_FILE=%q ", lfs.currentdir() .. "/luacov.stats.worker_" .. idx .. ".out")
    end

    local worker_config_dir = lfs.currentdir() .. "/worker_" .. idx
    lfs.mkdir(worker_config_dir)
    local worker_tmp_dir = worker_config_dir .. "/tmp"
    lfs.mkdir(worker_tmp_dir)

    local cmd = string.format("%sTMPDIR=%q %sKO_TEST_WORKER=1 XDG_CONFIG_HOME=%q TESSDATA_PREFIX=data ./luajit %s test_runner.lua %q 2>&1; echo \"EXIT_STATUS:$?\"", luacov_env, worker_tmp_dir, multi_user, worker_config_dir, lua_flags, spec_path)
    local pipe = io.popen(cmd)
    if pipe then
        active_jobs[idx] = {
            pipe = pipe,
            spec_path = spec_path,
            worker_config_dir = worker_config_dir,
        }
        total_tests = total_tests + 1
    else
        io.stderr:write("[!] Error: Failed to spawn test: " .. spec_path .. "\n")
        table.insert(failed_tests, spec_path)
    end
end

-- Initial spawn
while next_spec_idx <= #spec_files and next_spec_idx <= max_jobs do
    spawn_job(next_spec_idx)
    next_spec_idx = next_spec_idx + 1
end

-- Process queue
for i = 1, #spec_files do
    local job = active_jobs[i]
    if job then
        print_verbose("=========================================================================")
        print_verbose(string.format("[*] Running test (%d/%d): %s", i, #spec_files, job.spec_path))
        print_verbose("=========================================================================")

        local output = job.pipe:read("*a")
        job.pipe:close()

        local exit_code = 0
        local clean_output = output
        local status_str = output:match("\nEXIT_STATUS:(%d+)") or output:match("^EXIT_STATUS:(%d+)")
        if status_str then
            exit_code = tonumber(status_str)
            clean_output = output:gsub("\n?EXIT_STATUS:%d+\n?", "\n")
        else
            io.stderr:write("[!] Warning: Could not parse exit status for: " .. job.spec_path .. "\n")
            exit_code = 1
        end

        write_verbose(clean_output)

        local file_total = tonumber(output:match("\n%[%=+%] (%d+) tests? from")) or 0
        local file_passed = tonumber(output:match("\n%[%s+PASSED%s+%] (%d+) tests?%.\n")) or 0
        local file_failed = tonumber(output:match("\n%[%s+FAILED%s+%] (%d+) tests?, listed below:\n")) or 0

        if file_total == 0 then
            if exit_code ~= 0 then
                file_total = 1
                file_failed = 1
            end
        else
            if exit_code == 0 then
                file_passed = file_total
                file_failed = 0
            else
                if file_failed == 0 then
                    file_failed = file_total - file_passed
                end
                if file_failed <= 0 then
                    file_failed = 1
                end
            end
        end

        total_cases = total_cases + file_total
        passed_cases = passed_cases + file_passed
        failed_cases = failed_cases + file_failed

        if exit_code == 0 then
            passed_tests = passed_tests + 1
        else
            table.insert(failed_tests, job.spec_path)

            local file_failed_list = {}
            local seen_cases = {}
            for line in output:gmatch("[^\r\n]+") do
                local status, failed_case = line:match("^%[%s+([A-Z]+)%s+%] (.-%_spec%.lua%:%d+%:.+)$")
                if status == "FAILED" or status == "ERROR" then
                    failed_case = failed_case:gsub(" %(%d+%.%d+ ms%)$", "")
                    if not seen_cases[failed_case] then
                        seen_cases[failed_case] = true
                        table.insert(file_failed_list, failed_case)
                    end
                end
            end

            if #file_failed_list == 0 then
                table.insert(file_failed_list, job.spec_path .. " (entire file execution failed)")
            end

            for _, case in ipairs(file_failed_list) do
                table.insert(failed_cases_details, case)
            end
        end
        print_verbose("")

        if next_spec_idx <= #spec_files then
            spawn_job(next_spec_idx)
            next_spec_idx = next_spec_idx + 1
        end

        if job.worker_config_dir then
            os.execute("rm -rf " .. string.format("%q", job.worker_config_dir))
        end
    end
end

if lua_flags:find("luacov") then
    print_verbose("[*] Merging parallel LuaCov statistics files...")
    local stats = require("luacov.stats")
    local runner = require("luacov.runner")
    local merged_data = {}
    for i = 1, #spec_files do
        local wfile = lfs.currentdir() .. "/luacov.stats.worker_" .. i .. ".out"
        local data = stats.load(wfile)
        if data then
            for filename, filedata in pairs(data) do
                if merged_data[filename] then
                    runner.update_stats(merged_data[filename], filedata)
                else
                    merged_data[filename] = filedata
                end
            end
            os.remove(wfile)
        end
    end
    stats.save(lfs.currentdir() .. "/luacov.stats.out", merged_data)
    print_verbose("[*] Successfully merged parallel coverage statistics into luacov.stats.out")
end

print("=========================================================================")
print("[*] Test Suite Summary:")
print("    Total test files: " .. total_tests)
print("    Passed files:     " .. passed_tests .. "/" .. total_tests)
if #failed_tests > 0 then
    print("    Failed files:     " .. #failed_tests .. "/" .. total_tests)
end
print("    ---------------------------------------------------------------------")
print("    Total test cases: " .. total_cases)
print("    Passed cases:     " .. passed_cases .. "/" .. total_cases)
if failed_cases > 0 then
    print("    Failed cases:     " .. failed_cases .. "/" .. total_cases)
end
print("=========================================================================")

if #failed_cases_details > 0 then
    print("[!] Failed test cases:")
    for _, case in ipairs(failed_cases_details) do
        print("    - " .. case)
    end
    print("")
end

if #failed_tests > 0 then
    print("[!] Failed test files:")
    for _, failed in ipairs(failed_tests) do
        print("    - " .. failed)
    end
    original_os_exit(1, false)
end
original_os_exit(0, false)
