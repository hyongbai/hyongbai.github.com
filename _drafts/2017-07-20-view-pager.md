---
layout: post
title: "各种姿势使用ViewPager"
category: all-about-tech
tags: -[Android] -[ViewPager]
date: 2017-07-20 15:49:57+00:00
---

话说Android开发的时候我们会常常用到ViewPager，用起来很是方便。

基本上只要是用来做切换页面的功能，都可以使用ViewPager来实现。而且，Google还给我们封装了很多有用的API。

已经用了好几年了，现在来总结ViewPager会不会晚了呢？ 不管了，我思故我在啊，温故知新吧。下面就来一探究竟。

## 使用技巧

怎么接入ViewPager就不讲了。

### Decor

使用姿势：

```xml
<android.support.v4.view.ViewPager
    android:id="@id/vp"
    android:layout_width="match_parent"
    android:layout_height="180dp"
    android:clipChildren="false">

    <android.support.v4.view.PagerTabStrip
        android:layout_width="match_parent"
        android:layout_height="wrap_content"/>
</android.support.v4.view.ViewPager>

```

这个功能可能很少有人会用到吧。顾名思义就是修饰。

添加到ViewPager中之后，它会独立在正常的子View之外显示。比如我们可以使用`PagerTabStrip`来实现TabLayout的效果。

在老版本的ViewPager中隐藏了一个`Decor`接口，实现它的子view都会被识别为Decor。新版本中只要给你的View添加`@DecorView`的注解即可。

当一个view被标记为Decor之后，它的LayoutParams中的isDecor会被设定为true。

注意，使用PagerTabStrip时需要配合`PagerAdapter.getPageTitle(int position)`, 如果返回空那么将不显示内容。

(效果图，略)

### 设定间距

使用姿势为：`ViewPager.setPageMargin`。

用来设定两个pager之间的间距。滑动的时候能清楚的看到pager之间会有一条缝隙，但是变成idle状态之后这个缝隙不会显示出来，只对滑动时有效。

### 设定间隔图片

使用姿势：`ViewPager.setPageMarginDrawable`

既然可以设定pager间间距，那么也是可以设定这个间距里显示的图片的。最终的效果会是滚动时间距不再是ViewPager的背景，而是自定义的图片。

### 设定缓存数量

使用姿势： `ViewPager.setOffscreenPageLimit`

话说，正常情况下我们操作ViewPager时只能滑出上一个或者下一个pager。也就是说ViewPager显示出来的除了Decor之外的子view的数量为3。即： 1 + 1*2。

不过，ViewPager也可以设定多个Pager，数量为`1 + n*2`，为什么是2倍呢，主要是左右两边对称的。注意：这个n会自动修正为 `n > 0`

### 滚动到指定位置

使用姿势：`ViewPager.setCurrentItem(int item, boolean smoothScroll) `

可以自动滚动到指定的Position。并且可以指定是否顺滑。

### 设定切换动画

使用姿势： `ViewPager.setPageTransformer(boolean reverseDrawingOrder, PageTransformer transformer)`

这个是比较人性化的一个API，主要用来控制我们滑动时的动画。虽然在V4包里面没有提供现成的，但是Android也给我们提供了几个。可以访问:<https://developer.android.com/training/animation/screen-slide.html> 复制粘贴即可。

当ViewPager在滚动的时候，会讲每个除Decor之外的子View及其被滑动的比例通过`transformPage(View page, float position)`回调出来，我们只要在回调用根据position给予view相应程度的形变即可。

### 设定子View宽度

使用姿势： `PagerAdapger.getPageWidth(int position)`

一般情况下，ViewPager中每个pager的宽度就是ViewPager本身的宽度，也就是说它们之间比例是1f的关系。一般说一般情况下的时候我们都是可以更改一般情况的。

这不ViewPager就给我们敞开了大门，我们只要在PagerAdater的这个函数中更改其返回值即可。不过，需要注意的是，子View并不是居中显示的。它是按照current item贴着左边然后左右两边的其他pager线性排列的。

### 露出左右两边

使用姿势：Parent和自身添加clipChildren="false"，然后将ViewPager设定layout_marginLeft和layout_marginRight即可。

