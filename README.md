# CDi_playground

A repo dedicated to create an FPGA implementation of the Philips CD-i to be usable for the MiSTer project

This repository is very experimental! Use at your own risk!

The currently planned first milestone is having the boot rom usable
on the MiSTer.
It requires no CDIC to function.


## Usage

Place `cdi200.rom` as `boot0.rom` in `/media/fat/games/CD-i`.
Place `zx405042p__cdi_slave_2.0__b43t__zzmk9213.mc68hc705c8a_withtestrom.7206` as `boot1.rom` next to it.

## Status

* CD-I MONO BOARD low level test is functional
	* ROM parity check passed
	* Dram test passed
	* Nvram test passed
	* Cdic test passed (tests only memory...)
	* Slave processor test passed
* MCD212
	* SDRAM interface according to specification
	* ICA/DCA parser partially implemented
	* CLUT7 RLE partially implemented
	* Display File partially implemented
* SCC68070
	* UART interface accessible from MiSTer linux
	* Timer IRQ implemented
	* Custom bus error frames implemented
* SLAVE
	* Interface to main CPU implemented
	* Answers to basic requests from main CPU
	* Maneuvering device simulated with MiSTer controller input
* SERVO
	* High level behaviour simulation of closed empty tray
* CDIC
	* N/A
* MiSTer
	* Rom loading via Menu functional
	* Automatic rom loading for main cpu and slave

Core Utilization:

	Logic utilization (in ALMs)	11,535 / 41,910 ( 28 % )
	Total block memory bits	630,196 / 5,662,720 ( 11 % )
	Total DSP Blocks	45 / 112 ( 40 % )

## TODOs in order of priority

* Investigate why F$Sleep returns E$NoClk
	* System clock not detected?
	* Date can not be changed in the system settings. Correlation? Only -1 and +1 possible
* Added remaining ICA/DCA features
* Implement the CDIC audio parts
* Implement the CDIC CD parts
* OSD setting for input device conformance (1200 baud)
* Fix I2C for the front display and show the display as picture in picture during changes?
	* It might not even be required at all.
* Have CD data available for the CDIC
* Use the MiSTer framework to save the NVRAM to sdcard
	* Only when changes are detected and when the OSD is opened
	* The N64 core does it like that to

## Expected checksums of roms

This core is tested with these ROMs:

	2969341396aa61e0143dc2351aaa6ef6  cdi200.rom
	3d20cf7550f1b723158b42a1fd5bac62  zx405042p__cdi_slave_2.0__b43t__zzmk9213.mc68hc705c8a_withtestrom.7206

Due to legal reasons, these files must be sourced separately.

