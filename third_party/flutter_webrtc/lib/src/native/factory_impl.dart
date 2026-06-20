import 'dart:async';

import 'package:webrtc_interface/webrtc_interface.dart';

import '../desktop_capturer.dart';
import 'data_packet_cryptor_impl.dart';
import 'desktop_capturer_impl.dart';
import 'frame_cryptor_impl.dart';
import 'media_recorder_impl.dart';
import 'media_stream_impl.dart';
import 'media_stream_track_impl.dart';
import 'mediadevices_impl.dart';
import 'navigator_impl.dart';
import 'rtc_peerconnection_impl.dart';
import 'rtc_video_renderer_impl.dart';
import 'utils.dart';

class RTCFactoryNative extends RTCFactory {
  RTCFactoryNative._internal();

  static final RTCFactory instance = RTCFactoryNative._internal();

  @override
  Future<MediaStream> createLocalMediaStream(String label) async {
    final response = await WebRTC.invokeMethod('createLocalMediaStream');
    if (response == null) {
      throw Exception('createLocalMediaStream return null, something wrong');
    }
    return MediaStreamNative(response['streamId'], label);
  }

  @override
  Future<RTCPeerConnection> createPeerConnection(
      Map<String, dynamic> configuration,
      [Map<String, dynamic> constraints = const {}]) async {
    var defaultConstraints = <String, dynamic>{
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };

    final response = await WebRTC.invokeMethod(
      'createPeerConnection',
      <String, dynamic>{
        'configuration': configuration,
        'constraints': constraints.isEmpty ? defaultConstraints : constraints
      },
    );

    String peerConnectionId = response['peerConnectionId'];
    return RTCPeerConnectionNative(peerConnectionId, configuration);
  }

  @override
  MediaRecorder mediaRecorder() {
    return MediaRecorderNative();
  }

  @override
  VideoRenderer videoRenderer() {
    return RTCVideoRenderer();
  }

  @override
  Navigator get navigator => NavigatorNative.instance;

  @override
  FrameCryptorFactory get frameCryptorFactory =>
      FrameCryptorFactoryImpl.instance;

  @override
  Future<RTCRtpCapabilities> getRtpReceiverCapabilities(String kind) async {
    final response = await WebRTC.invokeMethod(
      'getRtpReceiverCapabilities',
      <String, dynamic>{
        'kind': kind,
      },
    );
    return RTCRtpCapabilities.fromMap(response);
  }

  @override
  Future<RTCRtpCapabilities> getRtpSenderCapabilities(String kind) async {
    final response = await WebRTC.invokeMethod(
      'getRtpSenderCapabilities',
      <String, dynamic>{
        'kind': kind,
      },
    );
    return RTCRtpCapabilities.fromMap(response);
  }
}

Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration,
    [Map<String, dynamic> constraints = const {}]) async {
  return RTCFactoryNative.instance
      .createPeerConnection(configuration, constraints);
}

Future<MediaStream> createLocalMediaStream(String label) async {
  return RTCFactoryNative.instance.createLocalMediaStream(label);
}

Future<RTCRtpCapabilities> getRtpReceiverCapabilities(String kind) async {
  return RTCFactoryNative.instance.getRtpReceiverCapabilities(kind);
}

Future<RTCRtpCapabilities> getRtpSenderCapabilities(String kind) async {
  return RTCFactoryNative.instance.getRtpSenderCapabilities(kind);
}

MediaRecorder mediaRecorder() {
  return RTCFactoryNative.instance.mediaRecorder();
}

Navigator get navigator => RTCFactoryNative.instance.navigator;

DesktopCapturer get desktopCapturer => DesktopCapturerNative.instance;

MediaDevices get mediaDevices => MediaDeviceNative.instance;

FrameCryptorFactory get frameCryptorFactory => FrameCryptorFactoryImpl.instance;

DataPacketCryptorFactory get dataPacketCryptorFactory =>
    DataPacketCryptorFactoryImpl.instance;

// gang-chat fork: screen-share audio isolation (macOS).
//
// createScreenAudioPeerConnection creates a PeerConnection on a second
// RTCPeerConnectionFactory whose audio device module is a custom
// FlutterScreenAudioDevice fed by ScreenCaptureKit. This keeps screen audio
// on a fully independent AudioState from the microphone ADM, so the two never
// share a send-stream capture race checker. The returned PeerConnection is
// wired exactly like a normal one (event channel + delegate), so addTransceiver
// / negotiate / dispose all work unchanged.
Future<RTCPeerConnection> createScreenAudioPeerConnection(
    Map<String, dynamic> configuration,
    [Map<String, dynamic> constraints = const {}]) async {
  final response = await WebRTC.invokeMethod(
    'screenAudioCreatePeerConnection',
    <String, dynamic>{
      'configuration': configuration,
      'constraints': constraints.isEmpty
          ? <String, dynamic>{
              'mandatory': <String, dynamic>{},
              'optional': <Map<String, dynamic>>[
                {'DtlsSrtpKeyAgreement': true},
              ],
            }
          : constraints,
    },
  );
  final peerConnectionId = response['peerConnectionId'] as String;
  return RTCPeerConnectionNative(peerConnectionId, configuration);
}

// createScreenAudioTrack creates an audio track on the screen-audio factory.
// Its audio is pulled from FlutterScreenAudioDevice (the second factory's ADM),
// which the ScreenCaptureKit capturer feeds. Returns a MediaStream containing
// the single audio track, matching LocalAudioTrack.create's shape so the
// caller can wrap it with LocalAudioTrack(screenShareAudio, stream, ...).
Future<MediaStream> createScreenAudioTrack() async {
  final response = await WebRTC.invokeMethod('screenAudioCreateTrack');
  final streamId = response['streamId'] as String;
  final stream = MediaStreamNative(streamId, 'local');
  final track = MediaStreamTrackNative.fromMap(response, 'local');
  await stream.addTrack(track, addToNative: false);
  return stream;
}
