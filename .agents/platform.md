# Platform, Launcher, and FFI Conventions

This document outlines architecture and conventions for target device platforms, launcher scripts, Linux input grabbing (`EVIOCGRAB`), subprocess execution, and LuaJIT FFI interactions in KOReader.

---

## 1. Launcher Scripts and Exit Codes

KOReader runs under platform-specific launcher scripts across e-ink and embedded Linux devices (such as Kindle and Kobo platform targets in `kindle/`, `pw2/`, `legacy/`, and `kobo/`).

### Standard Exit Codes
*   `0`: Clean normal shutdown (initiated via `UIManager:quit()`).
*   `85`: Application restart requested (e.g. after plugin toggling, language change, or OTA update).
*   `86`: Enter USB Mass Storage mode (Kobo).
*   `88`: Power off / halt device (Kobo).
*   `1`: Abnormal termination / unhandled error (`UIManager:abort()`).

### Target Launcher Behaviors
*   **Kobo (`kobo/koreader.sh`)**:
    *   Treats any non-zero exit code other than `85`, `86`, or `88` as an unexpected crash. The launcher displays a crash message, waits up to 15 seconds for user input, and restarts KOReader automatically.
    *   Crashes at least 20 seconds apart each reset `CRASH_COUNT` to 1, so the 5-crash cap never triggers for recurring failures that take >20 seconds.
    *   **Deliberate Protective Exits**: When KOReader must terminate deliberately on startup to protect device state (for example, detecting an unresolvable hardware conflict), it must terminate cleanly with exit code `0` via `UIManager:quit()`, rather than aborting with a non-zero exit code, to avoid triggering the Kobo restart crash loop.
*   **Kindle (`kindle/koreader.sh`)**:
    *   Loops only on exit code `85`.
    *   Executes `killall -TERM reader.lua` after any exit to reap any stray `reader.lua` processes.
    *   Copies `crash.log` to `/mnt/us/koreader.crash.<YYYYmmddHHMMSS>.log` (timestamped per crash) on non-zero exit for diagnostics.

---

## 2. Linux Input Device Grabs (`EVIOCGRAB`)

On Linux/evdev platforms, `libkoreader-input.so` opens input event devices (`/dev/input/event*`) and issues an exclusive kernel grab via `ioctl(fd, EVIOCGRAB, 1)` unless the `KO_DONT_GRAB_INPUT` environment variable is set.

### Kernel Evdev Grab Semantics
*   `ioctl(fd, EVIOCGRAB, 0)` returns `0` *only* if this open file description currently holds the grab; it returns `EINVAL` both when another client holds the grab and when nobody holds it.
*   Thus, calling `ioctl(fd, EVIOCGRAB, 0)` followed immediately by `ioctl(fd, EVIOCGRAB, 1)` returns `0` for both calls if and only if the current file descriptor held the grab. When another process holds the grab (or no grab was held), the `EVIOCGRAB 0` call itself fails with `EINVAL`.
*   **Subprocesses Inherit Grabs**: The `EVIOCGRAB` state is bound to the kernel open file description (`struct file`), which is shared across `fork()`. Forked subprocesses inherit all open input file descriptors. Forked children must **never** call `ioctl(fd, EVIOCGRAB, 0)`, as doing so releases the grab for the parent process as well.

### Startup Conflict Detection (`Input:UIManagerReady`)
*   During initialization, `Input:UIManagerReady` checks grab ownership on all opened event devices in `Input.opened_devices` (skipping synthetic devices like `"fake_events"` and respecting `KO_DONT_GRAB_INPUT`).
*   If that ownership check fails, KOReader displays an `InfoMessage` notifying the user, waits 10 seconds, spawns `sh -c 'sleep 1; pkill lua; pkill luajit' &`, and exits cleanly with `UIManager:quit()` (`exit 0`).

---

## 3. LuaJIT FFI Vararg Argument Promotion

In C vararg function prototypes (such as `int ioctl(int fd, unsigned long req, ...)` or `int fcntl(int fd, int cmd, ...)`), LuaJIT promotes untyped Lua numbers to 8-byte C `double`s by default:

*   On 32-bit ARM architectures, variadic arguments follow the base AAPCS calling convention (across both `softfp` and `hardfp` builds alike), where an 8-byte `double` argument must be passed in an even-aligned core register pair (`r2:r3`). When a plain Lua number `1` is promoted to IEEE-754 `double` `1.0`, the low word `r2` contains `0x00000000` and high word `r3` contains `0x3ff00000`. The kernel reads `r2 = 0` (releasing the grab instead of acquiring it).
*   **Always Cast Vararg Integer Arguments**: Explicitly cast integer arguments in vararg FFI calls:
    ```lua
    -- Correct:
    C.ioctl(fd, C.EVIOCGRAB, ffi.cast("int", 1))

    -- Incorrect:
    C.ioctl(fd, C.EVIOCGRAB, 1)
    ```

---

## 4. Subprocess Execution (`ffiUtil.runInSubProcess`)

Subprocesses spawned via `ffiUtil.runInSubProcess` on `master` run with isolated process groups, constrained scheduling, and clean lifecycle management:

*   **Process Group and Parent Death Signal**:
    *   The child calls `C.setpgid(0, 0)` to establish its own process group.
    *   The child calls `C.prctl(1, 15, 0, 0, 0)` (`PR_SET_PDEATHSIG, SIGTERM`) and checks `C.getppid() == parent_pid`. If the parent died before `prctl` ran, the child calls `C._exit(1)` immediately.
*   **Scheduling Priority**:
    *   Subprocesses run under `SCHED_IDLE` scheduling with `nice(19)` to ensure background operations never starve the main UI thread.
*   **Stream Redirection and IPC**:
    *   The child's `stdout` and `stderr` are redirected to an IPC pipe via `C.dup2`, allowing the parent to monitor progress and capture logs for debugging.
*   **After-Fork Event Broadcast (`ForkedProcess`)**:
    *   Immediately after `fork()`, the child executes listeners registered for the `ForkedProcess` event (such as `DeviceListener:onForkedProcess`), resetting platform-specific handles (e.g. Kindle `lipc` connections) and marking CREngine instances to skip teardown.
*   **Termination with `_exit`**:
    *   When the child completes, it flushes `io.stdout` and `io.stderr` and calls POSIX `C._exit(0)` directly instead of Lua `os.exit(0)`. This terminates the child process and all its threads immediately without running glibc `atexit` destructors, avoiding deadlocks with multi-threaded C libraries.
*   **Parent Cleanup and Reaping**:
    *   The parent terminates running subprocesses using `ffiUtil.terminateSubProcess(pid)`, which signals the entire process group using `C.kill(-pid, 9)`.
