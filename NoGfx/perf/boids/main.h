#pragma once

#include <stdio.h>

#define RGFW_IMPLEMENTATION
#define RGFW_METAL
#define RGFW_NATIVE
#include "RGFW.h"

#include "timer.h"

#define BOID_PRESERVE 1024 * 512
#define BOID_COUNT 1024 * 3
#define WINDOW_WIDTH 640
#define WINDOW_HEIGHT 480

#define VISUAL_RANGE 75.0f
#define MIN_DISTANCE 20.0f
#define CENTERING_FACTOR 0.005f
#define AVOID_FACTOR 0.05f
#define MATCHING_FACTOR 0.05f
#define SPEED_LIMIT 15.0f
#define TURN_FACTOR 1.0f
#define EDGE_MARGIN 200.0f

typedef struct {
	float x;
	float y;
	float dx;
	float dy;
} Boid;


typedef struct {
	RGFW_window* window;

	Boid* boids;
	int boidCount;
	FrameTimer updateTimer;
} State;
extern State gState;
