# Bootloader: Syslinux

The [Rufus chapter](04_bootloader_rufus.md) examined a Rufus MBR bootloader that boots MS-DOS from a USB drive — a custom bootloader focused on the USB boot experience. This chapter examines the **Syslinux** MBR bootloader used by Alpine Linux. Both are 446-byte programs, but they solve different problems: Rufus focuses on user interaction and multi-disk support, while Syslinux focuses on robust partition handling and general-purpose booting.

The [next chapter](06_bootloader_grub.md) examines GRUB, which takes the opposite approach — a three-stage architecture with filesystem awareness and a full scripting environment.

## What Is Syslinux?

Syslinux (1994) is a family of lightweight bootloaders designed for booting Linux from various media. It uses a **two-stage** architecture: a small boot sector program (Stage 1) loads the main Syslinux binary (Stage 2) from the filesystem.

The Syslinux family includes several specialized variants, each targeting a different boot medium:

| Variant      | Boot Medium        | Use Case |
|--------------|--------------------|----------|
| **SYSLINUX** | FAT filesystems    | USB drives, floppy disks |
| **ISOLINUX** | ISO 9660           | CD/DVD boot |
| **PXELINUX** | Network (PXE/TFTP) | Diskless boot, OS deployment (see [Boot Over Network](08_boot_over_network.md)) |
| **EXTLINUX** | ext2/3/4, Btrfs    | Installed Linux systems |

Syslinux supports menu-driven interfaces and chainloading of other bootloaders. It remains widely used for live USB drives, rescue disks, and embedded systems.

## Hands-On — Alpine Linux

