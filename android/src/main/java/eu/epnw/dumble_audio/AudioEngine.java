package eu.epnw.dumble_audio;

import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;

import java.util.HashMap;
import java.util.Map;

public class AudioEngine {

    public interface RecordingCallback {
        void callback(byte[] buffer);
    }

    private final AudioManager audioManager;
    private final RecordingCallback recordingCallback;
    private final AudioFormat recordingFormat;
    private final AudioFormat playingFormat;

    private AudioRecord audioRecord;

    private boolean microphoneEnabled = false;
    private boolean recording = false;


    Map<Integer, ThreadedAudioTrack> targets = new HashMap<>();

    AudioEngine(AudioFormat recordingFormat, AudioFormat playingFormat, RecordingCallback recordingCallback, Context context) {
        this.recordingCallback = recordingCallback;
        this.recordingFormat = recordingFormat;
        this.playingFormat = playingFormat;
        this.audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        startEngine();
    }

    private void startEngine() {
        //setSpeaker(false);
        setupAudioRecord();
    }

    public void stopEngine() {
        disposeAudioRecord();
        disposeAudioPlay();
    }


    public void setMicrophone(boolean enabled) {
        microphoneEnabled = enabled;
    }

    public void setSpeaker(boolean enabled) {
        if (audioManager == null) {
            DumbleAudioPlugin.print("Audio Manager: null");
            return;
        }
        audioManager.setSpeakerphoneOn(enabled);
    }

    public synchronized void addTarget(int targetId) {
        if (targets.containsKey(targetId)) {
            return;
        }
        ThreadedAudioTrack audioTrack = new ThreadedAudioTrack(targetId, playingFormat);
        targets.put(targetId, audioTrack);
        audioTrack.start();
    }

    public void removeTarget(int targetId) {
        ThreadedAudioTrack audioTrack = targets.remove(targetId);
        if (audioTrack != null) {
            audioTrack.stop();
        }
    }

    public void scheduleBuffer(int targetId, byte[] buffer) {
        ThreadedAudioTrack audioTrack = targets.get(targetId);
        if (audioTrack != null) {
            audioTrack.scheduleBuffer(buffer);
        }
    }
    
    private void setupAudioRecord() {
        final int recordBufferSize = AudioRecord.getMinBufferSize(recordingFormat.getSampleRate(), recordingFormat.getChannelMask(), recordingFormat.getEncoding());
        audioRecord = new AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                .setBufferSizeInBytes(recordBufferSize)
                .setAudioFormat(recordingFormat)
                .build();
        recording = true;
        audioRecord.startRecording();
        final Runnable recordingRunnable = new Runnable() {
            @Override
            public void run() {
                while (recording) {
                    if (microphoneEnabled) {
                        final byte[] buffer = new byte[recordBufferSize];
                        audioRecord.read(buffer, 0, recordBufferSize);
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                recordingCallback.callback(buffer);
                            }
                        });

                    }
                }
            }
        };
        new Thread(recordingRunnable).start();
    }

    private void disposeAudioRecord() {
        if (audioRecord == null) {
            return;
        }
        recording = false;
        audioRecord.stop();
        audioRecord.release();
        audioRecord = null;
    }

    private void disposeAudioPlay() {
        for (ThreadedAudioTrack audioTrack : targets.values()) {
            audioTrack.stop();
        }
        targets.clear();
    }
}


