#import <objc/runtime.h>
#if TARGET_OS_OSX
#import <CoreAudio/CoreAudio.h>
#endif
#import "AudioUtils.h"
#import "CameraUtils.h"
#import "FlutterRTCFrameCapturer.h"
#import "FlutterRTCMediaStream.h"
#import "FlutterRTCPeerConnection.h"
#import "VideoProcessingAdapter.h"
#import "LocalVideoTrack.h"
#import "LocalAudioTrack.h"

@implementation RTCMediaStreamTrack (Flutter)

- (id)settings {
  return objc_getAssociatedObject(self, _cmd);
}

- (void)setSettings:(id)settings {
  objc_setAssociatedObject(self, @selector(settings), settings, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

@implementation AVCaptureDevice (Flutter)

- (NSString*)positionString {
  switch (self.position) {
    case AVCaptureDevicePositionUnspecified:
      return @"unspecified";
    case AVCaptureDevicePositionBack:
      return @"back";
    case AVCaptureDevicePositionFront:
      return @"front";
  }
  return nil;
}

@end

@implementation FlutterWebRTCPlugin (RTCMediaStream)

/**
 * {@link https://www.w3.org/TR/mediacapture-streams/#navigatorusermediaerrorcallback}
 */
typedef void (^NavigatorUserMediaErrorCallback)(NSString* errorType, NSString* errorMessage);

/**
 * {@link https://www.w3.org/TR/mediacapture-streams/#navigatorusermediasuccesscallback}
 */
typedef void (^NavigatorUserMediaSuccessCallback)(RTCMediaStream* mediaStream);

- (NSDictionary*)defaultVideoConstraints {
    return @{@"minWidth" : @"1280", @"minHeight" : @"720", @"minFrameRate" : @"30"};
}

- (NSDictionary*)defaultAudioConstraints {
    return @{};
}


- (RTCMediaConstraints*)defaultMediaStreamConstraints {
  RTCMediaConstraints* constraints =
      [[RTCMediaConstraints alloc] initWithMandatoryConstraints:[self defaultVideoConstraints]
                                            optionalConstraints:nil];
  return constraints;
}


- (NSArray<AVCaptureDevice*> *) captureDevices {
    if (@available(iOS 13.0, macOS 10.15, macCatalyst 14.0, tvOS 17.0, *)) {
        NSArray<AVCaptureDeviceType> *deviceTypes = @[
#if TARGET_OS_IPHONE
            AVCaptureDeviceTypeBuiltInTripleCamera,
            AVCaptureDeviceTypeBuiltInDualCamera,
            AVCaptureDeviceTypeBuiltInDualWideCamera,
            AVCaptureDeviceTypeBuiltInWideAngleCamera,
            AVCaptureDeviceTypeBuiltInTelephotoCamera,
            AVCaptureDeviceTypeBuiltInUltraWideCamera,
#else
            AVCaptureDeviceTypeBuiltInWideAngleCamera,
#endif
        ];
        
#if !defined(TARGET_OS_IPHONE)
        if (@available(macOS 13.0, *)) {
            deviceTypes = [deviceTypes arrayByAddingObject:AVCaptureDeviceTypeDeskViewCamera];
        }
#endif

        if (@available(iOS 17.0, macOS 14.0, tvOS 17.0, *)) {
            deviceTypes = [deviceTypes arrayByAddingObjectsFromArray: @[
                AVCaptureDeviceTypeContinuityCamera,
                AVCaptureDeviceTypeExternal,
            ]];
        }

        return [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes
                                                                      mediaType:AVMediaTypeVideo
                                                                       position:AVCaptureDevicePositionUnspecified].devices;
    }
    return @[];
}

/**
 * Initializes a new {@link RTCAudioTrack} which satisfies specific constraints,
 * adds it to a specific {@link RTCMediaStream}, and reports success to a
 * specific callback. Implements the audio-specific counterpart of the
 * {@code getUserMedia()} algorithm.
 *
 * @param constraints The {@code MediaStreamConstraints} which the new
 * {@code RTCAudioTrack} instance is to satisfy.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is being initialized as
 * part of the execution of the {@code getUserMedia()} algorithm, to which a
 * new {@code RTCAudioTrack} is to be added, and which is to be reported to
 * {@code successCallback} upon success.
 */
- (void)getUserAudio:(NSDictionary*)constraints
     successCallback:(NavigatorUserMediaSuccessCallback)successCallback
       errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
         mediaStream:(RTCMediaStream*)mediaStream {
  id audioConstraints = constraints[@"audio"];
  NSString* audioDeviceId = @"";
  RTCMediaConstraints *rtcConstraints;
  if ([audioConstraints isKindOfClass:[NSDictionary class]]) {
    // constraints.audio.deviceId
    NSString* deviceId = audioConstraints[@"deviceId"];

    if (deviceId) {
      audioDeviceId = deviceId;
    }

    rtcConstraints = [self parseMediaConstraints:audioConstraints];
    // constraints.audio.optional.sourceId
    id optionalConstraints = audioConstraints[@"optional"];
    if (optionalConstraints && [optionalConstraints isKindOfClass:[NSArray class]] &&
        !deviceId) {
      NSArray* options = optionalConstraints;
      for (id item in options) {
        if ([item isKindOfClass:[NSDictionary class]]) {
          NSString* sourceId = ((NSDictionary*)item)[@"sourceId"];
          if (sourceId) {
            audioDeviceId = sourceId;
          }
        }
      }
    }
  } else {
      rtcConstraints = [self parseMediaConstraints:[self defaultAudioConstraints]];
  }

#if !defined(TARGET_OS_IPHONE)
  if (audioDeviceId != nil) {
    [self selectAudioInput:audioDeviceId result:nil];
  }
#endif

  NSString* trackId = [[NSUUID UUID] UUIDString];
  RTCAudioSource *audioSource = [self.peerConnectionFactory audioSourceWithConstraints:rtcConstraints];
  RTCAudioTrack* audioTrack = [self.peerConnectionFactory audioTrackWithSource:audioSource trackId:trackId];
  LocalAudioTrack *localAudioTrack = [[LocalAudioTrack alloc] initWithTrack:audioTrack];

  audioTrack.settings = @{
    @"deviceId" : audioDeviceId,
    @"kind" : @"audioinput",
    @"autoGainControl" : @YES,
    @"echoCancellation" : @YES,
    @"noiseSuppression" : @YES,
    @"channelCount" : @1,
    @"latency" : @0,
  };

  [mediaStream addAudioTrack:audioTrack];

  [self.localTracks setObject:localAudioTrack forKey:trackId];

  [self ensureAudioSession];

  successCallback(mediaStream);
}

// TODO: Use RCTConvert for constraints ...
- (void)getUserMedia:(NSDictionary*)constraints result:(FlutterResult)result {
  // Initialize RTCMediaStream with a unique label in order to allow multiple
  // RTCMediaStream instances initialized by multiple getUserMedia calls to be
  // added to 1 RTCPeerConnection instance. As suggested by
  // https://www.w3.org/TR/mediacapture-streams/#mediastream to be a good
  // practice, use a UUID (conforming to RFC4122).
  NSString* mediaStreamId = [[NSUUID UUID] UUIDString];
  RTCMediaStream* mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];

  [self getUserMedia:constraints
      successCallback:^(RTCMediaStream* mediaStream) {
        NSString* mediaStreamId = mediaStream.streamId;

        NSMutableArray* audioTracks = [NSMutableArray array];
        NSMutableArray* videoTracks = [NSMutableArray array];

        for (RTCAudioTrack* track in mediaStream.audioTracks) {
          [audioTracks addObject:@{
            @"id" : track.trackId,
            @"kind" : track.kind,
            @"label" : track.trackId,
            @"enabled" : @(track.isEnabled),
            @"remote" : @(YES),
            @"readyState" : @"live",
            @"settings" : track.settings
          }];
        }

        for (RTCVideoTrack* track in mediaStream.videoTracks) {
          [videoTracks addObject:@{
            @"id" : track.trackId,
            @"kind" : track.kind,
            @"label" : track.trackId,
            @"enabled" : @(track.isEnabled),
            @"remote" : @(YES),
            @"readyState" : @"live",
            @"settings" : track.settings
          }];
        }

        self.localStreams[mediaStreamId] = mediaStream;
        result(@{
          @"streamId" : mediaStreamId,
          @"audioTracks" : audioTracks,
          @"videoTracks" : videoTracks
        });
      }
      errorCallback:^(NSString* errorType, NSString* errorMessage) {
        result([FlutterError errorWithCode:[NSString stringWithFormat:@"Error %@", errorType]
                                   message:errorMessage
                                   details:nil]);
      }
      mediaStream:mediaStream];
}

/**
 * Initializes a new {@link RTCAudioTrack} or a new {@link RTCVideoTrack} which
 * satisfies specific constraints and adds it to a specific
 * {@link RTCMediaStream} if the specified {@code mediaStream} contains no track
 * of the respective media type and the specified {@code constraints} specify
 * that a track of the respective media type is required; otherwise, reports
 * success for the specified {@code mediaStream} to a specific
 * {@link NavigatorUserMediaSuccessCallback}. In other words, implements a media
 * type-specific iteration of or successfully concludes the
 * {@code getUserMedia()} algorithm. The method will be recursively invoked to
 * conclude the whole {@code getUserMedia()} algorithm either with (successful)
 * satisfaction of the specified {@code constraints} or with failure.
 *
 * @param constraints The {@code MediaStreamConstraints} which specifies the
 * requested media types and which the new {@code RTCAudioTrack} or
 * {@code RTCVideoTrack} instance is to satisfy.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is being initialized as
 * part of the execution of the {@code getUserMedia()} algorithm.
 */
- (void)getUserMedia:(NSDictionary*)constraints
     successCallback:(NavigatorUserMediaSuccessCallback)successCallback
       errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
         mediaStream:(RTCMediaStream*)mediaStream {
  // If mediaStream contains no audioTracks and the constraints request such a
  // track, then run an iteration of the getUserMedia() algorithm to obtain
  // local audio content.
  if (mediaStream.audioTracks.count == 0) {
    // constraints.audio
    id audioConstraints = constraints[@"audio"];
    BOOL constraintsIsDictionary = [audioConstraints isKindOfClass:[NSDictionary class]];
    if (audioConstraints && (constraintsIsDictionary || [audioConstraints boolValue])) {
      [self requestAccessForMediaType:AVMediaTypeAudio
                          constraints:constraints
                      successCallback:successCallback
                        errorCallback:errorCallback
                          mediaStream:mediaStream];
      return;
    }
  }

  // If mediaStream contains no videoTracks and the constraints request such a
  // track, then run an iteration of the getUserMedia() algorithm to obtain
  // local video content.
  if (mediaStream.videoTracks.count == 0) {
    // constraints.video
    id videoConstraints = constraints[@"video"];
    if (videoConstraints) {
      BOOL requestAccessForVideo = [videoConstraints isKindOfClass:[NSNumber class]]
                                       ? [videoConstraints boolValue]
                                       : [videoConstraints isKindOfClass:[NSDictionary class]];
#if !TARGET_IPHONE_SIMULATOR
      if (requestAccessForVideo) {
        [self requestAccessForMediaType:AVMediaTypeVideo
                            constraints:constraints
                        successCallback:successCallback
                          errorCallback:errorCallback
                            mediaStream:mediaStream];
        return;
      }
#endif
    }
  }

  // There are audioTracks and/or videoTracks in mediaStream as requested by
  // constraints so the getUserMedia() is to conclude with success.
  successCallback(mediaStream);
}

- (int)getConstrainInt:(NSDictionary*)constraints forKey:(NSString*)key {
  if (![constraints isKindOfClass:[NSDictionary class]]) {
    return 0;
  }

  id constraint = constraints[key];
  if ([constraint isKindOfClass:[NSNumber class]]) {
    return [constraint intValue];
  } else if ([constraint isKindOfClass:[NSString class]]) {
    int possibleValue = [constraint intValue];
    if (possibleValue != 0) {
      return possibleValue;
    }
  } else if ([constraint isKindOfClass:[NSDictionary class]]) {
    id idealConstraint = constraint[@"ideal"];
    if ([idealConstraint isKindOfClass:[NSString class]]) {
      int possibleValue = [idealConstraint intValue];
      if (possibleValue != 0) {
        return possibleValue;
      }
    }
  }

  return 0;
}

/**
 * Initializes a new {@link RTCVideoTrack} which satisfies specific constraints,
 * adds it to a specific {@link RTCMediaStream}, and reports success to a
 * specific callback. Implements the video-specific counterpart of the
 * {@code getUserMedia()} algorithm.
 *
 * @param constraints The {@code MediaStreamConstraints} which the new
 * {@code RTCVideoTrack} instance is to satisfy.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is being initialized as
 * part of the execution of the {@code getUserMedia()} algorithm, to which a
 * new {@code RTCVideoTrack} is to be added, and which is to be reported to
 * {@code successCallback} upon success.
 */
- (void)getUserVideo:(NSDictionary*)constraints
     successCallback:(NavigatorUserMediaSuccessCallback)successCallback
       errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
         mediaStream:(RTCMediaStream*)mediaStream {
  id videoConstraints = constraints[@"video"];
  AVCaptureDevice* videoDevice;
  NSString* videoDeviceId = nil;
  NSString* facingMode = nil;
  NSArray<AVCaptureDevice*>* captureDevices = [self captureDevices];

  if ([videoConstraints isKindOfClass:[NSDictionary class]]) {
    // constraints.video.deviceId
    NSString* deviceId = videoConstraints[@"deviceId"];

    if (deviceId) {
        for (AVCaptureDevice *device in captureDevices) {
            if( [deviceId isEqualToString:device.uniqueID]) {
                videoDevice = device;
                videoDeviceId = deviceId;
            }
        }
    }

    // constraints.video.optional
    id optionalVideoConstraints = videoConstraints[@"optional"];
    if (optionalVideoConstraints && [optionalVideoConstraints isKindOfClass:[NSArray class]] &&
        !videoDevice) {
      NSArray* options = optionalVideoConstraints;
      for (id item in options) {
        if ([item isKindOfClass:[NSDictionary class]]) {
          NSString* sourceId = ((NSDictionary*)item)[@"sourceId"];
          if (sourceId) {
              for (AVCaptureDevice *device in captureDevices) {
                  if( [sourceId isEqualToString:device.uniqueID]) {
                      videoDevice = device;
                      videoDeviceId = sourceId;
                  }
              }
            if (videoDevice) {
              break;
            }
          }
        }
      }
    }

    if (!videoDevice) {
      // constraints.video.facingMode
      // https://www.w3.org/TR/mediacapture-streams/#def-constraint-facingMode
      facingMode = videoConstraints[@"facingMode"];
      if (facingMode && [facingMode isKindOfClass:[NSString class]]) {
        AVCaptureDevicePosition position;
        if ([facingMode isEqualToString:@"environment"]) {
          self._usingFrontCamera = NO;
          position = AVCaptureDevicePositionBack;
        } else if ([facingMode isEqualToString:@"user"]) {
          self._usingFrontCamera = YES;
          position = AVCaptureDevicePositionFront;
        } else {
          // If the specified facingMode value is not supported, fall back to
          // the default video device.
          self._usingFrontCamera = NO;
          position = AVCaptureDevicePositionUnspecified;
        }
        videoDevice = [self findDeviceForPosition:position];
      }
    }
  }

  if ([videoConstraints isKindOfClass:[NSNumber class]]) {
    videoConstraints = @{@"mandatory": [self defaultVideoConstraints]};
  }

  NSInteger targetWidth = 0;
  NSInteger targetHeight = 0;
  NSInteger targetFps = 0;

  if (!videoDevice) {
    videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  }

  int possibleWidth = [self getConstrainInt:videoConstraints forKey:@"width"];
  if (possibleWidth != 0) {
    targetWidth = possibleWidth;
  }

  int possibleHeight = [self getConstrainInt:videoConstraints forKey:@"height"];
  if (possibleHeight != 0) {
    targetHeight = possibleHeight;
  }

  int possibleFps = [self getConstrainInt:videoConstraints forKey:@"frameRate"];
  if (possibleFps != 0) {
    targetFps = possibleFps;
  }

  id mandatory =
      [videoConstraints isKindOfClass:[NSDictionary class]] ? videoConstraints[@"mandatory"] : nil;

  // constraints.video.mandatory
  if (mandatory && [mandatory isKindOfClass:[NSDictionary class]]) {
    id widthConstraint = mandatory[@"minWidth"];
    if ([widthConstraint isKindOfClass:[NSString class]] ||
        [widthConstraint isKindOfClass:[NSNumber class]]) {
      int possibleWidth = [widthConstraint intValue];
      if (possibleWidth != 0) {
        targetWidth = possibleWidth;
      }
    }
    id heightConstraint = mandatory[@"minHeight"];
    if ([heightConstraint isKindOfClass:[NSString class]] ||
        [heightConstraint isKindOfClass:[NSNumber class]]) {
      int possibleHeight = [heightConstraint intValue];
      if (possibleHeight != 0) {
        targetHeight = possibleHeight;
      }
    }
    id fpsConstraint = mandatory[@"minFrameRate"];
    if ([fpsConstraint isKindOfClass:[NSString class]] ||
        [fpsConstraint isKindOfClass:[NSNumber class]]) {
      int possibleFps = [fpsConstraint intValue];
      if (possibleFps != 0) {
        targetFps = possibleFps;
      }
    }
  }

  if (videoDevice) {
    RTCVideoSource* videoSource = [self.peerConnectionFactory videoSource];
#if TARGET_OS_OSX
    if (self.videoCapturer) {
      [self.videoCapturer stopCapture];
    }
#endif
      
    VideoProcessingAdapter *videoProcessingAdapter = [[VideoProcessingAdapter alloc] initWithRTCVideoSource:videoSource];
    self.videoCapturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:videoProcessingAdapter];
      
    AVCaptureDeviceFormat* selectedFormat = [self selectFormatForDevice:videoDevice
                                                            targetWidth:targetWidth
                                                           targetHeight:targetHeight];

    CMVideoDimensions selectedDimension = CMVideoFormatDescriptionGetDimensions(selectedFormat.formatDescription);
    NSInteger selectedWidth = (NSInteger) selectedDimension.width;
    NSInteger selectedHeight = (NSInteger) selectedDimension.height;
    NSInteger selectedFps = [self selectFpsForFormat:selectedFormat targetFps:targetFps];

    self._lastTargetFps = selectedFps;
    self._lastTargetWidth = targetWidth;
    self._lastTargetHeight = targetHeight;
    
    NSLog(@"target format %ldx%ld, targetFps: %ld, selected format: %ldx%ld, selected fps %ld", targetWidth, targetHeight, targetFps, selectedWidth, selectedHeight, selectedFps);

    if ([videoDevice lockForConfiguration:NULL]) {
      @try {
        videoDevice.activeVideoMaxFrameDuration = CMTimeMake(1, (int32_t)selectedFps);
        videoDevice.activeVideoMinFrameDuration = CMTimeMake(1, (int32_t)selectedFps);
      } @catch (NSException* exception) {
        NSLog(@"Failed to set active frame rate!\n User info:%@", exception.userInfo);
      }
      [videoDevice unlockForConfiguration];
    }

    [self.videoCapturer startCaptureWithDevice:videoDevice
                                        format:selectedFormat
                                           fps:selectedFps
                             completionHandler:^(NSError* error) {
                               if (error) {
                                 NSLog(@"Start capture error: %@", [error localizedDescription]);
                               }
                             }];

    NSString* trackUUID = [[NSUUID UUID] UUIDString];
    RTCVideoTrack* videoTrack = [self.peerConnectionFactory videoTrackWithSource:videoSource
                                                                        trackId:trackUUID];
    LocalVideoTrack *localVideoTrack = [[LocalVideoTrack alloc] initWithTrack:videoTrack videoProcessing:videoProcessingAdapter];
      
    __weak RTCCameraVideoCapturer* capturer = self.videoCapturer;
    self.videoCapturerStopHandlers[videoTrack.trackId] = ^(CompletionHandler handler) {
      NSLog(@"Stop video capturer, trackID %@", videoTrack.trackId);
      [capturer stopCaptureWithCompletionHandler:handler];
    };

    if (!videoDeviceId) {
      videoDeviceId = videoDevice.uniqueID;
    }

    if (!facingMode) {
      facingMode = videoDevice.position == AVCaptureDevicePositionBack    ? @"environment"
                   : videoDevice.position == AVCaptureDevicePositionFront ? @"user"
                                                                          : @"unspecified";
    }

    videoTrack.settings = @{
      @"deviceId" : videoDeviceId,
      @"kind" : @"videoinput",
      @"width" : [NSNumber numberWithInteger:selectedWidth],
      @"height" : [NSNumber numberWithInteger:selectedHeight],
      @"frameRate" : [NSNumber numberWithInteger:selectedFps],
      @"facingMode" : facingMode,
    };

    [mediaStream addVideoTrack:videoTrack];

    [self.localTracks setObject:localVideoTrack forKey:trackUUID];

    successCallback(mediaStream);
  } else {
    // According to step 6.2.3 of the getUserMedia() algorithm, if there is no
    // source, fail with a new OverconstrainedError.
    errorCallback(@"OverconstrainedError", /* errorMessage */ nil);
  }
}

