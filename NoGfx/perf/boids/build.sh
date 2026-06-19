#!/bin/sh

set -e

xcrun -sdk macosx metal -frecord-sources -gline-tables-only -c ./boids.metal -o ./boids.air
xcrun -sdk macosx metallib ./boids.air -o ./boids.metallib
xcrun -sdk macosx metal -frecord-sources -gline-tables-only -c ./boids.vertex.metal -o ./boids.vertex.air
xcrun -sdk macosx metallib ./boids.vertex.air -o ./boids.vertex.metallib
xcrun -sdk macosx metal -frecord-sources -gline-tables-only -c ./boids.fragment.metal -o ./boids.fragment.air
xcrun -sdk macosx metallib ./boids.fragment.air -o ./boids.fragment.metallib

if [[ "$1" = "metal" ]]; then
        cc _build.m -I../../include/ -O2 -g -o boids -framework Cocoa -framework Metal -framework QuartzCore -L../../build -lgpu -DMETAL4_RENDERER
else
        cc _build.m -I../../include/ -O2 -g -o boids -framework Cocoa -framework Metal -framework QuartzCore -L../../build -lgpu -DNOGFX_RENDERER
fi
