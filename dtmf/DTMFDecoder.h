/*
 $Id$
 Dreadtech DTMF Decoder - Copyright 2009 Martin Wellard
 
 This file is part of Dreadtech DTMF Decoder.
 
 Dreadtech DTMF Decoder is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 Dreadtech DTMF Decoder is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with Dreadtech DTMF Decoder.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioFile.h>

#define SAMPLING_RATE		8000.0
#define DEBOUNCELEN			2
#define GAPLEN				2
#define NUM_BUFFERS			3
#define DETECTBUFFERLEN		8192

#define MIN_TONE_LENGTH		0.045	// 45ms
#define FRAMES_PER_TONE		4
#define BYTES_PER_CHANNEL	2
#define BUFFER_SIZE			(((int)(MIN_TONE_LENGTH / (1.0/SAMPLING_RATE)) * BYTES_PER_CHANNEL) / FRAMES_PER_TONE )

#define NUM_FREQS				8		// The number of dtmf frequencies (band pass filters)



struct FilterCoefficientsEntry
{
	double unityGainCorrection;
	double coeff1;
	double coeff2;
};

typedef struct
{
	AudioStreamBasicDescription dataFormat;
	AudioQueueRef				queue;
	AudioQueueBufferRef		buffers[NUM_BUFFERS];
	BOOL						recording;
	AudioFileID				audioFile;
	SInt64						currentPacket;
	short						filteredBuffer[BUFFER_SIZE];
	id							*decoderObject;
	char						*detectBuffer;
} recordState_t;


@interface DTMFDecoder : NSObject {	
	AudioStreamBasicDescription audioFormat;
	int			sample_count;
	double		*currentFreqs;
	int			lastcount;
	int			gaplen;
	char		last;
	int			ledbin;
	bool		running;
	recordState_t recordState;
	UIPasteboard *uip;
	NSUserDefaults	*defaults;	

}

@property (assign)		int lastcount;
@property (assign)		double *currentFreqs;
@property (assign)		int ledbin;
@property (readwrite)	bool running;

- (id) init;
- (void) resetBuffer;
- (void) startRecording;
- (void) setPowerMethod:(NSInteger)powerMethod;
- (void) setNoiseLevel:(float)noiseLevel;
- (void) loadSettings;
- (float) getNoiseLevel;
- (NSInteger) getPowerMethod;
- (char *) getDetectBuffer;
- (void) copyBuffer;
@end
