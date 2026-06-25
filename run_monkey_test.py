#!/usr/bin/env python3
import socket
import subprocess
import time
import random
import os
import sys

def main():
    # Options
    num_actions = 100
    if len(sys.argv) > 1:
        try:
            num_actions = int(sys.argv[1])
        except ValueError:
            pass

    print(f"[*] Starting monkey test with {num_actions} random actions...")

    # Set dummy video driver for headless execution
    env = os.environ.copy()
    env["SDL_VIDEODRIVER"] = "dummy"
    env["EMULATE_READER_W"] = "600"
    env["EMULATE_READER_H"] = "800"

    # Start KOReader process
    koreader_dir = os.path.abspath("linux")
    print(f"[*] Launching KOReader in {koreader_dir}...")
    proc = subprocess.Popen(
        ["./luajit", "reader.lua"],
        cwd=koreader_dir,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    # Wait for the TCP server to start
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.5)
    connected = False
    for attempt in range(20):
        if proc.poll() is not None:
            print("[-] KOReader exited prematurely during startup!")
            stdout, stderr = proc.communicate()
            print("--- STDOUT ---")
            print(stdout)
            print("--- STDERR ---")
            print(stderr)
            sys.exit(1)
        try:
            sock.connect(("127.0.0.1", 8088))
            connected = True
            break
        except socket.error:
            time.sleep(0.2)

    if not connected:
        print("[-] Could not connect to KOReader TCP event server on port 8088!")
        proc.terminate()
        sys.exit(1)

    print("[+] Connected to KOReader. Injecting events...")

    # Action loop
    passed = True
    try:
        for i in range(num_actions):
            if proc.poll() is not None:
                print(f"[-] KOReader crashed at action {i}!")
                passed = False
                break

            # 90% touches, 10% keys
            if random.random() < 0.90:
                x = random.randint(10, 590)
                y = random.randint(10, 790)
                cmd = f"touch {x} {y}\n"
            else:
                # Key codes: Right (1073741903), Left (1073741904), Down (1073741905), Up (1073741906)
                code = random.choice([1073741903, 1073741904, 1073741905, 1073741906])
                cmd = f"key {code}\n"

            sock.sendall(cmd.encode("utf-8"))
            response = sock.recv(1024).decode("utf-8")
            if response != "OK\n":
                print(f"[-] Unexpected response: {repr(response)}")
                passed = False
                break

            # Sleep between actions
            time.sleep(random.uniform(0.05, 0.15))

    except Exception as e:
        print(f"[-] Error during test execution: {e}")
        passed = False
    finally:
        sock.close()
        print("[*] Terminating KOReader process...")
        proc.terminate()
        try:
            stdout, stderr = proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            stdout, stderr = proc.communicate()

    if passed:
        print(f"[+] Monkey test PASSED. Successfully executed {num_actions} actions.")
        sys.exit(0)
    else:
        print("[-] Monkey test FAILED.")
        print("--- KOReader STDOUT ---")
        print(stdout)
        print("--- KOReader STDERR ---")
        print(stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
