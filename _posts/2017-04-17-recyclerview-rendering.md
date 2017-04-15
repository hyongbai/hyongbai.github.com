---
layout: post
title: "RecyclerView绘制流程详解"
category: all-about-tech
tags: -[Android] -[Support] -[RecyclerView] -[View]
date: 2017-04-17 00:39:00+00:00
---

> 注: 本文基于25.2.0

## Measure

```java
//RecyclerView.java
 @Override
protected void onMeasure(int widthSpec, int heightSpec) {
    if (mLayout == null) {
        defaultOnMeasure(widthSpec, heightSpec);
        return;
    }
    if (mLayout.mAutoMeasure) {
        final int widthMode = MeasureSpec.getMode(widthSpec);
        final int heightMode = MeasureSpec.getMode(heightSpec);
        final boolean skipMeasure = widthMode == MeasureSpec.EXACTLY
                && heightMode == MeasureSpec.EXACTLY;
        mLayout.onMeasure(mRecycler, mState, widthSpec, heightSpec);
        if (skipMeasure || mAdapter == null) {
            return;
        }
        if (mState.mLayoutStep == State.STEP_START) {
            dispatchLayoutStep1();
        }
        // set dimensions in 2nd step. Pre-layout should happen with old dimensions for
        // consistency
        mLayout.setMeasureSpecs(widthSpec, heightSpec);
        mState.mIsMeasuring = true;
        dispatchLayoutStep2();
        // ...
    }
    //...
}
```
这里会将测量的工作交给LayoutManager，在其中实现onMeasure。并且如果RecyclerView的宽高都是可以明确的，那么就直接忽略(skipMeasure)掉下面的逻辑了。否则会执行`dispatchLayoutStep1`和`dispatchLayoutStep2`，然后根据子View来确定RecyclerView的宽高。关于这两个函数，我们可以先从其注释看起来了解它们具体是什么角色。

```java
//RecyclerView.java
/**
 * The first step of a layout where we;
 * - process adapter updates
 * - decide which animation should run
 * - save information about current views
 * - If necessary, run predictive layout and save its information
 */
 private void dispatchLayoutStep1() {}
```
可以看到dispatchLayoutStep1主要就是做各种预处理。比如Relayout; 比如记录当前各个View的信息，为后面做动画做准备等等。

```java
//RecyclerView.java
/**
 * The second layout step where we do the actual layout of the views for the final state.
 * This step might be run multiple times if necessary (e.g. measure).
 */
 private void dispatchLayoutStep2() {}
```
dispatchLayoutStep2里面其实是真正做事情的公仆。正在确立需要显示多少个View，ItemView的Measure和Layout都是在这里做处理的。

其实还有一个`dispatchLayoutStep3`的方法。结合1和2，差不过可以猜出它是用来做善后的。比如真正做动画等等，都是在这里完成的。

(顺便吐槽一下，为什么会出现dispatchLayoutStep1/2/3这样的命名方式呢？？？)

好吧onMeasure就先这样的，因为后面讲Layout的时候会具体讲到。

## Layout

下面来讲讲RecyclerView中最核心的部分了。

```java
//RecyclerView.java
@Override
protected void onLayout(boolean changed, int l, int t, int r, int b) {
    TraceCompat.beginSection(TRACE_ON_LAYOUT_TAG);
    dispatchLayout();
    TraceCompat.endSection();
    mFirstLayoutComplete = true;
}

void dispatchLayout() {
    if (mAdapter == null) {
        Log.e(TAG, "No adapter attached; skipping layout");
        // leave the state in START
        return;
    }
    if (mLayout == null) {
        Log.e(TAG, "No layout manager attached; skipping layout");
        // leave the state in START
        return;
    }
    mState.mIsMeasuring = false;
    if (mState.mLayoutStep == State.STEP_START) {
        dispatchLayoutStep1();
        mLayout.setExactMeasureSpecsFrom(this);
        dispatchLayoutStep2();
    } else if (mAdapterHelper.hasUpdates() || mLayout.getWidth() != getWidth() ||
            mLayout.getHeight() != getHeight()) {
        // First 2 steps are done in onMeasure but looks like we have to run again due to
        // changed size.
        mLayout.setExactMeasureSpecsFrom(this);
        dispatchLayoutStep2();
    } else {
        // always make sure we sync them (to ensure mode is exact)
        mLayout.setExactMeasureSpecsFrom(this);
    }
    dispatchLayoutStep3();
}
```

