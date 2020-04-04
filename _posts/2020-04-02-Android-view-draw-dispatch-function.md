---
layout: post
title: "Android绘制流程2: View的draw函数分发和调用"
description: "Android绘制流程2: View的draw函数分发和调用"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-04-02 23:03:57+00:00
---

> 基于android-8.1.0_r60

## ViewRootImpl

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
private void draw(boolean fullRedrawNeeded) {
    ...
    if (!sFirstDrawComplete) {
        synchronized (sFirstDrawHandlers) {
            sFirstDrawComplete = true;
            final int count = sFirstDrawHandlers.size();
            for (int i = 0; i< count; i++) {
                mHandler.post(sFirstDrawHandlers.get(i));
            }
        }
    }
    ...
    mAttachInfo.mTreeObserver.dispatchOnDraw();
    ...
    mAttachInfo.mDrawingTime = mChoreographer.getFrameTimeNanos() / TimeUtils.NANOS_PER_MS;
    if (!dirty.isEmpty() || mIsAnimating || accessibilityFocusDirty) {
        if (mAttachInfo.mThreadedRenderer != null && mAttachInfo.mThreadedRenderer.isEnabled()) {
            ...
            mAttachInfo.mThreadedRenderer.draw(mView, mAttachInfo, this);
        } else {
            ...
            if (!drawSoftware(surface, mAttachInfo, xOffset, yOffset, scalingRequired, dirty)) {
                return;
            }
        }
    }
    if (animating) {
        mFullRedrawNeeded = true;
        scheduleTraversals();
    }
}
```

其中`mThreadedRenderer`为开启硬件加速后才会实例化的对象。默认不开启，则为空。因此软件绘制会走到下面的`drawSoftware`函数中去。

### # 软件绘制

软件绘制调用`drawSoftware`函数：

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
private boolean drawSoftware(Surface surface, AttachInfo attachInfo, int xoff, int yoff,
        boolean scalingRequired, Rect dirty) {

    // Draw with software renderer.
    final Canvas canvas;
    try {
        ...
        canvas = mSurface.lockCanvas(dirty);
        ...
    }
    ...

    try {
        ...
            mView.draw(canvas);
            drawAccessibilityFocusedDrawableIfNeeded(canvas);
        ...
    }
    ...
    return true;
}
```

可以看到这里会通过当前的Surface创建一个canvas对象，这个创建过程由`lockCanvas`完成。

其实Surface在构造之处就已经创建了Canvas对象，这里的lockCanvas只不过是在底层创建了一个SkBitmap，并调用Canvas对应的NativeCanvas的setBitmap函数设置进去。之后的绘制基于这个Bitmap。

之后调用mView即(DecorView)的draw函数。进入看起来熟悉的步骤了。

### # 硬件绘制

硬件绘制的触发来自下面这句话

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
mAttachInfo.mThreadedRenderer.draw(mView, mAttachInfo, this);
```

直接调用了`mThreadedRenderer`的draw函数，与软件加速看起了就不一样了。

再看硬件加速是如何初始化的：

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
public void setView(View view, WindowManager.LayoutParams attrs, View panelParentView) {
    synchronized (this) {
        if (mView == null) {
            mView = view;
            ...
            if (mSurfaceHolder == null) {
                enableHardwareAcceleration(attrs);
            }
            ...
        }
        ...
    }
}
```



而mThreadedRenderer的初始化是在setView时，通过`enableHardwareAcceleration`完成的。这个函数检测是否用`FLAG_HARDWARE_ACCELERATED`标记了WindowManager.LayoutParams，是则会被认为开启了硬件加速。

#### - ThreadedRenderer.draw

ThreadedRenderer是硬件时用到的核心类。其draw函数实现如下：

```java
// frameworks/base/core/java/android/view/ThreadedRenderer.java
void draw(View view, AttachInfo attachInfo, DrawCallbacks callbacks) {
    attachInfo.mIgnoreDirtyState = true;

    final Choreographer choreographer = attachInfo.mViewRootImpl.mChoreographer;
    // 通知Choreographer中的FrameInfo当前开始绘制
    choreographer.mFrameInfo.markDrawStart();

    // 生成DisplayList(Canvas)，完成对所有2D绘制指令的Recording
    updateRootDisplayList(view, callbacks);

    attachInfo.mIgnoreDirtyState = false;

    // register animating rendernodes which started animating prior to renderer
    // creation, which is typical for animators started prior to first draw
    if (attachInfo.mPendingAnimatingRenderNodes != null) {
        final int count = attachInfo.mPendingAnimatingRenderNodes.size();
        for (int i = 0; i < count; i++) {
            registerAnimatingRenderNode(
                    attachInfo.mPendingAnimatingRenderNodes.get(i));
        }
        attachInfo.mPendingAnimatingRenderNodes.clear();
        // We don't need this anymore as subsequent calls to
        // ViewRootImpl#attachRenderNodeAnimator will go directly to us.
        attachInfo.mPendingAnimatingRenderNodes = null;
    }
    
    // 通知OpenGLPipeline进行硬件绘制
    final long[] frameInfo = choreographer.mFrameInfo.mFrameInfo;
    int syncResult = nSyncAndDrawFrame(mNativeProxy, frameInfo, frameInfo.length);
    ...
}
```

- 通知Choreographer中的FrameInfo当前开始绘制
- 生成DisplayList(Canvas)，完成对所有2D绘制指令的Recording
- 通知OpenGLPipeline进行硬件绘制

