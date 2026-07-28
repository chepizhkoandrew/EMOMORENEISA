#!/bin/bash
# Usage: tap.sh <x_in_screenshot_px> <y_in_screenshot_px>
# Screenshot is 1320x2868, window is at 578,47 size 372x809
WX=578
WY=47
WW=372
WH=809
SW=1320
SH=2868
SX=$1
SY=$2
CX=$(python3 -c "print($WX + $SX * $WW / $SW)")
CY=$(python3 -c "print($WY + $SY * $WH / $SH)")
osascript -e 'tell application "Simulator" to activate'
sleep 0.5
osascript -e "tell application \"System Events\" to click at {$CX, $CY}"
