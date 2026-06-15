if jit == nil then
    jit = require("jit")
end
if bit == nil then
    bit = require("bit")
end
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
package.path = "./base/spec/unit/?.lua;./spec/unit/?.lua;./?.lua;./common/?.lua;./frontend/?.lua;/usr/share/lua/5.4/?.lua;/usr/share/lua/5.4/?/init.lua;;"
package.cpath = "./?.so;./common/?.so;./libs/?.so;/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;;"

-- 2. Load framework unit test helpers
if not pcall(dofile, "test_helper.lua") then
    dofile("ffi/loadlib.lua")
end


local test_file = arg[1]
if test_file then
    -- Force DocSettings to ALWAYS use "dir" location (docsettings/ folder) during tests.
    -- This ensures book settings are written to the isolated /tmp/.../koreader/docsettings/ directory
    -- instead of writing sidecars (.sdr/) next to the shared book files on the host filesystem,
    -- completely preventing parallel test conflicts on shared books (like leaves.epub)!
    -- NOTE: We exclude specs that specifically test named settings / metadata path generation logic
    -- to prevent breaking their assertions.
    local is_settings_test = test_file:match("docsettings_spec%.lua$") or test_file:match("named_settings_spec%.lua$")
    if not is_settings_test then
        local ok, named_settings = pcall(require, "named_settings")
        if ok then
            named_settings.document_metadata_folder = function()
                return "dir"
            end
        end
    end
end

