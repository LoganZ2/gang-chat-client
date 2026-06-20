#import "FlutterScreenAudioDevice.h"
#import "RTCAudioDevice.h"

#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <mach/mach_time.h>
#import <os/lock.h>

// We feed WebRTC 48 kHz mono int16. ScreenCaptureKit is configured for 48 kHz
// stereo, which we down-mix to mono here. Mono (not stereo) is deliberate: the
// native ADM's pre-filled `inputData` delivery path reads exactly `frameCount`
// int16 samples from buffer[0] regardless of channel count, so a mono layout is
// the only one it consumes correctly without the (more complex) render-block
// path. Screen-share audio collapsing to mono is acceptable for voice rooms.
static const double kScreenAudioSampleRate = 48000.0;
static const NSInteger kScreenAudioChannels = 1;
// 10 ms at 48 kHz. WebRTC re-chunks internally via FineAudioBuffer, so this only
// sets the ADM's buffer-duration hint.
static const NSTimeInterval kScreenAudioIOBufferDuration = 0.01;

static int16_t FlutterScreenAudioFloatToInt16(float value) {
  float scaled = value * 32767.0f;
  if (scaled > 32767.0f) scaled = 32767.0f;
  if (scaled < -32768.0f) scaled = -32768.0f;
  return (int16_t)lrintf(scaled);
}

// Read one source sample (any common PCM layout) as a float in [-1, 1].
static float FlutterScreenAudioReadSample(const AudioBufferList* list,
                                          const AudioStreamBasicDescription* asbd,
                                          size_t frame,
                                          UInt32 channel) {
  if (list == NULL || asbd == NULL || list->mNumberBuffers == 0) return 0.0f;

  const UInt32 channels = MAX((UInt32)1, asbd->mChannelsPerFrame);
  const BOOL nonInterleaved = (asbd->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
  const UInt32 bufferIndex = nonInterleaved ? MIN(channel, list->mNumberBuffers - 1) : 0;
  const AudioBuffer* buffer = &list->mBuffers[bufferIndex];
  if (buffer->mData == NULL || buffer->mDataByteSize == 0) return 0.0f;

  const UInt32 bytesPerSample = asbd->mBitsPerChannel / 8;
  if (bytesPerSample == 0) return 0.0f;

  const size_t sampleIndex = nonInterleaved ? frame : (frame * channels + channel);
  const size_t offset = sampleIndex * bytesPerSample;
  if (offset + bytesPerSample > buffer->mDataByteSize) return 0.0f;

  const uint8_t* sample = ((const uint8_t*)buffer->mData) + offset;
  const BOOL isFloat = (asbd->mFormatFlags & kAudioFormatFlagIsFloat) != 0;
  const BOOL isSignedInteger = (asbd->mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0;

  if (isFloat) {
    if (asbd->mBitsPerChannel == 32) {
      float v = *(const float*)sample;
      if (v > 1.0f) v = 1.0f;
      if (v < -1.0f) v = -1.0f;
      return v;
    }
    if (asbd->mBitsPerChannel == 64) {
      double v = *(const double*)sample;
      if (v > 1.0) v = 1.0;
      if (v < -1.0) v = -1.0;
      return (float)v;
    }
    return 0.0f;
  }

  if (!isSignedInteger) return 0.0f;
  if (asbd->mBitsPerChannel == 16) return (float)(*(const int16_t*)sample) / 32768.0f;
  if (asbd->mBitsPerChannel == 32) return (float)(*(const int32_t*)sample) / 2147483648.0f;
  return 0.0f;
}

// Down-mix all source channels to mono at the given source frame index.
static float FlutterScreenAudioMonoSample(const AudioBufferList* list,
                                          const AudioStreamBasicDescription* asbd,
                                          size_t frame) {
  const UInt32 channels = MAX((UInt32)1, asbd->mChannelsPerFrame);
  if (channels == 1) return FlutterScreenAudioReadSample(list, asbd, frame, 0);
  float sum = 0.0f;
  for (UInt32 c = 0; c < channels; c++) {
    sum += FlutterScreenAudioReadSample(list, asbd, frame, c);
  }
  return sum / (float)channels;
}


@implementation FlutterScreenAudioDevice {
  // Single serial queue for all native-ADM delivery, so OnDeliverRecordedData
  // is never re-entered concurrently and the send stream's capture race checker
  // (a fatal RTC_CHECK in this build) can never trip.
  dispatch_queue_t _deliveryQueue;

  os_unfair_lock _stateLock;
  id<RTC_OBJC_TYPE(RTCAudioDeviceDelegate)> _delegate;  // guarded by _stateLock
  BOOL _initialized;                                    // guarded by _stateLock
  BOOL _playoutInitialized;                             // guarded by _stateLock
  BOOL _recordingInitialized;                           // guarded by _stateLock
  BOOL _playing;                                        // guarded by _stateLock
  BOOL _recording;                                      // guarded by _stateLock

  // Linear-resampler carry state, touched only on _deliveryQueue.
  double _sourcePosition;
  double _lastSourceSampleRate;
  BOOL _loggedFirstBuffer;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _deliveryQueue =
        dispatch_queue_create("com.gangchat.screenaudio.adm", DISPATCH_QUEUE_SERIAL);
    _stateLock = OS_UNFAIR_LOCK_INIT;
    _lastSourceSampleRate = kScreenAudioSampleRate;
  }
  return self;
}

+ (instancetype)sharedInstance {
  static FlutterScreenAudioDevice* instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[FlutterScreenAudioDevice alloc] init];
  });
  return instance;
}