- (void)mediaStreamRelease:(RTCMediaStream*)stream {
  if (stream) {
    for (RTCVideoTrack* track in stream.videoTracks) {
      [self.localTracks removeObjectForKey:track.trackId];
    }
    for (RTCAudioTrack* track in stream.audioTracks) {
      [self.localTracks removeObjectForKey:track.trackId];
    }
    [self.localStreams removeObjectForKey:stream.streamId];
  }
}

/**
 * Obtains local media content of a specific type. Requests access for the
 * specified {@code mediaType} if necessary. In other words, implements a media
 * type-specific iteration of the {@code getUserMedia()} algorithm.
 *
 * @param mediaType Either {@link AVMediaTypAudio} or {@link AVMediaTypeVideo}
 * which specifies the type of the local media content to obtain.
 * @param constraints The {@code MediaStreamConstraints} which are to be
 * satisfied by the obtained local media content.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is to collect the
 * obtained local media content of the specified {@code mediaType}.
 */
- (void)requestAccessForMediaType:(NSString*)mediaType
                      constraints:(NSDictionary*)constraints
                  successCallback:(NavigatorUserMediaSuccessCallback)successCallback
                    errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
                      mediaStream:(RTCMediaStream*)mediaStream {
  // According to step 6.2.1 of the getUserMedia() algorithm, if there is no
  // source, fail "with a new DOMException object whose name attribute has the
  // value NotFoundError."
  // XXX The following approach does not work for audio in Simulator. That is
  // because audio capture is done using AVAudioSession which does not use
  // AVCaptureDevice there. Anyway, Simulator will not (visually) request access
  // for audio.
  if (mediaType == AVMediaTypeVideo && [self captureDevices].count == 0) {
    // Since successCallback and errorCallback are asynchronously invoked
    // elsewhere, make sure that the invocation here is consistent.
    dispatch_async(dispatch_get_main_queue(), ^{
      errorCallback(@"DOMException", @"NotFoundError");
    });
    return;
  }

#if TARGET_OS_OSX
  if (@available(macOS 10.14, *)) {
#endif
    [AVCaptureDevice requestAccessForMediaType:mediaType
                             completionHandler:^(BOOL granted) {
                               dispatch_async(dispatch_get_main_queue(), ^{
                                 if (granted) {
                                   NavigatorUserMediaSuccessCallback scb =
                                       ^(RTCMediaStream* mediaStream) {
                                         [self getUserMedia:constraints
                                             successCallback:successCallback
                                               errorCallback:errorCallback
                                                 mediaStream:mediaStream];
                                       };

                                   if (mediaType == AVMediaTypeAudio) {
                                     [self getUserAudio:constraints
                                         successCallback:scb
                                           errorCallback:errorCallback
                                             mediaStream:mediaStream];
                                   } else if (mediaType == AVMediaTypeVideo) {
                                     [self getUserVideo:constraints
                                         successCallback:scb
                                           errorCallback:errorCallback
                                             mediaStream:mediaStream];
                                   }
                                 } else {
                                   // According to step 10 Permission Failure of the getUserMedia()
                                   // algorithm, if the user has denied permission, fail "with a new
                                   // DOMException object whose name attribute has the value
                                   // NotAllowedError."
                                   errorCallback(@"DOMException", @"NotAllowedError");
                                 }
                               });
                             }];
#if TARGET_OS_OSX
  } else {
    // Fallback on earlier versions
    NavigatorUserMediaSuccessCallback scb = ^(RTCMediaStream* mediaStream) {
      [self getUserMedia:constraints
          successCallback:successCallback
            errorCallback:errorCallback
              mediaStream:mediaStream];
    };
    if (mediaType == AVMediaTypeAudio) {
      [self getUserAudio:constraints
          successCallback:scb
            errorCallback:errorCallback
              mediaStream:mediaStream];
    } else if (mediaType == AVMediaTypeVideo) {
      [self getUserVideo:constraints
          successCallback:scb
            errorCallback:errorCallback
              mediaStream:mediaStream];
    }
  }
#endif
}