其中`updateRootDisplayList`最终会调用到View的draw函数，这里就同软件绘制交汇在一起了。区别在于这里的Canvas对象不一样。硬件绘制的Canvas对象为DisplayCanvas，继承自RecordingCanvas。只用于记录操作指令，并不进行绘制工作。

而最后一个的`nSyncAndDrawFrame`则是进行正针的绘制行为。其中`mNativeProxy`为一个代理Render即RenderProxy，最后其会将当前的绘制命令放入一个DrawFrameTask中去。等待native的绘制线程处理这个绘制任务。

同时`mNativeProxy`在实例化时，已经和RenderNode绑定了，也就是说我们后面在对View的一些反应到RenderNode的操作(比如setTransalationX/Y等等)都会被mNativeProxy使用上。

接上`updateRootDisplayList`-这个函数，继续看如何进入到View的draw函数的。

#### - ThreadedRenderer.updateRootDisplayList

```java
// frameworks/base/core/java/android/view/ThreadedRenderer.java
private void updateRootDisplayList(View view, DrawCallbacks callbacks) {
    Trace.traceBegin(Trace.TRACE_TAG_VIEW, "Record View#draw()");
    // 通知子View进行绘制
    updateViewTreeDisplayList(view);

    if (mRootNodeNeedsUpdate || !mRootNode.isValid()) {
        DisplayListCanvas canvas = mRootNode.start(mSurfaceWidth, mSurfaceHeight);
        try {
            final int saveCount = canvas.save();
            canvas.translate(mInsetLeft, mInsetTop);
            callbacks.onPreDraw(canvas);

            canvas.insertReorderBarrier();
            canvas.drawRenderNode(view.updateDisplayListIfDirty());
            canvas.insertInorderBarrier();

            callbacks.onPostDraw(canvas);
            canvas.restoreToCount(saveCount);
            mRootNodeNeedsUpdate = false;
        } finally {
            mRootNode.end(canvas);
        }
    }
    Trace.traceEnd(Trace.TRACE_TAG_VIEW);
}
```

这里主要是调用View的`updateDisplayListIfDirty`函数，用于创建整个View树的DisplayList和使用RecordingCanvas(DisplayListCanvas)进行绘制指令的记录。

#### - View.updateDisplayListIfDirty

```java
// frameworks/base/core/java/android/view/View.java
public RenderNode updateDisplayListIfDirty() {
    final RenderNode renderNode = mRenderNode;
    if (!canHaveDisplayList()) {
        // can't populate RenderNode, don't try
        return renderNode;
    }

    // 初次setFrame会触发invalidate(true)清除`PFLAG_DRAWING_CACHE_VALID`标识位
    // renderNode由于没有DisplayList，因此isValid()为false。
    if ((mPrivateFlags & PFLAG_DRAWING_CACHE_VALID) == 0
            || !renderNode.isValid()
            || (mRecreateDisplayList)) {
        // Don't need to recreate the display list, just need to tell our
        // children to restore/recreate theirs
        if (renderNode.isValid()
                && !mRecreateDisplayList) {
            mPrivateFlags |= PFLAG_DRAWN | PFLAG_DRAWING_CACHE_VALID;
            mPrivateFlags &= ~PFLAG_DIRTY_MASK;
            dispatchGetDisplayList();

            return renderNode; // no work needed
        }

        // If we got here, we're recreating it. Mark it as such to ensure that
        // we copy in child display lists into ours in drawChild()
        // 除非手动将LAYER_TYPE改成SOFT，或者`PFLAG_INVALIDATED`被清除，`mRecreateDisplayList`将重新变为false。
        mRecreateDisplayList = true;

        int width = mRight - mLeft;
        int height = mBottom - mTop;
        int layerType = getLayerType();

        // RenderNode将其内部持有的native的DisplayListCanvas重置后重新返回给View
        final DisplayListCanvas canvas = renderNode.start(width, height);
        canvas.setHighContrastText(mAttachInfo.mHighContrastText);

        try {
            if (layerType == LAYER_TYPE_SOFTWARE) {
                buildDrawingCache(true);
                Bitmap cache = getDrawingCache(true);
                if (cache != null) {
                    canvas.drawBitmap(cache, 0, 0, mLayerPaint);
                }
            } else {
                computeScroll();
                // 将ScrollX/Y直接作用于Canvas对象
                canvas.translate(-mScrollX, -mScrollY);
                mPrivateFlags |= PFLAG_DRAWN | PFLAG_DRAWING_CACHE_VALID;
                mPrivateFlags &= ~PFLAG_DIRTY_MASK;

                // Fast path for layouts with no backgrounds
                if ((mPrivateFlags & PFLAG_SKIP_DRAW) == PFLAG_SKIP_DRAW) {
                    dispatchDraw(canvas);
                    drawAutofilledHighlight(canvas);
                    if (mOverlay != null && !mOverlay.isEmpty()) {
                        mOverlay.getOverlayView().draw(canvas);
                    }
                    if (debugDraw()) {
                        debugDrawFocus(canvas);
                    }
                } else {
                    draw(canvas);
                }
            }
        } finally {
            // DisplayListCanvas的DisplayList重新绑定到RenderNode中。并且在RenderNode的setStagingDisplayList函数将mValid重新设置为true。
            renderNode.end(canvas);
            setDisplayListProperties(renderNode);
        }
    } else {
        mPrivateFlags |= PFLAG_DRAWN | PFLAG_DRAWING_CACHE_VALID;
        mPrivateFlags &= ~PFLAG_DIRTY_MASK;
    }
    return renderNode;
}
```