还记得Measure中提到如果当前的RecyclerView的高度不确定时，会调用Step1和Step2吗？需要了解的是如果调用了Step2，那么mState.mLayoutStep的值就为`STEP_ANIMATIONS`。也就是说下一步你就老老实实处理动画吧(adapter或者尺寸有变化则另说)，别整Step1和Step2了。

### dispatchLayoutStep2

所以呢？我们先假设在Measure的时候会skipMeasure。

mState.mLayoutStep的默认值为`State.STEP_START`。所以我们老老实实看人民的公仆做了什么。所以先跳过Step1了哈。

```java
//RecyclerView.java
private void dispatchLayoutStep2() {
    eatRequestLayout();
    onEnterLayoutOrScroll();
    mState.assertLayoutStep(State.STEP_LAYOUT | State.STEP_ANIMATIONS);
    mAdapterHelper.consumeUpdatesInOnePass();
    mState.mItemCount = mAdapter.getItemCount();
    mState.mDeletedInvisibleItemCountSincePreviousLayout = 0;

    // Step 2: Run layout
    mState.mInPreLayout = false;
    mLayout.onLayoutChildren(mRecycler, mState);

    mState.mStructureChanged = false;
    mPendingSavedState = null;

    // onLayoutChildren may have caused client code to disable item animations; re-check
    mState.mRunSimpleAnimations = mState.mRunSimpleAnimations && mItemAnimator != null;
    mState.mLayoutStep = State.STEP_ANIMATIONS;
    onExitLayoutOrScroll();
    resumeRequestLayout(false);
}
```
这里其实最最最核心的也就是那一句` mLayout.onLayoutChildren(mRecycler, mState)`了。因此，其实RecyclerView对于View的Measure和Layout都完完全全交给LayoutManager去处理了。

### onLayoutChildren

接下来我们均以LinearLayoutManager为例来讲述。

```java
//LineaLayoutManager.java
@Override
public void onLayoutChildren(RecyclerView.Recycler recycler, RecyclerView.State state) {
    // layout algorithm:
    // 1) by checking children and other variables, find an anchor coordinate and an anchor
    //  item position.
    // 2) fill towards start, stacking from bottom
    // 3) fill towards end, stacking from top
    // 4) scroll to fulfill requirements like stack from bottom.
    // ...
	if (!mAnchorInfo.mValid || mPendingScrollPosition != NO_POSITION ||
            mPendingSavedState != null) {
        mAnchorInfo.reset();
        mAnchorInfo.mLayoutFromEnd = mShouldReverseLayout ^ mStackFromEnd;
        // calculate anchor position and coordinate
        updateAnchorInfoForLayout(recycler, state, mAnchorInfo);
        mAnchorInfo.mValid = true;
    }
    // ...
    onAnchorReady(recycler, state, mAnchorInfo, firstLayoutDirection);
    detachAndScrapAttachedViews(recycler);
    mLayoutState.mInfinite = resolveIsInfinite();
    mLayoutState.mIsPreLayout = state.isPreLayout();
    if (mAnchorInfo.mLayoutFromEnd) {
        // fill towards start
        updateLayoutStateToFillStart(mAnchorInfo);
        mLayoutState.mExtra = extraForStart;
        fill(recycler, mLayoutState, state, false);
        startOffset = mLayoutState.mOffset;
        final int firstElement = mLayoutState.mCurrentPosition;
        if (mLayoutState.mAvailable > 0) {
            extraForEnd += mLayoutState.mAvailable;
        }
        // fill towards end
        updateLayoutStateToFillEnd(mAnchorInfo);
        mLayoutState.mExtra = extraForEnd;
        mLayoutState.mCurrentPosition += mLayoutState.mItemDirection;
        fill(recycler, mLayoutState, state, false);
        endOffset = mLayoutState.mOffset;

        if (mLayoutState.mAvailable > 0) {
            // end could not consume all. add more items towards start
            extraForStart = mLayoutState.mAvailable;
            updateLayoutStateToFillStart(firstElement, startOffset);
            mLayoutState.mExtra = extraForStart;
            fill(recycler, mLayoutState, state, false);
            startOffset = mLayoutState.mOffset;
        }
    } else {
        // fill towards end
        updateLayoutStateToFillEnd(mAnchorInfo);
        mLayoutState.mExtra = extraForEnd;
        fill(recycler, mLayoutState, state, false);
        endOffset = mLayoutState.mOffset;
        final int lastElement = mLayoutState.mCurrentPosition;
        if (mLayoutState.mAvailable > 0) {
            extraForStart += mLayoutState.mAvailable;
        }
        // fill towards start
        updateLayoutStateToFillStart(mAnchorInfo);
        mLayoutState.mExtra = extraForStart;
        mLayoutState.mCurrentPosition += mLayoutState.mItemDirection;
        fill(recycler, mLayoutState, state, false);
        startOffset = mLayoutState.mOffset;

        if (mLayoutState.mAvailable > 0) {
            extraForEnd = mLayoutState.mAvailable;
            // start could not consume all it should. add more items towards end
            updateLayoutStateToFillEnd(lastElement, endOffset);
            mLayoutState.mExtra = extraForEnd;
            fill(recycler, mLayoutState, state, false);
            endOffset = mLayoutState.mOffset;
        }
    }

    // changes may cause gaps on the UI, try to fix them.
    // TODO we can probably avoid this if neither stackFromEnd/reverseLayout/RTL values have
    // changed
    if (getChildCount() > 0) {
        //...计算位置位移
    }
    layoutForPredictiveAnimations(recycler, state, startOffset, endOffset);
    if (!state.isPreLayout()) {
        mOrientationHelper.onLayoutComplete();
    } else {
        mAnchorInfo.reset();
    }
    mLastStackFromEnd = mStackFromEnd;
    if (DEBUG) {
        validateChildOrder();
    }
}
```

