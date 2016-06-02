---
layout: post
title: "VividPath让路径动起来"
category: all-about-tech
tags: 
 - android
 - path
 - animation
 - drawable
 - pathMeasure
date: 2016-04-26 02:05:57+00:00
---

前段时间，看了下path的动画部分。看完之后，就过去了。最近刚好抽点时间把之前看的内容整理下，就当做是温故而知新了。

不过，整理的过程中也确实学习到了新的东西。还是有收获的哈。

希望每一个爱学习的同学都把自己平时学习的心得体会写出来，避免自己以后犯错，也为他人谋福利。

效果图：

![image](/media/imgs/vivid-path-vivid-view.gif)

### 介绍
Path其实是android中很常见的一个类。它方便让用户自己先确定好一个轨迹后，方便在Canvas上面画出来。其实就是所谓矢量图形。比如我们常见的svg图片其实就是一层一层的Path轨迹排列组合出来的。想了解svg使用的可以参考[svg-android](https://code.google.com/archive/p/svg-android/).关于Path就不多说了。自行Google。

### 如何在Path上面运动。

其实也不是什么神秘的事情，Android提供了`PathMeasure`这个类。可以通过它来获取到整个`Path`的长度。然后我们可以通过它来获取某一段长度的path。然后使用animator不断获取改变区间，并把这个path不断画出来即可以动起来了。

使用这个API：

{% highlight java %}
/**
 * Given a start and stop distance, return in dst the intervening
 * segment(s). If the segment is zero-length, return false, else return
 * true. startD and stopD are pinned to legal values (0..getLength()).
 * If startD <= stopD then return false (and leave dst untouched).
 * Begin the segment with a moveTo if startWithMoveTo is true.
 *
 * <p>On {@link android.os.Build.VERSION_CODES#KITKAT} and earlier
 * releases, the resulting path may not display on a hardware-accelerated
 * Canvas. A simple workaround is to add a single operation to this path,
 * such as <code>dst.rLineTo(0, 0)</code>.</p>
 */
public boolean getSegment(float startD, float stopD, Path dst, boolean startWithMoveTo) {
    dst.isSimplePath = false;
    return native_getSegment(native_instance, startD, stopD, dst.ni(), startWithMoveTo);
}
{% endhighlight %}
通过这个api，我们可以获取到startD到stopD这一段的path。这样就可以实现截取一小段的问题。

其实要想让整个动画顺畅起来，用这个api是不能简单达到的。比如你想实现0.9到0.1这一段距离，你不能简单的使用 `startD = 0.9f * len, stopD = 0.1f * len` ,结果就是它只会显示0.9到1.0这一段。那么问题就来了，怎样才能显示出来0.9到1.0呢。其实思路很简单，它不允许超过1.0的话，我可以把它拆成两端嘛：`0.9~1.0`跟`0.0~0.1`。然后把这两段合并即可。同样的，比如我想实现-0.1到1.0这一段的话，也可以用这种思路，不过需要指出的时候PathMeasure只认正数。下面是我的解决方案：

{% highlight java %}
public static void setSegment(PathMeasure pm, Path p, float start, float end) {
    final float totalLen = pm.getLength();
    float len = end - start;
    // 长度超过1没有意义
    if (Math.abs(len) > 1) {
        len = len > 0 ? 1 : -1;
    }
    // 起始点在-1和1之间
    while (Math.abs(start) > 1) {
        //变成(-1,1)
        start = start + (start > 0 ? -1 : 1);
    }
    end = start + len;
    //
    start = Math.min(start, end);
    end = start + Math.abs(len);
    //
    if (start < 0) {
        if (end < 0) {
            pm.getSegment((1 + start) * totalLen, (1 + end) * totalLen, p, true);
            return;
        }
        pm.getSegment((1 + start) * totalLen, totalLen, p, true);
        start = 0;
    }
    if (end > 1) {
        pm.getSegment(0, (end - 1) * totalLen, p, true);
        end = 1;
    }
    pm.getSegment(start * totalLen, end * totalLen, p, true);
}
{% endhighlight %}

但是，path还有一个问题就是，一个path可以包含N个闭合路径。默认的操作都是在第一个闭合路径上面进行的。于是就有了下面的代码:

{% highlight java %}
public List<Pair<Path, PathMeasure>> extract() {
    if (mPathMeasure == null || mRawPath == null) {
        return null;
    }
    mList.clear();
    do {
        final float len = mPathMeasure.getLength();
        Path path = new Path();
        mPathMeasure.getSegment(0, len, path, true);
        path.close();
        //
        mList.add(new Pair<>(path, new PathMeasure(path, true)));
    } while (mPathMeasure.nextContour());
    return mList;
}
{% endhighlight %}
这段代码的主要作用是把一个Path分解成N个闭合路径，每一个路径生成一个单独的只有一条路径的path.

这样我们就可以在一个复杂的path上面将每一个闭合路径都显示出来了。当然了，如果需要动起来的话，我们还要有一个Animator。如下:

{% highlight java %}
public Animator start() {
    if (mAnimator != null) {
        mAnimator.cancel();
    }
    //
    final float lastProgress = (mProgress > 0 && mProgress < 1) ? mProgress : 0;
    //
    final ValueAnimator animator = ValueAnimator.ofFloat(0, 1.0f);
    animator.addUpdateListener(new ValueAnimator.AnimatorUpdateListener() {
        @Override
        public void onAnimationUpdate(ValueAnimator animation) {
            final Object value = animation.getAnimatedValue();
            if (value instanceof Float) {
                mProgress = ((Float) value).floatValue();
                invalidateSelf();
            }
        }
    });
    animator.setInterpolator(new TimeInterpolator() {
        @Override
        public float getInterpolation(float input) {
            input += lastProgress;
            if (input > 1) {
                input = input - 1;
            }
            return (mInterpolator != null) ? mInterpolator.getInterpolation(input) : input;
        }
    });
    animator.setRepeatMode(ValueAnimator.RESTART);
    animator.setRepeatCount(-1);
    animator.setDuration(500);
    animator.start();
    //
    return mAnimator = animator;
}
{% endhighlight %}

### 坑


给ImageView设定一个VividDrawable后，可以实现在VividDrawable中通过Animator来实现不断刷新自己从而让动画跑起来。但是在我自己写的VividView中自己draw这个VividDrawable就不能实现动画。

于是，我便怀疑起了人生。

我看了下IamgeView里面关于`setImageDrawable`的源码。如下：

{% highlight java %}
public void setImageDrawable(@Nullable Drawable drawable) {
    if (mDrawable != drawable) {
        mResource = 0;
        mUri = null;

        final int oldWidth = mDrawableWidth;
        final int oldHeight = mDrawableHeight;

        updateDrawable(drawable);

        if (oldWidth != mDrawableWidth || oldHeight != mDrawableHeight) {
            requestLayout();
        }
        invalidate();
    }
}
{% endhighlight %}
可以看到，当drawable传递过来的时候会执行了一个关键的`updateDrawable(drawable)`. 如下：

{% highlight java %}
private void updateDrawable(Drawable d) {
    if (d != mRecycleableBitmapDrawable && mRecycleableBitmapDrawable != null) {
        mRecycleableBitmapDrawable.setBitmap(null);
    }

    if (mDrawable != null) {
        mDrawable.setCallback(null);
        unscheduleDrawable(mDrawable);
    }

    mDrawable = d;

    if (d != null) {
        d.setCallback(this);
        d.setLayoutDirection(getLayoutDirection());
        if (d.isStateful()) {
            d.setState(getDrawableState());
        }
        d.setVisible(getVisibility() == VISIBLE, true);
        d.setLevel(mLevel);
        mDrawableWidth = d.getIntrinsicWidth();
        mDrawableHeight = d.getIntrinsicHeight();
        applyImageTint();
        applyColorMod();

        configureBounds();
    } else {
        mDrawableWidth = mDrawableHeight = -1;
    }
}
{% endhighlight %}
这时候可能还是不知道为啥。为什么ImageView就可以。此时，我们回到最初产生问题的地方。也就是Drawable里面的`invalidateSelf()`. 源码如下：

{% highlight java %}
public void invalidateSelf() {
    final Callback callback = getCallback();
    if (callback != null) {
        callback.invalidateDrawable(this);
    }
}
{% endhighlight %}`
有没有发现`invalidateSelf()`之后，会通过一个`CallBack`调用`callback.invalidateDrawable(this)`.此时就可以`updateDrawable`对应起来了，从它的源码可以看到它会把传过来的有效的drawable通过`setCallBack`把`CallBack`设置到Drawable里面。

在我以为雨过天晴，一切都将要顺风顺水的时候。我重新编译运行后发现，依然如故。就像一杯老酒，给人的挫败依然浓烈。不过，我们再看一下CallBack的实现的地方(View继承了那个`CallBack`)就可以知道问题了。先看源码:

{% highlight java %}
@Override
public void invalidateDrawable(@NonNull Drawable drawable) {
    if (verifyDrawable(drawable)) {
        final Rect dirty = drawable.getDirtyBounds();
        final int scrollX = mScrollX;
        final int scrollY = mScrollY;

        invalidate(dirty.left + scrollX, dirty.top + scrollY,
                dirty.right + scrollX, dirty.bottom + scrollY);
        rebuildOutline();
    }
}
{% endhighlight %}

在这里我们就看到了熟悉的`invalidate`，啊哈哈哈。也就是说如果没有刷新界面，那就是`invalidate`没有执行到。所以问题就出在了`verifyDrawable(drawable)`这个地方，源码如下:

{% highlight java %}
protected boolean verifyDrawable(Drawable who) {
    return who == mBackground || (mScrollCache != null && mScrollCache.scrollBar == who)
            || (mForegroundInfo != null && mForegroundInfo.mDrawable == who);
}
{% endhighlight %}
这里其实就是校验了一下，传入的drawable是不是有效的。因此解决方案就是让这里返回`true`即可，但是未免也太简单粗暴了点。下面是我的解决方案:

{% highlight java %}
@Override
protected boolean verifyDrawable(Drawable who) {
    // when Drawable.invalidateSelf is invoked, view need to check if the drawable is valid, make it valid
    return who == mVividDrawable || super.verifyDrawable(who);
}
{% endhighlight %}

### 总结

有坑不怕，来来来，我们看源码。