大概可以分为如下几个步骤：

- 触发条件

一个View在绘制之前，Canvas需要知道其尺寸位置等信息，用以确定其画框大小位置等等。而其默认的数据一定都是0。因此在第一次layout时，其`setFrame`中获取到其正式的位置信息相对于默认状态下就一定会是changed的状态，此时会触发`invalidate(true)`。这时View的`mPrivateFlags`会被标记上 `PFLAG_DIRTY` 和 `PFLAG_INVALIDATED`，同时`PFLAG_DRAWING_CACHE_VALID`也会被清除掉。

同时初次的时候`mRenderNode`由于没有被设置过DisplayList，因此`mRenderNode.isValid()`将为false。

除非手动将`LAYER_TYPE`改成`LAYER_TYPE_SOFT`，或者`PFLAG_INVALIDATED`被清除，`mRecreateDisplayList`将重新变为false。

- RenderNode将其内部持有的native的DisplayListCanvas重置后重新返回给View。所谓Reset其实是在底层为`DisplayListCanvas`创建了新的`DisplayList`对象。

- 在进入draw之前，如果当前设定了`PFLAG_SKIP_DRAW`，那么将直接跳过draw函数调用`dispatchDraw`。效果就是这个View本身的绘制信息(onDraw也不会调用)将全部丢弃，而child则照常绘制。

- draw结束后将DisplayListCanvas的DisplayList重新绑定到RenderNode中。并且在RenderNode的setStagingDisplayList函数将mValid重新设置为true。

### # 总结

软件绘制是所有的绘制直接操作在SkitBitmap上面。而硬件绘制则是通过RecordingCavans记录所有的绘制指令。最后交由底层管线处理。

下面就看看ViewGroup是如何分配ChildView进行绘制的。即软件绘制和硬件绘制都会调用到的`View.draw()`函数。

## View


```java
// frameworks/base/core/java/android/view/View.java
public void draw(Canvas canvas) {
    final int privateFlags = mPrivateFlags;
    final boolean dirtyOpaque = (privateFlags & PFLAG_DIRTY_MASK) == PFLAG_DIRTY_OPAQUE &&
            (mAttachInfo == null || !mAttachInfo.mIgnoreDirtyState);
    mPrivateFlags = (privateFlags & ~PFLAG_DIRTY_MASK) | PFLAG_DRAWN;

    // Step 1, draw the background, if needed
    int saveCount;

    if (!dirtyOpaque) {
        drawBackground(canvas);
    }

    // skip step 2 & 5 if possible (common case)
    final int viewFlags = mViewFlags;
    boolean horizontalEdges = (viewFlags & FADING_EDGE_HORIZONTAL) != 0;
    boolean verticalEdges = (viewFlags & FADING_EDGE_VERTICAL) != 0;
    if (!verticalEdges && !horizontalEdges) {
        // Step 3, draw the content
        if (!dirtyOpaque) onDraw(canvas);

        // Step 4, draw the children
        dispatchDraw(canvas);

        drawAutofilledHighlight(canvas);

        // Overlay is part of the content and draws beneath Foreground
        if (mOverlay != null && !mOverlay.isEmpty()) {
            mOverlay.getOverlayView().dispatchDraw(canvas);
        }

        // Step 6, draw decorations (foreground, scrollbars)
        onDrawForeground(canvas);

        // Step 7, draw the default focus highlight
        drawDefaultFocusHighlight(canvas);

        if (debugDraw()) {
            debugDrawFocus(canvas);
        }

        // we're done...
        return;
    }
    // 下面有以长段代码。主要是将Fade效果绘制在View之上，Foreground之下。
    // 所谓Fade效果就是滑动到底之后，继续滑动，此时对应的屏幕边缘会有一个灰色圆弧效果。
    // 具体调用流程同上面无区别，略过。
    ....
}
```

- drawBackground

绘制背景。

- onDraw:

这个接口用于绘制View自身的UI效果。比如TextView等文字等等。

如果自定义View，则最好在这个模板函数中操作Canvas实现UI效果即可。

- dispatchDraw

绘制子View。

所有ViewGroup中的子View都是从这个函数里面分发出去的。

- mOverlay

绘制悬浮的View。

- onDrawForeground

绘制前景。

- 其他信息:             

debugDrawFocus:绘制debug信息；drawDefaultFocusHighlight:绘制高亮焦点等；

### # dispatchDraw

主要是服务于ViewGroup的，因此这个函数在View中是空实现。

