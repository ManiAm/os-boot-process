# Bootloaders

The [firmware chapter](02_firmware_bios_and_uefi.md) explained how BIOS and UEFI initialize hardware and hand off to a bootloader. But which bootloaders are out there? This chapter catalogs the major bootloader software that has been developed over the past three decades, from early DOS-era loaders to modern UEFI boot managers. The [next chapter](04_bootloader_rufus.md) then goes hands-on — disassembling a real MBR and FAT32 boot sector to see how a bootloader works at the machine-code level.

Most of the bootloaders listed below are **two-stage**: a small Stage 1 in the boot sector locates and loads a larger Stage 2 from the filesystem. A few (like Loadlin) are **single-stage** — they run entirely from within an already-loaded OS. In the UEFI era, the firmware itself plays the Stage 1 role (reading the ESP filesystem and loading the `.efi` binary), so UEFI bootloaders like `systemd-boot` and `rEFInd` are effectively single-stage applications.

## Catalog

### Linux

| Name | Year | Description |
|---|---|---|
| LILO | 1992 | Legacy two-stage bootloader, now obsolete |
| SYSLINUX | 1994 | Lightweight bootloader family (ISOLINUX, PXELINUX, EXTLINUX) |
| Loadlin | 1994 | Single-stage loader — boots Linux from a running DOS session |
| GRUB | 1995 | Two-stage bootloader; became a GNU project in 1999 |
| GRUB4DOS | 2003 | GRUB variant for DOS environments, used in recovery tools and bootable USBs |
| GNU GRUB 2 | 2012 | Complete rewrite of GRUB — modular, scriptable, default on most distros |

### Windows

| Name | Year | Description |
|---|---|---|
| NTLDR | 1993 | Windows NT/2000/XP bootloader, replaced by BOOTMGR in Vista |
| Windows Boot Manager | 2007 | BOOTMGR + Winload.exe — default bootloader since Vista |

### macOS / Apple

| Name | Year | Description |
|---|---|---|
| BootX (Linux) | 1998 | Third-party bootloader for Linux on PowerPC Macs |
| BootX (Apple) | 2001 | Apple's bootloader for Mac OS X on PowerPC (Open Firmware-based) |
| boot.efi | 2006 | Apple's EFI-based bootloader, introduced with Intel Macs |

### BSD

| Name | Year | Description |
|---|---|---|
| FreeBSD loader | 1999 | Native FreeBSD three-stage bootloader (boot0 → boot2 → loader) |

### Embedded

| Name | Year | Description |
|---|---|---|
| RedBoot | 2000 | Bootloader and debug monitor for embedded systems (eCos-based) |
| U-Boot | 2000 | Universal bootloader for ARM, MIPS, PowerPC, x86 embedded systems |
| Barebox | 2009 | Versatile bootloader for embedded systems (forked from U-Boot) |

### Boot Managers & Multi-boot

| Name | Year | Description |
|---|---|---|
| SPFdisk | 1998 | Partitioning tool with multi-boot management |
| XOSL | 1999 | Graphical multi-boot manager with partition hiding |
| GAG | 2001 | Graphical MBR-based boot manager (up to 9 OSes) |
| rEFInd | 2012 | Graphical EFI boot manager with auto-detection of OSes |
| systemd-boot | 2012 | Simple UEFI boot manager — originally gummiboot (2012), merged into systemd in 2015 |

### UEFI / Hackintosh

| Name | Year | Description |
|---|---|---|
| Clover | 2012 | Open-source EFI bootloader for macOS on non-Apple hardware (fork of rEFIt) |
| OpenCore | 2019 | Modern EFI bootloader designed for macOS, successor to Clover |
| Limine | 2020 | Modern bootloader supporting both UEFI and legacy BIOS |

### Other

| Name | Year | Description |
|---|---|---|
| Quibble | 2020 | Open-source UEFI bootloader that reimplements Windows Boot Manager (boots Windows from Btrfs, etc.) |

## LILO (Linux Loader)

LILO is one of the earliest bootloaders for Linux, introduced in 1992. It is a **two-stage** bootloader: Stage 1 resides in the MBR or boot sector, and Stage 2 is loaded from a map file (`/boot/map`) that records the raw disk locations of the kernel.

LILO is configured through `/etc/lilo.conf` and supports multi-boot setups. However, it requires reinstallation (by running the `lilo` command) every time the configuration or kernel changes — it cannot dynamically detect new kernels at boot time.

LILO has been largely replaced by GRUB due to its lack of filesystem awareness, graphical menus, and dynamic configuration. Most Linux distributions dropped LILO support by the mid-2010s.

## SYSLINUX

SYSLINUX (1994) is a family of lightweight two-stage bootloaders for booting Linux from FAT, ISO 9660, ext2/3/4, and network (PXE) media. It includes ISOLINUX, PXELINUX, and EXTLINUX variants.

→ **Hands-on walkthrough:** [Bootloader: Syslinux](05_bootloader_syslinux.md)

## Loadlin

Loadlin (1994) is a **single-stage** bootloader that loads a Linux kernel directly from a running DOS or Windows real-mode session. It copies the kernel into memory and transfers control to it, bypassing the normal MBR/boot-sector boot path entirely.

