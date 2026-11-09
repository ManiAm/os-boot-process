# ONIE (Open Network Install Environment)

The [previous chapter](08_boot_over_network.md) covered PXE — a protocol for **booting** an OS from the network on every startup. ONIE takes a different approach: it **installs** a Network Operating System (NOS) over the network once, and subsequent boots load the OS from local storage.

## What Is ONIE?

**ONIE** (2012) is an open-source provisioning framework for bare-metal network switches, created by Cumulus Networks (now part of NVIDIA) and adopted by the **Open Compute Project (OCP)** in 2013.

A **bare-metal network switch** is a switch sold without a pre-installed operating system — just the hardware and a minimal boot environment. This is analogous to buying a PC without Windows or Linux: the customer chooses and installs the OS themselves. ONIE is that minimal boot environment.

ONIE is a small Linux-and-BusyBox operating system pre-installed in the switch's flash memory by the hardware vendor at the factory. **BusyBox** is a single executable that bundles stripped-down versions of common Unix utilities (shell, wget, DHCP client, etc.), keeping the image compact enough for embedded storage. ONIE acts as an intelligent installer platform — it discovers, downloads, and executes a NOS installer, then gets out of the way. Once the NOS is installed locally, ONIE hands off directly to it on subsequent boots.

> **Where does ONIE run?** A modern network switch has two subsystems: the **forwarding plane** (the switch ASIC — a specialized chip that forwards packets at line rate — and the front-panel ports) and the **management subsystem** (a small embedded computer with its own CPU, storage, serial console, and an out-of-band management Ethernet port). ONIE runs entirely on the management subsystem — installer traffic goes through the management port, not a front-panel port.

## How ONIE Works

An ONIE-enabled system consists of a boot loader, an ONIE-capable Linux kernel, and the **ONIE Discovery and Execution (ODE)** application. The boot loader varies by architecture:

- **ARM / PowerPC** — typically [**U-Boot**](03_bootloaders.md#u-boot-universal-boot-loader), which initializes the hardware and loads the ONIE kernel
- **x86** — **BIOS or UEFI** firmware initializes the hardware, then [**GRUB2**](06_bootloader_grub.md) loads the ONIE kernel

**First boot (provisioning):**

1. The boot loader loads the ONIE kernel from flash.
2. The ONIE kernel starts the ODE application, which configures the management Ethernet interface via DHCP or link-local addressing (an automatically assigned IP used when no DHCP server is available).
3. The ODE attempts to locate an NOS installer using the following methods, tried in order:
   - **Static configuration** — a URL passed from the boot loader (used for engineering and debugging)
   - **Local storage** — searches locally attached devices such as a USB drive for an installer file named `onie-installer`
   - **DHCPv4 exact URLs** — uses DHCP options (e.g., Option 114 `default-url`, or VIVSO Option 125 — a vendor-specific information option that carries ONIE parameters) to obtain the exact URL of the installer
   - **DHCPv4 partial URLs** — constructs URLs from DHCP responses (TFTP server IP, HTTP server IP) combined with default installer file names
   - **IPv6 neighbors** — queries link-local IPv6 and IPv4 neighbors via HTTP
   - **TFTP waterfall** — tries TFTP paths with decreasing specificity (machine-specific names down to the generic `onie-installer`)
4. The ODE downloads the installer (via HTTP, FTP, or TFTP) and executes it. The installer partitions the disk and installs the NOS.
5. The installer updates the boot configuration to boot straight into the NOS, and the system reboots.

If no method succeeds, the ODE sleeps for 20 seconds and retries the entire sequence — looping indefinitely until installation completes.

> HTTP is the preferred download method for its speed and reliability with large images. TFTP is supported but discouraged by the ONIE project in favor of HTTP.

**Subsequent boots:**

1. The boot loader launches the installed NOS directly, bypassing ONIE entirely.
2. The NOS boots and operates normally.

ONIE remains in flash as a recovery environment — if the NOS is uninstalled or corrupted, the switch falls back to ONIE and the discovery process begins again.

> **ONIE does not use PXE.** Because ONIE already runs a full Linux kernel, it does not need PXE firmware. Its TFTP-based discovery is described in the official specification as a "PXE-like TFTP waterfall" — it resembles PXE's approach but is ONIE's own implementation running in user space.

## Why ONIE Matters

ONIE decouples network hardware from network software — vendors ship switches with ONIE pre-installed, and customers choose their NOS independently (e.g., Cumulus Linux, SONiC, Dell OS10, DENT, FBOSS). This is a key enabler of the open networking ecosystem.

---

[← Previous: Boot Over Network](08_boot_over_network.md)
