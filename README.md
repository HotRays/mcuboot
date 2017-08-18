***
# BOARD specification #
- **SoC model**: Nordic nRF51822_QFAA
- **CPU**: ARM Cortex-M0
- **RAM**: 16KB SRAM
- **ROM**: 256KB NOR Flash
***
# Operating system specification #
- **Zephyr v1.8.0**
***
# Issues came up during development #
The mcuboot is just like a ordinary app running on zephyr kernel. Easily make it running on board nrf51_polyu by reading **REAMME-zephyr.rst**
## Image text offset BUG ##
When we put signed image into slot0's address, the bootloader crashed with **Hard Fault** occurs.
The reason cause the bug is illustrated in following image.

**Let's asume that:**
- Func1 will be linked into address 0x100 at link stage
- Func2 will be linked into address 0x200 at link stage
- Func2 will call func1 right before return to caller
- Slot0 text offset at address of 0x8000

```
--------------------------------------------------------------
|  code start of image  |  func1  |  func2 call func1@0x100  |
--------------------------------------------------------------
0x0                     0x100     0x200


-----------------------------------------------------------------------------
|  bootloader  |  code start of image  |  func1  |  func2 call func1@0x100  |
-----------------------------------------------------------------------------
0x0            0x8000                  0x8100    0x82000
```
The top of this image is normally code layout in flash, and the bottom is code layout in flash with bootloader reside at address of 0x0.

The gnu linker only put .out together and fix the address refer problem. The refer to func1 in func2 will be address 0x100 (abslute address referance). If we load the final bin file into address 0x8000, for func1 refered by func2 will not be at address of 0x100 but address of 0x8100. Once the SoC runs to func2, the PC pointer will point to 0x100 where is the bootloader's code reside.
### Fix plan ###
- If we set **CONFIG_TEXT_SECTION_OFFSET** to 0x8000, the final image size will great than 0x8000 will "zero hole" bettwen 0x0 and 0x8000(no signed).
- Fortunately, zephyr newest version after v1.8.0 release support flash partition dts description. Commit log can be find at *[https://github.com/zephyrproject-rtos/zephyr/commit/91f67a13f7836a0c516f3e3044338b438df63b3b](https://github.com/zephyrproject-rtos/zephyr/commit/91f67a13f7836a0c516f3e3044338b438df63b3b "Flash partition support")*.
- We described the flash partition of app where to put the code, and the gnu linker will automaticly add fixed address offset for all .out files.
- For more information please refer to **$(ZEPHYR_BASE)/dts/arm/nrf51_polyu.dts**
***
## Interrupt vector table BUG ##
By reading **ARM®v6-M Architecture Reference Manual**, **Cortex™-M0 Devices Generic User Guide** and **The Definitive Guide to the ARM Cortex-M0** we find that the IRQ handler in **ARM Cortex-M0** is very simple. Here is an simple figure illustraed as follow. Developer can check the interrupt related chapter of one of above three books.
```
-----------------------------------------------
|  vector table of bootloader  |  other code  |
-----------------------------------------------
0x0                            0xC0


|                bootloader                   |                slot0                   |
----------------------------------------------------------------------------------------
|  vector table of bootloader  |  other code  |  vector table of slot0  |  other code  |
----------------------------------------------------------------------------------------
0x0                            0xC0           0x8000                    0x80C0
```
### Fix plan ###
Nordic nRF51822 with **ARM Cortex-M0** CPU are [not support](https://devzone.nordicsemi.com/question/139887/interrupt-vectors-remap/ "Interrupt Vectors REMAP") interrupter vector table remap and VTOR(Vector Table Offset Register, this feature is supported by **ARM Cortex-M3** and above). Fortunately, we have another way introduced [here](https://devzone.nordicsemi.com/question/33621/how-to-make-the-nrf51822-flash-jump-successful-without-softdevice/?answer=33678#post-id-33678 "Bootloader without softdevice") to solve this kind of problem by **forward interrupter handler control** into slo0 as illustrated in following figure.
```
|       kernel independent irq forward handler       |                  bootloader                 |                slot0                   |
---------------------------------------------------------------------------------------------------------------------------------------------
|  irq forward vector table  |  irq forward handler  |  vector table of bootloader  |  other code  |  vector table of slot0  |  other code  |
---------------------------------------------------------------------------------------------------------------------------------------------
0x0                          0x100                   0x200                          0x2C0          0x8000                    0x80C0
```
Set an interrupter forwarder for all system exceptions and external interrupters at fixed address. And a flag in SRAM idicate the current interrupt is for bootloader or for slot0 to determine wher to jump exactly.

**Note**: The irq forward handler **MUST NOT** do any modify to the memory during the hole time.
***
## Thumb/Thumb2 instruction set BUG ##
By reading the source code of decompile of softdevice, we find the each vector in vector table has lsb(least significant bit) set to 1. And some instruct affected the PC pointer, has a little bit offset ahead about 4 byte.

- PC offset problem
The ARM Cortex-M0 CPU core have 3-stage pipe line design. In assembly language, the one instruction operate on PC pointer need be very careful. Gnu gcc/as tools will automaticly add such offset to its final binary code, use one of B/BL/BX/BLX instruction may not be bad effective in any code in this project.

- Vector LSB set to 1 problem
	ARM Cortex-M series is design to be backforward compatibility with ARM Cortex-R/A series. In ARM Cortex-A series, the lsb in PC pointer set to 1 means that the next instruction is a Thumb/Thumb2 instruction; the lsb in PC pointer set to 0 means that the next instruction is an ARM instruction.

	Here is a referance of **Chapter 2.3.4. Vector table** of **Cortex-M0 Devices Generic User Guide**:
	>The vector table contains the reset value of the stack pointer, and the start addresses, also called exception vectors, for all exception handlers. Figure 2.1 shows the order of the exception vectors in the vector table. **The least-significant bit of each vector must be 1, indicating that the exception handler is written in Thumb code**.

***
# Known issues #
1. Image sign is tested not pass

	When load an signed image into flash@slot0, the mcuboot will always detecte the image in slot0 is compromised and abort chain load image mission. At develop stage, we intended disable of macor define **MCUBOOT_VALIDDATE_SLOT0** so the mcuboot will not interested in integrity of image in slot0.

2. Zephyr v1.8.0 branch did not support flash partition dts description

	When compile the mcuboot with dts flash partition desctipted, may will get compile error of missing define of **FLASH_AREA_IMAGE0_OFFSET**, **FLASH_AREA_IMAGE0_SIZE** etc. Due to the flash partition description did not parsed into **generated_dts_board.config** and **generated_dts_board.h**.

	Fix plan is alredy commited into master branch after **v1.8.0** branch was released: *[https://github.com/zephyrproject-rtos/zephyr/commit/91f67a13f7836a0c516f3e3044338b438df63b3b](https://github.com/zephyrproject-rtos/zephyr/commit/91f67a13f7836a0c516f3e3044338b438df63b3b "Flash partition support")*

3. Mcuboot board's dts overlay not supported
	The board nrf51_polyu's dts file is in **$(ZEPHYR_BASE)/dts/arm**
4. Kernel config need enable **CONFIG_IS_BOOTLOADER** by default

***