#pragma mark - Public capture entry point

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
  if (sampleBuffer == NULL) return;
  static BOOL loggedFirstEnqueue = NO;
  if (!loggedFirstEnqueue) {
    loggedFirstEnqueue = YES;
    NSLog(@"FlutterScreenAudioDevice: enqueueSampleBuffer first call");
  }
  CFRetain(sampleBuffer);
  dispatch_async(_deliveryQueue, ^{
    [self deliverSampleBufferOnQueue:sampleBuffer];
    CFRelease(sampleBuffer);
  });
}

- (void)deliverSampleBufferOnQueue:(CMSampleBufferRef)sampleBuffer {
  os_unfair_lock_lock(&_stateLock);
  const BOOL recording = _recording;
  id<RTC_OBJC_TYPE(RTCAudioDeviceDelegate)> delegate = _delegate;
  os_unfair_lock_unlock(&_stateLock);
  static BOOL loggedState = NO;
  if (!loggedState) {
    loggedState = YES;
    NSLog(@"FlutterScreenAudioDevice: first deliver attempt recording=%d delegate=%d",
          recording, delegate != nil);
  }
  if (!recording || delegate == nil) return;

  CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
  const AudioStreamBasicDescription* asbd =
      CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
  if (asbd == NULL || asbd->mFormatID != kAudioFormatLinearPCM || asbd->mSampleRate <= 0.0 ||
      asbd->mChannelsPerFrame == 0) {
    return;
  }

  const CMItemCount sourceFrames = CMSampleBufferGetNumSamples(sampleBuffer);
  if (sourceFrames <= 0) return;

  size_t listSize = offsetof(AudioBufferList, mBuffers) +
                    (sizeof(AudioBuffer) * MAX((UInt32)1, asbd->mChannelsPerFrame));
  AudioBufferList* list = (AudioBufferList*)calloc(1, listSize);
  if (list == NULL) return;

  CMBlockBufferRef blockBuffer = NULL;
  OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, &listSize, list, listSize, kCFAllocatorDefault, kCFAllocatorDefault,
      kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer);
  if (status != noErr) {
    free(list);
    if (blockBuffer != NULL) CFRelease(blockBuffer);
    return;
  }

  // Reset resampler phase when the source rate changes (should be rare: SCK is
  // pinned to 48 kHz).
  if (_lastSourceSampleRate != asbd->mSampleRate) {
    _lastSourceSampleRate = asbd->mSampleRate;
    _sourcePosition = 0.0;
  }

  const double step = asbd->mSampleRate / kScreenAudioSampleRate;
  // Upper bound on output frames for this input block.
  const size_t maxOut = (size_t)((double)sourceFrames / step) + 2;
  int16_t* out = (int16_t*)malloc(maxOut * sizeof(int16_t));
  if (out == NULL) {
    free(list);
    if (blockBuffer != NULL) CFRelease(blockBuffer);
    return;
  }

  size_t outCount = 0;
  float peak = 0.0f;
  double pos = _sourcePosition;
  while (pos < (double)sourceFrames && outCount < maxOut) {
    const size_t frame = (size_t)pos;
    const size_t nextFrame = MIN(frame + 1, (size_t)sourceFrames - 1);
    const float frac = (float)(pos - (double)frame);
    const float a = FlutterScreenAudioMonoSample(list, asbd, frame);
    const float b = FlutterScreenAudioMonoSample(list, asbd, nextFrame);
    const float v = a + (b - a) * frac;
    if (fabsf(v) > peak) peak = fabsf(v);
    out[outCount++] = FlutterScreenAudioFloatToInt16(v);
    pos += step;
  }
  _sourcePosition = pos - (double)sourceFrames;

  free(list);
  if (blockBuffer != NULL) CFRelease(blockBuffer);

  if (outCount == 0) {
    free(out);
    return;
  }

  if (!_loggedFirstBuffer && peak > 0.0f) {
    _loggedFirstBuffer = YES;
    NSLog(@"FlutterScreenAudioDevice: first audio delivered to screen-audio ADM "
          @"(srcRate=%.0f srcCh=%u outFrames=%zu peak=%.4f)",
          asbd->mSampleRate, asbd->mChannelsPerFrame, outCount, peak);
  }

  AudioBufferList abl;
  abl.mNumberBuffers = 1;
  abl.mBuffers[0].mNumberChannels = (UInt32)kScreenAudioChannels;
  abl.mBuffers[0].mDataByteSize = (UInt32)(outCount * sizeof(int16_t));
  abl.mBuffers[0].mData = out;

  AudioUnitRenderActionFlags flags = 0;
  AudioTimeStamp ts;
  memset(&ts, 0, sizeof(ts));
  ts.mHostTime = mach_absolute_time();
  ts.mFlags = kAudioTimeStampHostTimeValid;

  RTC_OBJC_TYPE(RTCAudioDeviceDeliverRecordedDataBlock) deliver = delegate.deliverRecordedData;
  if (deliver == nil) {
    static BOOL loggedNilBlock = NO;
    if (!loggedNilBlock) {
      loggedNilBlock = YES;
      NSLog(@"FlutterScreenAudioDevice: deliverRecordedData block is nil!");
    }
  } else {
    deliver(&flags, &ts, /*inputBusNumber=*/0, (UInt32)outCount, &abl,
            /*renderContext=*/NULL, /*renderBlock=*/nil);
  }
  free(out);
}