- (void)createLocalMediaStream:(FlutterResult)result {
  NSString* mediaStreamId = [[NSUUID UUID] UUIDString];
  RTCMediaStream* mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];

  self.localStreams[mediaStreamId] = mediaStream;
  result(@{@"streamId" : [mediaStream streamId]});
}

- (void)getSources:(FlutterResult)result {
  NSMutableArray* sources = [NSMutableArray array];
  NSArray* videoDevices =  [self captureDevices];
  for (AVCaptureDevice* device in videoDevices) {
    [sources addObject:@{
      @"facing" : device.positionString,
      @"deviceId" : device.uniqueID,
      @"label" : device.localizedName,
      @"kind" : @"videoinput",
    }];
  }
#if TARGET_OS_IPHONE

  RTCAudioSession* session = [RTCAudioSession sharedInstance];
  for (AVAudioSessionPortDescription* port in session.session.availableInputs) {
    // NSLog(@"input portName: %@, type %@", port.portName,port.portType);
    [sources addObject:@{
      @"deviceId" : port.UID,
      @"label" : port.portName,
      @"groupId" : port.portType,
      @"kind" : @"audioinput",
    }];
  }

  for (AVAudioSessionPortDescription* port in session.currentRoute.outputs) {
    // NSLog(@"output portName: %@, type %@", port.portName,port.portType);
    if (session.currentRoute.outputs.count == 1 && ![port.UID isEqualToString:@"Speaker"]) {
      [sources addObject:@{
        @"deviceId" : @"Speaker",
        @"label" : @"Speaker",
        @"groupId" : @"Speaker",
        @"kind" : @"audiooutput",
      }];
    }
    [sources addObject:@{
      @"deviceId" : port.UID,
      @"label" : port.portName,
      @"groupId" : port.portType,
      @"kind" : @"audiooutput",
    }];
  }
#endif
#if TARGET_OS_OSX
  RTCAudioDeviceModule* audioDeviceModule = [self.peerConnectionFactory audioDeviceModule];

  NSArray* inputDevices = [audioDeviceModule inputDevices];
  for (RTCIODevice* device in inputDevices) {
    [sources addObject:@{
      @"deviceId" : device.deviceId,
      @"label" : device.name,
      @"kind" : @"audioinput",
    }];
  }

  NSArray* outputDevices = [audioDeviceModule outputDevices];
  for (RTCIODevice* device in outputDevices) {
    [sources addObject:@{
      @"deviceId" : device.deviceId,
      @"label" : device.name,
      @"kind" : @"audiooutput",
    }];
  }
#endif
  result(@{@"sources" : sources});
}

