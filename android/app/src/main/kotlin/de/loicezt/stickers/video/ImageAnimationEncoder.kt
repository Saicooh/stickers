package de.loicezt.stickers.video

import java.nio.ByteBuffer

/** Flutter supplies composited GIF/WebP frames as unpremultiplied RGBA. */
class ImageAnimationEncoder {
    private val encoder = LibWebP()
    private val pixels = ByteBuffer.allocateDirect(512 * 512 * 4)
    private var started = false
    private var lastTimestamp = -1

    fun begin(config: WebPConfig) {
        check(!started) { "An image animation export is already running" }
        check(encoder.nativeInitEncoder(512, 512, config)) { "Could not initialize WebP encoder" }
        started = true
        lastTimestamp = -1
    }

    fun add(bytes: ByteArray, timestampMs: Int) {
        check(started) { "Image animation encoder is not initialized" }
        require(bytes.size == pixels.capacity()) { "Expected a 512 x 512 RGBA frame" }
        require(timestampMs >= 0 && timestampMs > lastTimestamp) { "Frame timestamps must increase" }
        pixels.clear()
        pixels.put(bytes)
        pixels.rewind()
        check(encoder.nativeAddFrame(pixels, timestampMs)) { "Could not encode animation frame" }
        lastTimestamp = timestampMs
    }

    fun finish(durationMs: Int): ByteArray {
        check(started) { "Image animation encoder is not initialized" }
        require(lastTimestamp >= 0 && durationMs > lastTimestamp) { "Invalid animation duration" }
        try {
            return checkNotNull(encoder.nativeReleaseEncoder(durationMs)) { "Could not assemble animated WebP" }
        } finally {
            cancel()
        }
    }

    fun cancel() {
        if (started) encoder.nativeAbortEncoder()
        started = false
    }
}
