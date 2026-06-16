#import <Foundation/Foundation.h>
#import "FlutterWebRTCPlugin.h"

@interface RTCMediaStreamTrack (Flutter)
@property(nonatomic, strong, nonnull) id settings;
@end

@interface FlutterWebRTCPlugin (RTCMediaStream)

- (void)getUserMedia:(nonnull NSDictionary*)constraints result:(nonnull FlutterResult)result;

- (void)createLocalMediaStream:(nonnull FlutterResult)result;

- (void)getSources:(nonnull FlutterResult)result;

- (void)mediaStreamTrackCaptureFrame:(nonnull RTCMediaStreamTrack*)track
                              toPath:(nonnull NSString*)path
                              result:(nonnull FlutterResult)result;

- (void)selectAudioInput:(nonnull NSString*)deviceId result:(nullable FlutterResult)result;

- (void)selectAudioOutput:(nonnull NSString*)deviceId result:(nullable FlutterResult)result;

#if TARGET_OS_OSX
// gang-chat fork: re-apply the user's pending device selection once the ADM's
// device list changes (it's empty until a peer connection is recording/playing).
- (void)gcReapplyDesiredDevices;

// gang-chat fork: call on room teardown. Stops the ADM's recording first so a
// Bluetooth headset can drop HFP/SCO, then restores each output device's clean
// (A2DP) nominal sample rate captured during the call. Cures the post-call
// "sample rate mismatch" where BT audio stays stuck at the HFP rate.
- (void)gcResetAudioOnLeave;
#endif
@end