其实这个主要是用到了`clipChildren`这个属性，主要原理就是当parent的clipChildren为false时，它在画子view的时候就允许子view画出自己的layout区域之外。

所以，ViewPager两边的内容就可以不受它自己尺寸的影响而画出其外了。

### 嵌入多个Fragment

使用姿势：实现FragmentPagerAdapter中的`Fragment getItem(int position)`即可。

V4给我们封装了一个`FragmentPagerAdapter`，并实现了它的`instantiateItem`，并且抽象出来了一个`Fragment getItem，(int position)`。我们只要填充这个函数就行了。

FragmentPagerAdapter会按照一定规则(主要是：`"android:switcher:" + ViewPagerId + ":" + getItemId`)帮我们生成一个唯一的tag。首先它回去FragmentManager中根据这个tag查找，如果找不到就会调用getItem，然后让我们自己生成一个fragment。然后将其add到FragmentManger中去。

同时，你会发现Fragment里面的`setUserVisibleHint`终于起作用了。FragmentPagerAdapter中会判断当前是不是current item，然后调用setUserVisibleHint，是则true，不是则false。

## 触摸处理

ViewPager本身继承自ViewGroup要说到触摸时间的处理的话，那么自然就要涉及到两块，即：触摸拦截以及触摸处理。

### 触摸拦截

基于Android本身Touch事件的处理逻辑，ViewPager只需要在`onInterceptTouchEvent()`中做拦截逻辑即可。ViewPager在MotionEvent.ACTION_MOVE的核心逻辑逻辑如下：

```java
final int pointerIndex = MotionEventCompat.findPointerIndex(ev, activePointerId);
final float x = MotionEventCompat.getX(ev, pointerIndex);
final float dx = x - mLastMotionX;
// ....
 if (dx != 0 && !isGutterDrag(mLastMotionX, dx) &&
        canScroll(this, false, (int) dx, (int) x, (int) y)) {
    // Nested view has scrollable area under this point. Let it be handled there.
    mLastMotionX = x;
    mLastMotionY = y;
    mIsUnableToDrag = true;
    return false;
}
if (xDiff > mTouchSlop && xDiff * 0.5f > yDiff) {
    if (DEBUG) Log.v(TAG, "Starting drag!");
    mIsBeingDragged = true;
    requestParentDisallowInterceptTouchEvent(true);
    setScrollState(SCROLL_STATE_DRAGGING);
    mLastMotionX = dx > 0 ? mInitialMotionX + mTouchSlop :
            mInitialMotionX - mTouchSlop;
    mLastMotionY = y;
    setScrollingCacheEnabled(true);
} 
// ...
if (mIsBeingDragged) {
    // Scroll to follow the motion event
    if (performDrag(x)) {
        ViewCompat.postInvalidateOnAnimation(this);
    }
}
```

这里面核心是两个判断逻辑。


> `dx != 0 && !isGutterDrag(mLastMotionX, dx) && canScroll(this, false, (int) dx, (int) x, (int) y)`

- `dx != 0`很好理解。
- `isGutterDrag` 其实是指当前滑动时间是不是在两旁的边界区域。源码为`(x < mGutterSize && dx > 0) || (x > getWidth() - mGutterSize && dx < 0)`, 也就是只要点击在两边的区域ViewPager都会截获点击区域，子View就没有机会了接收事件了，(除非子view在TOUCH_DOWN的时候就禁止Parent拦截触摸事件)。
- `canScroll` 意为判断`点击区域`所在的`所有的`子(孙)View是不是`canScrollHorizontally`，简而言之就是子View如果能滚动ViewPager就不拦截。

> `xDiff > mTouchSlop && xDiff * 0.5f > yDiff` 

- 有效滑动并且是在水平方向, 水平移动距离是竖直移动距离的2倍多(35°左右吧)

当确定为可以拖动之后设定`mIsBeingDragged = true`，此后`onInterceptTouchEvent()`收到非ACTION_DOWN之后会直接return true。从而在可以在onTouchEvent中处理触摸事件了。代码如下：

```java
if (action != MotionEvent.ACTION_DOWN) {
    if (mIsBeingDragged) {
        if (DEBUG) Log.v(TAG, "Intercept returning true!");
        return true;
    }
    if (mIsUnableToDrag) {
        if (DEBUG) Log.v(TAG, "Intercept returning false!");
        return false;
    }
}
```

