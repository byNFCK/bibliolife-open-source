package org.readium.r2.navigator.epub.continuous

import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.atomic.AtomicLong

/** Immutable provenance for one CSS mutation/measurement epoch. */
internal data class ContinuousCssMutationOwner(
    val token: Long,
    val preferenceGeneration: Long?,
    val transactionGeneration: Long?,
    val layoutGeneration: Int,
    val resourceGeneration: Long,
    val measurementEpoch: Long,
)

/**
 * Synchronous JavaScript bridge gate. Revocation prevents queued scripts from
 * starting a CSS mutation; an already-started synchronous setter is drained
 * asynchronously by its transaction owner before terminal publication.
 */
internal class ContinuousCssMutationGate {
    private data class LeaseState(
        val drained: CompletableDeferred<Unit> = CompletableDeferred(),
        var activeSections: Int = 0,
        var revoked: Boolean = false,
        var mutationStarted: Boolean = false,
    )

    private val lock get() = ownershipLock
    private val states = mutableMapOf<Long, LeaseState>()
    private var currentToken: Long? = null

    fun activate(token: Long) = synchronized(lock) {
        currentToken?.let { oldToken ->
            states[oldToken]?.let { old ->
                old.revoked = true
                if (old.activeSections == 0) {
                    old.drained.complete(Unit)
                    states.remove(oldToken)
                }
            }
        }
        states[token] = LeaseState()
        currentToken = token
    }

    fun begin(token: Long): Boolean = synchronized(lock) {
        val state = states[token] ?: return@synchronized false
        if (currentToken != token || state.revoked) return@synchronized false
        state.activeSections += 1
        true
    }

    fun beginMutation(token: Long): Boolean = synchronized(lock) {
        if (!begin(token)) return@synchronized false
        states.getValue(token).mutationStarted = true
        true
    }

    fun hasMutationObligation(token: Long): Boolean = synchronized(lock) {
        states[token]?.mutationStarted == true
    }

    fun geometryCommitted(token: Long) = synchronized(lock) {
        states[token]?.mutationStarted = false
    }

    companion object {
        // The supersession decision and every resource's JS setter admission
        // share this short synchronous boundary. No coroutine waits under it.
        private val ownershipLock = Any()
        fun <T> withOwnershipLock(block: () -> T): T = synchronized(ownershipLock, block)
    }

    fun end(token: Long) {
        synchronized(lock) {
            val state = states[token] ?: return
            if (state.activeSections == 0) return
            state.activeSections -= 1
            if (state.revoked && state.activeSections == 0) {
                state.drained.complete(Unit)
                if (currentToken != token) states.remove(token)
            }
        }
    }

    fun revoke(token: Long): CompletableDeferred<Unit> = synchronized(lock) {
        val state = states[token] ?: return@synchronized CompletableDeferred(Unit)
        state.revoked = true
        if (currentToken == token) currentToken = null
        if (state.activeSections == 0) {
            state.drained.complete(Unit)
            states.remove(token)
        }
        state.drained
    }

    fun revokeCurrent(): Pair<Long, CompletableDeferred<Unit>>? = synchronized(lock) {
        val token = currentToken ?: return@synchronized null
        val state = states[token] ?: return@synchronized null
        state.revoked = true
        currentToken = null
        if (state.activeSections == 0) {
            state.drained.complete(Unit)
            states.remove(token)
        }
        token to state.drained
    }

    fun isCurrent(token: Long): Boolean = synchronized(lock) {
        currentToken == token && states[token]?.revoked == false
    }
}

internal object ContinuousCssMutationTokenSource {
    private val next = AtomicLong(0)
    fun next(): Long = next.incrementAndGet()
}

internal fun guardedReadiumCssScript(cssPropertiesJson: String, token: Long, textRenderContext: String? = null): String =
    """(function(){
        var gate=window.BiblioLifeContinuousMeasurement;
        if(!gate || !gate.beginCssMutation($token)){return false;}
        try {
            ${if (textRenderContext != null) "if(readium.textRenderDiagnostic){readium.textRenderDiagnostic('before_css',$token,$textRenderContext);}" else ""}
            readium.setCSSProperties($cssPropertiesJson); gate.cssApplied($token);
            ${if (textRenderContext != null) "if(readium.textRenderDiagnostic){readium.textRenderDiagnostic('after_css',$token);}" else ""}
            return true;
        }
        finally { gate.endCssApply($token); }
    })()"""