```java
// frameworks/base/core/java/android/view/ViewGroup.java
@Override
protected void dispatchDraw(Canvas canvas) {
    boolean usingRenderNodeProperties = canvas.isRecordingFor(mRenderNode);
    final int childrenCount = mChildrenCount;
    final View[] children = mChildren;
    int flags = mGroupFlags;

    if ((flags & FLAG_RUN_ANIMATION) != 0 && canAnimate()) {
        ...
    }

    int clipSaveCount = 0;
    final boolean clipToPadding = (flags & CLIP_TO_PADDING_MASK) == CLIP_TO_PADDING_MASK;
    if (clipToPadding) {
        clipSaveCount = canvas.save(Canvas.CLIP_SAVE_FLAG);
        // 用于将Padding剪切出来。这样Child就只能在不包含Padding的区域绘制了。因此，如果可以滚动，那么子View只能除去Padding的区域进行滚动了。
        canvas.clipRect(mScrollX + mPaddingLeft, mScrollY + mPaddingTop,
                mScrollX + mRight - mLeft - mPaddingRight,
                mScrollY + mBottom - mTop - mPaddingBottom);
    }

    // We will draw our child's animation, let's reset the flag
    mPrivateFlags &= ~PFLAG_DRAW_ANIMATION;
    mGroupFlags &= ~FLAG_INVALIDATE_REQUIRED;

    boolean more = false;
    final long drawingTime = getDrawingTime();

    if (usingRenderNodeProperties) canvas.insertReorderBarrier();
    final int transientCount = mTransientIndices == null ? 0 : mTransientIndices.size();
    int transientIndex = transientCount != 0 ? 0 : -1;
    // Only use the preordered list if not HW accelerated, since the HW pipeline will do the
    // draw reordering internally
    final ArrayList<View> preorderedList = usingRenderNodeProperties
            ? null : buildOrderedChildList();
    final boolean customOrder = preorderedList == null
            && isChildrenDrawingOrderEnabled();
    for (int i = 0; i < childrenCount; i++) {
        // 从临时绘制的View列表中，找到所有插入在当前位置的临时View
        // 临时绘制的view不参与ViewGroup的measure/layout过程，仅仅是为了搭上绘制班车。
        // transientView翻译成寄居View可能更合适一些。
        // 寄居View添加的时候，需要指定插入在正式Child列表中的位置，即目标index。mTransientViews则按照插入位置记录了所有的寄居View，而`mTransientIndices`则记录了`mTransientViews`中每个View在列表的位置和Child列表的位置(目标index)。
        // 这段逻辑可以略过。
        while (transientIndex >= 0 && mTransientIndices.get(transientIndex) == i) {
            final View transientChild = mTransientViews.get(transientIndex);
            if ((transientChild.mViewFlags & VISIBILITY_MASK) == VISIBLE ||
                    transientChild.getAnimation() != null) {
                more |= drawChild(canvas, transientChild, drawingTime);
            }
            transientIndex++;
            if (transientIndex >= transientCount) {
                transientIndex = -1;
            }
        }

        // 从`PreorderedIndex`中拿到排好序的View。并调用`drawChild`绘制具体的Child。
        // 等到这个for循环结束，所有的Child也就绘制完成了。
        final int childIndex = getAndVerifyPreorderedIndex(childrenCount, i, customOrder);
        final View child = getAndVerifyPreorderedView(preorderedList, children, childIndex);
        if ((child.mViewFlags & VISIBILITY_MASK) == VISIBLE || child.getAnimation() != null) {
            more |= drawChild(canvas, child, drawingTime);
        }
    }
    // 绘制剩下的寄居View。很有可能某些寄居View设定的目标index过大，超出了所有Child的数量。因此这里需要继续绘制剩下的寄居View。关于寄居的整段代码看起来让人有些费解。
    while (transientIndex >= 0) {
        // there may be additional transient views after the normal views
        final View transientChild = mTransientViews.get(transientIndex);
        if ((transientChild.mViewFlags & VISIBILITY_MASK) == VISIBLE ||
                transientChild.getAnimation() != null) {
            more |= drawChild(canvas, transientChild, drawingTime);
        }
        transientIndex++;
        if (transientIndex >= transientCount) {
            break;
        }
    }
    if (preorderedList != null) preorderedList.clear();

    // 绘制因动画原因，正在消失的View。因为这个View还在做动画，所以还需要画出来。
    if (mDisappearingChildren != null) {
        final ArrayList<View> disappearingChildren = mDisappearingChildren;
        final int disappearingCount = disappearingChildren.size() - 1;
        // Go backwards -- we may delete as animations finish
        for (int i = disappearingCount; i >= 0; i--) {
            final View child = disappearingChildren.get(i);
            more |= drawChild(canvas, child, drawingTime);
        }
    }
    ...
}
```

- ClipToPadding(CLIP_TO_PADDING_MASK)

用于将Padding剪切出来。这样Child就只能在不包含Padding的区域绘制了。因此，如果可以滚动，那么子View只能除去Padding的区域进行滚动了。

这个属性可以WindowInsets，在Translucent状态下，然后可滚动的View(ListView/ScrollView/RecyclerView)能滚动到状态栏/ActionBar底部。

- 遍历所有的Child

按照index从预先排序的Child列表中拿出子View一个个调用drawChild进行绘制。

- 寄居View(transientView)

(可以忽略。)

不包含在ChildView当中，不影响ChildViewCount。

从临时绘制的View列表中，找到所有插入在当前位置的临时View。临时绘制的view不参与ViewGroup的measure/layout过程，仅仅是为了搭上绘制班车。transientView翻译成寄居View可能更合适一些。寄居View添加的时候，需要指定插入在正式Child列表中的位置，即目标index。mTransientViews则按照插入位置记录了所有的寄居View，而`mTransientIndices`则记录了`mTransientViews`中每个View在列表的位置和Child列表的位置(目标index)。

在遍历完所有Child后，如果还有寄居View未被绘制。则会绘制剩下的寄居View。很有可能某些寄居View设定的目标index过大，超出了所有Child的数量。因此这里需要继续绘制剩下的寄居View。

关于寄居的整段代码看起来让人有些费解。

- 绘制正在消失的View

