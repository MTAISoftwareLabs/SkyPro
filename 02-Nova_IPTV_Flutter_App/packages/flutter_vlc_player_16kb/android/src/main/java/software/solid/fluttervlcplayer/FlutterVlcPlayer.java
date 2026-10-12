package software.solid.fluttervlcplayer;

import android.content.Context;
import android.graphics.Bitmap;
import android.net.Uri;
import android.util.Base64;
import android.util.Log;
import android.view.View;

import androidx.annotation.Nullable;

import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.RendererDiscoverer;
import org.videolan.libvlc.RendererItem;
import org.videolan.libvlc.interfaces.IMedia;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.view.TextureRegistry;
import software.solid.fluttervlcplayer.Enums.HwAcc;

final class FlutterVlcPlayer implements PlatformView {

    private final String TAG = this.getClass().getSimpleName();
    private final boolean debug = false;
    //
    private final Context context;
    private final VLCTextureView textureView;
    private final TextureRegistry.SurfaceTextureEntry textureEntry;
    //
    private final QueuingEventSink mediaEventSink = new QueuingEventSink();
    private final EventChannel mediaEventChannel;
    //
    private final QueuingEventSink rendererEventSink = new QueuingEventSink();
    private final EventChannel rendererEventChannel;
    //
    private LibVLC libVLC;
    private MediaPlayer mediaPlayer;
    private List<String> options;
    private List<RendererDiscoverer> rendererDiscoverers = new ArrayList<>();
    private List<RendererItem> rendererItems = new ArrayList<>();
    private boolean isDisposed = false;

    // Platform view
    @Override
    public View getView() {
        return textureView;
    }

    @Override
    public void dispose() {
        if (isDisposed)
            return;
        //
        textureView.dispose();
        textureEntry.release();
        mediaEventChannel.setStreamHandler(null);
        rendererEventChannel.setStreamHandler(null);
        if (mediaPlayer != null) {
            try {
                if (mediaPlayer.isPlaying()) {
                    mediaPlayer.pause();
                }
            } catch (Exception ignored) {
            }
            mediaPlayer.setEventListener(null);
            mediaPlayer.getVLCVout().detachViews();
            mediaPlayer.release();
            mediaPlayer = null;
        }
        if (libVLC != null) {
            libVLC.release();
            libVLC = null;
        }
        isDisposed = true;
    }

