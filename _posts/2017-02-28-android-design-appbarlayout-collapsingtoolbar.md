---
layout: post
title: "Design之AppBarLayout如何与CollapsingToolbarLayout协作"
category: all-about-tech
tags:
 - Design
 - Android
date: 2017-02-27 04:11:00+00:00
---

## CollapsingToolbarLayout

### 属性介绍

#### expandedTitleMarginStart

表示【展开】状态下Title左边的Margin。同理还有`expandedTitleMarginEnd` `expandedTitleMarginTop` `expandedTitleMarginBottom`等。看名字应该就知道其意义了，不多介绍。默认值都是`0`

```java
 mExpandedMarginStart = mExpandedMarginTop = mExpandedMarginEnd = mExpandedMarginBottom = a.getDimensionPixelSize(R.styleable.CollapsingToolbarLayout_expandedTitleMargin, 0);
```

#### expandedTitleGravity和collapsedTitleGravity
分别表示展开和折叠时Title的gravity。前者默认为`GravityCompat.START | Gravity.BOTTOM`，后者默认为`GravityCompat.START | Gravity.CENTER_VERTICAL`

#### titleEnabled
表示是否折叠Title，默认为`true`。关闭此属性的时候`Toolbar`的Title自己设定的效果，并且不会之前关于Title的属性全部都不会作用。因此也不会随着滚动而调整间距，大小等等。

#### contentScrim
表示折叠后在Toolbar后面，但是盖住其他View的背景。

#### scrimVisibleHeightTrigger
显示contentScrim的高度。默认值为-1。但是，并不是inflate的时候给了-1就说它的值就是-1了。你只要设定`contentScrim`就需要这个trigger。它的计算方式如下：

```java
    public int getScrimVisibleHeightTrigger() {
        if (mScrimVisibleHeightTrigger >= 0) {
            // If we have one explicitly set, return it
            return mScrimVisibleHeightTrigger;
        }

        // Otherwise we'll use the default computed value
        final int insetTop = mLastInsets != null ? mLastInsets.getSystemWindowInsetTop() : 0;

        final int minHeight = ViewCompat.getMinimumHeight(this);
        if (minHeight > 0) {
            // If we have a minHeight set, lets use 2 * minHeight (capped at our height)
            return Math.min((minHeight * 2) + insetTop, getHeight());
        }

        // If we reach here then we don't have a min height set. Instead we'll take a
        // guess at 1/3 of our height being visible
        return getHeight() / 3;
    }
```

可以看到，如果有设定正确的高度的话，就直接使用正确的高度。否则，如果设置了`miniHeight`的话，它会使用两倍minHeight加上insetTop两者和整个View的高度的最小值。如果没有`miniHeight`的话，他就简单粗暴地使用View高度的一半。为什么要加一个“insetTop”呢？我猜是因为还有个属性叫做`statusBarScrim`。

#### toolbarId
此属性表示与CollapsingToolbarLayout合作的Toolbar的id。默认为-1。那么它是怎么知道那个是Toolbar呢？翻看下源码中的`ensureToolbar()`函数可以看到：

```java
    private void ensureToolbar() {
        if (!mRefreshToolbar) {
            return;
        }

        // First clear out the current Toolbar
        mToolbar = null;
        mToolbarDirectChild = null;

        if (mToolbarId != -1) {
            // If we have an ID set, try and find it and it's direct parent to us
            mToolbar = (Toolbar) findViewById(mToolbarId);
            if (mToolbar != null) {
                mToolbarDirectChild = findDirectChild(mToolbar);
            }
        }

        if (mToolbar == null) {
            // If we don't have an ID, or couldn't find a Toolbar with the correct ID, try and find
            // one from our direct children
            Toolbar toolbar = null;
            for (int i = 0, count = getChildCount(); i < count; i++) {
                final View child = getChildAt(i);
                if (child instanceof Toolbar) {
                    toolbar = (Toolbar) child;
                    break;
                }
            }
            mToolbar = toolbar;
        }

        updateDummyView();
        mRefreshToolbar = false;
    }
```

如果设定了Toolbar，那么它会根据id去`findViewById`。接下来如果发现`mToolbar`为空的话，它回去子View中遍历一遍，直到找到Toolbar为止。这就是为什么`CollapsingToolbarLayout`和`Toolbar`基情满满的原因。

#### layout_collapseMode
默认是`COLLAPSE_MODE_OFF`,也就是跟随AppBarLayout被滚走。`COLLAPSE_MODE_PIN`如此字意表名在滚动的过程中保持自身的View不变。`COLLAPSE_MODE_PARALLAX`即是视差之意，表明在滚动过程中就不跟AppBarLayout保持步调一致，但是会滚(动)，故而为视差。

#### collapseParallaxMultiplier
只有layout_collapseMode为`COLLAPSE_MODE_PARALLAX`的时候此字段方才起作用，可以理解为视差系数，默认值为0.5f。比如AppBarLayout滑动了10px, 那么设定为parallax的child只会滑动10*0.5=5px。注意，当此系数为0.6f的时候，Child相对于屏幕的移动距离就变成了4px。为什么呢？看下面的源码解释。

### 注意

值得注意的是，在inflate结束的时候，`CollapsingToolbarLayout`会一刀斩地设置了`setWillNotDraw(false)`

此外`CollapsingToolbarLayout`是一个FrameLayout。不要忘记了。


