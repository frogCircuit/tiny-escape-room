<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Tiny Escape Room is a ten-room escape room in one tile. The seven-segment display shows the current room (0 to 9).
Clearing a room opens the next one, and clearing room 9 shifts out a flag. Each room is a small hardware puzzle.

This is work in progress. The pin names above are the planned pin plan; the rooms are not implemented yet.

## How to test

Set a code on the 8 input switches, then press the submit button (`uio[0]`) to try it. Some rooms use the serial
pins driven by the RP2040 on the Tiny Tapeout demo board. The source is public, and reading it is part of the game.

## External hardware

A push button on `uio[0]` for submit. An optional piezo buzzer on `uio[5]`.
