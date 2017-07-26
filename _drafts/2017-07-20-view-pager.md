---
layout: post
title: "各种姿势使用ViewPager"
category: all-about-tech
tags: -[Android] -[ViewPager]
date: 2017-07-20 15:49:57+00:00
---

话说Android开发的时候我们会常常用到ViewPager，用起来很是方便。

基本上只要是用来做切换页面的功能，都可以使用ViewPager来实现。而且，Google还给我们封装了很多有用的API。

下面就来一探究竟。


## 使用技巧

怎么接入ViewPager就不讲了。

#### Decor

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

#### 设定间距

使用姿势为：`ViewPager.setPageMargin`。

用来设定两个pager之间的间距。滑动的时候能清楚的看到pager之间会有一条缝隙，但是变成idle状态之后这个缝隙不会显示出来，只对滑动时有效。

#### 设定间隔图片

使用姿势：`ViewPager.setPageMarginDrawable`

既然可以设定pager间间距，那么也是可以设定这个间距里显示的图片的。最终的效果会是滚动时间距不再是ViewPager的背景，而是自定义的图片。

#### 设定缓存数量

使用姿势： `ViewPager.setOffscreenPageLimit`

话说，正常情况下我们操作ViewPager时只能滑出上一个或者下一个pager。也就是说ViewPager显示出来的除了Decor之外的子view的数量为3。即： 1 + 1*2。

不过，ViewPager也可以设定多个Pager，数量为`1 + n*2`，为什么是2倍呢，主要是左右两边对称的。注意：这个n会自动修正为 `n > 0`

#### 滚动到指定位置

使用姿势：`ViewPager.setCurrentItem(int item, boolean smoothScroll) `

可以自动滚动到指定的Position。并且可以指定是否顺滑。

#### 设定切换动画

使用姿势： `ViewPager.setPageTransformer(boolean reverseDrawingOrder, PageTransformer transformer)`

这个是比较人性化的一个API，主要用来控制我们滑动时的动画。虽然在V4包里面没有提供现成的，但是Android也给我们提供了几个。可以访问:<https://developer.android.com/training/animation/screen-slide.html> 复制粘贴即可。

当ViewPager在滚动的时候，会讲每个除Decor之外的子View及其被滑动的比例通过`transformPage(View page, float position)`回调出来，我们只要在回调用根据position给予view相应程度的形变即可。

#### 设定子View宽度

使用姿势： `PagerAdapger.getPageWidth(int position)`

一般情况下，ViewPager中每个pager的宽度就是ViewPager本身的宽度，也就是说它们之间比例是1f的关系。一般说一般情况下的时候我们都是可以更改一般情况的。

这不ViewPager就给我们敞开了大门，我们只要在PagerAdater的这个函数中更改其返回值即可。不过，需要注意的是，子View并不是居中显示的。它是按照current item贴着左边然后左右两边的其他pager线性排列的。

#### 露出左右两边

使用姿势：Parent和自身添加clipChildren="false"，然后将ViewPager设定layout_marginLeft和layout_marginRight即可。

其实这个主要是用到了`clipChildren`这个属性，主要原理就是当parent的clipChildren为false时，它在画子view的时候就允许子view画出自己的layout区域之外。

所以，ViewPager两边的内容就可以不受它自己尺寸的影响而画出其外了。

#### 嵌入多个Fragment

使用姿势：实现FragmentPagerAdapter中的`Fragment getItem(int position)`即可。

V4给我们封装了一个`FragmentPagerAdapter`，并实现了它的`instantiateItem`，并且抽象出来了一个`Fragment getItem，(int position)`。我们只要填充这个函数就行了。

FragmentPagerAdapter会按照一定规则(主要是：`"android:switcher:" + ViewPagerId + ":" + getItemId`)帮我们生成一个唯一的tag。首先它回去FragmentManager中根据这个tag查找，如果找不到就会调用getItem，然后让我们自己生成一个fragment。然后将其add到FragmentManger中去。

同时，你会发现Fragment里面的`setUserVisibleHint`终于起作用了。FragmentPagerAdapter中会判断当前是不是current item，然后调用setUserVisibleHint，是则true，不是则false。

## 触摸处理

ViewPager本身继承自ViewGroup要说到触摸时间的处理的话，那么自然就要涉及到两块，即：触摸拦截以及触摸处理。

#### 触摸拦截

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

到这里拦截的核心逻辑基本上就这样了。

#### 触摸处理

当ViewPager拦截了触摸事件之后接下来就要响应之了，比如跟着手指滑动/手指停下来之后分配上下一页等等。

## 内部逻辑

## 遇到的坑

话说ViewPager其实也还是有坑的。

#### 子View滚动判断错误

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