绘制因动画原因，正在消失的View。因为这个View还在做动画，所以还需要画出来。

这些View存在于`mDisappearingChildren`这个list当中。因此遍历这个列表即可。

- getAndVerifyPreorderedView

> ***TODO***

以上的绘制，不论何种子View，都通过同一个绘制函数(即drawChild)进行绘制。

下面继续看如何绘制Child。

### # drawChild

`drawChild`本身很简单。如下：

```java
// frameworks/base/core/java/android/view/ViewGroup.java
protected boolean drawChild(Canvas canvas, View child, long drawingTime) {
    return child.draw(canvas, this, drawingTime);
}
```

可以看到直接调用了View的另一draw函数，进行绘制。需要注意的是，这个draw函数跟ViewRoot调用的draw函数是有不同的签名的。

```java
// frameworks/base/core/java/android/view/View.java
boolean draw(Canvas canvas, ViewGroup parent, long drawingTime) {
    // 判断当前的Canvas是否支持硬件加速。Canvas默认为false。而DisplayListCanvas则为true。
    final boolean hardwareAcceleratedCanvas = canvas.isHardwareAccelerated();
    // 判断当前是否支持硬件加速。如果一个detached，那么它不应该存在DisplayList。如果是软件绘制，那么它将不应该操作RenderNode。
    boolean drawingWithRenderNode = mAttachInfo != null
            && mAttachInfo.mHardwareAccelerated
            && hardwareAcceleratedCanvas;

    boolean more = false;
    final boolean childHasIdentityMatrix = hasIdentityMatrix();
    final int parentFlags = parent.mGroupFlags;

    if ((parentFlags & ViewGroup.FLAG_CLEAR_TRANSFORMATION) != 0) {
        parent.getChildTransformation().clear();
        parent.mGroupFlags &= ~ViewGroup.FLAG_CLEAR_TRANSFORMATION;
    }

    Transformation transformToApply = null;
    boolean concatMatrix = false;
    ...

    concatMatrix |= !childHasIdentityMatrix;

    // Sets the flag as early as possible to allow draw() implementations
    // to call invalidate() successfully when doing animations
    mPrivateFlags |= PFLAG_DRAWN;

    ...
    // 如果是硬件加速，则通过PFLAG_INVALIDATED标识位来判断是否`mRecreateDisplayList`，并清除标识位。
    if (hardwareAcceleratedCanvas) {
        // Clear INVALIDATED flag to allow invalidation to occur during rendering, but
        // retain the flag's value temporarily in the mRecreateDisplayList flag
        mRecreateDisplayList = (mPrivateFlags & PFLAG_INVALIDATED) != 0;
        mPrivateFlags &= ~PFLAG_INVALIDATED;
    }

    RenderNode renderNode = null;
    Bitmap cache = null;
    int layerType = getLayerType(); // TODO: signify cache state with just 'cache' local
    // 如果当前的绘制类型为SOFTWARE或者不开启硬件加速，那么就会创建绘制缓存，即绘制一个bitmap出来。同时缓存会有一上限大小，超过则认为不支持。getScaledMaximumDrawingCacheSize为当前屏幕的总像素即width*height*4(ARGB8888)。
    if (layerType == LAYER_TYPE_SOFTWARE || !drawingWithRenderNode) {
         if (layerType != LAYER_TYPE_NONE) {
             // If not drawing with RenderNode, treat HW layers as SW
             layerType = LAYER_TYPE_SOFTWARE;
             buildDrawingCache(true);
        }
        cache = getDrawingCache(true);
    }

    // 硬件加速绘制的情况下，就调用`updateDisplayListIfDirty`进行硬件绘制。
    if (drawingWithRenderNode) {
        // Delay getting the display list until animation-driven alpha values are
        // set up and possibly passed on to the view
        renderNode = updateDisplayListIfDirty();
        if (!renderNode.isValid()) {
            // Uncommon, but possible. If a view is removed from the hierarchy during the call
            // to getDisplayList(), the display list will be marked invalid and we should not
            // try to use it again.
            renderNode = null;
            drawingWithRenderNode = false;
        }
    }

    int sx = 0;
    int sy = 0;
    if (!drawingWithRenderNode) {
        computeScroll();
        sx = mScrollX;
        sy = mScrollY;
    }

    final boolean drawingWithDrawingCache = cache != null && !drawingWithRenderNode;
    final boolean offsetForScroll = cache == null && !drawingWithRenderNode;

    int restoreTo = -1;
    if (!drawingWithRenderNode || transformToApply != null) {
        restoreTo = canvas.save();
    }
    if (offsetForScroll) {
        canvas.translate(mLeft - sx, mTop - sy);
    } else {
        if (!drawingWithRenderNode) {
            canvas.translate(mLeft, mTop);
        }
        if (scalingRequired) {
            if (drawingWithRenderNode) {
                // TODO: Might not need this if we put everything inside the DL
                restoreTo = canvas.save();
            }
            // mAttachInfo cannot be null, otherwise scalingRequired == false
            final float scale = 1.0f / mAttachInfo.mApplicationScale;
            canvas.scale(scale, scale);
        }
    }

    float alpha = drawingWithRenderNode ? 1 : (getAlpha() * getTransitionAlpha());
    if (transformToApply != null
            || alpha < 1
            || !hasIdentityMatrix()
            || (mPrivateFlags3 & PFLAG3_VIEW_IS_ANIMATING_ALPHA) != 0) {
        if (transformToApply != null || !childHasIdentityMatrix) {
            int transX = 0;
            int transY = 0;

            if (offsetForScroll) {
                transX = -sx;
                transY = -sy;
            }
            ...
            // 处理Matrix。
            if (!childHasIdentityMatrix && !drawingWithRenderNode) {
                canvas.translate(-transX, -transY);
                canvas.concat(getMatrix()); //重要
                canvas.translate(transX, transY);
            }
        }

        // 处理透明度。即正在进行的Alpha动画和Alpha设定。
        if (alpha < 1 || (mPrivateFlags3 & PFLAG3_VIEW_IS_ANIMATING_ALPHA) != 0) {
            if (alpha < 1) {
                mPrivateFlags3 |= PFLAG3_VIEW_IS_ANIMATING_ALPHA;
            } else {
                mPrivateFlags3 &= ~PFLAG3_VIEW_IS_ANIMATING_ALPHA;
            }
            parent.mGroupFlags |= ViewGroup.FLAG_CLEAR_TRANSFORMATION;
            if (!drawingWithDrawingCache) { // 未绘制缓存。因为绘制缓存的时候已经处理过了。
                final int multipliedAlpha = (int) (255 * alpha);
                if (!onSetAlpha(multipliedAlpha)) {
                    if (drawingWithRenderNode) { // 硬件加速的情况，则直接修改RenderNode的Alpha值。
                        renderNode.setAlpha(alpha * getAlpha() * getTransitionAlpha());
                    } else if (layerType == LAYER_TYPE_NONE) {
                        canvas.saveLayerAlpha(sx, sy, sx + getWidth(), sy + getHeight(),
                                multipliedAlpha);
                    }
                } else {
                    // Alpha is handled by the child directly, clobber the layer's alpha
                    mPrivateFlags |= PFLAG_ALPHA_SET;
                }
            }
        }
    } else if ((mPrivateFlags & PFLAG_ALPHA_SET) == PFLAG_ALPHA_SET) {
        onSetAlpha(255);
        mPrivateFlags &= ~PFLAG_ALPHA_SET;
    }

    if (!drawingWithRenderNode) {
        // 限定Child是否允许绘制在自己的区域之外。如果存在FLAG_CLIP_CHILDREN，则不允许。
        if ((parentFlags & ViewGroup.FLAG_CLIP_CHILDREN) != 0 && cache == null) {
            if (offsetForScroll) {
                canvas.clipRect(sx, sy, sx + getWidth(), sy + getHeight());
            } else {
                if (!scalingRequired || cache == null) {
                    canvas.clipRect(0, 0, getWidth(), getHeight());
                } else {
                    canvas.clipRect(0, 0, cache.getWidth(), cache.getHeight());
                }
            }
        }

        if (mClipBounds != null) {
            // 如果用户setClipBounds，则再次ClipView到指定区域大小。
            canvas.clipRect(mClipBounds);
        }
    }

    if (!drawingWithDrawingCache) {
        if (drawingWithRenderNode) {
            mPrivateFlags &= ~PFLAG_DIRTY_MASK;
            // 硬件绘制：此时将RenderNode中收集的参数，作用到前面绘制的结果上。
            ((DisplayListCanvas) canvas).drawRenderNode(renderNode);
        } else {
            // 非绘制缓存：这里同viewGroup类似：如果设定了`PFLAG_SKIP_DRAW`，则不绘制自身。直接`dispatchDraw`，绘制自View。
            // 理论上来说这里不会执行到，原因在于非硬件加速的时候。就一定开启了绘制缓存。但是，绘制缓存还有个bitmap尺寸上限的问题。
            if ((mPrivateFlags & PFLAG_SKIP_DRAW) == PFLAG_SKIP_DRAW) {
                mPrivateFlags &= ~PFLAG_DIRTY_MASK;
                dispatchDraw(canvas);
            } else {
            // 正常绘制
                draw(canvas);
            }
        }
    } else if (cache != null) {
        // 如果绘制缓存，那么将不再调用`dispatchDraw`或者`draw(canvas)`。因为在创建绘制缓存(buildDrawingCache)时这一步已经运行过一次了。
        // 这一步是将缓存的Bitmap绘制到surface创建的Canvas上面。同时也将用户设置的画笔(即`mLayerPaint`)作用到绘制结果上面。
        mPrivateFlags &= ~PFLAG_DIRTY_MASK;
        if (layerType == LAYER_TYPE_NONE || mLayerPaint == null) {
            // no layer paint, use temporary paint to draw bitmap
            Paint cachePaint = parent.mCachePaint;
            if (cachePaint == null) {
                cachePaint = new Paint();
                cachePaint.setDither(false);
                parent.mCachePaint = cachePaint;
            }
            cachePaint.setAlpha((int) (alpha * 255));
            canvas.drawBitmap(cache, 0.0f, 0.0f, cachePaint);
        } else {
            // use layer paint to draw the bitmap, merging the two alphas, but also restore
            int layerPaintAlpha = mLayerPaint.getAlpha();
            if (alpha < 1) {
                mLayerPaint.setAlpha((int) (alpha * layerPaintAlpha));
            }
            canvas.drawBitmap(cache, 0.0f, 0.0f, mLayerPaint);
            if (alpha < 1) {
                mLayerPaint.setAlpha(layerPaintAlpha);
            }
        }
    }

    if (restoreTo >= 0) { //恢复Canvas到绘制前，使不影响其他View。
        canvas.restoreToCount(restoreTo);
    }
    ...
    return more;
}
```