#if TARGET_OS_OSX
// gang-chat fork: per-app audio device routing helpers. The CoreAudio ADM
// (type 0) binds its record/playout device only at init time, so on a running
// stream a plain `inputDevice =`/`outputDevice =` assignment is stored but the
// active device keeps reading back as "default". To actually switch, stop the
// affected direction, set the device, then re-init+start it. The ADM's device
// list is also empty until a peer connection is recording/playing, so when the
// requested id isn't present yet we just store it (gcDesiredInput/OutputDeviceId)
// and re-apply from audioDeviceModuleDidUpdateDevices: once the list populates.

// macOS 12 renamed kAudioObjectPropertyElementMaster -> ...Main; keep building
// against older SDKs/deployment targets too.
#ifndef kAudioObjectPropertyElementMain
#define kAudioObjectPropertyElementMain kAudioObjectPropertyElementMaster
#endif

// RTCIODevice.deviceId on macOS is the CoreAudio AudioDeviceID as a string.
// Returns kAudioObjectUnknown when the id can't be parsed.
static AudioDeviceID GCAudioDeviceIDFromString(NSString* deviceId) {
  if (deviceId.length == 0) {
    return kAudioObjectUnknown;
  }
  // The id is an unsigned 32-bit AudioObjectID rendered in base 10.
  const char* utf8 = deviceId.UTF8String;
  char* end = NULL;
  unsigned long value = strtoul(utf8, &end, 10);
  if (end == utf8 || *end != '\0') {
    return kAudioObjectUnknown;  // not a clean integer string
  }
  return (AudioDeviceID)value;
}