到这里拦截的核心逻辑基本上就这样了。注意，在这期间调用了`requestParentDisallowInterceptTouchEvent`，这一步很关键。主要目的是告诉Parent你就别截获我的触摸事件了，以后的触摸事件你就老老实实往下面传递就好了。

### 触摸处理

当ViewPager拦截了触摸事件之后接下来就要响应之了，比如跟着手指滑动/手指停下来之后分配上下一页等等。

#### ACTION_DOWN 

接收到ActionDown的时候，ViewPager会停止当前的滚动动画，让ViewPager停留在手指触摸的位置。并且执行一次populate， 这个下一节再讲。

#### ACTION_MOVE

此处仍然会判断是不是需要mIsBeingDragged。逻辑同OnIntercepTouchEvent。略。来看看是如何处理滚动的。

核心处理代码如下：

```java
if (mIsBeingDragged) {
    // Scroll to follow the motion event
    final int activePointerIndex = MotionEventCompat.findPointerIndex(
            ev, mActivePointerId);
    final float x = MotionEventCompat.getX(ev, activePointerIndex);
    needsInvalidate |= performDrag(x);
}
```

可以看到处理拖动主要是通过`performDrag`，传入的x左边是当前的`activePointerIndex`的左边，也就是说当你一开始是第一根手机在触摸后面又来了第二根手机同时触摸的话，那么滚动控制权就交给了后面的那个手指了。当performDrag返回true的时候表示需要刷新view。

好了，来看看performDrag是如何实现的。

```java
private boolean performDrag(float x) {
    boolean needsInvalidate = false;

    final float deltaX = mLastMotionX - x;
    mLastMotionX = x;

    float oldScrollX = getScrollX();
    float scrollX = oldScrollX + deltaX;
    final int width = getClientWidth();

    float leftBound = width * mFirstOffset;
    float rightBound = width * mLastOffset;
    boolean leftAbsolute = true;
    boolean rightAbsolute = true;

    final ItemInfo firstItem = mItems.get(0);
    final ItemInfo lastItem = mItems.get(mItems.size() - 1);
    if (firstItem.position != 0) {
        leftAbsolute = false;
        leftBound = firstItem.offset * width;
    }
    if (lastItem.position != mAdapter.getCount() - 1) {
        rightAbsolute = false;
        rightBound = lastItem.offset * width;
    }

    if (scrollX < leftBound) {
        if (leftAbsolute) {
            float over = leftBound - scrollX;
            needsInvalidate = mLeftEdge.onPull(Math.abs(over) / width);
        }
        scrollX = leftBound;
    } else if (scrollX > rightBound) {
        if (rightAbsolute) {
            float over = scrollX - rightBound;
            needsInvalidate = mRightEdge.onPull(Math.abs(over) / width);
        }
        scrollX = rightBound;
    }
    // Don't lose the rounded component
    mLastMotionX += scrollX - (int) scrollX;
    scrollTo((int) scrollX, getScrollY());
    pageScrolled((int) scrollX);

    return needsInvalidate;
}
```

这个函数的代码可能有点多，其实就两部分。

一个是处理`EdgeEffect`，如果当前是边缘的话，会根据左边的pager的边缘和当前的总滚动区域算出一个滑动距离：`leftBound - scrollX`。然后通过`mLeftEdge.onPull(Math.abs(over) / width)`交给LeftEdge。之后在onDraw里面会将其画出来。

另一部分就是处理滚动，同样也会考虑边界问题，上限为leftBound或者rightBound。然后通过`scrollTo`，来执行滚动。这个就是View自身的API，不做赘述。基本上跟着手机滚动就完了。

#### ACTION_UP

当手指离开屏幕的时候，它会根据当前的滚动距离，来断定往前滚动还是往后滚动或者退回原来的位置。核心处理逻辑如下：