这段代码的核心最终其实是调用了fill。先不去管`mAnchorInfo.mLayoutFromEnd`到底是啥。首先去看官方在这个方法内部的注释：它会根据子View和其他变量确定一个Anchor(会包括坐标位和位置)，然后从它的bottom开始fill start同时从它的top开始fill end。因为Anchor很有可能在屏幕的中间，因此Anchor之上和之下的控件都需要填充Item，这里就是为什么会出现fill两次的缘故。

### fill

好，那么我们来看看fill吧。

```java
//LineatLayoutManager.java
/**
 * The magic functions :). Fills the given layout, defined by the layoutState. This is fairly
 * independent from the rest of the {@link android.support.v7.widget.LinearLayoutManager}
 * and with little change, can be made publicly available as a helper class.
 *
 * @param recycler        Current recycler that is attached to RecyclerView
 * @param layoutState     Configuration on how we should fill out the available space.
 * @param state           Context passed by the RecyclerView to control scroll steps.
 * @param stopOnFocusable If true, filling stops in the first focusable new child
 * @return Number of pixels that it added. Useful for scroll functions.
 */
int fill(RecyclerView.Recycler recycler, LayoutState layoutState,
        RecyclerView.State state, boolean stopOnFocusable) {
    // max offset we should set is mFastScroll + available
    final int start = layoutState.mAvailable;
    if (layoutState.mScrollingOffset != LayoutState.SCROLLING_OFFSET_NaN) {
        // TODO ugly bug fix. should not happen
        if (layoutState.mAvailable < 0) {
            layoutState.mScrollingOffset += layoutState.mAvailable;
        }
        recycleByLayoutState(recycler, layoutState);
    }
    int remainingSpace = layoutState.mAvailable + layoutState.mExtra;
    LayoutChunkResult layoutChunkResult = mLayoutChunkResult;
    while ((layoutState.mInfinite || remainingSpace > 0) && layoutState.hasMore(state)) {
        layoutChunkResult.resetInternal();
        layoutChunk(recycler, state, layoutState, layoutChunkResult);
        if (layoutChunkResult.mFinished) {
            break;
        }
        layoutState.mOffset += layoutChunkResult.mConsumed * layoutState.mLayoutDirection;
        /**
         * Consume the available space if:
         * * layoutChunk did not request to be ignored
         * * OR we are laying out scrap children
         * * OR we are not doing pre-layout
         */
        if (!layoutChunkResult.mIgnoreConsumed || mLayoutState.mScrapList != null
                || !state.isPreLayout()) {
            layoutState.mAvailable -= layoutChunkResult.mConsumed;
            // we keep a separate remaining space because mAvailable is important for recycling
            remainingSpace -= layoutChunkResult.mConsumed;
        }

        if (layoutState.mScrollingOffset != LayoutState.SCROLLING_OFFSET_NaN) {
            layoutState.mScrollingOffset += layoutChunkResult.mConsumed;
            if (layoutState.mAvailable < 0) {
                layoutState.mScrollingOffset += layoutState.mAvailable;
            }
            recycleByLayoutState(recycler, layoutState);
        }
        if (stopOnFocusable && layoutChunkResult.mFocusable) {
            break;
        }
    }
    if (DEBUG) {
        validateChildOrder();
    }
    return start - layoutState.mAvailable;
}
```

