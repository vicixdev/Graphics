#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "main.h"
#include "renderer.h"

State gState;

float randomFloat(float min, float max) {
	return min + (max - min) * ((float)rand() / (float)RAND_MAX);
}

void initBoid(Boid* boid) {
	boid->x = randomFloat(0.0f, (float)WINDOW_WIDTH);
	boid->y = randomFloat(0.0f, (float)WINDOW_HEIGHT);
	boid->dx = randomFloat(-5.0f, 5.0f);
	boid->dy = randomFloat(-5.0f, 5.0f);
}

float distanceBoids(const Boid* boid1, const Boid* boid2) {
	float dx = boid1->x - boid2->x;
	float dy = boid1->y - boid2->y;
	return sqrtf(dx * dx + dy * dy);
}

void keepWithinBounds(Boid* boid) {
	if (boid->x < EDGE_MARGIN) {
		boid->dx += TURN_FACTOR;
	}
	if (boid->x > (float)WINDOW_WIDTH - EDGE_MARGIN) {
		boid->dx -= TURN_FACTOR;
	}
	if (boid->y < EDGE_MARGIN) {
		boid->dy += TURN_FACTOR;
	}
	if (boid->y > (float)WINDOW_HEIGHT - EDGE_MARGIN) {
		boid->dy -= TURN_FACTOR;
	}
}

void flyTowardsCenter(Boid* boid) {
	float centerX = 0.0f;
	float centerY = 0.0f;
	int numNeighbors = 0;

	for (int i = 0; i < gState.boidCount; i++) {
		Boid* otherBoid = &gState.boids[i];
		if (distanceBoids(boid, otherBoid) < VISUAL_RANGE) {
			centerX += otherBoid->x;
			centerY += otherBoid->y;
			numNeighbors += 1;
		}
	}

	if (numNeighbors > 0) {
		centerX /= (float)numNeighbors;
		centerY /= (float)numNeighbors;
		boid->dx += (centerX - boid->x) * CENTERING_FACTOR;
		boid->dy += (centerY - boid->y) * CENTERING_FACTOR;
	}
}

void avoidOthers(Boid* boid) {
	float moveX = 0.0f;
	float moveY = 0.0f;

	for (int i = 0; i < gState.boidCount; i++) {
		Boid* otherBoid = &gState.boids[i];
		if (otherBoid != boid && distanceBoids(boid, otherBoid) < MIN_DISTANCE) {
			moveX += boid->x - otherBoid->x;
			moveY += boid->y - otherBoid->y;
		}
	}

	boid->dx += moveX * AVOID_FACTOR;
	boid->dy += moveY * AVOID_FACTOR;
}

void matchVelocity(Boid* boid) {
	float avgDX = 0.0f;
	float avgDY = 0.0f;
	int numNeighbors = 0;

	for (int i = 0; i < gState.boidCount; i++) {
		Boid* otherBoid = &gState.boids[i];
		if (distanceBoids(boid, otherBoid) < VISUAL_RANGE) {
			avgDX += otherBoid->dx;
			avgDY += otherBoid->dy;
			numNeighbors += 1;
		}
	}

	if (numNeighbors > 0) {
		avgDX /= (float)numNeighbors;
		avgDY /= (float)numNeighbors;
		boid->dx += (avgDX - boid->dx) * MATCHING_FACTOR;
		boid->dy += (avgDY - boid->dy) * MATCHING_FACTOR;
	}
}

void limitSpeed(Boid* boid) {
	float speed = sqrtf(boid->dx * boid->dx + boid->dy * boid->dy);
	if (speed > SPEED_LIMIT) {
		boid->dx = (boid->dx / speed) * SPEED_LIMIT;
		boid->dy = (boid->dy / speed) * SPEED_LIMIT;
	}
}

void init(void) {
	gState.window = RGFW_createWindow("Boids", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, RGFW_windowNoResize);
	assert(gState.window);

	gState.boids = (Boid*)calloc(BOID_PRESERVE, sizeof(Boid));
	gState.boidCount = BOID_COUNT;

	for (int i = 0; i < gState.boidCount; i++) {
		initBoid(&gState.boids[i]);
	}

	frameTimerInit(&gState.updateTimer, "boid update");

	initRenderer();
}

void fini(void) {
	free(gState.boids);

	RGFW_deinit();
}

void tick(void) {
	double updateStart = frameTimerNowSeconds();
	for (int i = 0; i < gState.boidCount; i++) {
		Boid* boid = &gState.boids[i];

		flyTowardsCenter(boid);
		avoidOthers(boid);
		matchVelocity(boid);
		limitSpeed(boid);
		keepWithinBounds(boid);

		boid->x += boid->dx;
		boid->y += boid->dy;
	}
	frameTimerRecord(&gState.updateTimer, frameTimerNowSeconds() - updateStart);
	frameTimerPrintAndReset(&gState.updateTimer);
}

int main(void) {
	init();

	RGFW_window_show(gState.window);
	while (!RGFW_window_shouldClose(gState.window)) {
		tick();
		draw();

		RGFW_pollEvents();
	}

}