```java
final VelocityTracker velocityTracker = mVelocityTracker;
velocityTracker.computeCurrentVelocity(1000, mMaximumVelocity);
int initialVelocity = (int) VelocityTrackerCompat.getXVelocity(
        velocityTracker, mActivePointerId);
mPopulatePending = true;
final int width = getClientWidth();
final int scrollX = getScrollX();
final ItemInfo ii = infoForCurrentScrollPosition();
final float marginOffset = (float) mPageMargin / width;
final int currentPage = ii.position;
final float pageOffset = (((float) scrollX / width) - ii.offset)
        / (ii.widthFactor + marginOffset);
final int activePointerIndex =
        MotionEventCompat.findPointerIndex(ev, mActivePointerId);
final float x = MotionEventCompat.getX(ev, activePointerIndex);
final int totalDelta = (int) (x - mInitialMotionX);
int nextPage = determineTargetPage(currentPage, pageOffset, initialVelocity,
        totalDelta);
setCurrentItemInternal(nextPage, true, true, initialVelocity);

needsInvalidate = resetTouch();
```

这里需要注意的是`currentPage`指的不一定是current item，它返回的其实是当前可见的最左边的那个pager。

```java
private ItemInfo infoForCurrentScrollPosition() {
    final float scrollOffset = width > 0 ? (float) getScrollX() / width : 0;
    // ...
    ItemInfo lastItem = null;
    for (int i = 0; i < mItems.size(); i++) {
        ItemInfo ii = mItems.get(i);
        // ...
        offset = ii.offset;
        final float leftBound = offset;
        final float rightBound = offset + ii.widthFactor + marginOffset;
        if (first || scrollOffset >= leftBound) {
            if (scrollOffset < rightBound || i == mItems.size() - 1) {
                return ii;
            }
        } else {
            return lastItem;
        }
        // ...
    }
    return lastItem;
}
```

看到没，最要最左边iitem的边界在当前的滚动区域内就会返回。好了，知道拿到的currentPage是什么之后就好理解后面的逻辑了。

下面来看看ViewPager是如何来确定该选择哪一个位置停留下来：

```java
private int determineTargetPage(int currentPage, float pageOffset, int velocity, int deltaX) {
    int targetPage;
    if (Math.abs(deltaX) > mFlingDistance && Math.abs(velocity) > mMinimumVelocity) {
        targetPage = velocity > 0 ? currentPage : currentPage + 1;
    } else {
        final float truncator = currentPage >= mCurItem ? 0.4f : 0.6f;
        targetPage = currentPage + (int) (pageOffset + truncator);
    }
    // ...
    return targetPage;
}
```

这里有两个判断：

**滚动速度**

如果超过最小距离并且速度的绝对值超过最小速度的话，就认定需要滚动。

当速度为正的时候，使用的是currentPage，也就是当前显示出来的最左边的page。

反之，使用的是当前显示的最左边的page的下一个。

**滚动距离**

最终结果是currentPage加上pageOffset(滑动距离，百分比)与truncator的和取整。注意，不是四舍五入。

是不是不好理解为什么`final float truncator = currentPage >= mCurItem ? 0.4f : 0.6f`啊？ 先告诉你最后的结果都是滚动的距离超过60%才会认定为有效滚动距离，也就是说才会进行切换，而非一半。

那么为什么一个是0.4一个是0.6呢？其实我们通常意义上面想想的是基于当前的item而言的移动距离，而这里currentPage指的是显示出来的最左边的page，而不是mCurItem。那么转化一下其实也就是说 currentPage + 0.4f = mCurItem - 0.6f。请不要混淆currentPage和mCurItem，这样就很好理解这段代码的含义了。

之后根据最终确定好的Position，再以动画的形式滚动到指定位置就万事大吉了。触摸的处理逻辑就这样了。

## 内部逻辑

这一节，我们来讲讲ViewPager是如何绘制的。

用过ViewPager的同学大概都知道，当我们的数据有变化的时候都会调用adapter里面的notifyDataSetChange()方法来更新我们的数据。那么我们就以notifyDataSetChange()为分界来分解ViewPager的内部逻辑。

### setAdapter

ViewPager必须要配合一个Adapter才能正常运行，我们来看看setAdapter干了什么吧。

