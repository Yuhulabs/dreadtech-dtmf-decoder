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

#import "DTMFDecoder.h"
#define MAX_HOLDING_BUFFER	 200

static double	powers[NUM_FREQS];		// Location to store the powers for all the frequencies
static double	filterBuf0[NUM_FREQS];	// Buffer for the IIR filter slot 0
static double	filterBuf1[NUM_FREQS];	// Buffer for the IIR filter slot 1
static char	holdingBuffer[2];
static int		holdingBufferCount[2];
static char	outputBuffer[200];
static int		powerMeasurementMethod;	// 0 = Peak Value -> RMS, 1 = Sqrt of Sum of Squares, 2 = Sum of Abs Values
static BOOL	rawOutput;
static double	noiseTolerenceFactor;




// Filter coefficients
const struct FilterCoefficientsEntry filterCoefficients[NUM_FREQS] =
{
	{0.002729634465943104,	1.703076309365611,	0.994540731068114		},	//697 Hz
	{0.003014658069540622,	1.640321076289727,	0.9939706838609188	},	//770 Hz
	{0.003334626751652912,	1.563455998285116,	0.9933307464966943	},	//852 Hz
	{0.003681676706860666,	1.472762296913335,	0.9926366465862788	},	//941 Hz
	{0.00472526211613835,	1.158603326387692,	0.9905494757677233	},	//1209 Hz
	{0.005219030413485972,	0.991170124246961,	0.989561939173028		},	//1336 Hz
	{0.005766653227008568,	0.7940130339147109,	0.9884666935459827	},	//1477 Hz
	{0.006371827557152048,	0.5649101144069607,	0.9872563448856961	}	//1633 Hz
};



const char dtmfCodes[4][4] =
{
	{'1','2','3','A'},
	{'4','5','6','B'},
	{'7','8','9','C'},
	{'*','0','#','D'},
};


// 40ms signal 40ms off


// BpRe/100/frequency == Bandpass resonator, Q=100 (0=>Inf), frequency 
// e.g. ./fiview 8000 -i BpRe/100/1336
// Generated using  http://uazu.net/fiview/

double bandPassFilter(register double val, int filterIndex)
{
	register double tmp, fir, iir;
	tmp= filterBuf0[filterIndex];
	filterBuf0[filterIndex] = filterBuf1[filterIndex];
	val *= filterCoefficients[filterIndex].unityGainCorrection;
	iir = val+filterCoefficients[filterIndex].coeff1 * filterBuf0[filterIndex] - filterCoefficients[filterIndex].coeff2 * tmp;
	fir = iir-tmp;
	filterBuf1[filterIndex] = iir; val = fir;
	return val;
}



char lookupDTMFCode(void)
{
	//Find the highest powered frequency index
	int max1Index = 0;
	for (int i=0; i<NUM_FREQS; i++) {
		if ( powers[i] >= powers[max1Index] ) max1Index = i;
	}
	
	//Find the 2nd highest powered frequency index
	int max2Index;
	if ( max1Index == 0 )	max2Index = 1;
	else					max2Index = 0;
	
	for (int i=0; i<NUM_FREQS; i++) {
		if (( powers[i] >= powers[max2Index] ) && ( i != max1Index )) max2Index = i;
	}
	
	//Check that fequency 1 and 2 are substantially bigger than any other frequencies
	BOOL valid = YES;
	for (int i=0; i<NUM_FREQS; i++) {
		if (( i == max1Index ) || ( i == max2Index ))	continue;
		
		if (powers[i] > ( powers[max2Index] / noiseTolerenceFactor )) {valid = NO;break;}
	}
	
	if ( valid ) {
		NSLog(@"Highest Frequencies found: %d %d", max1Index, max2Index);
		
		//Figure out which one is a row and which one is a column
		int row = -1;
		int col = -1;
		if (( max1Index >= 0 ) && ( max1Index <=3 ))	row = max1Index;
		else											col = max1Index;
		
		if (( max2Index >= 4 ) && ( max2Index <=7 ))	col = max2Index;
		else											row = max2Index;
		
		// Check we have both the row and column and fail if we have 2 rows or 2 columns
		if (( row == -1 ) || ( col == -1 )) {
			// We have to rows or 2 cols, fail
			NSLog(@"We have 2 rows or 2 columns, must have gotten it wrong");
		}
		else return dtmfCodes[row][col-4];		//We got it
	}
	
	return ' ';
}



