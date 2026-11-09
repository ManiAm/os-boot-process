# OS Boot Process

A ground-up walkthrough of the OS boot sequence — CPU reset, BIOS/UEFI, bootloaders, kernel initialization, and hands-on boot-sector disassembly.

## Boot Sequence & Overview

| #  | Topic                                                          | Description |
| -- | -------------------------------------------------------------- | ------------------------------------------------------ |
| 01 | [OS Boot Process](docs/01_os_boot_process.md)                  | CPU reset, firmware, POST, boot overview for multiple OSes |
| 02 | [Firmware: BIOS and UEFI](docs/02_firmware_bios_and_uefi.md)   | BIOS vs UEFI, POST, CMOS/NVRAM, Secure Boot, UEFI Boot Manager |
| 03 | [Bootloaders](docs/03_bootloaders.md)                          | Bootloader software catalog (LILO, SYSLINUX, GRUB, U-Boot, etc.) |

## Bootloader Deep Dives

| #  | Topic                                                     | Description |
| -- | --------------------------------------------------------- | ----------------------------------------------------------- |
| 04 | [Bootloader: Rufus](docs/04_bootloader_rufus.md)          | Hands-on MBR/VBR bootloader disassembly, FAT32 boot sector analysis |
| 05 | [Bootloader: Syslinux](docs/05_bootloader_syslinux.md)    | Syslinux MBR bootloader — Alpine Linux, scan-and-chainload design |
| 06 | [Bootloader: GRUB](docs/06_bootloader_grub.md)            | GRUB three-stage architecture — Ubuntu, core.img, filesystem awareness |

## Multi-Boot & Network Boot

| #  | Topic                                              | Description |
| -- | -------------------------------------------------- | ----------------------------------------- |
| 07 | [Dual Boot](docs/07_dualboot.md)                   | Windows + Linux dual boot — chainloading, os-prober, installation order |
| 08 | [Boot Over Network](docs/08_boot_over_network.md)  | PXE, PXELINUX, iPXE, HTTP Boot — booting from the network |

## Network Provisioning

| #  | Topic                                              | Description |
| -- | -------------------------------------------------- | ----------------------------------------- |
| 09 | [ONIE](docs/09_onie.md)                            | Open Network Install Environment — bare-metal switch provisioning |