```java
public void setAdapter(PagerAdapter adapter) {
    if (mAdapter != null) {
        mAdapter.setViewPagerObserver(null);
        mAdapter.startUpdate(this);
        for (int i = 0; i < mItems.size(); i++) {
            final ItemInfo ii = mItems.get(i);
            mAdapter.destroyItem(this, ii.position, ii.object);
        }
        mAdapter.finishUpdate(this);
        mItems.clear();
        removeNonDecorViews();
        mCurItem = 0;
        scrollTo(0, 0);
    }

    final PagerAdapter oldAdapter = mAdapter;
    mAdapter = adapter;
    mExpectedAdapterCount = 0;

    if (mAdapter != null) {
        if (mObserver == null) {
            mObserver = new PagerObserver();
        }
        mAdapter.setViewPagerObserver(mObserver);
        mPopulatePending = false;
        final boolean wasFirstLayout = mFirstLayout;
        mFirstLayout = true;
        mExpectedAdapterCount = mAdapter.getCount();
        if (mRestoredCurItem >= 0) {
            mAdapter.restoreState(mRestoredAdapterState, mRestoredClassLoader);
            setCurrentItemInternal(mRestoredCurItem, false, true);
            mRestoredCurItem = -1;
            mRestoredAdapterState = null;
            mRestoredClassLoader = null;
        } else if (!wasFirstLayout) {
            populate();
        } else {
            requestLayout();
        }
    }

    if (mAdapterChangeListener != null && oldAdapter != adapter) {
        mAdapterChangeListener.onAdapterChanged(oldAdapter, adapter);
    }
}
```

如此看来，这里其实还是很重的。

首先，它不会去比较新旧adapter是否为同一对象。

其次，一上来就会讲之前所有的item全部都destroy一遍，并且滚动回0,0位置。

然后，就是重点了。

### notifyDataSetChange


## 遇到的坑

话说ViewPager其实也还是有坑的。

### 子View滚动判断错误

某天遇到一个非常莫名奇妙的bug：当弹出某一控件之后使之不可见，然后ViewPager就不能滚动了。本以为这是处理了触摸事件，翻遍代码也没发现。猜测是因为那个控件是一个可滚动的listview导致被这个listview给截获了，但这个view不可见啊。 后来发现它虽然不可见但是`canScrollHorizontally`一直被调用，并且返回的是true。

麻痹啊。然后看了ViewPager的源码。

这个是最坑的。还记得上面的拦截逻辑里面有个`canScroll`函数不，坑就在那里。理论上来说你判断子view是不是可以滚动，再来确定需要不需要滚动本身这件事是好的。

但是，剧情总是需要转折的。来看看惨案是如何发生的：

```java
/**
 * Tests scrollability within child views of v given a delta of dx.
 *
 * @param v View to test for horizontal scrollability
 * @param checkV Whether the view v passed should itself be checked for scrollability (true),
 *               or just its children (false).
 * @param dx Delta scrolled in pixels
 * @param x X coordinate of the active touch point
 * @param y Y coordinate of the active touch point
 * @return true if child views of v can be scrolled by delta of dx.
 */
protected boolean canScroll(View v, boolean checkV, int dx, int x, int y) {
    if (v instanceof ViewGroup) {
        final ViewGroup group = (ViewGroup) v;
        final int scrollX = v.getScrollX();
        final int scrollY = v.getScrollY();
        final int count = group.getChildCount();
        // Count backwards - let topmost views consume scroll distance first.
        for (int i = count - 1; i >= 0; i--) {
            // TODO: Add versioned support here for transformed views.
            // This will not work for transformed views in Honeycomb+
            final View child = group.getChildAt(i);
            if (x + scrollX >= child.getLeft() && x + scrollX < child.getRight() &&
                    y + scrollY >= child.getTop() && y + scrollY < child.getBottom() &&
                    canScroll(child, true, dx, x + scrollX - child.getLeft(),
                            y + scrollY - child.getTop())) {
                return true;
            }
        }
    }

    return checkV && ViewCompat.canScrollHorizontally(v, -dx);
}

```

看出问题来了没有？

这里递归地检索点击区域的所有的View的子View，而不管这个view是不是可见，因而问题就暴露了出来。

解决思路是重写这个函数，并且讲view的可见当做一个必须的条件。问题迎刃而解。

## 最后

其实在RecyclerView出来之后ViewPager的功能也可以通过自己写LayoutManager来实现了。但是，ViewPager已经是一个成熟的控件了，用起来也是方便的不得了。

如果你有心的话，可以试试自己入RecyclerView的坑。