#### - 判断是否是硬件绘制

判断当前的Canvas是否支持硬件加速。Canvas默认为false。而DisplayListCanvas则为true。

通过判断Canvas以及AttachInfo的mHardwareAccelerated。这些逻辑是在enableHardwareAcceleration是设定的。

如果一个detached，那么它不应该存在DisplayList。如果是软件绘制，那么它将不应该操作RenderNode。

#### - 创建绘制缓存

如果当前的绘制类型为SOFTWARE或者不开启硬件加速，那么就会创建绘制缓存，即绘制一个bitmap出来。

同时缓存会有一上限大小，超过此大小则认为不支持。这写在Configuration中：

```java
// frameworks/base/core/java/android/content/res/Configuration.java
private ViewConfiguration(Context context) {
    ...
    final WindowManager win = (WindowManager)context.getSystemService(Context.WINDOW_SERVICE);
    final Display display = win.getDefaultDisplay();
    final Point size = new Point();
    display.getRealSize(size);
    mMaximumDrawingCacheSize = 4 * size.x * size.y;
    ...
}
```
getScaledMaximumDrawingCacheSize为当前屏幕的总像素即`width * height * 4(ARGB8888)`。

如果是软件绘制，那么就一定会创建绘制缓存。此时其调用draw(Canvas)/dispatchDraw(Canvas)过程就是在`buildDrawingCache`调用的了。