// Reads a device's current nominal sample rate, or 0 on failure.
static Float64 GCGetNominalSampleRate(AudioDeviceID device) {
  if (device == kAudioObjectUnknown) {
    return 0;
  }
  AudioObjectPropertyAddress addr = {
      kAudioDevicePropertyNominalSampleRate,
      kAudioObjectPropertyScopeOutput,
      kAudioObjectPropertyElementMain};
  Float64 rate = 0;
  UInt32 size = sizeof(rate);
  OSStatus status = AudioObjectGetPropertyData(device, &addr, 0, NULL, &size, &rate);
  return status == noErr ? rate : 0;
}

// Returns the highest nominal sample rate the device advertises, or 0 on
// failure. Used as the restore target when no clean rate was snapshotted.
static Float64 GCGetMaxAvailableSampleRate(AudioDeviceID device) {
  if (device == kAudioObjectUnknown) {
    return 0;
  }
  AudioObjectPropertyAddress addr = {
      kAudioDevicePropertyAvailableNominalSampleRates,
      kAudioObjectPropertyScopeOutput,
      kAudioObjectPropertyElementMain};
  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(device, &addr, 0, NULL, &size) != noErr || size == 0) {
    return 0;
  }
  UInt32 count = size / sizeof(AudioValueRange);
  AudioValueRange* ranges = (AudioValueRange*)malloc(size);
  if (ranges == NULL) {
    return 0;
  }
  Float64 maxRate = 0;
  if (AudioObjectGetPropertyData(device, &addr, 0, NULL, &size, ranges) == noErr) {
    for (UInt32 i = 0; i < count; i++) {
      if (ranges[i].mMaximum > maxRate) {
        maxRate = ranges[i].mMaximum;
      }
    }
  }
  free(ranges);
  return maxRate;
}

