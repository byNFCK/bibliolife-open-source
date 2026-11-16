package org.readium.r2.navigator.epub.continuous

import android.view.View
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.LinearLayoutManager
import kotlinx.coroutines.CompletableDeferred

/**
 * Passive, package-internal observation point for JVM tests of the real host.
 * Runtime always uses [None]; this binding owns neither readiness nor restore
 * semantics and can only drive a real RecyclerView layout pass.
 */
/**
 * Passive observation of the same real holder lifecycle used at runtime.
 * It has no Locator, Progress, readiness, or materialization authority.
 */
internal interface ContinuousResourceMaterializationObserver {
    fun onResourceAttached(materialization: ContinuousResourceMaterialization)
    fun onResourceDetached(materialization: ContinuousResourceMaterialization)
}

internal data class ContinuousResourceMaterialization(
    val target: ContinuousReflowTarget,
    val resource: ContinuousResourceView,
)

internal interface ContinuousReflowHostTestBinding : ContinuousResourceMaterializationObserver {
    fun onTargetCreated(target: ContinuousReflowTarget, recyclerView: RecyclerView)
    fun onAuthoritativeRestore(target: ContinuousReflowTarget, recyclerView: RecyclerView)

    data object None : ContinuousReflowHostTestBinding {
        override fun onTargetCreated(target: ContinuousReflowTarget, recyclerView: RecyclerView) = Unit
        override fun onAuthoritativeRestore(target: ContinuousReflowTarget, recyclerView: RecyclerView) = Unit
        override fun onResourceAttached(materialization: ContinuousResourceMaterialization) = Unit
        override fun onResourceDetached(materialization: ContinuousResourceMaterialization) = Unit
    }
}

/** JVM-only driver which retains the real target identity and lays out the real RecyclerView. */
internal class RobolectricContinuousReflowHostTestBinding : ContinuousReflowHostTestBinding {
    var createdTarget: ContinuousReflowTarget? = null
        private set
    var restoredTarget: ContinuousReflowTarget? = null
        private set
    var restoreCount: Int = 0
        private set
    private var recyclerView: RecyclerView? = null
    private val authoritativeRestore = CompletableDeferred<ContinuousReflowTarget>()
    var attachedMaterialization: ContinuousResourceMaterialization? = null
        private set
    private val attachedByTarget = mutableMapOf<ContinuousReflowTarget, ContinuousResourceMaterialization>()
    val detachedMaterializations = mutableListOf<ContinuousResourceMaterialization>()

    override fun onTargetCreated(target: ContinuousReflowTarget, recyclerView: RecyclerView) {
        createdTarget = target
        this.recyclerView = recyclerView
    }

    override fun onAuthoritativeRestore(target: ContinuousReflowTarget, recyclerView: RecyclerView) {
        restoredTarget = target
        restoreCount += 1
        this.recyclerView = recyclerView
        authoritativeRestore.complete(target)
    }

    override fun onResourceAttached(materialization: ContinuousResourceMaterialization) {
        attachedMaterialization = materialization
        attachedByTarget[materialization.target] = materialization
    }

    override fun onResourceDetached(materialization: ContinuousResourceMaterialization) {
        if (attachedMaterialization == materialization) attachedMaterialization = null
        attachedByTarget.remove(materialization.target)
        detachedMaterializations += materialization
    }

    /** Delivers an actual Robolectric RecyclerView measure/layout/global-layout pass. */
    fun commitRecyclerViewLayout(width: Int = 1080, height: Int = 1920) {
        val view = checkNotNull(recyclerView) { "A production target has not been created" }
        view.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, width, height)
        view.viewTreeObserver.dispatchOnGlobalLayout()
    }

    /** Drives the real adapter/layout path to the already-requested target. */
    fun materializeRequestedTarget(width: Int = 1080, height: Int = 1920) {
        val target = checkNotNull(createdTarget) { "A production target has not been created" }
        materializeTarget(target, width, height)
    }

    /** Drives the real adapter/layout path to the supplied already-created target. */
    fun materializeTarget(target: ContinuousReflowTarget, width: Int = 1080, height: Int = 1920) {
        val view = checkNotNull(recyclerView) { "A production RecyclerView has not been observed" }
        // Establish the RecyclerView viewport before asking LinearLayoutManager
        // for an exact item offset, matching the attached runtime order.
        commitRecyclerViewLayout(width, height)
        (view.layoutManager as? LinearLayoutManager)?.scrollToPositionWithOffset(target.index, 0)
            ?: view.scrollToPosition(target.index)
        commitRecyclerViewLayout(width, height)
    }

    fun attachedMaterialization(target: ContinuousReflowTarget): ContinuousResourceMaterialization? = attachedByTarget[target]

    suspend fun awaitAuthoritativeRestore(): ContinuousReflowTarget = authoritativeRestore.await()
}

/** Construction seam only: it does not alter host transaction behavior. */
internal fun interface ContinuousReflowHostFactory {
    fun create(
        context: android.content.Context,
        publication: org.readium.r2.shared.publication.Publication,
        readingOrder: List<org.readium.r2.shared.publication.Link>,
        resourceFactory: ContinuousResourceViewFactory,
        eventPort: ContinuousReflowEventPort,
        testBinding: ContinuousReflowHostTestBinding,
    ): ContinuousReflowableHostView
}

internal object RuntimeContinuousReflowHostFactory : ContinuousReflowHostFactory {
    override fun create(
        context: android.content.Context,
        publication: org.readium.r2.shared.publication.Publication,
        readingOrder: List<org.readium.r2.shared.publication.Link>,
        resourceFactory: ContinuousResourceViewFactory,
        eventPort: ContinuousReflowEventPort,
        testBinding: ContinuousReflowHostTestBinding,
    ) = ContinuousReflowableHostView(context, publication, readingOrder, resourceFactory, eventPort, testBinding)
}
