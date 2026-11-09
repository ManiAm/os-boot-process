# OS Boot Process

This chapter walks through what happens from the moment you press the power button to the login prompt. Every computer — regardless of operating system — follows the same high-level sequence:

```mermaid
flowchart LR
    A[Power On] --> B[CPU Reset] --> C["Firmware\n(BIOS / UEFI)"] --> D[Bootloader] --> E[OS Kernel] --> F[User Login]
```

Each stage hands control to the next. The sections below explain each stage in order.

## CPU Power-On and Reset

When the computer is powered on, the CPU starts in a known state called the **reset state**. All registers are set to predefined values, and the Program Counter (PC) — also called the Instruction Pointer (IP) — is set to a fixed memory address known as the **reset vector**.

The reset vector is the very first address the CPU reads after power-on. It points to firmware code (BIOS or UEFI) that begins the boot process.

### Reset Vectors by Architecture

Different CPU architectures define different reset vector addresses:

| Architecture                | Reset Address                | Notes |
|-----------------------------|------------------------------|------------------------------------------|
| **x86 (8086/8088)**         | `0xFFFF0`                    | 16 bytes below 1 MiB; CS=`0xFFFF`, IP=`0x0000` |
| **x86 (386 and later)**     | `0xFFFFFFF0`                 | 16 bytes below 4 GiB; CS base is `0xFFFF0000`, EIP=`0xFFF0`. The CPU is in real mode — not protected or long mode |
| **ARM (Cortex-M)**          | Vector table at `0x00000000` | Reads initial SP from `0x00000000` and Reset_Handler address from `0x00000004`, then jumps to the handler. The table location can be changed via VTOR |
| **ARM (Cortex-A, AArch32)** | `0x00000000` or `0xFFFF0000` | Selected by the `SCTLR.V` bit. VBAR controls non-reset exception vectors |
| **ARM (Cortex-A, AArch64)** | Implementation-defined       | Set by hardware pins (`RVBARADDR`), readable via `RVBAR_EL3` |
| **RISC-V**                  | Implementation-defined       | Platform-specific; common values include `0x00001000` (QEMU), `0x10000` (Rocket/Chipyard), `0x80000000` |
| **MIPS**                    | `0xBFC00000` (virtual)       | Maps to physical address `0x1FC00000` in the uncached KSEG1 region |
| **PowerPC**                 | `0xFFF00100`                 | Reset exception at offset `0x100` from base `0xFFF00000` (MSR[IP]=1 at power-on) |

The original 8086 had a fixed reset vector. Later x86 processors (386+) kept the same CS:IP appearance (`F000:FFF0`) but use a special hidden CS base to reach the top of their larger address space. Modern architectures like ARM (AArch64) and RISC-V leave the reset address entirely implementation-defined, configured through hardware pins or platform design.

## Firmware (BIOS / UEFI)

The reset vector points to **firmware** — software stored on a chip on the motherboard. The CPU executes firmware directly at power-on, before RAM or storage devices are initialized.

Two firmware standards have been used in PCs:

- **BIOS** (Basic Input/Output System) — the original firmware standard, dating back to the IBM PC in 1981. Operates in 16-bit real mode, boots from MBR sectors, and provides hardware services through software interrupts.

- **UEFI** (Unified Extensible Firmware Interface) — the modern replacement, running in 32/64-bit mode. Boots from `.efi` files on a FAT32 partition (the EFI System Partition), supports GPT disks, Secure Boot, and includes a built-in boot manager.

> **EFI vs UEFI:** EFI was Intel's original specification. UEFI is the current version maintained by an industry consortium. The terms are often used interchangeably.

Regardless of the standard, the firmware performs the same high-level steps:

1. **Power-On Self-Test (POST)** — verifies that the CPU, memory, and essential hardware are functional.
2. **Hardware initialization** — configures memory controllers, buses, and detects peripherals.
3. **Searches for a bootable device** — checks devices in the configured boot order.
4. **Loads the bootloader** — reads bootloader code from the boot device into memory and transfers control to it.

> For a detailed comparison of BIOS and UEFI — including boot phases, Secure Boot, CMOS/NVRAM, and the UEFI Boot Manager — see [Firmware: BIOS and UEFI](02_firmware_bios_and_uefi.md).

## Bootloader

The **bootloader** is a small program responsible for loading the operating system kernel into memory and handing control to it. The BIOS finds the bootloader by checking each device in the boot order until it finds one with valid boot code.

For example, with a boot order of **USB → Hard Disk → Network**:

- If a bootable USB is inserted, the system loads the USB's bootloader.
- If no USB is present, it falls back to the hard disk's bootloader.
- If that also fails, it attempts a network boot (PXE) to download a bootloader over the network.

### Bootloader Location

Where the bootloader is stored on disk depends on the **partitioning scheme**:

**MBR (Master Boot Record)**

