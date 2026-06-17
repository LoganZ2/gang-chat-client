package com.cloudwebrtc.webrtc.audio;

import org.webrtc.ExternalAudioProcessingFactory;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

public class AudioProcessingAdapter implements ExternalAudioProcessingFactory.AudioProcessing {
    public interface ExternalAudioFrameProcessing {
        void initialize(int sampleRateHz, int numChannels);

        void reset(int newRate);

        void process(int numBands, int numFrames, ByteBuffer buffer);
    }

    public AudioProcessingAdapter() {}
    List<ExternalAudioFrameProcessing> audioProcessors = new ArrayList<>();
    private volatile double processingVolume = 1.0;

    public void setProcessingVolume(double volume) {
        if (Double.isNaN(volume) || Double.isInfinite(volume)) {
            volume = 1.0;
        }
        processingVolume = Math.max(0.0, Math.min(1.0, volume));
    }

    public void addProcessor(ExternalAudioFrameProcessing audioProcessor) {
        synchronized (audioProcessors) {
            audioProcessors.add(audioProcessor);
        }
    }

    public void removeProcessor(ExternalAudioFrameProcessing audioProcessor) {
        synchronized (audioProcessors) {
            audioProcessors.remove(audioProcessor);
        }
    }

    @Override
    public void initialize(int sampleRateHz, int numChannels) {
        synchronized (audioProcessors) {
            for (ExternalAudioFrameProcessing audioProcessor : audioProcessors) {
                audioProcessor.initialize(sampleRateHz, numChannels);
            }
        }
    }

    @Override
    public void reset(int newRate) {
        synchronized (audioProcessors) {
            for (ExternalAudioFrameProcessing audioProcessor : audioProcessors) {
                audioProcessor.reset(newRate);
            }
        }
    }

    @Override
    public void process(int numBands, int numFrames, ByteBuffer buffer) {
        double volume = processingVolume;
        if (volume < 0.999999) {
            ByteBuffer duplicate = buffer.duplicate();
            duplicate.order(buffer.order());
            int sampleCount = duplicate.limit() / 4;
            for (int index = 0; index < sampleCount; index++) {
                int offset = index * 4;
                duplicate.putFloat(offset, (float) (duplicate.getFloat(offset) * volume));
            }
        }
        synchronized (audioProcessors) {
            for (ExternalAudioFrameProcessing audioProcessor : audioProcessors) {
                audioProcessor.process(numBands, numFrames, buffer);
            }
        }
    }
}
