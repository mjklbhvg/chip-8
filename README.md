# Chip-8 Emulator and Assembler in hare

Please note that these are my first attempts at hare,
so there are probably many bugs :)

This uses the terminal as the display, which
makes Input pretty bad.
Sound is "implemented" using the terminal bell.
![Pong](screenshot.png "The included test.asm example running in Alacritty")

## Resources:
* http://devernay.free.fr/hacks/chip8/C8TECH10.HTM
* https://en.wikipedia.org/wiki/CHIP-8

## Run:
You will need the hare build tool and compiler:
https://harelang.org/installation/
After that it should be just:
```
hare build
./chip8 test.asm
```
