package app.bibliolife.reader.readium

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import android.util.Log

/** Reader-session search coordinator; all stale work is guarded by a monotonically increasing token. */
internal class EpubSearchController(
    private val scope: CoroutineScope,
    private val gateway: EpubSearchGateway,
    private val state: MutableStateFlow<EpubSearchState>,
) : AutoCloseable {
    private var token = 0L
    private var job: Job? = null
    private var session: EpubSearchSession? = null
    private var query: String = ""
    private val targets = linkedMapOf<String, EpubSearchNavigationTarget>()
    private val obsoleteIds = ArrayDeque<String>()

    fun submitQuery(rawQuery: String) {
        val normalized = rawQuery.trim()
        invalidateTargets()
        cancelActive()
        val request = ++token
        query = normalized
        if (normalized.isEmpty()) { state.value = EpubSearchState.Idle; return }
        state.value = EpubSearchState.Loading(normalized, request)
        job = scope.launch {
            runCatching { gateway.start(normalized) }.onSuccess { started ->
                if (request != token) { started.close(); return@onSuccess }
                session = started
                loadPage(request, emptyList(), false)
            }.onFailure {
                Log.w(TAG, "SEARCH_START_FAILED generation=$request length=${normalized.length} cause=${it.javaClass.simpleName}")
                if (request == token) state.value = EpubSearchState.Error(normalized, request, EpubSearchError.Generic)
            }
        }
    }

    fun loadNextPage() {
        val current = state.value as? EpubSearchState.Results ?: return
        if (current.loadingMore || !current.hasMore) return
        state.value = current.copy(loadingMore = true)
        job = scope.launch { loadPage(current.token, current.results, true) }
    }

    fun retry() = submitQuery(query)
    fun clear() = submitQuery("")

    private suspend fun loadPage(request: Long, existing: List<EpubSearchResult>, loadingMore: Boolean) {
        val active = session ?: return
        active.nextPage().onSuccess { locators ->
            if (request != token) return@onSuccess
            val occurrence = HashMap<String, Int>()
            existing.forEach { result ->
                val locator = targets[result.id]?.locator ?: return@forEach
                val identity = EpubSearchResultMapper.identity(targets[result.id]!!.hit)
                occurrence[identity] = (occurrence[identity] ?: 0) + 1
            }
            val page = locators.map { hit ->
                val identity = EpubSearchResultMapper.identity(hit)
                val index = occurrence[identity] ?: 0
                occurrence[identity] = index + 1
                EpubSearchResultMapper.map(hit, "$request:$identity:$index")
            }
            page.forEach { targets[it.result.id] = it }
            val merged = existing + page.map(EpubSearchNavigationTarget::result)
            if (locators.isEmpty()) {
                active.close(); if (session === active) session = null
                state.value = if (merged.isEmpty()) EpubSearchState.Empty(query, request) else EpubSearchState.Results(query, request, merged, false, false)
            } else {
                state.value = EpubSearchState.Results(query, request, merged, false, true)
            }
        }.onFailure {
            Log.w(TAG, "SEARCH_PAGE_FAILED generation=$request existing=${existing.size} cause=${it.javaClass.simpleName}")
            if (request != token) return@onFailure
            if (existing.isNotEmpty()) {
                active.close(); if (session === active) session = null
                state.value = EpubSearchState.Results(query, request, existing, false, false)
            } else {
                active.close(); if (session === active) session = null
                state.value = EpubSearchState.Error(query, request, EpubSearchError.Generic)
            }
        }
    }

    fun targetFor(id: String): TargetResolution = when {
        targets[id] != null -> TargetResolution.Current(targets.getValue(id))
        obsoleteIds.contains(id) -> TargetResolution.Obsolete
        else -> TargetResolution.Unknown
    }

    private fun invalidateTargets() {
        targets.keys.forEach { id ->
            obsoleteIds.addLast(id)
            if (obsoleteIds.size > MAX_OBSOLETE_IDS) obsoleteIds.removeFirst()
        }
        targets.clear()
    }

    private fun cancelActive() { job?.cancel(); job = null; session?.close(); session = null }
    override fun close() { ++token; invalidateTargets(); cancelActive(); state.value = EpubSearchState.Idle }

    sealed interface TargetResolution {
        data class Current(val target: EpubSearchNavigationTarget) : TargetResolution
        data object Unknown : TargetResolution
        data object Obsolete : TargetResolution
    }

    private companion object {
        const val MAX_OBSOLETE_IDS = 512
        const val TAG = "BiblioLifeReadium"
    }
}

/** Session-owned facade used by [ReadiumReaderSession] and JVM tests. */
internal class ReadiumSearchSessionOwner(
    scope: CoroutineScope,
    gateway: EpubSearchGateway,
    state: MutableStateFlow<EpubSearchState> = MutableStateFlow(EpubSearchState.Idle),
) : AutoCloseable {
    private val controller = EpubSearchController(scope, gateway, state)
    private var disposed = false
    val state: StateFlow<EpubSearchState> = state

    fun search(query: String) { if (!disposed) controller.submitQuery(query) }
    fun loadNextPage() { if (!disposed) controller.loadNextPage() }
    fun retry() { if (!disposed) controller.retry() }
    fun clear() { if (!disposed) controller.clear() }
    fun cancel() { clear() }
    fun targetFor(id: String): EpubSearchController.TargetResolution =
        if (disposed) EpubSearchController.TargetResolution.Obsolete else controller.targetFor(id)

    override fun close() {
        if (disposed) return
        disposed = true
        controller.close()
    }
}
