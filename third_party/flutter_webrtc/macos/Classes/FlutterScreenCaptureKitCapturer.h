#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

@interface FlutterScreenCaptureKitCapturer : NSObject

- (instancetype _Nonnull)initWithDelegate:(id<RTCVideoCapturerDelegate> _Nonnull)delegate;

/// Starts screen capture. When `captureAudio` is YES, ScreenCaptureKit also
/// captures system audio; those audio sample buffers are forwarded to the
/// shared `FlutterScreenAudioDevice` (the second factory's ADM), NOT mixed
/// into the microphone. The audio is therefore published through an isolated
/// screen-audio track, fully independent of the mic.
- (void)startCaptureWithFPS:(NSInteger)fps
                   sourceId:(NSString* _Nullable)sourceId
              captureWindow:(BOOL)captureWindow
               captureAudio:(BOOL)captureAudio
                  onStarted:(void (^_Nonnull)(NSError* _Nullable error))onStarted;

/// Starts an AUDIO-ONLY ScreenCaptureKit stream filtered to the window
/// identified by `sourceId`. No video output is added; the captured audio
/// sample buffers are forwarded to the shared `FlutterScreenAudioDevice`.
/// Used for window screen-share, where the video is captured separately by
/// RTCDesktopCapturer (SCK window video capture has quirks) but the window
/// application's audio still needs to flow to the isolated screen-audio track.
/// Requires macOS 13.0+.
- (void)startAudioOnlyCaptureForWindowSourceId:(NSString* _Nonnull)sourceId
                                     onStarted:(void (^_Nonnull)(NSError* _Nullable error))onStarted;

- (void)stopCaptureWithCompletion:(void (^_Nonnull)(void))completion;

@end