[Alpine Linux](https://alpinelinux.org/) is a lightweight, security-oriented distribution popular in containers and embedded systems. It uses Syslinux as its default bootloader.

### Creating the Bootable USB

1. Download the **Standard x86_64** ISO from [alpinelinux.org/downloads](https://alpinelinux.org/downloads/).
2. Launch [Rufus](https://rufus.ie/) and select the Alpine ISO.
3. Write the image to a USB drive (MBR partition scheme, BIOS target).

Once the bootable USB is created, open it in [ImHex](https://imhex.werwolv.net/) to inspect the MBR — the same approach used in the [Rufus chapter](04_bootloader_rufus.md).

## MBR Bootloader — How It Works

The following sections walk through the Syslinux MBR using the actual source code — the same step-by-step approach used for the Rufus MBR in [Chapter 4](04_bootloader_rufus.md).

**MBR source code:** [syslinux/mbr/mbr.S](https://github.com/Sha0/syslinux/blob/01fc061d9851463296347d3834185ea5c5618a68/mbr/mbr.S)

> **Syntax note:** The code below is shown in Intel-style syntax with `#` comments for readability. The original Syslinux source uses AT&T/GAS syntax (operands reversed, `%` register prefix).

### Boot Flow Overview

Syslinux is **two-stage**: the MBR and VBR together form Stage 1, and their combined job is to get `ldlinux.sys` (Stage 2) into memory:

| Stage         | Component                 | Role                                               |
|---------------|---------------------------|----------------------------------------------------|
| Stage 1 (MBR) | MBR boot code (446 bytes) | Scans partition table, loads VBR of the active partition |
| Stage 1 (VBR) | Partition boot sector     | Reads the FAT filesystem to locate and load `ldlinux.sys` |
| Stage 2       | `ldlinux.sys`             | Core Syslinux binary — reads `syslinux.cfg`, displays boot menu, loads the Linux kernel and initramfs |

When the BIOS finishes POST, it loads the MBR (512 bytes) from the USB disk into memory at address `0x7C00` and jumps to it. The Syslinux MBR then:

1. **Relocates itself** — copies itself to `0x0600` to free `0x7C00` for the VBR it will load later.
2. **Detects EBIOS** — checks whether the BIOS supports LBA disk access (INT 13h extensions), and if so, patches the disk read routine at runtime.
3. **Queries disk geometry** — gets CHS parameters from the BIOS (used as a fallback if EBIOS is unavailable).
4. **Scans the partition table** for an active partition — including recursive traversal of extended partition chains.
5. **Loads and validates the VBR** — reads the boot sector of the active partition into `0x7C00` and checks for the `0xAA55` signature.
6. **Jumps to the VBR** — restores registers and transfers control.

### Step 1 — Self-Relocation

Like the Rufus MBR, the first job is to copy itself out of `0x7C00` to free that address for the VBR. Syslinux uses the standard relocation address `0x0600` — just above the BIOS data area:

```asm
_start:
    cli                    # disable interrupts during stack setup
    xor  ax, ax
    mov  ds, ax            # DS = 0
    mov  ss, ax            # SS = 0
    mov  sp, 0x7C00        # stack grows downward from 0x7C00
    mov  si, sp            # SI = 0x7C00 (source address)
    push es                # save ES:DI → $PnP header (passed by BIOS)
    push di
    mov  es, ax            # ES = 0
    sti                    # re-enable interrupts
    cld                    # clear direction flag (forward copy)

    mov  di, 0x0600        # DI = destination address
    mov  cx, 256           # 256 words = 512 bytes
    rep  movsw             # copy MBR: 0:0x7C00 → 0:0x0600

    ljmp 0:next            # far jump to the relocated copy
next:
    push dx                # save DL (drive number from BIOS)
```

> **Relocation address:** The Rufus MBR steals 1 KB from the top of conventional memory and uses a segment trick to keep `0x7C00`-based offsets. Syslinux takes the simpler, more conventional approach — it copies to the fixed address `0x0600` (used by most standard MBRs). Both achieve the same goal: free `0x7C00` for the VBR.

The `push es` / `push di` pair saves the **$PnP header pointer** that the BIOS passed in `ES:DI`. These values are restored in Step 6 before jumping to the VBR — some VBRs (and Syslinux's own) use this pointer to query Plug-and-Play BIOS services.

After the `ljmp`, execution continues at `next:` in the relocated copy at `0x0600`. The `push dx` saves the drive number (in `DL`) that the BIOS passed — the VBR will need it to know which disk to read from.

### Step 2 — EBIOS Detection

Before reading any sectors, the MBR checks whether the BIOS supports **Extended Disk Services** (EBIOS) — the LBA-based INT 13h functions that can address disks larger than the 8 GB CHS limit:

```asm
    push dx                # save drive number
    mov  ah, 0x41          # INT 13h function 41h: check extensions
    mov  bx, 0x55AA        # magic number
    xor  cx, cx
    xor  dh, dh
    stc                    # pre-set carry (some BIOSes don't clear it on failure)
    int  0x13              # ask BIOS: does this drive support EBIOS?
    jc   no_ebios          # carry set → not supported
    cmp  bx, 0xAA55        # BIOS must return the magic reversed
    jne  no_ebios
    shr  cx, 1             # bit 0 of CX = fixed disk access subset
    jnc  no_ebios

    # EBIOS available — patch the CHS read code to use LBA instead
    mov  dword [read_sector_cbios], <patched_bytes>

no_ebios:
    pop  dx                # restore drive number
```

The last four lines before `no_ebios` are the cleverest part of the entire MBR. Instead of adding a runtime `if EBIOS then ... else ...` branch on every disk read, Syslinux **overwrites its own code** — it patches the first 4 bytes of the CHS read routine (`read_sector_cbios`) with:

```asm
    mov  ah, 0x42          # INT 13h function 42h: extended read (LBA)
    jmp  read_common       # skip the CHS conversion entirely
```

From this point on, every call to `read_sector` automatically uses LBA. The CHS code is gone — physically overwritten in memory. This is called **runtime code patching** (or self-modifying code), and it eliminates a branch from every disk read without using any extra bytes.

### Step 3 — Disk Geometry

Even if EBIOS is available, the MBR still queries the CHS geometry — the `sectors` and `secpercyl` values are needed if the EBIOS check failed and the CHS path was not patched out:

```asm
    mov  ah, 0x08          # INT 13h function 08h: get drive parameters
    int  0x13
    and  cx, 0x3F          # extract sectors per track (bits 0–5)
    push cx                # save on stack → [sectors]
    movzx ax, dh           # DH = max head number (0-based)
    inc  ax                # convert to count (1-based)
    mul  cx                # AX = heads × sectors = sectors per cylinder

    push dx                # save high word of result → [secpercyl+2]
    push ax                # save low word of result → [secpercyl]
```

These values are pushed onto the stack at known offsets, forming the stack frame that `read_sector` references by address:

```
    ┌──────────────────┐ ← 0x7C00 (bootsec / VBR loads here)
    │  ES (PnP segment)│ ← 0x7BFE (saved in Step 1)
    │  DI (PnP offset) │ ← 0x7BFC (saved in Step 1)
    │  DX (drive no.)  │ ← 0x7BFA [driveno]
    │  sectors/track   │ ← 0x7BF8 [sectors]
    │  sec/cyl (high)  │ ← 0x7BF6 [secpercyl+2]
    │  sec/cyl (low)   │ ← 0x7BF4 [secpercyl]
    └──────────────────┘ ← SP after Step 3
```

### Step 4 — Scan the Partition Table

With disk I/O ready, the MBR begins its main task: finding an active partition to boot. The `scan_partition_table` routine is called with the MBR itself as the starting point:

```asm
    xor  eax, eax          # base = 0 (sector 0 = the MBR)
    cdq                    # root = 0 (sign-extend EAX into EDX)
    call scan_partition_table

    # If scan_partition_table returns, no bootable partition was found
    call error
    .ascii "Missing operating system.\r\n"
```

If the scan returns (instead of jumping to `boot`), it means no active partition was found anywhere — not in the primary table, and not in any extended partition chain. The MBR prints an error and halts.

The scan itself has two phases:

#### Phase A — Search the four primary entries

```asm
scan_partition_table:
    pushal
    mov  bp, sp            # BP → stack frame (for accessing base/root later)

    mov  bx, ptab          # BX → partition table buffer (at 0x07BE)
    mov  cx, 4             # four entries
    xor  ax, ax            # active count = 0
    push bx
    push cx

check_entry:
    test byte [bx], 0x80   # is the active flag set?
    jz   skip_entry
    inc  ax                # count this active entry
    mov  si, bx            # SI → remember this entry
skip_entry:
    add  bx, 16            # next entry (16 bytes each)
    loop check_entry

    dec  ax                # exactly 1 active partition?
    jz   boot              # yes → boot it (Step 5)
    jns  too_many_active   # more than 1 → error
```

If exactly one active partition is found, execution jumps to `boot` (Step 5). If more than one:

```asm
too_many_active:
    call error
    .ascii "Multiple active partitions.\r\n"
```

#### Phase B — Search extended partitions (recursive)

If no active partition was found in the primary table (`AX` went from 0 to −1), the scan looks for extended partition entries (types `0x05`, `0x0F`, or `0x85`) and follows them recursively:

```asm
    pop  cx                # CX = 4
    pop  bx                # BX → partition table buffer

search_extended:
    mov  al, [bx+4]        # partition type byte
    cmp  al, 0x0F          # Win9x extended?
    je   found_extended
    and  al, 0x7F          # clear bit 7 (turns 0x85 into 0x05)
    cmp  al, 0x05          # MS-DOS extended?
    jne  next_entry

found_extended:
    mov  eax, [bx+8]       # LBA start of the extended partition
    mov  edx, [bp+20]      # root (0 for MBR, or the first extended partition's LBA)
    add  eax, edx          # compute absolute sector address
    and  edx, edx          # is this the MBR level?
    jnz  not_mbr
    mov  edx, eax          # first extended partition becomes the root
not_mbr:
    call read_partition_table   # read the extended partition's boot record
    jc   reload
    call scan_partition_table   # ← RECURSIVE CALL

reload:
    mov  eax, [bp+28]      # reload base (current table was overwritten)
    call read_partition_table

next_entry:
    add  bx, 16
    loop search_extended

    popal                  # nothing found — return to caller
    ret
```

> **Why recursion?** Extended partitions form a linked list: each Extended Boot Record (EBR) contains one logical partition and optionally a pointer to the next EBR. The MBR must follow this chain to find an active partition that may be several levels deep. The `read_partition_table` helper reads a sector into `0x7C00` and copies its 64-byte partition table into a buffer at `0x07BE` (inside the relocated MBR area) so it can be scanned without being overwritten by the next read. For a detailed breakdown of the MBR and extended partition structures, see [MBR](https://github.com/ManiAm/storage-and-file-systems/blob/master/docs/04_mbr.md) in the Disk Storage project.

### Step 5 — Load and Validate the VBR

When an active partition is found (in either a primary or extended table), `boot` is reached:

```asm
boot:
    mov  eax, [si+8]       # LBA start of the active partition
    add  eax, [bp+28]      # add the partition table's base offset
    mov  [si+8], eax       # update the entry with the absolute LBA
    call read_sector        # read VBR into 0x7C00
    jc   disk_error         # read failed → error

    cmp  word [0x7DFE], 0xAA55   # check the boot signature
    jne  missing_os              # invalid → "Missing operating system"
```

The `mov [si+8], eax` line updates the partition entry in memory with the absolute LBA — this is important because the VBR may inspect its own partition entry (some VBRs use the LBA to locate the partition on disk).

Unlike the Rufus MBR (which trusts whatever it loads), Syslinux **validates the boot signature** before jumping. If the loaded sector does not end with `0xAA55`, the MBR treats it as "Missing operating system" rather than jumping to garbage code.

If the disk read itself fails:

```asm
disk_error:
    call error
    .ascii "Operating system load error.\r\n"
```

### Step 6 — Jump to the VBR

With a validated VBR at `0x7C00`, the MBR restores the register state that the VBR expects and jumps:

```asm
    mov  sp, driveno        # SP → 0x7BFA (saved values on the stack)
    pop  dx                 # DL = drive number (saved in Step 1)
    pop  di                 # DI = PnP offset (saved in Step 1)
    pop  es                 # ES = PnP segment (saved in Step 1)
    cli                     # disable interrupts for the jump
    jmp  sp                 # SP = 0x7C00 → jump to VBR!
```

The `jmp sp` is a space-saving trick. After the three pops, `SP` lands exactly at `0x7C00` — the start of the VBR. Instead of encoding a separate `jmp 0x7C00` instruction (3 bytes), `jmp sp` reuses the stack pointer as the jump target (2 bytes). Every byte matters in 446 bytes of boot code.

The VBR receives:
- **DL** = drive number (so it knows which disk to read from)
- **ES:DI** = $PnP BIOS header pointer (for Plug-and-Play services)
- **0x7C00** = the VBR itself in memory

From this point on, the MBR's job is done. The VBR takes over, reads the FAT filesystem to locate `ldlinux.sys`, and loads Stage 2 of the Syslinux boot process.

### The read_sector Routine

Every disk read in the MBR goes through `read_sector`. It builds a **Disk Address Packet (DAP)** on the stack and then either uses EBIOS (if patched in Step 2) or falls back to CHS:

```asm
read_sector:
    pushal
    xor  edx, edx
    mov  bx, 0x7C00        # buffer address

    # Build the DAP on the stack
    push edx               # upper 32 bits of LBA (always 0)
    push eax               # lower 32 bits of LBA
    push es                # buffer segment
    push bx                # buffer offset
    push 1                 # sector count
    push 16                # DAP size (16 bytes)
    mov  si, sp            # SI → DAP

    # --- CHS path (or EBIOS if patched) ---
read_sector_cbios:         # ← this code is overwritten if EBIOS detected
    div  dword [secpercyl] # EAX = cylinder, EDX = remainder
    shl  ah, 6             # cylinder high bits → bits 6–7
    mov  cl, ah
    mov  ch, al            # CH = cylinder low, CL bits 6–7 = cylinder high
    xchg dx, ax
    div  byte [sectors]    # AL = head, AH = sector (0-based)
    mov  dh, al            # DH = head
    or   cl, ah
    inc  cx                # sectors are 1-based
    mov  ax, 0x0201        # AH=02 (read), AL=01 (1 sector)

    # --- Common path (both CHS and EBIOS arrive here) ---
read_common:
    mov  dl, [driveno]     # drive number
    int  0x13              # BIOS disk services
    lea  sp, [si+16]       # drop the DAP from the stack
    popal
    ret
```

When EBIOS is available, the runtime patch from Step 2 replaces `read_sector_cbios` with `mov ah, 0x42; jmp read_common` — the CHS conversion code is skipped entirely, and INT 13h receives the DAP for an LBA read instead.

### The error Routine

All three error messages use the same compact print-and-halt routine. The `call error` instruction pushes the return address — which points to the error string — onto the stack. The `error` routine pops it and prints characters until it hits a newline:

```asm
error:
    pop  si                # SI = return address = start of string
print_loop:
    lodsb                  # load next character
    mov  ah, 0x0E          # INT 10h: teletype output
    mov  bh, [BIOS_page]   # current display page
    mov  bl, 0x07          # light gray on black
    int  0x10              # print character
    cmp  al, 10            # newline (\n)?
    jne  print_loop        # keep printing

    int  0x18              # signal boot failure (BIOS tries next device)
die:
    hlt
    jmp  die               # hang if INT 18h returns
```

This "string after `call`" technique is a classic trick for embedding error messages directly in the code flow — it avoids needing a separate data section and a pointer to each string, saving precious bytes.

### MBR Boot Summary

```
 BIOS loads Syslinux MBR → 0x7C00
       │
       ▼
 Step 1: Relocate to 0x0600
       │
       ▼
 Step 2: Detect EBIOS → patch read routine (if supported)
       │
       ▼
 Step 3: Query CHS geometry
       │
       ▼
 Step 4: Scan partition table for active entry
       │
       ├─ found 0 → search extended partitions (recursive)
       │              │
       │              ├─ found active → boot it
       │              │
       │              └─ none found → "Missing operating system"
       │
       ├─ found 1 → boot it
       │
       └─ found 2+ → "Multiple active partitions"
                          │
                          ▼
 Step 5: Load VBR into 0x7C00
       │
       ├─ read failed → "Operating system load error"
       │
       ├─ no 0xAA55 → "Missing operating system"
       │
       ▼
 Step 6: Restore registers, jmp sp → VBR at 0x7C00
       │
       ▼
 VBR loads ldlinux.sys → Stage 2 takes over
```

## How It Compares to the Rufus MBR

Both the Syslinux and Rufus MBRs are sophisticated programs that fill the same 446 bytes, but they prioritize different capabilities:

| Feature | Rufus MBR ([Ch. 4](04_bootloader_rufus.md)) | Syslinux MBR |
|---|---|---|
| **Partition scan** | 4 primary entries only | Primary + **extended partitions** (recursive traversal) |
| **Extended partition support** | No | Yes — follows chains of type `0x05`, `0x0F`, `0x85` |
| **EBIOS (LBA) detection** | No (delegated to VBR) | Yes — runtime code patching to switch CHS ↔ LBA |
| **CHS fallback** | No (delegated to VBR) | Yes — built into the MBR read routine |
| **Boot sector validation** | No (trusts VBR) | Yes — checks `0xAA55` before jumping |
| **Error messages** | None | 3: "Missing operating system", "Multiple active partitions", "Operating system load error" |
| **Read another disk's MBR** | Yes (drive `0x81`) | No |
| **User prompt / timeout** | Yes (RTC-based countdown) | No |
| **Disk-swap mechanism** | Yes (INT 13h hook) | No |
| **Self-relocation** | Steals 1 KB from top of RAM, adjusts segment | Standard copy to `0x0600` |

**Rufus** is purpose-built for USB boot — it reads another disk, prompts the user, and installs a disk-swap hook. These features are specific to the "boot from USB with a fallback to the internal drive" use case.

**Syslinux** is a general-purpose MBR — it handles any partition layout (including extended partitions nested inside logical drives), detects LBA support at the MBR level, validates the boot sector before jumping, and provides descriptive error messages. This makes it robust across a wider range of disk configurations.

> **Common ground:** Both MBRs use **BIOS INT 13h** for all disk I/O, relocate themselves to free `0x7C00`, scan the partition table for an active entry, and load the VBR of that partition.

---

[← Previous: Bootloader: Rufus](04_bootloader_rufus.md) | [Next: Bootloader: GRUB →](06_bootloader_grub.md)
