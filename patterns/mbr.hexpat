#pragma description MBR (Master Boot Record)
#pragma endian little

struct PartitionEntry {
    u8  status         [[comment("0x80 = active, 0x00 = inactive")]];
    u8  chs_start[3]   [[comment("CHS address of first sector")]];
    u8  type           [[comment("Partition type (0x0C = FAT32 LBA)")]];
    u8  chs_end[3]     [[comment("CHS address of last sector")]];
    u32 lba_start      [[comment("LBA of first sector")]];
    u32 num_sectors    [[comment("Total sectors in partition")]];
};

struct MBR {
    u8  boot_code[440]              [[color("5B7FCC"), name("Boot Code (440 bytes)")]];
    u32 disk_signature              [[color("D4A843"), name("Disk Signature")]];
    u16 reserved                    [[color("808080"), name("Reserved")]];
    PartitionEntry partition_1      [[color("66BB6A"), name("Partition Entry 1")]];
    PartitionEntry partition_2      [[color("81C784"), name("Partition Entry 2")]];
    PartitionEntry partition_3      [[color("A5D6A7"), name("Partition Entry 3")]];
    PartitionEntry partition_4      [[color("C8E6C9"), name("Partition Entry 4")]];
    u16 boot_signature              [[color("EF5350"), name("Boot Signature (0xAA55)")]];
};

MBR mbr @ 0x00;
