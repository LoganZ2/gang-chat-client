#if TARGET_OS_IPHONE
#import <Flutter/Flutter.h>
#elif TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#endif

#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>
#import "LocalTrack.h"

@class FlutterRTCVideoRenderer;
@class FlutterRTCFrameCapturer;
@class FlutterRTCMediaRecorder;
@class AudioManager;

void postEvent(FlutterEventSink _Nullable sink, id _Nullable event);

typedef void (^CompletionHandler)(void);

typedef void (^CapturerStopHandler)(CompletionHandler _Nonnull handler);

@interface FlutterWebRTCPlugin : NSObject <FlutterPlugin,
                                           RTCPeerConnectionDelegate,
                                           RTCAudioDeviceModuleDelegate,
                                           FlutterStreamHandler
#if TARGET_OS_OSX
                                           ,
                                           RTCDesktopMediaListDelegate,
                                           RTCDesktopCapturerDelegate
#endif
                                           >

@property(nonatomic, strong) RTCPeerConnectionFactory* _Nullable peerConnectionFactory;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, RTCPeerConnection*>* _Nullable peerConnections;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, RTCMediaStream*>* _Nullable localStreams;
@property(nonatomic, strong) NSMutableDictionary<NSString*, id<LocalTrack>>* _Nullable localTracks;
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber*, FlutterRTCVideoRenderer*>* _Nullable renders;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, FlutterRTCMediaRecorder*>* _Nonnull recorders;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, CapturerStopHandler>* _Nullable videoCapturerStopHandlers;

@property(nonatomic, strong)
    NSMutableDictionary<NSString*, RTCFrameCryptor*>* _Nullable frameCryptors;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, RTCFrameCryptorKeyProvider*>* _Nullable keyProviders;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, RTCDataPacketCryptor*>* _Nullable dataCryptors;

#if TARGET_OS_IPHONE
@property(nonatomic, retain)
    UIViewController* _Nullable viewController; /*for broadcast or ReplayKit */
#endif

@property(nonatomic, strong) FlutterEventSink _Nullable eventSink;
@property(nonatomic, strong) NSObject<FlutterBinaryMessenger>* _Nonnull messenger;
@property(nonatomic, strong) RTCCameraVideoCapturer* _Nullable videoCapturer;
@property(nonatomic, strong) FlutterRTCFrameCapturer* _Nullable frameCapturer;
@property(nonatomic, strong) AVAudioSessionPort _Nullable preferredInput;

@property(nonatomic, strong) NSString* _Nonnull focusMode;
@property(nonatomic, strong) NSString* _Nonnull exposureMode;

@property(nonatomic) BOOL _usingFrontCamera;
@property(nonatomic) NSInteger _lastTargetWidth;
@property(nonatomic) NSInteger _lastTargetHeight;
@property(nonatomic) NSInteger _lastTargetFps;

@property(nonatomic, strong) AudioManager* _Nullable audioManager;

#if TARGET_OS_OSX
// gang-chat fork: per-app audio device routing. The CoreAudio ADM (type 0)
// binds the device only at init time, so selectAudioInput/Output stop the
// affected direction, set the device, then re-init+start it. The desired
// device ids (CoreAudio AudioDeviceID as string) are stored so they can be
// re-applied once the ADM starts (its device list is empty until a peer
// connection is recording/playing).
@property(nonatomic, copy) NSString* _Nullable gcDesiredInputDeviceId;
@property(nonatomic, copy) NSString* _Nullable gcDesiredOutputDeviceId;

// Bluetooth A2DP<->HFP recovery: starting the mic forces a BT headset into HFP
// (mono, 8/16 kHz), which also drags the device's nominal sample rate down.
// macOS does not reliably restore the high A2DP rate when the call ends, so the
// headset is left "stuck" at the HFP rate and system playback sounds wrong.
// We snapshot the clean (>= 32 kHz) nominal rate per output device id whenever we
// observe one, then force it back on call teardown. See gcResetAudioOnLeave.
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSNumber*>* _Nullable gcCleanOutputSampleRates;

// gang-chat fork: a second PeerConnection factory whose audio device module
// is FlutterScreenAudioDevice (ScreenCaptureKit system audio), fully isolated
// from the primary factory's CoreAudio microphone ADM. Screen-share audio is
// published through PeerConnections created by this factory so it never shares
// an AudioState/AudioTransportImpl with the mic (which would race the send
// stream's capture checker). Lazily created; nil until first use.
@property(nonatomic, strong) RTCPeerConnectionFactory* _Nullable screenAudioPeerConnectionFactory;
 #endif

- (RTCMediaStream* _Nullable)streamForId:(NSString* _Nonnull)streamId
                        peerConnectionId:(NSString* _Nullable)peerConnectionId;
- (RTCMediaStreamTrack* _Nullable)trackForId:(NSString* _Nonnull)trackId
                            peerConnectionId:(NSString* _Nullable)peerConnectionId;
- (NSString* _Nullable)audioTrackIdForVideoTrackId:(NSString* _Nonnull)videoTrackId;
- (RTCRtpTransceiver* _Nullable)getRtpTransceiverById:(RTCPeerConnection* _Nonnull)peerConnection
                                                   Id:(NSString* _Nullable)Id;
- (NSDictionary* _Nullable)mediaStreamToMap:(RTCMediaStream* _Nonnull)stream
                                   ownerTag:(NSString* _Nullable)ownerTag;
- (NSDictionary* _Nullable)mediaTrackToMap:(RTCMediaStreamTrack* _Nonnull)track;
- (NSDictionary* _Nullable)receiverToMap:(RTCRtpReceiver* _Nonnull)receiver;
- (NSDictionary* _Nullable)transceiverToMap:(RTCRtpTransceiver* _Nonnull)transceiver;

- (RTCMediaStreamTrack* _Nullable)remoteTrackForId:(NSString* _Nonnull)trackId;

- (BOOL)hasLocalAudioTrack;
- (void)ensureAudioSession;
- (void)deactiveRtcAudioSession;

- (RTCRtpReceiver* _Nullable)getRtpReceiverById:(RTCPeerConnection* _Nonnull)peerConnection
                                             Id:(NSString* _Nonnull)Id;
- (RTCRtpSender* _Nullable)getRtpSenderById:(RTCPeerConnection* _Nonnull)peerConnection
                                         Id:(NSString* _Nonnull)Id;

+ (FlutterWebRTCPlugin* _Nullable)sharedSingleton;

@end
