package com.example.viewsys

import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File

@OptIn(UnstableApi::class)
class NativePlayerView(
    private val context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    creationParams: Map<String, Any>?
) : PlatformView, MethodChannel.MethodCallHandler {

    companion object {
        private var cache: SimpleCache? = null

        @Synchronized
        fun getCache(context: Context): SimpleCache {
            if (cache == null) {
                val cacheDir = File(context.cacheDir, "exo_video_cache")
                val evictor = LeastRecentlyUsedCacheEvictor(500 * 1024 * 1024L) // 500MB
                val databaseProvider = StandaloneDatabaseProvider(context)
                cache = SimpleCache(cacheDir, evictor, databaseProvider)
            }
            return cache!!
        }
    }

    // ── UI ────────────────────────────────────────────────────────────
    private val container: FrameLayout = FrameLayout(context)
    private val playerView: PlayerView = PlayerView(context)

    // ── ExoPlayer ─────────────────────────────────────────────────────
    private var exoPlayer: ExoPlayer? = null

    // ── Flutter MethodChannel ─────────────────────────────────────────
    // Flutter calls methods on "native_video_player_$viewId"
    private val methodChannel = MethodChannel(messenger, "native_video_player_$viewId")

    init {
        // Hide player controller UI (pure video, no play/pause buttons)
        playerView.useController = false
        playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        playerView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        container.addView(playerView)

        // Listen for method calls from Flutter
        methodChannel.setMethodCallHandler(this)

        // If Flutter passed a URL via creationParams, start playing immediately
        val initialUrl = creationParams?.get("url") as? String
        val initialLoop = creationParams?.get("loop") as? Boolean ?: true
        val initialVolume = (creationParams?.get("volume") as? Double) ?: 1.0

        if (!initialUrl.isNullOrEmpty()) {
            setupPlayer(initialUrl, initialLoop, initialVolume.toFloat())
        }
    }

    // ── PlatformView interface ────────────────────────────────────────

    override fun getView(): View = container

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        releasePlayer()
    }

    // ── MethodChannel — called from Flutter ───────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                val url = call.argument<String>("url") ?: ""
                val loop = call.argument<Boolean>("loop") ?: true
                val volume = call.argument<Double>("volume") ?: 1.0
                setupPlayer(url, loop, volume.toFloat())
                result.success(null)
            }
            "pause" -> {
                exoPlayer?.pause()
                result.success(null)
            }
            "resume" -> {
                exoPlayer?.play()
                result.success(null)
            }
            "stop" -> {
                exoPlayer?.stop()
                result.success(null)
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume") ?: 1.0
                exoPlayer?.volume = volume.toFloat()
                result.success(null)
            }
            "setLoop" -> {
                val loop = call.argument<Boolean>("loop") ?: true
                exoPlayer?.repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                result.success(null)
            }
            "release" -> {
                releasePlayer()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Player setup ──────────────────────────────────────────────────

    private fun setupPlayer(url: String, loop: Boolean, volume: Float) {
        // Release any previous player instance first
        releasePlayer()

        exoPlayer = ExoPlayer.Builder(context).build().also { player ->
            playerView.player = player

            val uri = Uri.parse(url)
            val defaultDataSourceFactory = DefaultDataSource.Factory(context)
            val cacheDataSourceFactory = CacheDataSource.Factory()
                .setCache(getCache(context))
                .setUpstreamDataSourceFactory(defaultDataSourceFactory)
                .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

            val mediaSource = ProgressiveMediaSource.Factory(cacheDataSourceFactory)
                .createMediaSource(MediaItem.fromUri(uri))

            player.setMediaSource(mediaSource)

            player.repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            player.volume = volume

            // Listen for playback events — notify Flutter when video ends
            player.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) {
                    when (state) {
                        Player.STATE_ENDED -> {
                            // Notify Flutter the video finished (useful when loop=false)
                            methodChannel.invokeMethod("onVideoEnded", null)
                        }
                        Player.STATE_READY -> {
                            methodChannel.invokeMethod("onVideoReady", null)
                        }
                        else -> {}
                    }
                }

                override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                    methodChannel.invokeMethod("onVideoError", error.message)
                }
            })

            player.prepare()
            player.playWhenReady = true
        }
    }

    private fun releasePlayer() {
        exoPlayer?.let { player ->
            player.stop()
            player.release()
        }
        exoPlayer = null
        playerView.player = null
    }
}