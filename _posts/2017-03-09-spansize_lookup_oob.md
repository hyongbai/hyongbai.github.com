---
layout: post
title: "自定义SpanSizeLookup出现的指针问题"
category: all-about-tech
tags:
 - Android
 - RecyclerView
date: 2017-03-09 13:30:00+00:00
---

最近在将项目中的Gridview切换成RecyclerView(没依赖v4，因此一直没从v7中抽出)。其中有个需求是跨一整行显示一个类似title的东西。于是自定义了SpanSizeLookup。代码如下:

```java
    private final GridLayoutManager.SpanSizeLookup lookup = new GridLayoutManager.SpanSizeLookup() {
        @Override
        public int getSpanSize(int position) {
            return span(position);
        }
    };


    private int span(int position) {
        return get(position) instanceof Divider ? mColumn : 1;
    }

```

很简单。但是蛋疼的问题来了，当position 0返回SpanSize为4(即SpanCount为4)的时候出现了如下的奔溃：

```java
java.lang.ArrayIndexOutOfBoundsException: length=5; index=5
	at android.support.v7.widget.GridLayoutManager.getSpaceForSpanRange(GridLayoutManager.java:350)
	at android.support.v7.widget.GridLayoutManager.measureChild(GridLayoutManager.java:720)
	at android.support.v7.widget.GridLayoutManager.layoutChunk(GridLayoutManager.java:595)
	at android.support.v7.widget.LinearLayoutManager.fill(LinearLayoutManager.java:1489)
	at android.support.v7.widget.LinearLayoutManager.onLayoutChildren(LinearLayoutManager.java:586)
	at android.support.v7.widget.GridLayoutManager.onLayoutChildren(GridLayoutManager.java:173)
	at android.support.v7.widget.RecyclerView.dispatchLayoutStep2(RecyclerView.java:3525)
	at android.support.v7.widget.RecyclerView.dispatchLayout(RecyclerView.java:3254)
	at android.support.v7.widget.RecyclerView.onLayout(RecyclerView.java:3786)
	at android.view.View.layout(View.java:17641)
	at android.view.ViewGroup.layout(ViewGroup.java:5575)
	at android.widget.FrameLayout.layoutChildren(FrameLayout.java:323)
	at android.widget.FrameLayout.onLayout(FrameLayout.java:261)
	at android.view.View.layout(View.java:17641)
	at android.view.ViewGroup.layout(ViewGroup.java:5575)
	at as.v4.view.ViewPager.onLayout(ViewPager.java:1706)
	at android.view.View.layout(View.java:17641)
	at android.view.ViewGroup.layout(ViewGroup.java:5575)
	at android.widget.FrameLayout.layoutChildren(FrameLayout.java:323)
	at android.widget.FrameLayout.onLayout(FrameLayout.java:261)
	at android.view.View.layout(View.java:17641)
	at android.view.ViewGroup.layout(ViewGroup.java:5575)
	at android.widget.FrameLayout.layoutChildren(FrameLayout.java:323)
	at android.widget.FrameLayout.onLayout(FrameLayout.java:261)
	at android.view.View.layout(View.java:17641)
	at android.view.ViewGroup.layout(ViewGroup.java:5575)
	at com.android.internal.widget.ActionBarOverlayLayout.onLayout(ActionBarOverlayLayout.java:493)
	at android.view.View.layout(View.java:17641)
	at android.view.ViewGroup.layout(ViewGroup.java:5575)
	at android.widget.FrameLayout.layoutChildren(FrameLayout.java:323)
	at android.widget.FrameLayout.onLayout(FrameLayout.java:261)
	at com.android.internal.policy.DecorView.onLayout(DecorView.java:726)
	at android.view.View.layout(View.java:17641)
	at android.view.ViewGroup.layout(ViewGroup.java:5575)
	at android.view.ViewRootImpl.performLayout(ViewRootImpl.java:2346)
	at android.view.ViewRootImpl.performTraversals(ViewRootImpl.java:2068)
	at android.view.ViewRootImpl.doTraversal(ViewRootImpl.java:1254)
	at android.view.ViewRootImpl$TraversalRunnable.run(ViewRootImpl.java:6343)
	at android.view.Choreographer$CallbackRecord.run(Choreographer.java:874)
	at android.view.Choreographer.doCallbacks(Choreographer.java:686)
	at android.view.Choreographer.doFrame(Choreographer.java:621)
	at android.view.Choreographer$FrameDisplayEventReceiver.run(Choreographer.java:860)
	at android.os.Handler.handleCallback(Handler.java:751)
	at android.os.Handler.dispatchMessage(Handler.java:95)
	at android.os.Looper.loop(Looper.java:154)
	at android.app.ActivityThread.main(ActivityThread.java:6126)
	at java.lang.reflect.Method.invoke(Native Method)
	at com.android.internal.os.ZygoteInit$MethodAndArgsCaller.run(ZygoteInit.java:886)
	at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:776)
```

