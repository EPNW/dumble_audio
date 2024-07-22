package eu.epnw.dumble_audio;


import android.content.Context;

import android.media.AudioFormat;

import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;


/**
 * DumbleAudioPlugin
 */
public class DumbleAudioPlugin implements FlutterPlugin, EventChannel.StreamHandler, MethodCallHandler, AudioEngine.RecordingCallback {

    @Override
    public void onAttachedToEngine(FlutterPluginBinding flutterPluginBinding) {
        context = flutterPluginBinding.getApplicationContext();
        methodChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "eu.epnw.dumble_audio/audio");
        methodChannel.setMethodCallHandler(this);

        eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "eu.epnw.dumble_audio/audio_stream");
        eventChannel.setStreamHandler(this);
    }

    private Context context;
    private MethodChannel methodChannel;
    private EventChannel eventChannel;
    private EventChannel.EventSink eventSink;
    private AudioEngine audioEngine;

    private static int getEncoding(int flutterValue) {
        switch (flutterValue) {
            case 0:
                return AudioFormat.ENCODING_PCM_16BIT;
            case 1:
                return AudioFormat.ENCODING_PCM_FLOAT;
            default:
                return AudioFormat.ENCODING_PCM_16BIT;
        }
    }

    private static int getPlayingChannelCount(int flutterValue) {
        switch (flutterValue) {
            case 0:
                return AudioFormat.CHANNEL_OUT_MONO;
            case 1:
                return AudioFormat.CHANNEL_OUT_STEREO;
            default:
                return AudioFormat.CHANNEL_OUT_MONO;
        }
    }

    private static int getRecordingChannelCount(int flutterValue) {
        switch (flutterValue) {
            case 0:
                return AudioFormat.CHANNEL_IN_MONO;
            case 1:
                return AudioFormat.CHANNEL_IN_STEREO;
            default:
                return AudioFormat.CHANNEL_IN_MONO;
        }
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        if (call.method.equals("startEngine")) {
            AudioFormat recordingFormat = new AudioFormat.Builder()
                    .setEncoding(getEncoding(call.<Integer>argument("recordingEncoding")))
                    .setSampleRate(call.<Integer>argument("recordingSampleRate"))
                    .setChannelMask(getRecordingChannelCount(call.<Integer>argument("recordingChannelCount")))
                    .build();

            AudioFormat playingFormat = new AudioFormat.Builder()
                    .setEncoding(getEncoding(call.<Integer>argument("playingEncoding")))
                    .setSampleRate(call.<Integer>argument("playingSampleRate"))
                    .setChannelMask(getPlayingChannelCount(call.<Integer>argument("playingChannelCount")))
                    .build();
            startEngine(recordingFormat, playingFormat);
            result.success(null);
        } else if (call.method.equals("stopEngine")) {
            stopEngine();
            result.success(null);
        } else if (call.method.equals("setMicrophone")) {
            setMicrophone(call.<Boolean>argument("enabled"));
            result.success(null);
        } else if (call.method.equals("addTarget")) {
            addTarget(call.<Integer>argument("targetId"));
            result.success(null);
        } else if (call.method.equals("removeTarget")) {
            removeTarget(call.<Integer>argument("targetId"));
            result.success(null);
        } else if (call.method.equals("scheduleBuffer")) {
            scheduleBuffer(call.<Integer>argument("targetId"), call.<byte[]>argument("buffer"));
            result.success(null);
        } else if (call.method.equals("setSpeaker")) {
            setSpeaker(call.<Boolean>argument("enabled"));
            result.success(null);
        } else {
            result.notImplemented();
        }
    }


    private void startEngine(AudioFormat recordingFormat, AudioFormat playingFormat) {
        if (audioEngine != null) {
            print("Error: Audio Engine already started");
            return;
        }
        audioEngine = new AudioEngine(recordingFormat, playingFormat, this, context);
    }

    private void stopEngine() {
        if (audioEngine == null) {
            print("Error: Audio Engine not started");
            return;
        }
        audioEngine.stopEngine();
        audioEngine = null;
    }

    private void setMicrophone(boolean enabled) {
        if (audioEngine == null) {
            print("Error: Audio Engine not started");
            return;
        }
        audioEngine.setMicrophone(enabled);
    }

    private void setSpeaker(boolean enabled) {
        if (audioEngine == null) {
            print("Error: Audio Engine not started");
        }
        audioEngine.setSpeaker(enabled);
    }

    private void addTarget(int targetId) {
        if (audioEngine == null) {
            print("Error: Audio Engine not started");
            return;
        }
        audioEngine.addTarget(targetId);
    }

    private void removeTarget(int targetId) {
        if (audioEngine == null) {
            print("Error: Audio Engine not started");
            return;
        }
        audioEngine.removeTarget(targetId);
    }

    private void scheduleBuffer(int targetId, byte[] buffer) {
        if (audioEngine == null) {
            print("Error: Audio Engine not started");
            return;
        }
        audioEngine.scheduleBuffer(targetId, buffer);
    }


    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        methodChannel.setMethodCallHandler(null);
        eventChannel.setStreamHandler(null);
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        eventSink = events;
    }

    @Override
    public void onCancel(Object arguments) {
        eventSink = null;
    }

    public static void print(String message) {
        Log.i("Dumble Audio", message);
    }

    @Override
    public void callback(byte[] buffer) {
        if (eventSink == null) {
            return;
        }
        eventSink.success(buffer);
    }
}
