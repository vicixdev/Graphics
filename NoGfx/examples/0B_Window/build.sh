#!/usr/bin/env sh

xcrun -sdk macosx metal -frecord-sources -gline-tables-only -c ./vertex.metal -o ./vertex.air
xcrun -sdk macosx metal -frecord-sources -gline-tables-only -c ./fragment.metal -o ./fragment.air
xcrun -sdk macosx metallib ./vertex.air -o ./vertex.metallib
xcrun -sdk macosx metallib ./fragment.air -o ./fragment.metallib

cc main.c -I../../include -L../../build -lgpu -framework Metal -framework Foundation -framework QuartzCore -framework Cocoa -g -o out