The bootloader code is stored in the first 512 bytes of the storage device — a region called the MBR. This 512-byte block contains the boot code, the partition table, and a two-byte magic number (`0x55AA`) that tells the BIOS the sector is bootable.

> For a detailed breakdown of the MBR structure, see [MBR](https://github.com/ManiAm/storage-and-file-systems/blob/master/docs/04_mbr.md) in the Disk Storage project.

**GPT (GUID Partition Table) with UEFI**

On GPT disks, the bootloader is not embedded in the first sector. Instead, UEFI firmware reads the GPT and locates a dedicated **EFI System Partition (ESP)** — a small FAT32-formatted partition (typically 100–500 MB) that stores bootloader files as `.efi` executables:

> For a detailed breakdown of the GPT structure, see [GPT](https://github.com/ManiAm/storage-and-file-systems/blob/master/docs/05_gpt.md) in the Disk Storage project.

| Bootloader           | Path on ESP            |
|----------------------|------------------------|
| Default (fallback)   | `\EFI\BOOT\BOOTX64.EFI` |
| Windows Boot Manager | `\EFI\Microsoft\Boot\bootmgfw.efi` |
| Linux GRUB2          | `\EFI\ubuntu\grubx64.efi` |

**GPT with Legacy BIOS (Compatibility Mode)**

It is possible to boot from a GPT disk using a legacy BIOS through a **BIOS Boot Partition** — a small (~1 MB) partition with no filesystem that holds raw bootloader code (e.g., GRUB's core image). The BIOS reads the Protective MBR and jumps to this partition. This mode uses **CSM** (Compatibility Support Module), a UEFI component that emulates legacy BIOS behavior.

> CSM/Legacy BIOS boot with GPT is a compatibility workaround. For new systems, UEFI boot with GPT is the standard approach.

### One-Stage vs Two-Stage Bootloaders

| Feature            | One-Stage Bootloader                    | Two-Stage Bootloader |
|--------------------|-----------------------------------------|----------------------|
| Size               | Fits within the MBR (446 bytes of code) | Uses additional space in partitions or files |
| Complexity         | Simple and minimal                      | Supports advanced features |
| Filesystem support | None — loads raw sectors                | Reads filesystems (FAT, ext4, etc.) |
| OS support         | Loads a single OS                       | Supports multi-boot menus |
| Configuration      | None                                    | Allows kernel parameters, recovery tools |

A **one-stage bootloader** is a self-contained program that fits entirely in the MBR. It loads the kernel directly from a known disk location and transfers control to it.

A **two-stage bootloader** splits the work:

- **Stage 1** resides in the MBR (or EFI partition). Its only job is to locate and load the Stage 2 code from elsewhere on disk.
- **Stage 2** is a larger program that can read filesystems, display a boot menu, accept user input, load kernel files, and pass boot parameters. GRUB is the most common example.

## OS-Specific Boot Processes

Once the bootloader loads the kernel, the remaining boot process is OS-specific. The sections below describe how each major OS family completes the boot sequence.

### MS-DOS

| Stage          | Key Components |
|----------------|----------------|
| Bootloader     | Boot sector loads `IO.SYS` |
| Kernel         | `IO.SYS` → `MSDOS.SYS` |
| Configuration  | `CONFIG.SYS` → `AUTOEXEC.BAT` |
| User interface | `COMMAND.COM` (text shell) |

1. The boot sector locates and loads `IO.SYS`, which initializes hardware and default device drivers (console, disk, serial port).
2. `IO.SYS` loads `MSDOS.SYS` — the DOS kernel that provides file management, memory handling, and system services.
3. `CONFIG.SYS` is processed (if present) to load additional device drivers and memory managers.
4. The command interpreter `COMMAND.COM` is loaded.
5. `COMMAND.COM` executes `AUTOEXEC.BAT` (if present) to configure environment variables and run startup programs.
6. The `C:\>` prompt appears, ready for user input.

| File           | Type        | Role |
|----------------|-------------|--------------------------------|
| `IO.SYS`       | System file | Hardware init, default drivers, loads the DOS kernel |
| `MSDOS.SYS`    | System file | DOS kernel — file management, memory handling |
| `COMMAND.COM`  | Executable  | Command-line interpreter and shell |
| `CONFIG.SYS`   | Text file   | Device drivers and system parameters (processed before COMMAND.COM) |
| `AUTOEXEC.BAT` | Batch file  | Startup environment setup (PATH, PROMPT, etc.) |

### Windows 95, 98, and ME

These versions use a DOS-based boot stage but transition to a 32-bit protected-mode kernel. Unlike MS-DOS, `IO.SYS` in Windows 9x contains both the I/O system **and** the kernel — `MSDOS.SYS` is no longer a binary kernel but a text configuration file that stores boot options and paths.

1. The boot sector loads `IO.SYS`, which initializes hardware, reads `MSDOS.SYS` (for boot configuration), and displays "Starting Windows."
2. `CONFIG.SYS` and `AUTOEXEC.BAT` are processed for backward compatibility (Windows ME skips this step).
3. `WIN.COM` runs and loads `VMM32.VXD` (Virtual Machine Manager), which contains the protected-mode kernel and core virtual device drivers (VxDs).
4. `VMM32.VXD` switches the CPU from real mode to **protected mode** and initializes protected-mode VxDs in three phases.
5. `explorer.exe` starts, launching the graphical desktop.

### Windows XP

Windows XP is a pure NT-based operating system with no DOS dependency.

1. **NTLDR** — The boot sector loads `NTLDR`, which switches from real mode to protected mode, reads `BOOT.INI` for OS selection, and runs `NTDETECT.COM` to detect hardware.
2. **Kernel loading** — `NTLDR` loads `ntoskrnl.exe` (the Windows kernel) and `HAL.DLL` (Hardware Abstraction Layer), then initializes boot-start device drivers.
3. **Session Manager** — The kernel starts `SMSS.EXE`, which loads the Win32 subsystem driver (`Win32k.sys`), starts `CSRSS.EXE` (Client/Server Runtime), and launches `WINLOGON.EXE`.
4. **Login and desktop** — `WINLOGON.EXE` handles user authentication via `LSASS.EXE`, then loads `explorer.exe` to display the desktop.

### Windows Vista and Later

Vista introduced a redesigned boot architecture with `BOOTMGR` and `Winload.exe`.

1. **BOOTMGR** — The boot sector loads `BOOTMGR`, which reads the Boot Configuration Data (BCD) store, displays the boot menu if needed, and selects the OS to boot.
2. **Winload.exe** — `BOOTMGR` hands off to `Winload.exe`, which loads `ntoskrnl.exe`, `HAL.DLL`, and boot-start device drivers into memory.
3. **Kernel initialization** — `ntoskrnl.exe` initializes executive subsystems and starts `SMSS.EXE` (Session Manager).
4. **Session Manager** — `SMSS.EXE` loads `Win32k.sys`, then starts `CSRSS.EXE` and `Wininit.exe` (for session 0 — services), and `CSRSS.EXE` and `Winlogon.exe` (for session 1 — user login).
5. **Login and desktop** — `Wininit.exe` starts the Service Control Manager (`services.exe`) and `LSASS.EXE`. `Winlogon.exe` launches `LogonUI.exe` for user authentication, then loads `explorer.exe`.

### Linux

1. **Bootloader** — GRUB (or LILO) loads the Linux kernel into memory and passes boot parameters (e.g., root filesystem location).
2. **Kernel initialization** — The kernel decompresses itself, initializes CPU and memory management, and mounts `initrd` or `initramfs` as a temporary root filesystem.
3. **Init system** — The kernel starts the first userspace process (`init` or `systemd`, PID 1), which reads its configuration and brings up system services.
4. **Login prompt** — A login manager starts: `getty` for a text console, or a display manager (GDM, LightDM) for a graphical login. After authentication, the user session begins.

### macOS

**Intel Macs:**

1. **EFI firmware** — Performs POST, initializes hardware, and selects the boot volume.
2. **boot.efi** — The bootloader loads the XNU kernel and required boot drivers (from a prelinked kernelcache when available).
3. **XNU kernel** — Initializes Mach and BSD subsystems and the I/O Kit (which links loaded drivers using the device tree), then mounts the root filesystem.
4. **launchd** — The first userspace process (PID 1) parses launch daemon plists and starts system services, including `WindowServer` (display server) and `loginwindow` (login UI).
5. **User session** — After authentication, `loginwindow` creates an Aqua session and launches Finder, Dock, and user agents.

**Apple Silicon Macs** follow the same flow but use **iBoot** instead of EFI + `boot.efi`.

### Boot Process Comparison

| Stage          | MS-DOS      | Windows 9x/ME         | Windows XP   | Windows Vista+         | Linux          | macOS              |
|----------------|-------------|-----------------------|--------------|------------------------|----------------|--------------------|
| Bootloader     | Boot sector | Boot sector → WIN.COM | NTLDR        | BOOTMGR → Winload.exe  | GRUB / LILO    | boot.efi / iBoot   |
| Kernel         | MSDOS.SYS   | IO.SYS → VMM32.VXD    | ntoskrnl.exe | ntoskrnl.exe           | vmlinuz        | XNU                |
| Init system    | CONFIG.SYS  | VxD init phases       | SMSS.EXE     | SMSS.EXE → Wininit.exe | init / systemd | launchd            |
| User interface | COMMAND.COM | explorer.exe          | explorer.exe | explorer.exe           | Shell or DE    | Aqua (loginwindow) |

---

[Next: Firmware: BIOS and UEFI →](02_firmware_bios_and_uefi.md)