首先，注释中出现了`The magic functions`的字眼，可见这里对LineaLayoutManager来说是见证奇迹的部分。那么它是如何让我们一起来见证奇迹的呢？

然后，我们可以看到这里其实主要的逻辑都在一个while循环里面。最关键的两个条件是`remainingSpace > 0`和`layoutState.hasMore(state)`。前者表示还有多少的剩余空间可以存放view，后者其实就是在计算`mCurrentPosition`有没有达到itemCount。

接着，通过layoutChunk实现对下一个View的处理，然后将产生的信息交给`layoutChunkResult`。

最后，使用LayoutChunkResult中的`mConsumed`来消耗`remainingSpace`。接着进入下一个循环(如果满足条件)。好吧，fill的逻辑就是这样。等等，别走，说好的见证奇迹呢？

### layoutChunk

上面讲了一大堆啊。还是没讲到见证奇迹的部分。

```java
//LinearLayoutManager.java
void layoutChunk(RecyclerView.Recycler recycler, RecyclerView.State state,
        LayoutState layoutState, LayoutChunkResult result) {
    View view = layoutState.next(recycler);
    if (view == null) {
        if (DEBUG && layoutState.mScrapList == null) {
            throw new RuntimeException("received null view when unexpected");
        }
        // if we are laying out views in scrap, this may return null which means there is
        // no more items to layout.
        result.mFinished = true;
        return;
    }
    LayoutParams params = (LayoutParams) view.getLayoutParams();
    if (layoutState.mScrapList == null) {
        if (mShouldReverseLayout == (layoutState.mLayoutDirection
                == LayoutState.LAYOUT_START)) {
            addView(view);
        } else {
            addView(view, 0);
        }
    } else {
        if (mShouldReverseLayout == (layoutState.mLayoutDirection
                == LayoutState.LAYOUT_START)) {
            addDisappearingView(view);
        } else {
            addDisappearingView(view, 0);
        }
    }
    measureChildWithMargins(view, 0, 0);
    result.mConsumed = mOrientationHelper.getDecoratedMeasurement(view);
    int left, top, right, bottom;
    if (mOrientation == VERTICAL) {
        if (isLayoutRTL()) {
            right = getWidth() - getPaddingRight();
            left = right - mOrientationHelper.getDecoratedMeasurementInOther(view);
        } else {
            left = getPaddingLeft();
            right = left + mOrientationHelper.getDecoratedMeasurementInOther(view);
        }
        if (layoutState.mLayoutDirection == LayoutState.LAYOUT_START) {
            bottom = layoutState.mOffset;
            top = layoutState.mOffset - result.mConsumed;
        } else {
            top = layoutState.mOffset;
            bottom = layoutState.mOffset + result.mConsumed;
        }
    } else {
        top = getPaddingTop();
        bottom = top + mOrientationHelper.getDecoratedMeasurementInOther(view);

        if (layoutState.mLayoutDirection == LayoutState.LAYOUT_START) {
            right = layoutState.mOffset;
            left = layoutState.mOffset - result.mConsumed;
        } else {
            left = layoutState.mOffset;
            right = layoutState.mOffset + result.mConsumed;
        }
    }
    // We calculate everything with View's bounding box (which includes decor and margins)
    // To calculate correct layout position, we subtract margins.
    layoutDecoratedWithMargins(view, left, top, right, bottom);
    if (DEBUG) {
        Log.d(TAG, "laid out child at position " + getPosition(view) + ", with l:"
                + (left + params.leftMargin) + ", t:" + (top + params.topMargin) + ", r:"
                + (right - params.rightMargin) + ", b:" + (bottom - params.bottomMargin));
    }
    // Consume the available space if the view is not removed OR changed
    if (params.isItemRemoved() || params.isItemChanged()) {
        result.mIgnoreConsumed = true;
    }
    result.mFocusable = view.isFocusable();
}
```

