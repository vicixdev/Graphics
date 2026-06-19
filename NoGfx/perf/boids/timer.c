#include "timer.h"

#include <stdio.h>
#include <QuartzCore/QuartzCore.h>

void frameTimerInit(FrameTimer* timer, const char* name) {
	timer->name = name;
	timer->sampleCount = 0;
	timer->sampleIndex = 0;
}

double frameTimerNowSeconds(void) {
	return CACurrentMediaTime();
}

void frameTimerRecord(FrameTimer* timer, double sampleSeconds) {
	timer->samples[timer->sampleIndex] = sampleSeconds;
	timer->sampleIndex = (timer->sampleIndex + 1) % FRAME_TIMER_WINDOW;
	if (timer->sampleCount < FRAME_TIMER_WINDOW) {
		timer->sampleCount += 1;
	}
}

double frameTimerAverageMilliseconds(const FrameTimer* timer) {
	double total = 0.0;
	for (int i = 0; i < timer->sampleCount; i++) {
		total += timer->samples[i];
	}
	return (total / (double)timer->sampleCount) * 1000.0;
}

double frameTimerLow1PercentMilliseconds(const FrameTimer* timer) {
	double sorted[FRAME_TIMER_WINDOW];
	for (int i = 0; i < timer->sampleCount; i++) {
		sorted[i] = timer->samples[i];
	}

	for (int i = 1; i < timer->sampleCount; i++) {
		double value = sorted[i];
		int j = i - 1;
		while (j >= 0 && sorted[j] > value) {
			sorted[j + 1] = sorted[j];
			j -= 1;
		}
		sorted[j + 1] = value;
	}

	int lowSampleCount = (timer->sampleCount + 99) / 100;
	if (lowSampleCount < 1) {
		lowSampleCount = 1;
	}

	double total = 0.0;
	for (int i = 0; i < lowSampleCount; i++) {
		total += sorted[i];
	}

	return (total / (double)lowSampleCount) * 1000.0;
}

void frameTimerPrintAndReset(FrameTimer* timer) {
	if (timer->sampleCount < FRAME_TIMER_WINDOW) {
		return;
	}

	printf("%s: avg %.3f ms, 1%% low %.3f ms\n",
		timer->name,
		frameTimerAverageMilliseconds(timer),
		frameTimerLow1PercentMilliseconds(timer));
	fflush(stdout);
	timer->sampleCount = 0;
	timer->sampleIndex = 0;
}