#### - 硬件加速绘制

如果开启硬件加速，则调用`updateDisplayListIfDirty`进行硬件绘制。

#### - 处理透明度

如果用户设置的alpha值，或者alpha动画。那么在这一步将会把alpha值(0~1.0f)换算成0xFF进制下值。硬件加速则直接修改RenderNode的属性，否则通过saveLayerAlpha修改Canvas。

#### - 处理ClipChildren

如果当前View的Parent没有清除FLAG_CLIP_CHILDREN，那View就在绘制的时候强制将自己限定在自己的位置框中。

#### - 进行绘制

- 硬件绘制

此时只要将RenderNode中收集的参数作用到前面绘制的结果上。因为updateDisplayListIfDirty时已完成View的绘制。

- 软件绘制(绘制缓存)

如果绘制缓存，那么将不再调用`dispatchDraw`或者`draw(canvas)`。因为在创建绘制缓存(buildDrawingCache)时这一步已经运行过一次了。这一步也只是是将缓存的Bitmap绘制到surface创建的Canvas上面。同时也将用户设置的画笔(即`mLayerPaint`)作用到绘制结果上面。

- 其他情况

由于绘制缓存有尺寸上限，如果View尺寸过大。那么即使不是硬件加速，也无法绘制缓存。

直接调用`draw(Canvas, ViewGroup, long)`或者`dispatchDraw`

注意：很多逻辑都排除了硬件加速的情况。不是因为硬件加速时，这些逻辑无法工作。而是这个逻辑的是上游(即属性修改之初)，就一定作用在RenderNode了。因此不能再次进行操作。

不论是软件绘制还是硬件加速，在ViewGroup调用`draw(Canvas, ViewGroup, long)`函数之后，这个函数都会调用draw(Canvas)完成View的绘制。

### # 创建绘制缓存(buildDrawingCache)