    // VLC Player
    FlutterVlcPlayer(int viewId, Context context, BinaryMessenger binaryMessenger, TextureRegistry textureRegistry) {
        this.context = context;
        // event for media
        mediaEventChannel = new EventChannel(binaryMessenger, "flutter_video_plugin/getVideoEvents_" + viewId);
        mediaEventChannel.setStreamHandler(
                new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object o, EventChannel.EventSink sink) {
                        mediaEventSink.setDelegate(sink);
                    }

                    @Override
                    public void onCancel(Object o) {
                        mediaEventSink.setDelegate(null);
                    }
                });
        // event for renderer
        rendererEventChannel = new EventChannel(binaryMessenger, "flutter_video_plugin/getRendererEvents_" + viewId);
        rendererEventChannel.setStreamHandler(
                new EventChannel.StreamHandler() {
                    @Override
                    public void onListen(Object o, EventChannel.EventSink sink) {
                        rendererEventSink.setDelegate(sink);
                    }

                    @Override
                    public void onCancel(Object o) {
                        rendererEventSink.setDelegate(null);
                    }
                });
        //
        textureEntry = textureRegistry.createSurfaceTexture();
        textureView = new VLCTextureView(context);
        textureView.setSurfaceTexture(textureEntry.surfaceTexture());
        textureView.forceLayout();
        textureView.setFitsSystemWindows(true);
    }

    public void initialize(List<String> options) {
        this.options = options;
        libVLC = new LibVLC(context, options);
        mediaPlayer = new MediaPlayer(libVLC);
        setupVlcMediaPlayer();
    }

    private void setupVlcMediaPlayer() {

        //
        mediaPlayer.getVLCVout().setWindowSize(textureView.getWidth(), textureView.getHeight());
        mediaPlayer.getVLCVout().setVideoSurface(textureView.getSurfaceTexture());
        textureView.setTextureEntry(textureEntry);
        textureView.setMediaPlayer(mediaPlayer);
        mediaPlayer.setVideoTrackEnabled(true);
        //
        mediaPlayer.setEventListener(
                new MediaPlayer.EventListener() {
                    @Override
                    public void onEvent(MediaPlayer.Event event) {
                        HashMap<String, Object> eventObject = new HashMap<>();
                        //
                        // Get video dimensions from texture view as fallback
                        int height = textureView.getHeight();
                        int width = textureView.getWidth();
                        //
                        switch (event.type) {

                            case MediaPlayer.Event.Opening:
                                eventObject.put("event", "opening");
                                mediaEventSink.success(eventObject);
                                break;

                            case MediaPlayer.Event.Paused:
                                eventObject.put("event", "paused");
                                mediaEventSink.success(eventObject);
                                break;

                            case MediaPlayer.Event.Stopped:
                                eventObject.put("event", "stopped");
                                mediaEventSink.success(eventObject);
                                break;

                            case MediaPlayer.Event.Playing:
                                eventObject.put("event", "playing");
                                eventObject.put("height", height);
                                eventObject.put("width", width);
                                eventObject.put("speed", mediaPlayer.getRate());
                                eventObject.put("duration", mediaPlayer.getLength());
                                eventObject.put("audioTracksCount", getAudioTracksCount());
                                eventObject.put("activeAudioTrack", getAudioTrack());
                                eventObject.put("spuTracksCount", getSpuTracksCount());
                                eventObject.put("activeSpuTrack", getSpuTrack());
                                mediaEventSink.success(eventObject.clone());
                                break;

                            case MediaPlayer.Event.Vout:
                                break;

                            case MediaPlayer.Event.EndReached:
                                eventObject.put("event", "ended");
                                eventObject.put("position", mediaPlayer.getTime());
                                mediaEventSink.success(eventObject);
                                break;

                            case MediaPlayer.Event.Buffering:
                            case MediaPlayer.Event.TimeChanged:
                                eventObject.put("event", "timeChanged");
                                eventObject.put("height", height);
                                eventObject.put("width", width);
                                eventObject.put("speed", mediaPlayer.getRate());
                                eventObject.put("position", mediaPlayer.getTime());
                                eventObject.put("duration", mediaPlayer.getLength());
                                eventObject.put("buffer", event.getBuffering());
                                eventObject.put("audioTracksCount", getAudioTracksCount());
                                eventObject.put("activeAudioTrack", getAudioTrack());
                                eventObject.put("spuTracksCount", getSpuTracksCount());
                                eventObject.put("activeSpuTrack", getSpuTrack());
                                eventObject.put("isPlaying", mediaPlayer.isPlaying());
                                mediaEventSink.success(eventObject);
                                break;

                            case MediaPlayer.Event.EncounteredError:
                                eventObject.put("event", "error");
                                mediaEventSink.success(eventObject);
                                break;

                            case MediaPlayer.Event.RecordChanged:
                                eventObject.put("event", "recording");
                                eventObject.put("isRecording", event.getRecording());
                                eventObject.put("recordPath", event.getRecordPath());
                                mediaEventSink.success(eventObject);
                                break;

                            case MediaPlayer.Event.LengthChanged:
                            case MediaPlayer.Event.MediaChanged:
                            case MediaPlayer.Event.ESAdded:
                            case MediaPlayer.Event.ESDeleted:
                            case MediaPlayer.Event.ESSelected:
                            case MediaPlayer.Event.PausableChanged:
                            case MediaPlayer.Event.SeekableChanged:
                            case MediaPlayer.Event.PositionChanged:
                            default:
                                break;
                        }
                    }
                }
        );
    }

    void play() {
        if (mediaPlayer != null && !mediaPlayer.isPlaying()) {
            mediaPlayer.play();
        }
    }

    void pause() {
        if (mediaPlayer != null && mediaPlayer.isPlaying()) {
            mediaPlayer.pause();
        }
    }

    void stop() {
        if (mediaPlayer != null) {
            mediaPlayer.stop();
        }
    }

    boolean isPlaying() {
        if (mediaPlayer == null) return false;
        return mediaPlayer.isPlaying();
    }

    boolean isSeekable() {
        if (mediaPlayer == null) return false;
        return mediaPlayer.isSeekable();
    }

    void setStreamUrl(String url, boolean isAssetUrl, boolean autoPlay, long hwAcc) {
        if (mediaPlayer == null) return;

        try {
            // Prefer pause over stop — stop() blocks Android UI thread on live TS (ANR).
            if (mediaPlayer.isPlaying()) {
                mediaPlayer.pause();
            }
            //
            Media media;
            if (isAssetUrl)
                media = new Media(libVLC, context.getAssets().openFd(url));
            else if (url.startsWith("content://"))
                media = new Media(libVLC, context.getContentResolver().openFileDescriptor(Uri.parse(url), "r").getFileDescriptor());
            else
                media = new Media(libVLC, Uri.parse(url));
            final HwAcc hwAccValue = HwAcc.values()[(int) hwAcc];
            switch (hwAccValue) {
                case DISABLED:
                    media.setHWDecoderEnabled(false, false);
                    break;
                case DECODING:
                case FULL:
                    media.setHWDecoderEnabled(true, true);
                    break;
            }
            if (hwAccValue == HwAcc.DECODING) {
                media.addOption(":no-mediacodec-dr");
                media.addOption(":no-omxil-dr");
            }
            if (options != null) {
                for (String option : options)
                    media.addOption(option);
            }
            mediaPlayer.setMedia(media);
            media.release();
            //
            if (autoPlay) {
                mediaPlayer.play();
            }
        } catch (IOException e) {
            log(e.getMessage());
        }
    }

    void setLooping(boolean value) {
        if (mediaPlayer != null) {
            if (mediaPlayer.getMedia() != null)
                mediaPlayer.getMedia().addOption(value ? "--loop" : "--no-loop");
        }
    }

    void setVolume(long value) {
        if (mediaPlayer == null) return;

        long bracketedValue = Math.max(0, Math.min(100, value));
        mediaPlayer.setVolume((int) bracketedValue);
    }

    int getVolume() {
        if (mediaPlayer == null) return -1;

        return mediaPlayer.getVolume();
    }

    void setPlaybackSpeed(double value) {
        if (mediaPlayer == null) return;

        mediaPlayer.setRate((float) value);
    }

    float getPlaybackSpeed() {
        if (mediaPlayer == null) return -1.0f;

        return mediaPlayer.getRate();
    }

    void seekTo(long location) {
        if (mediaPlayer == null) return;

        mediaPlayer.setTime(location);
    }

    long getPosition() {
        if (mediaPlayer == null) return -1;

        return mediaPlayer.getTime();
    }

    long getDuration() {
        if (mediaPlayer == null) return -1;

        return mediaPlayer.getLength();
    }

    int getSpuTracksCount() {
        if (mediaPlayer == null) return -1;

        IMedia.Track[] spuTracks = mediaPlayer.getTracks(IMedia.Track.Type.Text);
        return spuTracks != null ? spuTracks.length : 0;
    }

    HashMap<Integer, String> getSpuTracks() {
        if (mediaPlayer == null) return new HashMap<Integer, String>();

        IMedia.Track[] spuTracks = mediaPlayer.getTracks(IMedia.Track.Type.Text);
        HashMap<Integer, String> subtitles = new HashMap<>();
        if (spuTracks != null)
            for (IMedia.Track trackDescription : spuTracks) {
                subtitles.put(Integer.parseInt(trackDescription.id.replaceAll("\\D", "")), trackDescription.name);
            }
        return subtitles;
    }

    void setSpuTrack(int index) {
        if (mediaPlayer == null) return;

        try {
          
            if ( index >= 0) {
            // Select the track by its ID
            mediaPlayer.selectTrack("spu/"+index);
            } else if (index == -1) {
            // Unselect all text tracks
                mediaPlayer.unselectTrackType(IMedia.Track.Type.Text);
            }
        } catch (Exception e) {
        Log.e(TAG, "setAudioTrack failed: " + e.getMessage());
        }
    }

    int getSpuTrack() {
        if (mediaPlayer == null) return -1;

        IMedia.Track track = mediaPlayer.getSelectedTrack(IMedia.Track.Type.Text);
        if(track == null) {
            return -1;
        }
        return Integer.parseInt(track.id.replaceAll("\\D", ""));
    }

    void setSpuDelay(long delay) {
        if (mediaPlayer == null) return;

        mediaPlayer.setSpuDelay(delay);
    }

    long getSpuDelay() {
        if (mediaPlayer == null) return -1;

        return mediaPlayer.getSpuDelay();
    }

    void addSubtitleTrack(String url, boolean isSelected) {
        if (mediaPlayer == null) return;

        mediaPlayer.addSlave(Media.Slave.Type.Subtitle, Uri.parse(url), isSelected);
    }

    int getAudioTracksCount() {
        if (mediaPlayer == null) return -1;

        IMedia.Track[] audioTracks = mediaPlayer.getTracks(IMedia.Track.Type.Audio);
        return audioTracks != null ? audioTracks.length : 0;
    }

    HashMap<Integer, String> getAudioTracks() {
        if (mediaPlayer == null) return new HashMap<Integer, String>();

        IMedia.Track[] audioTracks = mediaPlayer.getTracks(IMedia.Track.Type.Audio);
        HashMap<Integer, String> audios = new HashMap<>();
        float playerFps = novaPlayerFps();
        if (audioTracks != null)
            for (IMedia.Track trackDescription : audioTracks) {
                try {
                    int id = Integer.parseInt(trackDescription.id.replaceAll("\\D", ""));
                    // Keep nova: for stream-info parsing; name/language in last segment for UI.
                    audios.put(id, novaAudioTrackLabel(trackDescription, playerFps));
                } catch (Exception ignored) {
                }
            }
        return audios;
    }

    void setAudioTrack(int index) {
        if (mediaPlayer == null) return;

        try {
            IMedia.Track[] audioTracks = mediaPlayer.getTracks(IMedia.Track.Type.Audio);
            if (index < 0) {
                // Default = first demux audio track (unselect mutes — avoid that).
                if (audioTracks != null && audioTracks.length > 0) {
                    mediaPlayer.selectTrack(audioTracks[0].id);
                }
                return;
            }
            if (audioTracks != null) {
                for (IMedia.Track trackDescription : audioTracks) {
                    try {
                        int id = Integer.parseInt(trackDescription.id.replaceAll("\\D", ""));
                        if (id == index) {
                            mediaPlayer.selectTrack(trackDescription.id);
                            return;
                        }
                    } catch (Exception ignored) {
                    }
                }
            }
            mediaPlayer.selectTrack("audio/" + index);
        } catch (Exception e) {
            Log.e(TAG, "setAudioTrack failed: " + e.getMessage());
        }
    }

    int getAudioTrack() {
        if (mediaPlayer == null) return -1;

        IMedia.Track track = mediaPlayer.getSelectedTrack(IMedia.Track.Type.Audio);
        if(track == null) {
            return -1;
        }
        return Integer.parseInt(track.id.replaceAll("\\D", ""));
    }

    void setAudioDelay(long delay) {
        if (mediaPlayer == null) return;

        mediaPlayer.setAudioDelay(delay);
    }

    long getAudioDelay() {
        if (mediaPlayer == null) return -1;

        return mediaPlayer.getAudioDelay();
    }

    void addAudioTrack(String url, boolean isSelected) {
        if (mediaPlayer == null) return;

        mediaPlayer.addSlave(Media.Slave.Type.Audio, Uri.parse(url), isSelected);
    }

    int getVideoTracksCount() {
        if (mediaPlayer == null) return -1;

        IMedia.Track[] videoTracks = mediaPlayer.getTracks(IMedia.Track.Type.Video);
        return videoTracks != null ? videoTracks.length : 0;

    }

    HashMap<Integer, String> getVideoTracks() {
        if (mediaPlayer == null) return new HashMap<Integer, String>();

        IMedia.Track[] videoTracks = mediaPlayer.getTracks(IMedia.Track.Type.Video);
        HashMap<Integer, String> videos = new HashMap<>();
        float playerFps = novaPlayerFps();
        if (videoTracks != null)
            for (IMedia.Track trackDescription : videoTracks) {
                    videos.put(Integer.parseInt(trackDescription.id.replaceAll("\\D", "")), novaStreamLabel(trackDescription, playerFps));
            }
        return videos;
    }

    void setVideoTrack(int index) {
        if (mediaPlayer == null) return;

        try {
          
            if ( index >= 0) {
            // Select the track by its ID
            mediaPlayer.selectTrack("video/"+index);
            } else if (index == -1) {
            // Unselect all video tracks
                mediaPlayer.unselectTrackType(IMedia.Track.Type.Video);
            }
        } catch (Exception e) {
        Log.e(TAG, "setAudioTrack failed: " + e.getMessage());
        }
    }

    int getVideoTrack() {
        if (mediaPlayer == null) return -1;

        IMedia.Track track = mediaPlayer.getSelectedTrack(IMedia.Track.Type.Video);
        if(track == null) {
            return -1;
        }
        return Integer.parseInt(track.id.replaceAll("\\D", ""));

    }

    void setVideoScale(float scale) {
        if (mediaPlayer == null) return;

        mediaPlayer.setScale(scale);
    }

    float getVideoScale() {
        if (mediaPlayer == null) return -1.0f;

        return mediaPlayer.getScale();
    }

    void setVideoAspectRatio(String aspectRatio) {
        if (mediaPlayer == null) return;

        mediaPlayer.setAspectRatio(aspectRatio);
    }

    String getVideoAspectRatio() {
        if (mediaPlayer == null) return "";

        return mediaPlayer.getAspectRatio();
    }

    void startRendererScanning(String rendererService) {
        if (libVLC == null) return;

        rendererDiscoverers = new ArrayList<>();
        rendererItems = new ArrayList<>();
        //
        RendererDiscoverer.Description[] renderers = RendererDiscoverer.list(libVLC);
        for (RendererDiscoverer.Description renderer : renderers) {
            RendererDiscoverer rendererDiscoverer = new RendererDiscoverer(libVLC, renderer.name);
            try {
                rendererDiscoverer.setEventListener(new RendererDiscoverer.EventListener() {
                    @Override
                    public void onEvent(RendererDiscoverer.Event event) {
                        HashMap<String, Object> eventObject = new HashMap<>();
                        RendererItem item = event.getItem();
                        switch (event.type) {
                            case RendererDiscoverer.Event.ItemAdded:
                                rendererItems.add(item);
                                eventObject.put("event", "attached");
                                eventObject.put("id", item.name);
                                eventObject.put("name", item.displayName);
                                rendererEventSink.success(eventObject);
                                break;

                            case RendererDiscoverer.Event.ItemDeleted:
                                rendererItems.remove(item);
                                eventObject.put("event", "detached");
                                eventObject.put("id", item.name);
                                eventObject.put("name", item.displayName);
                                rendererEventSink.success(eventObject);
                                break;

                            default:
                                break;
                        }
                    }
                });
                rendererDiscoverer.start();
                rendererDiscoverers.add(rendererDiscoverer);
            } catch (Exception ex) {
                rendererDiscoverer.setEventListener(null);
            }
        }
    }

    void stopRendererScanning() {
        if (mediaPlayer == null) return;

        if (isDisposed)
            return;
        //
        for (RendererDiscoverer rendererDiscoverer : rendererDiscoverers) {
            rendererDiscoverer.stop();
            rendererDiscoverer.setEventListener(null);
        }
        rendererDiscoverers.clear();
        rendererItems.clear();
        //
        if (mediaPlayer != null) {
            mediaPlayer.pause();
            mediaPlayer.setRenderer(null);
            mediaPlayer.play();
        }
    }

    ArrayList<String> getAvailableRendererServices() {
        if (libVLC == null) return new ArrayList<String>();

        RendererDiscoverer.Description[] renderers = RendererDiscoverer.list(libVLC);
        ArrayList<String> availableRendererServices = new ArrayList<>();
        for (RendererDiscoverer.Description renderer : renderers) {
            availableRendererServices.add(renderer.name);
        }
        return availableRendererServices;
    }

    HashMap<String, String> getRendererDevices() {
        HashMap<String, String> renderers = new HashMap<>();
        if (rendererItems != null)
            for (RendererItem rendererItem : rendererItems) {
                renderers.put(rendererItem.name, rendererItem.displayName);
            }
        return renderers;
    }

    void castToRenderer(String rendererDevice) {
        if (mediaPlayer == null) return;

        if (isDisposed) {
            return;
        }
        if (mediaPlayer.isPlaying())
            mediaPlayer.pause();

        RendererItem rendererItem = null;
        for (RendererItem item : rendererItems) {
            if (item.name.equals(rendererDevice)) {
                rendererItem = item;
                break;
            }
        }
        mediaPlayer.setRenderer(rendererItem);

        mediaPlayer.play();
    }

    @Nullable
    String getSnapshot() {
        if (textureView == null) return null;
        if (!mediaPlayer.isPlaying()) return null;
        Bitmap bitmap = textureView.getBitmap();
        if (bitmap == null) return null;

        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        bitmap.compress(Bitmap.CompressFormat.JPEG, 100, outputStream);
        return Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP);
    }

    Boolean startRecording(String directory) {
        return mediaPlayer.record(directory, false);
    }

    Boolean stopRecording() {
        if (mediaPlayer == null) return true;
        return mediaPlayer.record(null, false);
    }

    private float novaPlayerFps() {
        if (mediaPlayer == null) return 0f;
        float fps = novaReflectFloat(mediaPlayer, "fps");
        if (fps <= 0f) {
            fps = novaReflectFloat(mediaPlayer, "framesPerSecond");
        }
        return fps;
    }

    private static String novaStreamLabel(IMedia.Track track, float playerFps) {
        String name = track.name != null ? track.name : "";
        String codec = novaReflectString(track, "codec");
        if (codec.isEmpty()) {
            codec = novaReflectString(track, "originalCodec");
        }
        int bitrate = novaReflectInt(track, "bitrate");
        int width = novaReflectInt(track, "width");
        int height = novaReflectInt(track, "height");
        int fpsNum = novaReflectInt(track, "frameRateNum");
        int fpsDen = novaReflectInt(track, "frameRateDen");
        float fps = 0f;
        if (fpsNum > 0) {
            fps = fpsDen > 0 ? (fpsNum / (float) fpsDen) : fpsNum;
        }
        if (fps <= 0f) {
            fps = novaReflectFloat(track, "frameRate");
        }
        if (fps <= 0f) {
            fps = playerFps;
        }
        return "nova:" + codec + "|" + width + "x" + height + "|" + fps + "/1|" + bitrate + "|" + name;
    }

    /** Audio label with language/name for picker UI (still nova: prefixed for stream info). */
    private static String novaAudioTrackLabel(IMedia.Track track, float playerFps) {
        String language = novaReflectString(track, "language");
        if (language.isEmpty()) {
            language = novaReflectString(track, "lang");
        }
        String name = track.name != null ? track.name.trim() : "";
        String display = !name.isEmpty() ? name : language;
        if (display.isEmpty()) {
            display = language;
        }
        String codec = novaReflectString(track, "codec");
        if (codec.isEmpty()) {
            codec = novaReflectString(track, "originalCodec");
        }
        int bitrate = novaReflectInt(track, "bitrate");
        if (display.isEmpty()) {
            display = !codec.isEmpty() ? codec.toUpperCase() : "Audio";
        }
        return "nova:" + codec + "|0x0|0/1|" + bitrate + "|" + display;
    }

    private static String novaReflectString(Object target, String field) {
        try {
            java.lang.reflect.Field f = novaFindField(target.getClass(), field);
            if (f != null) {
                f.setAccessible(true);
                Object v = f.get(target);
                return v != null ? v.toString().trim() : "";
            }
        } catch (Exception ignored) {
        }
        try {
            String getter = "get" + field.substring(0, 1).toUpperCase() + field.substring(1);
            Object v = target.getClass().getMethod(getter).invoke(target);
            return v != null ? v.toString().trim() : "";
        } catch (Exception ignored) {
        }
        return "";
    }

    private static int novaReflectInt(Object target, String field) {
        try {
            java.lang.reflect.Field f = novaFindField(target.getClass(), field);
            if (f != null) {
                f.setAccessible(true);
                return f.getInt(target);
            }
        } catch (Exception ignored) {
        }
        try {
            String getter = "get" + field.substring(0, 1).toUpperCase() + field.substring(1);
            Object v = target.getClass().getMethod(getter).invoke(target);
            if (v instanceof Number) {
                return ((Number) v).intValue();
            }
        } catch (Exception ignored) {
        }
        return 0;
    }

    private static float novaReflectFloat(Object target, String field) {
        try {
            java.lang.reflect.Field f = novaFindField(target.getClass(), field);
            if (f != null) {
                f.setAccessible(true);
                Class<?> t = f.getType();
                if (t == float.class) {
                    return f.getFloat(target);
                }
                if (t == double.class) {
                    return (float) f.getDouble(target);
                }
                Object v = f.get(target);
                if (v instanceof Number) {
                    return ((Number) v).floatValue();
                }
            }
        } catch (Exception ignored) {
        }
        try {
            String getter = "get" + field.substring(0, 1).toUpperCase() + field.substring(1);
            Object v = target.getClass().getMethod(getter).invoke(target);
            if (v instanceof Number) {
                return ((Number) v).floatValue();
            }
        } catch (Exception ignored) {
        }
        return 0f;
    }

    private static java.lang.reflect.Field novaFindField(Class<?> type, String name) {
        Class<?> cursor = type;
        while (cursor != null && cursor != Object.class) {
            try {
                return cursor.getDeclaredField(name);
            } catch (NoSuchFieldException ignored) {
                cursor = cursor.getSuperclass();
            }
        }
        return null;
    }

    private void log(String message) {
        if (debug) {
            Log.d(TAG, message);
        }
    }
}