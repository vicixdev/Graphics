#pragma once

#define FRAME_TIMER_WINDOW 60

typedef struct {
	const char* name;
	double samples[FRAME_TIMER_WINDOW];
	int sampleCount;
	int sampleIndex;
} FrameTimer;

void frameTimerInit(FrameTimer* timer, const char* name);
double frameTimerNowSeconds(void);
void frameTimerRecord(FrameTimer* timer, double sampleSeconds);
double frameTimerAverageMilliseconds(const FrameTimer* timer);
double frameTimerLow1PercentMilliseconds(const FrameTimer* timer);
void frameTimerPrintAndReset(FrameTimer* timer);