void AudioInputCallback(void *inUserData, 
						AudioQueueRef inAQ, 
						AudioQueueBufferRef inBuffer, 
						const AudioTimeStamp *inStartTime, 
						UInt32 inNumberPacketDescriptions, 
						const AudioStreamPacketDescription *inPacketDescs)
{	
	recordState_t* recordState = (recordState_t *)inUserData;
	NSLog(@"Tick");
	if ( ! recordState->recording ) NSLog(@"Not recording, returning");
	
	recordState->currentPacket += inNumberPacketDescriptions;
	
	size_t i, numberOfSamples = inBuffer->mAudioDataByteSize / 2;
	short *p = inBuffer->mAudioData;
	short min,max;
	
	// Normalize - AKA Automatic Gain
	min=p[0]; max=p[0];
	for (i=0L; i<numberOfSamples; i++) {
		if ( p[i] < min )	min = p[i];
		if ( p[i] > max )	max = p[i];
	}
	if ( min < 0 )		min = -min;	//abs it
	if ( max < 0 )		max = -max;	//abs it
	if ( max < min )	max = min;	//Pick bigger of max and min
	
	for (i=0L; i<numberOfSamples; i++)
	{
		p[i] = (short)(((double)p[i] / (double)max) * (double)32767);
	}
	
	//Reset all previous power calculations
	int t;
	double val;
	for (t=0; t< NUM_FREQS; t++)	powers[t] = (double)0.0;
	
	//Run the bandpass filter and calculate the power
	for (i=0L; i<numberOfSamples; i++)
	{
		for (t=0; t< NUM_FREQS; t++)
		{
			//Find the highest value
			switch(powerMeasurementMethod) {
					
			if	( powerMeasurementMethod == 0 ) {
				val= fabs(bandPassFilter((double)p[i], t));
				if ( val > powers[t] )	powers[t] = val;
			}
			else if ( powerMeasurementMethod == 1 )
			{
				val = bandPassFilter((double)p[i], t);
				powers[t] += val * val;				
			}
			else if ( powerMeasurementMethod == 2 )
				powers[t] += fabs(bandPassFilter((double)p[i], t));
		}
	}
	
	//Scale 0 - 1, then convert into an power value
	for (t=0; t<NUM_FREQS; t++)
	{
		if		( powerMeasurementMethod == 0 )	powers[t] = (powers[t] / (double)32768.0) * ((double)1.0 / sqrt((double)2.0));	
		else if ( powerMeasurementMethod == 1 )	powers[t] = sqrt(powers[t] / (double)numberOfSamples) / (double)32768.0;
		else if ( powerMeasurementMethod == 2 )	powers[t] = (powers[t] / (double)numberOfSamples) / (double)32768.0;
	}
	
	NSLog(@"RMS Powers: %0.3lf, %0.3lf, %0.3lf, %0.3lf, %0.3lf, %0.3lf, %0.3lf, %0.3lf", powers[0], powers[1], powers[2], powers[3], powers[4], powers[5], powers[6], powers[7]);
	
	//Figure out the dtmf code <space> is nothing recognized
	char chr = lookupDTMFCode();	
	NSLog(@"DTMF Code: %c",chr);
	AudioQueueEnqueueBuffer(recordState->queue, inBuffer, 0, NULL);
	return;
	
	//Add it to the buffer
	bool prodBuffer = false;
	
	if ( chr == holdingBuffer[1] )	{
		holdingBufferCount[1]++;
		
		//To deal with the case where we've received nothing for a while, spit out the buffer
		if (( holdingBuffer[1] == ' ' ) && ( holdingBufferCount[1] >= 40 )) prodBuffer = true;
	} else {
		prodBuffer = true;
	}
	
	if ( prodBuffer ) 	{
		//Combine the buffer entries if they're the same
		if ( holdingBuffer[1] == holdingBuffer[0] ) {
			holdingBufferCount[1] += holdingBufferCount[0];
			holdingBuffer[0] = 0;
			holdingBufferCount[0] = 0;
		}
		
		//Archive the current value if we have more than 4 samples
		if (( holdingBufferCount[1] >= 4 ) || ( rawOutput ))
		{
			if (( holdingBuffer[0] != 0 ) && ( holdingBuffer[0] != ' ' ))
			{
				//NSLog(@"%c", holdingBuffer[0]);
				char tmp[20];
				if ( rawOutput )	sprintf(tmp, "%c(%d) ", holdingBuffer[0], holdingBufferCount[0]);
				else				sprintf(tmp, "%c", holdingBuffer[0]);
				strcat(outputBuffer,tmp); 
			}
			holdingBuffer[0]		= holdingBuffer[1];
			holdingBufferCount[0]	= holdingBufferCount[1];
		}
		holdingBuffer[1]		= chr;
		holdingBufferCount[1]	= 1;			
	}
	
	AudioQueueEnqueueBuffer(recordState->queue, inBuffer, 0, NULL);
}



@implementation DTMFDecoder

@synthesize currentFreqs, detectBuffer, running, lastcount, ledbin;

-(id) init
{
	[super init];
	[self setCurrentFreqs:nil];
	AudioQueueBufferRef qref[10];
	currentFreqs = nil;
	detectBuffer = (char *)calloc(1,DETECTBUFFERLEN);
	// these statements define the audio stream basic description
	// for the file to record into.
	audioFormat.mSampleRate			= SAMPLING_RATE;
	audioFormat.mFormatID			= kAudioFormatLinearPCM;
	audioFormat.mFormatFlags		= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	audioFormat.mFramesPerPacket	= 1;
	audioFormat.mChannelsPerFrame	= 1;
	audioFormat.mBitsPerChannel		= 16;
	audioFormat.mBytesPerPacket		= 2;
	audioFormat.mBytesPerFrame		= 2;
	audioFormat.mReserved = 0;
	

    OSStatus status;
	// Create the new audio queue
	status = AudioQueueNewInput (&audioFormat,
						AudioInputCallback,
						&recordState, // User Data
						CFRunLoopGetCurrent(),
						kCFRunLoopCommonModes,
						0, // Reserved
						&recordState.queue
						);
	
	if (status != 0) {
	    NSLog(@"Can't create new input");
		return self;
	}
	
	// Get the *actual* recording format back from the queue's audio converter.
	// We may not have been given what we asked for.
	UInt32 fsize = sizeof(audioFormat);
	
	AudioQueueGetProperty(recordState.queue,
						  kAudioQueueProperty_StreamDescription,	// this constant is only available in iPhone OS
						  &audioFormat,
						  &fsize
						  );
	
	if (audioFormat.mSampleRate != SAMPLING_RATE) {
		NSLog(@"Wrong sample rate !");
		return self;
	}
	
	for (int i = 0; i < NUM_BUFFERS; ++i) {
		//Allocate buffer. Size is in bytes.
		AudioQueueAllocateBuffer(recordState.queue, 4096, &qref[i]);
		AudioQueueEnqueueBuffer(recordState.queue, qref[i] , 0, NULL);			
	}

	last = ' ';
	lastcount = 0;
	gaplen = 0;
	[self resetBuffer];
	
	AudioQueueStart(recordState.queue,NULL);
	NSLog(@"started queue");
	recordState.recording = true; 
	running = YES;
	return self;
	// Animation timer	
}





- (void) resetBuffer
{
	if ([self running]) {
		[self setRunning: NO];
		memset(detectBuffer, '\0', sizeof(detectBuffer));
		last = ' ';
		[self setRunning: YES];
	}
}
//////////////////////////



- (void)startRecording
{
	NSLog(@"Start Recording");
	
	
	recordState.currentPacket = 0;
	
	OSStatus status;
	status = AudioQueueNewInput(&recordState.dataFormat,
								AudioInputCallback,
								&recordState,
								CFRunLoopGetCurrent(),
								kCFRunLoopCommonModes,
								0,
								&recordState.queue);
	
	if ( status == 0 ) {
		for(int i = 0; i < NUM_BUFFERS; i++) {
			AudioQueueAllocateBuffer(recordState.queue, BUFFER_SIZE, &recordState.buffers[i]);
			AudioQueueEnqueueBuffer(recordState.queue, recordState.buffers[i], 0, NULL);
        }
		
		recordState.recording = true;        
		status = AudioQueueStart(recordState.queue, NULL);
		if ( status == 0 ) {
			NSLog(@"Recording");
		} else {
			NSLog(@"Arses");
		}
	}
	if ( status != 0 )	NSLog(@"Record Failed %d", status);
}



- (void)stopRecording
{
	NSLog(@"Stop Recording");
	recordState.recording = false;
	
	AudioQueueStop(recordState.queue, true);
	 
	for(int i = 0; i < NUM_BUFFERS; i++)
		AudioQueueFreeBuffer(recordState.queue, recordState.buffers[i]);
	
	AudioQueueDispose(recordState.queue, true);
	AudioFileClose(recordState.audioFile);
}



- (void)awakeFromNib
{
	// Init state variables
	recordState.recording = false;	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopRecording) name:UIApplicationWillTerminateNotification object:nil];	
}




- (void)loadSettings
{
	//noiseTolerenceFactor	= (double)(((1.0 - [MZUserDefaults floatForKey:	kPreferenceNoiseEnvironment]) * (kMaxNoiseTolerenceFactor - kMinNoiseTolerenceFactor)) + kMinNoiseTolerenceFactor);
	//NSLog(@"Noise Tolerence Factor: %lf", noiseTolerenceFactor);
	//rawOutput				=		  [MZUserDefaults boolForKey:	kPreferenceRawOutput];
	//powerMeasurementMethod	=		  [MZUserDefaults integerForKey:kPreferencePowerMethod];	
}



- (void)viewDidUnload {
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
}




@end