Loadlin was valuable during the early 1990s when dual-booting DOS and Linux was common but configuring LILO was difficult. It is largely obsolete today.

## GRUB (Grand Unified Bootloader)

GRUB (1995) is the most widely used bootloader in the Linux ecosystem. It is a two-stage bootloader with an optional Stage 1.5 that provides filesystem awareness before the OS is running. GRUB 2 (2012) is a complete rewrite — modular, scriptable, and the default on most Linux distributions.

→ **Hands-on walkthrough:** [Bootloader: GRUB](06_bootloader_grub.md)

## NTLDR (NT Loader)

NTLDR is the two-stage bootloader introduced with Windows NT 3.1 in 1993 and used through Windows XP and Server 2003:

- **Stage 1** — the boot sector loads `NTLDR` from the root of the active partition.
- **Stage 2** — `NTLDR` switches from real mode to protected mode, runs `NTDETECT.COM` to detect hardware, reads `BOOT.INI` for OS selection, and loads the Windows kernel (`ntoskrnl.exe`) and HAL.

NTLDR supports chainloading non-Windows operating systems via `BOOTSECT.DOS`. It was replaced by the Windows Boot Manager in Windows Vista.

## Windows Boot Manager

The Windows Boot Manager was introduced with Windows Vista (RTM November 2006, consumer release January 2007) and remains the default bootloader on all modern Windows versions. It replaced NTLDR with a cleaner two-component architecture:

- **BOOTMGR** — the first-stage boot manager. It is loaded by the boot sector (on BIOS systems) or directly by UEFI firmware from the ESP. BOOTMGR reads the **BCD** (Boot Configuration Data) store — a registry-like database that replaced NTLDR's text-based `BOOT.INI` — and displays the boot menu if multiple OSes or recovery options are available.

- **Winload.exe** — the second-stage OS loader. BOOTMGR hands off to `Winload.exe`, which loads the Windows kernel (`ntoskrnl.exe`), the HAL (`HAL.DLL`), and boot-start device drivers into memory.

On UEFI systems, BOOTMGR is stored on the ESP at `\EFI\Microsoft\Boot\bootmgfw.efi`. The BCD store can be managed from the command line using the `bcdedit` utility.

## Apple / Mac Bootloaders

Apple has used different bootloaders across its hardware generations:

- **BootX (Linux)** (1998) — a third-party bootloader by Benjamin Herrenschmidt for PowerPC-based Macs that enabled booting Linux alongside Mac OS. It loaded Linux kernels directly from the Mac OS environment.
- **BootX (Apple)** (2001–2006) — Apple's native bootloader for Mac OS X on PowerPC. Loaded by Open Firmware, it prepared the execution environment and launched the XNU kernel. Replaced by `boot.efi` when Apple transitioned to Intel processors.
- **boot.efi** (2006–2020) — the EFI-based bootloader introduced with Intel Macs. It initializes hardware via EFI services, locates the XNU kernel (typically from a prelinked kernelcache), and transfers control to the kernel.
- **iBoot** (2020–present) — the secure bootloader for Apple Silicon Macs, rooted in the Secure Enclave Boot ROM. It verifies the integrity of each boot stage before loading the kernel.

## SPFDisk (Special Fdisk)

SPFDisk (1998) is a combined partitioning tool and MBR-based boot manager. It provides an interface for creating and managing partitions, and includes basic multi-boot capabilities for selecting between installed operating systems. It is primarily of historical interest today.

## XOSL (Extended Operating System Loader)

XOSL (1999) is a graphical multi-boot manager that operates from the MBR. It features a point-and-click interface for selecting between installed operating systems, with support for partition hiding, password protection, and customizable boot menus. Development has ceased, but XOSL remains notable as one of the first graphical boot managers.

## GAG (Graphical Boot Manager)

GAG (2001) is a free, MBR-based graphical boot manager that supports up to nine operating systems. It runs directly from the MBR without requiring installation on any OS partition. GAG includes password protection and partition hiding but has become uncommon with the shift to UEFI.

## RedBoot

RedBoot (2000) is a bootloader and debug monitor for embedded systems, based on the eCos (Embedded Configurable Operating System) project. It supports booting from flash memory, RAM, or over the network via TFTP, and provides a command-line interface for hardware debugging.

RedBoot has been largely superseded by U-Boot and Barebox but remains in use on some legacy embedded platforms.

## U-Boot (Universal Boot Loader)

U-Boot (2000) is the most widely used open-source bootloader for embedded systems. It supports ARM, x86, PowerPC, MIPS, and RISC-V architectures. U-Boot is typically a **two-stage** bootloader:

- **SPL (Secondary Program Loader)** — a minimal first-stage loader that initializes DRAM and loads the full U-Boot binary.

- **U-Boot proper** — the full bootloader with a command-line interface, environment variables, scripting, and support for loading kernels from flash, SD cards, USB, TFTP, PXE, and NFS.

U-Boot is the standard bootloader for routers, single-board computers (Raspberry Pi alternatives), automotive systems, and IoT devices.

---

[← Previous: Firmware: BIOS and UEFI](02_firmware_bios_and_uefi.md) | [Next: Bootloader: Rufus →](04_bootloader_rufus.md)
