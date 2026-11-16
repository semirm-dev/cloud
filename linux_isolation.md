# Linux Container Isolation: The Big Picture

At the Linux kernel level, **there is no such thing as a "container."**

A container is just a normal Linux process (or group of processes) running directly on the host machine's kernel, isolated by **Namespaces** (which restrict what the process can *see*) and **cgroups** (which limit how much hardware it can *use*).

Everything Docker, Podman, or Kubernetes does under the hood is just automating built-in Linux kernel features.

## 1. The Two Core Pillars: Namespaces vs. cgroups

Although container tools bundle them together, **Namespaces** and **cgroups** are two completely independent Linux subsystems. They don't talk to each other; they just attach separately to the same running process (`PID`).

| Feature | **Namespaces** *(The Walls)* | **cgroups** *(The Leash)* | 
| ----- | ----- | ----- | 
| **Core Job** | Controls what a process can **SEE**. | Controls how much hardware a process can **USE**. | 
| **What it actually is** | Invisible isolation bubbles in kernel RAM. | **Literally folders and virtual files** under `/sys/fs/cgroup/`. | 
| **How you create it** | Passed as **launch flags** when starting a process (`unshare` CLI or `clone()` syscall). | Run `mkdir` in `/sys/fs/cgroup/` and `echo` limits into files. | 
| **Where you inspect it** | `/proc/<PID>/ns/` (read-only links & doorways). | `/sys/fs/cgroup/<name>/` (live stats & control knobs). | 

## 2. Namespaces: Putting Blindfolds on a Process

Normally, all Linux processes live in one big shared room. Namespaces split global OS resources so a process only sees its own private slice:

* **PID (`--pid`):** Gives the process its own process table. Inside the bubble, your app sees itself as **PID 1**. On the host, it still has a normal host PID (e.g., `19402`).

* **Mount (`--mount`):** Gives the process its own private list of mounted folders. Combined with `pivot_root`, this swaps `/` for a container image so the host's hard drive is completely hidden.

* **Network (`--net`):** Gives the process a blank network stack (just a `lo` loopback interface) with its own IP addresses and ports.

* **UTS (`--uts`):** Lets the process have its own `hostname` without changing the host's name.

* **IPC (`--ipc`):** Isolates inter-process communication and shared memory.

* **User (`--user`):** Maps `root` (UID `0`) inside the bubble to an unprivileged regular user (e.g., UID `100000`) on the host.

* **Cgroup (`--cgroup`):** Hides the host's full `/sys/fs/cgroup/` directory tree so the container only sees its own cgroup folder as `/`.

### `clone()` vs. `unshare()` vs. `nsenter`

There is no config file you edit to create a namespace—you create or enter them using three core mechanisms:

1. **`clone()` (Kernel Syscall):** Used by container runtimes (`runc`) in code. It spawns a brand-new child process *directly* inside new namespaces via bitmask flags (`CLONE_NEWPID | CLONE_NEWNS | CLONE_NEWNET`).

2. **`unshare` (CLI Tool & Syscall):** Detaches the current process into new namespaces and (with `--fork`) launches your command inside the bubble.

3. **`nsenter` (`setns()` Syscall):** Opens the doorways in `/proc/<PID>/ns/` to drop a new shell into an *already running* container's namespaces (this is how `docker exec` works).

## 3. cgroups: Resource Limits Are Just Files

In Linux (**cgroups v2**), the kernel exposes its resource controller as a virtual filesystem mounted at `/sys/fs/cgroup/`. There is no daemon or database—**the filesystem is the API**.

### How to Build a Resource Cage Manually

```
# 1. Create a folder (the kernel auto-populates ~30 control files inside it)
sudo mkdir /sys/fs/cgroup/my-app

# 2. Set hardware limits by writing into virtual files
echo "104857600" | sudo tee /sys/fs/cgroup/my-app/memory.max   # 100 MB hard RAM limit
echo "50000 100000" | sudo tee /sys/fs/cgroup/my-app/cpu.max   # 50% of 1 CPU core
echo "20" | sudo tee /sys/fs/cgroup/my-app/pids.max           # Max 20 processes/threads

# 3. Drop a running PID into the cage
echo <PID> | sudo tee /sys/fs/cgroup/my-app/cgroup.procs

```

From that moment on, that PID (and any child process it spawns) is trapped inside those limits. If it exceeds `memory.max`, the kernel's OOM Killer terminates it without affecting the rest of the machine.

## 4. What `/proc` Actually Is

`/proc` is **not** a real folder on your hard drive—it is a live window into kernel RAM (`procfs`):

* **Numbered folders (`/proc/813/`):** One folder for every running process, containing its live stats, open files (`fd/`), cgroup path (`cgroup`), and namespace IDs (`ns/`).

* **Kernel files (`/proc/cpuinfo`, `/proc/cgroups`):** Live hardware and kernel configuration readouts (size `0` on disk because the text is generated on the fly when you read them).

* **Why `/proc` needs to be remounted in a container:** Tools like `ps` and `top` simply read `/proc`. Even if you start a process with `unshare --pid`, it will still see host PIDs until you also isolate `--mount` and mount a fresh `/proc` (`mount -t proc proc /proc`) inside the bubble.

## 5. The Other 4 Pieces That Complete a Container

Beyond Namespaces and cgroups, four other Linux features turn an isolated process into a full container:

1. **OverlayFS (`overlay`):** Stacks read-only image folders (`lowerdir`) with a single writable folder (`upperdir`) into one `merged` directory. Editing an image file triggers **Copy-on-Write**, leaving the base image untouched.

2. **`veth` Pairs & Bridges:** Virtual Ethernet cables in kernel RAM (`ip link add ... type veth`) that plug one end into the container's isolated network namespace and the other into a host network bridge (`docker0`).

3. **Linux Capabilities:** Breaks traditional `root` power into \~40 individual on/off flags attached to the process, letting runtimes strip dangerous powers (like rebooting the host or loading kernel drivers) even if the container runs as `root`.

4. **Seccomp-BPF:** A lightweight syscall firewall attached to the process in RAM that blocks dangerous kernel calls (like `reboot()` or `mount()`) before they execute.

## Quick Cheat Sheet: Try It Safely in 10 Seconds

Run this on any Linux machine (or WSL 2) to spin up a temporary isolated bubble and tear it down on `exit`:

```
# Launch bash in a new PID, Hostname, and Mount namespace
sudo unshare --pid --uts --mount-proc --fork /bin/bash

# Inside the bubble:
hostname my-sandbox   # Changes hostname ONLY inside this shell
ps aux                # Shows ONLY 2 processes: bash (PID 1) and ps (PID 2)
ls -l /proc/$$/ns/    # Shows the unique kernel inode IDs of your new namespaces
exit                  # Destroys the bubble and returns to your normal host

```