看到了原来是IndexOutOfBounds，很蛋疼。一个成熟的程序员不应该出现这个问题呀。

但是异常又是GridLayoutManager里面的，于是只好去看源码。源码中奔溃的地方只是简单的从数组中读取数值而已，如下：
```java
    int getSpaceForSpanRange(int startSpan, int spanSize) {
        if (mOrientation == VERTICAL && isLayoutRTL()) {
            return mCachedBorders[mSpanCount - startSpan]
                    - mCachedBorders[mSpanCount - startSpan - spanSize];
        } else {
            return mCachedBorders[startSpan + spanSize] - mCachedBorders[startSpan];
        }
    }
```
于是又追溯到startSpan和spanSize，发现这两个值是在`assignSpans`：
```java
    private void assignSpans(RecyclerView.Recycler recycler, RecyclerView.State state, int count,
            int consumedSpanCount, boolean layingOutInPrimaryDirection) {
        // spans are always assigned from 0 to N no matter if it is RTL or not.
        // RTL is used only when positioning the view.
        int span, start, end, diff;
        // make sure we traverse from min position to max position
        if (layingOutInPrimaryDirection) {
            start = 0;
            end = count;
            diff = 1;
        } else {
            start = count - 1;
            end = -1;
            diff = -1;
        }
        span = 0;
        for (int i = start; i != end; i += diff) {
            View view = mSet[i];
            LayoutParams params = (LayoutParams) view.getLayoutParams();
            params.mSpanSize = getSpanSize(recycler, state, getPosition(view));
            params.mSpanIndex = span;
            span += params.mSpanSize;
        }
    }
```
即是其中的`params.mSpanSize`和`params.mSpanIndex`，一个有意思的地方在于`arams.mSpanIndex`是之前的`mSpanSize`的累加值。也就是加入第3/4/5个View在同一行的话，第5个view的index是3/4的spansize之和。

记住`getSpanSize(recycler, state, getPosition(view))`就是拿到我们设置的`SpanSizeLookUp`调用上面实现的`getSpanSize`

那么问题来了，如何才能保证3/4/5是在同一行呢？如若不然必然会出现`IndexOutOfBoundsException`的异常。其实主要还是在于`count`这个参数。因为不论是哪个position对应的SpanSize都不可能会超过`SpanCount`。继续看代码，`assignSpans`是在`layoutChunk`中调用的。如下是其中关于`count`的部分:

```java
	void layoutChunk(RecyclerView.Recycler recycler, RecyclerView.State state,
            LayoutState layoutState, LayoutChunkResult result) {
        ...
        while (count < mSpanCount && layoutState.hasMore(state) && remainingSpan > 0) {
            int pos = layoutState.mCurrentPosition;
            final int spanSize = getSpanSize(recycler, state, pos);
            if (spanSize > mSpanCount) {
                throw new IllegalArgumentException("Item at position " + pos + " requires " +
                        spanSize + " spans but GridLayoutManager has only " + mSpanCount
                        + " spans.");
            }
            remainingSpan -= spanSize;
            if (remainingSpan < 0) {
                break; // item did not fit into this row or column
            }
            View view = layoutState.next(recycler);
            if (view == null) {
                break;
            }
            consumedSpanCount += spanSize;
            mSet[count] = view;
            count++;
        }
        ...
        assignSpans(recycler, state, count, consumedSpanCount, layingOutInPrimaryDirection);
        ...
    }
```

在while中打断点发现，`getSpanSize(recycler, state, pos)`中使用的是`DefaultSpanSizeLookup`,而不是我设定的。


![](/media/imgs/span-size-look-up-layoutChunk.gif)

卧槽。问题来了，这就导致在这里决定count的时候先使用了默认的，得到的值是1，而我要返回的是4(也就是最大值，一个view整行显示)。但是在assignSpans中拿到的是4。此处的count正确的值应当是1。必然导致会出现此View后面的SpanIndex为4，从而出现越界的问题。

那么为什么会出现这个问题呢？

我发现我的SpanSizeLookUp是在`onCreateViewHolder`时设定的(因为我不想让外部传入RecyclerView以及LayoutManager)。而`onCreateViewHolder`这个函数是在`layoutState.next(recycler)`之后设置的。所以会出现计算count的时候得到的是1，计算spanIndex的时候能到的是4。从而出现崩溃。


解决方案：老老实实在初始化GridLayoutManager的时候把我们的SpanSizeLookUp设置进去。