#pragma mark - RTCAudioDevice: parameters

- (double)deviceInputSampleRate { return kScreenAudioSampleRate; }
- (NSTimeInterval)inputIOBufferDuration { return kScreenAudioIOBufferDuration; }
- (NSInteger)inputNumberOfChannels { return kScreenAudioChannels; }
- (NSTimeInterval)inputLatency { return 0; }
- (double)deviceOutputSampleRate { return kScreenAudioSampleRate; }
- (NSTimeInterval)outputIOBufferDuration { return kScreenAudioIOBufferDuration; }
- (NSInteger)outputNumberOfChannels { return kScreenAudioChannels; }
- (NSTimeInterval)outputLatency { return 0; }

#pragma mark - RTCAudioDevice: lifecycle

- (BOOL)isInitialized {
  os_unfair_lock_lock(&_stateLock);
  BOOL v = _initialized;
  os_unfair_lock_unlock(&_stateLock);
  return v;
}

- (BOOL)initializeWithDelegate:(id<RTC_OBJC_TYPE(RTCAudioDeviceDelegate)>)delegate {
  os_unfair_lock_lock(&_stateLock);
  _delegate = delegate;
  _initialized = YES;
  os_unfair_lock_unlock(&_stateLock);
  NSLog(@"FlutterScreenAudioDevice: initializeWithDelegate delegate=%d", delegate != nil);
  return YES;
}

- (BOOL)terminateDevice {
  os_unfair_lock_lock(&_stateLock);
  _delegate = nil;
  _initialized = NO;
  _playoutInitialized = NO;
  _recordingInitialized = NO;
  _playing = NO;
  _recording = NO;
  os_unfair_lock_unlock(&_stateLock);
  return YES;
}

#pragma mark - RTCAudioDevice: playout (unused — publish-only device)

- (BOOL)isPlayoutInitialized {
  os_unfair_lock_lock(&_stateLock);
  BOOL v = _playoutInitialized;
  os_unfair_lock_unlock(&_stateLock);
  return v;
}

- (BOOL)initializePlayout {
  os_unfair_lock_lock(&_stateLock);
  _playoutInitialized = YES;
  os_unfair_lock_unlock(&_stateLock);
  return YES;
}

- (BOOL)isPlaying {
  os_unfair_lock_lock(&_stateLock);
  BOOL v = _playing;
  os_unfair_lock_unlock(&_stateLock);
  return v;
}

- (BOOL)startPlayout {
  os_unfair_lock_lock(&_stateLock);
  _playing = YES;
  os_unfair_lock_unlock(&_stateLock);
  return YES;
}

- (BOOL)stopPlayout {
  os_unfair_lock_lock(&_stateLock);
  _playing = NO;
  os_unfair_lock_unlock(&_stateLock);
  return YES;
}

#pragma mark - RTCAudioDevice: recording (SCK system audio)

- (BOOL)isRecordingInitialized {
  os_unfair_lock_lock(&_stateLock);
  BOOL v = _recordingInitialized;
  os_unfair_lock_unlock(&_stateLock);
  return v;
}

- (BOOL)initializeRecording {
  os_unfair_lock_lock(&_stateLock);
  _recordingInitialized = YES;
  os_unfair_lock_unlock(&_stateLock);
  return YES;
}

- (BOOL)isRecording {
  os_unfair_lock_lock(&_stateLock);
  BOOL v = _recording;
  os_unfair_lock_unlock(&_stateLock);
  return v;
}
- (BOOL)startRecording {
  os_unfair_lock_lock(&_stateLock);
  _recording = YES;
  os_unfair_lock_unlock(&_stateLock);
  NSLog(@"FlutterScreenAudioDevice: startRecording");
  return YES;
}

- (BOOL)stopRecording {
  os_unfair_lock_lock(&_stateLock);
  _recording = NO;
  os_unfair_lock_unlock(&_stateLock);
  return YES;
}

@end
