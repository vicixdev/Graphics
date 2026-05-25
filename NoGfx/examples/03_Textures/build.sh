#!/usr/bin/env sh

cc main.c -I../../include -L../../build -lgpu -framework Metal -framework Foundation -framework QuartzCore -g -o out

