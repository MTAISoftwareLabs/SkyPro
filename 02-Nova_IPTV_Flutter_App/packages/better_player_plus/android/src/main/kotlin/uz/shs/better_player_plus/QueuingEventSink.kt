// Copyright 2019 The Chromium Authors. All rights reserved.
package uz.shs.better_player_plus

import io.flutter.plugin.common.EventChannel.EventSink
import java.util.ArrayList

/**
 * EventSink that queues until a Flutter delegate is attached.
 * Caps the queue to avoid unbounded growth during rapid buffering
 * before the EventChannel listener is ready.
 */
internal class QueuingEventSink : EventSink {
    private var delegate: EventSink? = null
    private val eventQueue = ArrayList<Any>(16)
    private var done = false

    fun setDelegate(delegate: EventSink?) {
        this.delegate = delegate
        maybeFlush()
    }

    override fun endOfStream() {
        enqueue(EndOfStreamEvent())
        maybeFlush()
        done = true
    }

    override fun error(code: String, message: String?, details: Any?) {
        enqueue(ErrorEvent(code, message, details))
        maybeFlush()
    }

    override fun success(event: Any) {
        enqueue(event)
        maybeFlush()
    }

    private fun enqueue(event: Any) {
        if (done) return
        // Drop oldest non-error events when capped (keep latest state).
        if (eventQueue.size >= MAX_QUEUE) {
            val idx = eventQueue.indexOfFirst { it !is ErrorEvent && it !is EndOfStreamEvent }
            if (idx >= 0) {
                eventQueue.removeAt(idx)
            } else if (eventQueue.isNotEmpty()) {
                eventQueue.removeAt(0)
            }
        }
        eventQueue.add(event)
    }

    private fun maybeFlush() {
        val sink = delegate ?: return
        for (event in eventQueue) {
            when (event) {
                is EndOfStreamEvent -> sink.endOfStream()
                is ErrorEvent -> sink.error(event.code, event.message, event.details)
                else -> sink.success(event)
            }
        }
        eventQueue.clear()
    }

    private class EndOfStreamEvent
    private class ErrorEvent(
        var code: String,
        var message: String?,
        var details: Any?
    )

    companion object {
        private const val MAX_QUEUE = 32
    }
}
