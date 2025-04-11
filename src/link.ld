MEMORY
{
    BOOT2_FLASH(rwx) : ORIGIN = 0x10000000, LENGTH = 256
    FLASH(rwx) : ORIGIN = 0x10000100, LENGTH = 2m - 256
    RAM(rwx) : ORIGIN =  0x20000000, LENGTH = 256k - 256
    BOOT2_RAM(rwx) : ORIGIN =  0x20041f00, LENGTH = 256
}

SECTIONS
{

    .boot2 : {
        __boot2_start__ = .;
        KEEP(*(.boot2))
        . = ALIGN(256);
        __boot2_end__ = .;
    } > BOOT2_RAM AT> BOOT2_FLASH

    .text : {
        *(.text .text.*);
    } > RAM AT> FLASH

    .rodata : {
        __rodata_start = .;
        *(.rodata .rodata.*);
    } > RAM AT> FLASH

    __text_start = LOADADDR(.text);
    __text_size = SIZEOF(.text);

    __rodata_flash_start = LOADADDR(.rodata);
    __rodata_size = SIZEOF(.rodata);

    /DISCARD/ : {
        *(.ARM .ARM.*)
    }

    ASSERT(__boot2_end__ - __boot2_start__ == 256,
        "ERROR: Pico second stage bootloader must be 256 bytes in size")
}