这里首先去`LayoutState`中获取下一个View(这里听起来很屌的样子啊，所以各种缓存还有bindHolder等等都是在这里处理的，不过这里我们只讲RecyvlerView的绘制流程，这里的逻辑先不插入).

如果，没有下一个View了，跳出，并标记finished。

接着，将View添加到ViewGroup(即Recycler中去)。其中那个`mScrapList`表示是否有缓存的view。在这里我们就可以看到，`LAYOUT_START`(mLayoutDirection)时是从END往START方向排列的，如果mShouldReverseLayout时那么就会反过来，也就是addView(View)。

再接着，调用measureChildWithMargins对View进行测量了。终于，子View的测量在这里完成了。

然后，计算好View的尺寸之后我们就可以计算出View的left/top/right/bottom了，这段逻辑没啥好讲的。

最后，有了位置之后我们就可以layout了。

所以这里需要见证奇迹我们还需要搞定两个东西：`measureChildWithMargins`和`layoutDecoratedWithMargins`

#### measureChildWithMargins

这里其实也没啥好讲的。代码如下：

```java
//RecyclerView$LayoutManager.java
public void measureChildWithMargins(View child, int widthUsed, int heightUsed) {
    final LayoutParams lp = (LayoutParams) child.getLayoutParams();

    final Rect insets = mRecyclerView.getItemDecorInsetsForChild(child);
    widthUsed += insets.left + insets.right;
    heightUsed += insets.top + insets.bottom;

    final int widthSpec = getChildMeasureSpec(getWidth(), getWidthMode(),
            getPaddingLeft() + getPaddingRight() +
                    lp.leftMargin + lp.rightMargin + widthUsed, lp.width,
            canScrollHorizontally());
    final int heightSpec = getChildMeasureSpec(getHeight(), getHeightMode(),
            getPaddingTop() + getPaddingBottom() +
                    lp.topMargin + lp.bottomMargin + heightUsed, lp.height,
            canScrollVertically());
    if (shouldMeasureChild(child, widthSpec, heightSpec, lp)) {
        child.measure(widthSpec, heightSpec);
    }
}
```

需要注意的是在计算宽高的时候会把`mDecorInsets`的尺寸也算进去的，这个就是`ItemDecoration`，比如实现ListView那样的间隔线等等。

#### layoutDecoratedWithMargins

这里也是一样。

```java
//RecyclerView$LayoutManager.java
public void layoutDecoratedWithMargins(View child, int left, int top, int right,
        int bottom) {
    final LayoutParams lp = (LayoutParams) child.getLayoutParams();
    final Rect insets = lp.mDecorInsets;
    child.layout(left + insets.left + lp.leftMargin, top + insets.top + lp.topMargin,
            right - insets.right - lp.rightMargin,
            bottom - insets.bottom - lp.bottomMargin);
}
```
从源码可以看到，这个地方会将`mDecorInsets`的尺寸也给算上去。

至此，Layout完结了。其实LayoutManager是将原先ViewGroup中布局的逻辑给抽象出来交给LayoutManger，这样，如果你需要实现不同的布局样式的话，只需要实现不同的LayoutManager即可。RecyclerView自带了LinearLayoutManager/GridLayoutManger/StaggeredGridLayoutManager三种样式。

> dispatchLayoutStep1/dispatchLayoutStep3 其实跟Layout没有多大关系了。这里就不表述了。

## Draw

上面在Layout的时候讲到子View会以AddView的形式存在RecyclerView中，因此子View到底是啥样样子它自己绘制即可。与RecycvlerView无关。这里就提一下在Layout的时候提到的ItemDecoration。

```java
//RecyclerView.java
@Override
public void draw(Canvas c) {
    super.draw(c);

    final int count = mItemDecorations.size();
    for (int i = 0; i < count; i++) {
        mItemDecorations.get(i).onDrawOver(c, this, mState);
    }
    // ... 省略OverFlow
}

@Override
public void onDraw(Canvas c) {
    super.onDraw(c);

    final int count = mItemDecorations.size();
    for (int i = 0; i < count; i++) {
        mItemDecorations.get(i).onDraw(c, this, mState);
    }
}
```

其实就是在onDraw的时候回调ItemDecorations然后自己实现ItemDecoration中的onDraw函数，自己画即可。



## 结尾

> 如何确立Anchor的呢？
> ItemViewAnimator如何实现？