// Sets a device's nominal sample rate. Returns YES on success.
static BOOL GCSetNominalSampleRate(AudioDeviceID device, Float64 rate) {
  if (device == kAudioObjectUnknown || rate <= 0) {
    return NO;
  }
  AudioObjectPropertyAddress addr = {
      kAudioDevicePropertyNominalSampleRate,
      kAudioObjectPropertyScopeOutput,
      kAudioObjectPropertyElementMain};
  OSStatus status =
      AudioObjectSetPropertyData(device, &addr, 0, NULL, sizeof(rate), &rate);
  return status == noErr;
}

// A "clean" rate is the A2DP/high-quality rate (>= 32 kHz). HFP drags the device
// down to 8/16 kHz, so anything below the threshold is the degraded profile we
// don't want to memorise as the restore target.
static const Float64 kGCCleanSampleRateThreshold = 32000.0;

// Remembers a device's nominal sample rate while it's still clean, so call
// teardown can put it back if HFP/SCO dragged it down. No-op once HFP is active.
- (void)gcSnapshotCleanOutputRateFor:(NSString*)deviceId {
  if (deviceId.length == 0) {
    return;
  }
  AudioDeviceID device = GCAudioDeviceIDFromString(deviceId);
  Float64 rate = GCGetNominalSampleRate(device);
  if (rate < kGCCleanSampleRateThreshold) {
    return;
  }
  if (!self.gcCleanOutputSampleRates) {
    self.gcCleanOutputSampleRates = [NSMutableDictionary dictionary];
  }
  self.gcCleanOutputSampleRates[deviceId] = @(rate);
}

// Returns the routing result dict, or nil if the id isn't in the ADM list yet.
- (NSDictionary*)gcApplyInputDevice:(NSString*)deviceId {
  RTCAudioDeviceModule* adm = [self.peerConnectionFactory audioDeviceModule];
  for (RTCIODevice* device in [adm inputDevices]) {
    if ([deviceId isEqualToString:device.deviceId]) {
      BOOL wasRecording = adm.recording;
      NSInteger stopRc = wasRecording ? [adm stopRecording] : 0;
      adm.inputDevice = device;
      NSInteger startRc = wasRecording ? [adm initAndStartRecording] : 0;
      return @{@"routed": @YES, @"applied": @YES,
               @"stopRc": @(stopRc), @"startRc": @(startRc),
               @"nowInput": adm.inputDevice.deviceId ?: @""};
    }
  }
  return nil;
}

- (NSDictionary*)gcApplyOutputDevice:(NSString*)deviceId {
  RTCAudioDeviceModule* adm = [self.peerConnectionFactory audioDeviceModule];
  for (RTCIODevice* device in [adm outputDevices]) {
    if ([deviceId isEqualToString:device.deviceId]) {
      // Capture the clean nominal rate before recording can force HFP, so
      // teardown can restore it. See gcResetAudioOnLeave.
      [self gcSnapshotCleanOutputRateFor:deviceId];
      BOOL wasPlaying = adm.playing;
      NSInteger stopRc = wasPlaying ? [adm stopPlayout] : 0;
      adm.outputDevice = device;
      NSInteger initRc = 0, startRc = 0;
      if (wasPlaying) {
        initRc = [adm initPlayout];
        startRc = [adm startPlayout];
      }
      return @{@"routed": @YES, @"applied": @YES,
               @"stopRc": @(stopRc), @"initRc": @(initRc), @"startRc": @(startRc),
               @"nowOutput": adm.outputDevice.deviceId ?: @""};
    }
  }
  return nil;
}