```java
// frameworks/base/core/java/android/view/View.java
/**
 * private, internal implementation of buildDrawingCache, used to enable tracing
 */
private void buildDrawingCacheImpl(boolean autoScale) {
    mCachingFailed = false;

    int width = mRight - mLeft;
    int height = mBottom - mTop;

    final AttachInfo attachInfo = mAttachInfo;
    final boolean scalingRequired = attachInfo != null && attachInfo.mScalingRequired;

    if (autoScale && scalingRequired) {
        width = (int) ((width * attachInfo.mApplicationScale) + 0.5f);
        height = (int) ((height * attachInfo.mApplicationScale) + 0.5f);
    }

    final int drawingCacheBackgroundColor = mDrawingCacheBackgroundColor;
    final boolean opaque = drawingCacheBackgroundColor != 0 || isOpaque();
    final boolean use32BitCache = attachInfo != null && attachInfo.mUse32BitDrawingCache;

    final long projectedBitmapSize = width * height * (opaque && !use32BitCache ? 2 : 4);
    final long drawingCacheSize =
            ViewConfiguration.get(mContext).getScaledMaximumDrawingCacheSize();
    // View的尺寸不合法，或者超过MaximumDrawingCacheSize则无法进行绘制缓存。
    if (width <= 0 || height <= 0 || projectedBitmapSize > drawingCacheSize) {
        if (width > 0 && height > 0) {
            Log.w(VIEW_LOG_TAG, getClass().getSimpleName() + " not displayed because it is"
                    + " too large to fit into a software layer (or drawing cache), needs "
                    + projectedBitmapSize + " bytes, only "
                    + drawingCacheSize + " available");
        }
        destroyDrawingCache();
        mCachingFailed = true;
        return;
    }

    boolean clear = true;
    Bitmap bitmap = autoScale ? mDrawingCache : mUnscaledDrawingCache;
    
    // 创建Bitmap对象。并绘制先前绘制的缓存对象，即`mDrawingCache`。
    if (bitmap == null || bitmap.getWidth() != width || bitmap.getHeight() != height) {
        Bitmap.Config quality;
        if (!opaque) {
            // Never pick ARGB_4444 because it looks awful
            // Keep the DRAWING_CACHE_QUALITY_LOW flag just in case
            switch (mViewFlags & DRAWING_CACHE_QUALITY_MASK) {
                case DRAWING_CACHE_QUALITY_AUTO:
                case DRAWING_CACHE_QUALITY_LOW:
                case DRAWING_CACHE_QUALITY_HIGH:
                default:
                    quality = Bitmap.Config.ARGB_8888;
                    break;
            }
        } else {
            // Optimization for translucent windows
            // If the window is translucent, use a 32 bits bitmap to benefit from memcpy()
            quality = use32BitCache ? Bitmap.Config.ARGB_8888 : Bitmap.Config.RGB_565;
        }

        // Try to cleanup memory
        if (bitmap != null) bitmap.recycle();

        try {
            bitmap = Bitmap.createBitmap(mResources.getDisplayMetrics(),
                    width, height, quality);
            bitmap.setDensity(getResources().getDisplayMetrics().densityDpi);
            if (autoScale) {
                mDrawingCache = bitmap;
            } else {
                mUnscaledDrawingCache = bitmap;
            }
            if (opaque && use32BitCache) bitmap.setHasAlpha(false);
        } catch (OutOfMemoryError e) {
            // If there is not enough memory to create the bitmap cache, just
            // ignore the issue as bitmap caches are not required to draw the
            // view hierarchy
            if (autoScale) {
                mDrawingCache = null;
            } else {
                mUnscaledDrawingCache = null;
            }
            mCachingFailed = true;
            return;
        }

        clear = drawingCacheBackgroundColor != 0;
    }

    // 创建Canvas对象。
    Canvas canvas;
    if (attachInfo != null) {
        canvas = attachInfo.mCanvas;
        if (canvas == null) {
            canvas = new Canvas();
        }
        canvas.setBitmap(bitmap);
        // Temporarily clobber the cached Canvas in case one of our children
        // is also using a drawing cache. Without this, the children would
        // steal the canvas by attaching their own bitmap to it and bad, bad
        // thing would happen (invisible views, corrupted drawings, etc.)
        attachInfo.mCanvas = null;
    } else {
        // This case should hopefully never or seldom happen
        canvas = new Canvas(bitmap);
    }

    if (clear) {
        bitmap.eraseColor(drawingCacheBackgroundColor);
    }

    computeScroll();
    final int restoreCount = canvas.save();

    if (autoScale && scalingRequired) {
        final float scale = attachInfo.mApplicationScale;
        canvas.scale(scale, scale);
    }

    canvas.translate(-mScrollX, -mScrollY);

    mPrivateFlags |= PFLAG_DRAWN;
    if (mAttachInfo == null || !mAttachInfo.mHardwareAccelerated ||
            mLayerType != LAYER_TYPE_NONE) {
        mPrivateFlags |= PFLAG_DRAWING_CACHE_VALID;
    }

    // 调用`draw(canvas)`或者`dispatchDraw(canvas)`绘制Bitmap。
    if ((mPrivateFlags & PFLAG_SKIP_DRAW) == PFLAG_SKIP_DRAW) {
        mPrivateFlags &= ~PFLAG_DIRTY_MASK;
        dispatchDraw(canvas);
        drawAutofilledHighlight(canvas);
        if (mOverlay != null && !mOverlay.isEmpty()) {
            mOverlay.getOverlayView().draw(canvas);
        }
    } else {
        draw(canvas);
    }

    canvas.restoreToCount(restoreCount);
    canvas.setBitmap(null);

    if (attachInfo != null) {
    // 重复利用Canvas对象。
        // Restore the cached Canvas for our siblings
        attachInfo.mCanvas = canvas;
    }
}
```

这里的关键步骤同`draw(Canvas,ViewGroup,int)`的某些步骤类似：

- 判断是否满足条件。
- 创建Bitmap对象，同时删除旧的缓存。
- 创建Canvas对象(重复利用)。
- 调用绘制函数绘制Bitmap。`draw(Canvas)`或者`dispatchDraw(Canvas)`。

### # 总结

```
sequenceDiagram
STARTER->>ViewGroup: draw(Canvas)
ViewGroup->>ViewGroup: onDraw(Canvas)
ViewGroup->>ViewGroup: dispatchDraw(Canvas)
ViewGroup->>View: draw(Canvas, ViewGroup, long)
View->>View: draw(Canvas)
View->>View: onDraw(Canvas)
```

android 4.0之后提供了属性动画，比如通过动态修改TransationY即可让View移动起来，并且不影响其接受触摸事件。但是，你翻看setTranslationY的源码你会发现这个值貌似只作用于RenderNode。如下：

```java
public void setTranslationY(float translationY) {
    if (translationY != getTranslationY()) {
        invalidateViewProperty(true, false);
        mRenderNode.setTranslationY(translationY);
        invalidateViewProperty(false, true);

        invalidateParentIfNeededAndWasQuickRejected();
        notifySubtreeAccessibilityStateChangedIfNeeded();
    }
}
```

而RenderNode以及DisplayList等，只有硬件加速的情况才有用。而软件绘制的情况下，这些个属性也是同样生效的。那么是如何工作的呢？

其实在`draw(Canvas,ViewGroup,int)`中，有一步是`canvas.concat(getMatrix())`。这里的`getMatrix()`会将RenderNode中存储的所有属性作用于复合于其自身。