## 视差原理

下面端上来热腾腾的。。。。。。。。。。。。。。。。。。。。。。。源码

```java
protected void onAttachedToWindow() {
    super.onAttachedToWindow();

    // Add an OnOffsetChangedListener if possible
    final ViewParent parent = getParent();
    if (parent instanceof AppBarLayout) {
        // Copy over from the ABL whether we should fit system windows
        ViewCompat.setFitsSystemWindows(this, ViewCompat.getFitsSystemWindows((View) parent));

        if (mOnOffsetChangedListener == null) {
            mOnOffsetChangedListener = new OffsetUpdateListener();
        }
        ((AppBarLayout) parent).addOnOffsetChangedListener(mOnOffsetChangedListener);

        // We're attached, so lets request an inset dispatch
        ViewCompat.requestApplyInsets(this);
    }
}
```

通过上面的代码可以了解到，在Layout被Attach到Window的时候，会判断parent是不是AppBarLayout如果是则会向其注册一个OffsetUpdateListener(也就是说只有CollapsingToolbarLayout被嵌套在AppBarLayout的时候才会起作用)。用来监听AppBarLayout的滑动距离。如下：

```java
private class OffsetUpdateListener implements AppBarLayout.OnOffsetChangedListener {
    OffsetUpdateListener() {
    }

    @Override
    public void onOffsetChanged(AppBarLayout layout, int verticalOffset) {
        mCurrentOffset = verticalOffset;

        final int insetTop = mLastInsets != null ? mLastInsets.getSystemWindowInsetTop() : 0;

        for (int i = 0, z = getChildCount(); i < z; i++) {
            final View child = getChildAt(i);
            final LayoutParams lp = (LayoutParams) child.getLayoutParams();
            final ViewOffsetHelper offsetHelper = getViewOffsetHelper(child);

            switch (lp.mCollapseMode) {
                case LayoutParams.COLLAPSE_MODE_PIN:
                    offsetHelper.setTopAndBottomOffset(
                            constrain(-verticalOffset, 0, getMaxOffsetForPinChild(child)));
                    break;
                case LayoutParams.COLLAPSE_MODE_PARALLAX:
                    offsetHelper.setTopAndBottomOffset(
                            Math.round(-verticalOffset * lp.mParallaxMult));
                    break;
            }
        }

        // Show or hide the scrims if needed
        updateScrimVisibility();

        if (mStatusBarScrim != null && insetTop > 0) {
            ViewCompat.postInvalidateOnAnimation(CollapsingToolbarLayout.this);
        }

        // Update the collapsing text's fraction
        final int expandRange = getHeight() - ViewCompat.getMinimumHeight(
                CollapsingToolbarLayout.this) - insetTop;
        mCollapsingTextHelper.setExpansionFraction(
                Math.abs(verticalOffset) / (float) expandRange);
    }
}
```

可以看出来，有滑动回调的时候，会遍历所有的view。当Child的LayoutParams的mCollapseMode为PIN的时候会将child往返方向滚动同样的距离，从而可以实现让Child定住的效果。当mCollapseMode为PARALLAX时候，会将child往反方向滚动系数为mParallaxMult的移动距离，从而实现了视觉差。

这也解释了上面说的系数为0.6f的时候，AppBarLayout往上滚动10时，Child相当于屏幕只滚动了4px。因此PARALLAX时的滚动距离计算方式为: verticalOffset*(1-mParallaxMult)。

所以即使是`parallax`模式也不一定就会有视差效果。比如将layout_collapseParallaxMultiplier设置为1.0的时候。其实就相当于`pin`效果了。

## contentScrim

contentScrim会刚刚好盖住Toolbar后面的所有的View，是如果做到的呢？其实很简单。在CollapsingToolbarLayout执行drawChild的时候，它才会画contentScrim。实现如下：

```java
@Override
protected boolean drawChild(Canvas canvas, View child, long drawingTime) {
    // This is a little weird. Our scrim needs to be behind the Toolbar (if it is present),
    // but in front of any other children which are behind it. To do this we intercept the
    // drawChild() call, and draw our scrim just before the Toolbar is drawn
    boolean invalidated = false;
    if (mContentScrim != null && mScrimAlpha > 0 && isToolbarChild(child)) {
        mContentScrim.mutate().setAlpha(mScrimAlpha);
        mContentScrim.draw(canvas);
        invalidated = true;
    }
    return super.drawChild(canvas, child, drawingTime) || invalidated;
}
```
可以看到如果当前的child是Toolbar它就会画mContentScrim。那么问题来了，如果没有Toolbar做何解呢？

接着往下看：

```java
@Override
public void draw(Canvas canvas) {
    super.draw(canvas);

    // If we don't have a toolbar, the scrim will be not be drawn in drawChild() below.
    // Instead, we draw it here, before our collapsing text.
    ensureToolbar();
    if (mToolbar == null && mContentScrim != null && mScrimAlpha > 0) {
        mContentScrim.mutate().setAlpha(mScrimAlpha);
        mContentScrim.draw(canvas);
    }
    ...
}
```

注释也说得很明白。也就是说如果没有Toolbar作为CollapsingToolbarLayout的子view，那么mContentScrim会盖住所有的子View。

也就是说，如果View声明在Toolbar后面，那么此View是不会在collapse的时候被盖住。

【未完待续】