// Re-apply any pending desired devices once the ADM's device list changes
// (e.g. it just started recording/playing for a freshly connected room).
- (void)gcReapplyDesiredDevices {
  if (self.gcDesiredInputDeviceId.length > 0) {
    [self gcApplyInputDevice:self.gcDesiredInputDeviceId];
  }
  if (self.gcDesiredOutputDeviceId.length > 0) {
    [self gcApplyOutputDevice:self.gcDesiredOutputDeviceId];
  }
}

- (void)gcResetAudioOnLeave {
  RTCAudioDeviceModule* adm = [self.peerConnectionFactory audioDeviceModule];
  // Stop the mic first: it's the recording claim that holds a BT headset in
  // HFP/SCO. Dropping it lets macOS renegotiate back to A2DP.
  if (adm.recording) {
    [adm stopRecording];
  }
  // Restore each output device that got dragged down to an HFP rate during the
  // call. Prefer the clean rate we snapshotted; fall back to the device's max
  // advertised rate. Skip devices already sitting at a clean rate.
  NSMutableSet<NSString*>* candidateIds = [NSMutableSet set];
  if (self.gcCleanOutputSampleRates) {
    [candidateIds addObjectsFromArray:self.gcCleanOutputSampleRates.allKeys];
  }
  if (self.gcDesiredOutputDeviceId.length > 0) {
    [candidateIds addObject:self.gcDesiredOutputDeviceId];
  }
  for (NSString* deviceId in candidateIds) {
    AudioDeviceID device = GCAudioDeviceIDFromString(deviceId);
    if (device == kAudioObjectUnknown) {
      continue;
    }
    Float64 current = GCGetNominalSampleRate(device);
    if (current >= kGCCleanSampleRateThreshold) {
      continue;  // already clean, nothing to undo
    }
    Float64 target = [self.gcCleanOutputSampleRates[deviceId] doubleValue];
    if (target < kGCCleanSampleRateThreshold) {
      target = GCGetMaxAvailableSampleRate(device);
    }
    if (target >= kGCCleanSampleRateThreshold) {
      GCSetNominalSampleRate(device, target);
    }
  }
}
#endif

- (void)selectAudioInput:(NSString*)deviceId result:(FlutterResult)result {
#if TARGET_OS_OSX
  // gang-chat fork: store the desired id (for re-apply once the ADM populates)
  // then route now if the device is already in the list. See gcApplyInputDevice:.
  self.gcDesiredInputDeviceId = deviceId;
  NSDictionary* routed = [self gcApplyInputDevice:deviceId];
  if (result)
    result(routed ?: @{@"routed": @YES, @"applied": @NO, @"deferred": @YES});
  return;
#endif
#if TARGET_OS_IPHONE
  RTCAudioSession* session = [RTCAudioSession sharedInstance];
  for (AVAudioSessionPortDescription* port in session.session.availableInputs) {
    if ([port.UID isEqualToString:deviceId]) {
      if (self.preferredInput != port.portType) {
        self.preferredInput = port.portType;
        [AudioUtils selectAudioInput:self.preferredInput];
      }
      break;
    }
  }
  if (result)
    result(nil);
#endif
  if (result)
    result([FlutterError errorWithCode:@"selectAudioInputFailed"
                               message:[NSString stringWithFormat:@"Error: deviceId not found!"]
                               details:nil]);
}

- (void)selectAudioOutput:(NSString*)deviceId result:(FlutterResult)result {
#if TARGET_OS_OSX
  // gang-chat fork: see selectAudioInput: / gcApplyOutputDevice:.
  self.gcDesiredOutputDeviceId = deviceId;
  NSDictionary* routed = [self gcApplyOutputDevice:deviceId];
  result(routed ?: @{@"routed": @YES, @"applied": @NO, @"deferred": @YES});
  return;
#endif
#if TARGET_OS_IPHONE
  RTCAudioSession* session = [RTCAudioSession sharedInstance];
  NSError* setCategoryError = nil;

  if ([deviceId isEqualToString:@"Speaker"]) {
    [session.session overrideOutputAudioPort:kAudioSessionOverrideAudioRoute_Speaker
                                       error:&setCategoryError];
  } else {
    [session.session overrideOutputAudioPort:kAudioSessionOverrideAudioRoute_None
                                       error:&setCategoryError];
  }

  if (setCategoryError == nil) {
    result(nil);
    return;
  }

  result([FlutterError
      errorWithCode:@"selectAudioOutputFailed"
            message:[NSString
                        stringWithFormat:@"Error: %@", [setCategoryError localizedFailureReason]]
            details:nil]);

#endif
  result([FlutterError errorWithCode:@"selectAudioOutputFailed"
                             message:[NSString stringWithFormat:@"Error: deviceId not found!"]
                             details:nil]);
}

- (void)mediaStreamTrackRelease:(RTCMediaStream*)mediaStream track:(RTCMediaStreamTrack*)track {
  // what's different to mediaStreamTrackStop? only call mediaStream explicitly?
  if (mediaStream && track) {
    track.isEnabled = NO;
    // FIXME this is called when track is removed from the MediaStream,
    // but it doesn't mean it can not be added back using MediaStream.addTrack
    // TODO: [self.localTracks removeObjectForKey:trackID];
    if ([track.kind isEqualToString:@"audio"]) {
      [mediaStream removeAudioTrack:(RTCAudioTrack*)track];
    } else if ([track.kind isEqualToString:@"video"]) {
      [mediaStream removeVideoTrack:(RTCVideoTrack*)track];
    }
  }
}

