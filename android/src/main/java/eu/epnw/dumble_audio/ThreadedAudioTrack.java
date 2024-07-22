package eu.epnw.dumble_audio;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingDeque;
import java.util.concurrent.TimeUnit;

public class ThreadedAudioTrack implements Runnable {
    private final BlockingQueue<byte[]> queue;
    private final AudioFormat playingFormat;
    private final int id;
    private boolean running;
    private boolean started;

    public ThreadedAudioTrack(int id, AudioFormat playingFormat) {
        this.id = id;
        this.playingFormat = playingFormat;
        this.queue = new LinkedBlockingDeque<>();
    }

    public void start() {
        if (!running && !started) {
            running = true;
            started = true;
            Thread t = new Thread(this, "ThreadedAudioTrack" + id);
            t.setDaemon(true);
            t.start();
        }
    }

    public void stop() {
        running = false;
    }

    public void scheduleBuffer(byte[] buffer) {
        queue.add(buffer);
    }

    @Override
    public void run() {
        final int bufferSize = AudioTrack.getMinBufferSize(playingFormat.getSampleRate(), playingFormat.getChannelMask(), playingFormat.getEncoding());
        final AudioTrack audioTrack = new AudioTrack.Builder()
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build())
                .setAudioFormat(playingFormat)
                .build();
        audioTrack.play();
        while (running) {
            byte[] buffer;
            try {
                buffer = queue.poll(500, TimeUnit.MILLISECONDS);
            } catch (InterruptedException e) {
                continue;
            }
            if (buffer == null) {
                continue;
            }
            audioTrack.write(ByteBuffer.wrap(buffer, 0, buffer.length).order(ByteOrder.LITTLE_ENDIAN),
                    buffer.length, AudioTrack.WRITE_BLOCKING);
        }
        audioTrack.stop();
        audioTrack.release();
    }
}
