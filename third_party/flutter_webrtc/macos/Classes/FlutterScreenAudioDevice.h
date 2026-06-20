#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import "RTCAudioDevice.h"
NS_ASSUME_NONNULL_BEGIN

/// A send-only `RTCAudioDevice` whose "microphone" is ScreenCaptureKit system
/// audio. It is injected as the audio device module (ADM) of a *second*
/// `RTCPeerConnectionFactory` so that screen audio rides an audio pipeline that
/// is fully independent of the primary factory's CoreAudio microphone.
///
/// Why a whole separate device/factory: in this WebRTC build a factory owns one
/// `AudioState`, whose single ADM capture is fanned out to *every* local audio
/// send stream (`AudioTransportImpl::SendProcessedData`). Pushing screen audio
/// into a custom `RTCAudioSource` on the primary factory therefore races the
/// microphone capture against the screen-audio thread on the send stream's
/// `audio_capture_race_checker_`, which is a fatal `RTC_CHECK`. Giving screen
/// audio its own factory + ADM removes the shared send path entirely: this
/// device is the only producer for its factory, and it delivers strictly
/// serialized, so the race checker can never trip.
///
/// Playout is never used (the screen-audio participant is publish-only); the
/// playout side returns silence.
@interface FlutterScreenAudioDevice : NSObject <RTCAudioDevice>

/// Shared singleton. The ScreenCaptureKit capturer feeds it; the second
/// factory's ADM reads it. A single device backs the local screen-audio track.
+ (instancetype)sharedInstance;

/// Feed one ScreenCaptureKit audio sample buffer. Safe to call from the SCK
/// capture queue; the data is converted to 48 kHz mono int16 and handed to
/// WebRTC on the device's own serial delivery queue, so deliveries to the
/// native ADM never overlap.
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end

NS_ASSUME_NONNULL_END