- (void)mediaStreamTrackHasTorch:(RTCMediaStreamTrack*)track result:(FlutterResult)result {
  if (!self.videoCapturer) {
    result(@NO);
    return;
  }
  if (self.videoCapturer.captureSession.inputs.count == 0) {
    result(@NO);
    return;
  }

  AVCaptureDeviceInput* deviceInput = [self.videoCapturer.captureSession.inputs objectAtIndex:0];
  AVCaptureDevice* device = deviceInput.device;

  result(@([device isTorchModeSupported:AVCaptureTorchModeOn]));
}

- (void)mediaStreamTrackSetTorch:(RTCMediaStreamTrack*)track
                           torch:(BOOL)torch
                          result:(FlutterResult)result {
  if (!self.videoCapturer) {
    NSLog(@"Video capturer is null. Can't set torch");
    return;
  }
  if (self.videoCapturer.captureSession.inputs.count == 0) {
    NSLog(@"Video capturer is missing an input. Can't set torch");
    return;
  }

  AVCaptureDeviceInput* deviceInput = [self.videoCapturer.captureSession.inputs objectAtIndex:0];
  AVCaptureDevice* device = deviceInput.device;

  if (![device isTorchModeSupported:AVCaptureTorchModeOn]) {
    NSLog(@"Current capture device does not support torch. Can't set torch");
    return;
  }

  NSError* error;
  if ([device lockForConfiguration:&error] == NO) {
    NSLog(@"Failed to aquire configuration lock. %@", error.localizedDescription);
    return;
  }

  device.torchMode = torch ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
  [device unlockForConfiguration];

  result(nil);
}

- (void)mediaStreamTrackSetZoom:(RTCMediaStreamTrack*)track
                           zoomLevel:(double)zoomLevel
                          result:(FlutterResult)result {
#if TARGET_OS_OSX
  NSLog(@"Not supported on macOS. Can't set zoom");
  return;
#endif
#if TARGET_OS_IPHONE
  if (!self.videoCapturer) {
    NSLog(@"Video capturer is null. Can't set zoom");
    return;
  }
  if (self.videoCapturer.captureSession.inputs.count == 0) {
    NSLog(@"Video capturer is missing an input. Can't set zoom");
    return;
  }

  AVCaptureDeviceInput* deviceInput = [self.videoCapturer.captureSession.inputs objectAtIndex:0];
  AVCaptureDevice* device = deviceInput.device;

  NSError* error;
  if ([device lockForConfiguration:&error] == NO) {
    NSLog(@"Failed to acquire configuration lock. %@", error.localizedDescription);
    return;
  }
  
  CGFloat desiredZoomFactor = (CGFloat)zoomLevel;
  device.videoZoomFactor = MAX(1.0, MIN(desiredZoomFactor, device.activeFormat.videoMaxZoomFactor));
  [device unlockForConfiguration];

  result(nil);
#endif
}

- (void)mediaStreamTrackCaptureFrame:(RTCVideoTrack*)track
                              toPath:(NSString*)path
                              result:(FlutterResult)result {
  self.frameCapturer = [[FlutterRTCFrameCapturer alloc] initWithTrack:track
                                                               toPath:path
                                                               result:result];
}

- (void)mediaStreamTrackStop:(RTCMediaStreamTrack*)track {
  if (track) {
    track.isEnabled = NO;
    [self.localTracks removeObjectForKey:track.trackId];
  }
}

- (AVCaptureDevice*)findDeviceForPosition:(AVCaptureDevicePosition)position {
  if (position == AVCaptureDevicePositionUnspecified) {
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  }
  NSArray<AVCaptureDevice*>* captureDevices = [RTCCameraVideoCapturer captureDevices];
  for (AVCaptureDevice* device in captureDevices) {
    if (device.position == position) {
      return device;
    }
  }
  if(captureDevices.count > 0) {
    return captureDevices[0];
  }
  return nil;
}

- (AVCaptureDeviceFormat*)selectFormatForDevice:(AVCaptureDevice*)device
                                    targetWidth:(NSInteger)targetWidth
                                   targetHeight:(NSInteger)targetHeight {
  NSArray<AVCaptureDeviceFormat*>* formats =
      [RTCCameraVideoCapturer supportedFormatsForDevice:device];
  AVCaptureDeviceFormat* selectedFormat = nil;
  long currentDiff = INT_MAX;
  for (AVCaptureDeviceFormat* format in formats) {
    CMVideoDimensions dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    FourCharCode pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription);
#if TARGET_OS_IPHONE
    if (@available(iOS 13.0, *)) {
      if(format.isMultiCamSupported != AVCaptureMultiCamSession.multiCamSupported) {
        continue;
      }
    }
#endif
    //NSLog(@"AVCaptureDeviceFormats,fps %d, dimension: %dx%d", format.videoSupportedFrameRateRanges, dimension.width, dimension.height);
    long diff = labs(targetWidth - dimension.width) + labs(targetHeight - dimension.height);
    if (diff < currentDiff) {
      selectedFormat = format;
      currentDiff = diff;
    } else if (diff == currentDiff &&
               pixelFormat == [self.videoCapturer preferredOutputPixelFormat]) {
      selectedFormat = format;
    }
  }
  return selectedFormat;
}

- (NSInteger)selectFpsForFormat:(AVCaptureDeviceFormat*)format targetFps:(NSInteger)targetFps {
  Float64 maxSupportedFramerate = 0;
  for (AVFrameRateRange* fpsRange in format.videoSupportedFrameRateRanges) {
    maxSupportedFramerate = fmax(maxSupportedFramerate, fpsRange.maxFrameRate);
  }
  return fmin(maxSupportedFramerate, targetFps);
}

@end