if not test_file then
    -- Orchestrator mode: run spec files in parallel worker pool of processes
    print("=========================================================================")
    print("[*] Test Runner: Orchestrating all tests in parallel processes...")
    print("=========================================================================")

    -- List of spec files that must be exempted from environment isolation (KO_MULTIUSER)
    -- because they test path resolution, local file creation, or monkeypatch 
    -- core settings logic (like docsettings/named_settings) that breaks isolation.
    local env_exemptions = {
        ["spec/unit/datastorage_spec.lua"] = true,
        ["spec/unit/screenshoter_spec.lua"] = true,
        ["spec/unit/docsettings_spec.lua"] = true,
        ["spec/unit/named_settings_spec.lua"] = true,
    }

    -- If we are running in origin.linux, we must also exempt tests that fail
    -- due to KO_MULTIUSER causing the device to be detected as Desktop instead of Emulator.
    local target = lfs.symlinkattributes("test_runner.lua", "target")
    if target and target:match("origin%.linux") then
        env_exemptions["spec/unit/autosuspend_spec.lua"] = true
        env_exemptions["spec/unit/device_spec.lua"] = true
        env_exemptions["spec/unit/eink_optimization_spec.lua"] = true
        env_exemptions["spec/unit/network_manager_spec.lua"] = true
        env_exemptions["spec/unit/readerfooter_spec.lua"] = true
    end

    -- Find all spec files under base/spec/unit and spec/unit
    local spec_files = {}
    local function find_specs(dir, specs)
        local attributes = lfs.attributes(dir)
        if not attributes then return specs end

        if attributes.mode == "directory" then
            for file in lfs.dir(dir) do
                if file ~= "." and file ~= ".." then
                    local path = dir .. "/" .. file
                    local f_attr = lfs.attributes(path)
                    if f_attr then
                        if f_attr.mode == "directory" then
                            find_specs(path, specs)
                        elseif f_attr.mode == "file" and file:match("_spec%.lua$") then
                            table.insert(specs, path)
                        end
                    end
                end
            end
        end
        return specs
    end

    find_specs("base/spec/unit", spec_files)
    find_specs("spec/unit", spec_files)
    table.sort(spec_files)

    if #spec_files == 0 then
        io.stderr:write("[!] Error: No spec files found.\n")
        original_os_exit(1, false)
    end

    -- Determine optimal parallelism (number of CPU cores, default to 4)
    local max_jobs = 4
    local nproc_p = io.popen("nproc 2>/dev/null")
    if nproc_p then
        local cores = tonumber(nproc_p:read("*l"))
        nproc_p:close()
        if cores and cores > 0 then
            max_jobs = cores
        end
    end
    print("[*] Running with parallelism limit: " .. max_jobs)
    print("")

    local active_jobs = {}
    local failed_tests = {}
    local failed_cases_details = {}
    local total_tests = 0
    local passed_tests = 0
    local total_cases = 0
    local passed_cases = 0
    local failed_cases = 0
    local next_spec_idx = 1

    -- Helper to spawn a job with isolated environment (or clean default env if exempted)
    local function spawn_job(idx)
        local spec_path = spec_files[idx]
        local use_isolated_env = not env_exemptions[spec_path]

        local cmd
        local worker_config_dir

        if use_isolated_env then
            worker_config_dir = lfs.currentdir() .. "/worker_" .. idx
            lfs.mkdir(worker_config_dir)
            -- We set KO_MULTIUSER=1 and XDG_CONFIG_HOME to direct all configuration/settings
            -- writes to this isolated directory, preventing parallel file access conflicts!
            -- We also set TESSDATA_PREFIX=data so Tesseract OCR can find the trained data in the isolated environment.
            cmd = string.format("KO_MULTIUSER=1 XDG_CONFIG_HOME=%q TESSDATA_PREFIX=data ./lua test_runner.lua %q 2>&1; echo \"EXIT_STATUS:$?\"", worker_config_dir, spec_path)
        else
            -- Run without environment manipulation for exempted tests
            cmd = string.format("./lua test_runner.lua %q 2>&1; echo \"EXIT_STATUS:$?\"", spec_path)
        end

        local pipe = io.popen(cmd)
        if pipe then
            active_jobs[idx] = {
                pipe = pipe,
                spec_path = spec_path,
                worker_config_dir = worker_config_dir, -- will be nil for exempted tests
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

    -- Process the queue sequentially to keep printed logs clean and ordered
    for i = 1, #spec_files do
        local job = active_jobs[i]
        if job then
            print("=========================================================================")
            print(string.format("[*] Running test (%d/%d): %s", i, #spec_files, job.spec_path))
            print("=========================================================================")

            -- Block until this specific job's output is fully read
            local output = job.pipe:read("*a")
            job.pipe:close()

            -- Parse exit status from the end of the output
            local exit_code = 0
            local clean_output = output
            local status_pattern = "\nEXIT_STATUS:(%d+)\n$"
            if not output:match(status_pattern) then
                status_pattern = "EXIT_STATUS:(%d+)$"
            end
            local status_str = output:match(status_pattern)
            if status_str then
                exit_code = tonumber(status_str)
                clean_output = output:gsub("\n?EXIT_STATUS:%d+\n?$", "")
            else
                io.stderr:write("[!] Warning: Could not parse exit status for: " .. job.spec_path .. "\n")
                exit_code = 1
            end

            -- Print the clean output
            io.write(clean_output)

            -- Parse and accumulate individual test case counts from Busted output
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
                        if file_failed <= 0 then file_failed = 1 end
                    end
                    if file_passed == 0 then
                        file_passed = file_total - file_failed
                        if file_passed < 0 then file_passed = 0 end
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

                -- Parse and collect individual failed test cases from Busted output
                local file_failed_list = {}
                local seen_cases = {}
                for line in output:gmatch("[^\r\n]+") do
                    local failed_case = line:match("^%[%s+FAILED%s+%] (.-%_spec%.lua%:%d+%:.+)$")
                    if failed_case then
                        -- Remove " (X.XX ms)" timing suffix if present to make duplicate lines identical
                        failed_case = failed_case:gsub(" %(%d+%.%d+ ms%)$", "")
                        if not seen_cases[failed_case] then
                            seen_cases[failed_case] = true
                            table.insert(file_failed_list, failed_case)
                        end
                    end
                end

                if #file_failed_list == 0 then
                    -- Fallback if the file failed to execute at all (e.g. crash or syntax error)
                    table.insert(file_failed_list, job.spec_path .. " (entire file execution failed)")
                end

                for _, case in ipairs(file_failed_list) do
                    table.insert(failed_cases_details, case)
                end
            end
            print("")



            -- Spawn the next job in line to keep the worker pool busy
            if next_spec_idx <= #spec_files then
                spawn_job(next_spec_idx)
                next_spec_idx = next_spec_idx + 1
            end
        end
    end

    print("=========================================================================")
    print("[*] Test Suite Summary:")
    print("    Total test files: " .. total_tests)
    print("    Passed files:     " .. passed_tests .. "/" .. total_tests)
    print("    Failed files:     " .. #failed_tests .. "/" .. total_tests)
    print("    ---------------------------------------------------------------------")
    print("    Total test cases: " .. total_cases)
    print("    Passed cases:     " .. passed_cases .. "/" .. total_cases)
    print("    Failed cases:     " .. failed_cases .. "/" .. total_cases)
    print("=========================================================================")

    if #failed_cases_details > 0 then
        print("[!] Failed test cases:")
        for _, failed_case in ipairs(failed_cases_details) do
            print("    - " .. failed_case)
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
end

-- 4. Execute Busted runner (loads options automatically from .busted config file)
local ok, err = pcall(function()
    require("busted.runner")({ standalone = false })
end)

if not ok then
    io.stderr:write("RUNNER ERROR: " .. tostring(err) .. "\n")
    exit_code = 1
end

-- 5. Clean up and finalize all unreachable FFI objects while C dynamic libraries are still loaded
collectgarbage("collect")
collectgarbage("collect")

-- 6. Exit cleanly bypassing out-of-order VM teardown crashes
original_os_exit(exit_code, false)
