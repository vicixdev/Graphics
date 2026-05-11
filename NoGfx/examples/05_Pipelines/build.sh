#!/usr/bin/env sh

xcrun -sdk macosx metal -frecord-sources -gline-tables-only -c ./kernel.metal -o ./kernel.air
xcrun -sdk macosx metallib ./kernel.air -o ./kernel.metallib
cc main.c -I../../include -L../../build -lgpu -framework Metal -framework Foundation -g -o out

