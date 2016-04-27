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

### 介绍
Path其实是android中很常见的一个类。它方便让用户自己先确定好一个轨迹后，方便在Canvas上面画出来。其实就是所谓矢量图形。比如我们常见的svg图片其实就是一层一层的Path轨迹排列组合出来的。想了解svg使用的可以参考[svg-android](https://code.google.com/archive/p/svg-android/).

...

**<文章没写完>**

...

### 坑


给ImageView设定一个VividDrawable后，可以实现在VividDrawable中通过Animator来实现不断刷新自己从而让动画跑起来。但是在我自己写的VividView中自己draw这个VividDrawable就不能实现动画。

于是，我便怀疑起了人生。

我看了下IamgeView里面关于`setImageDrawable`的源码。如下：

```Java
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
```
可以看到，当drawable传递过来的时候会执行了一个关键的`updateDrawable(drawable)`. 如下：

```Java
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
```
这时候可能还是不知道为啥。为什么ImageView就可以。此时，我们回到最初产生问题的地方。也就是Drawable里面的`invalidateSelf()`. 源码如下：

```Java
public void invalidateSelf() {
    final Callback callback = getCallback();
    if (callback != null) {
        callback.invalidateDrawable(this);
    }
}
````
有没有发现`invalidateSelf()`之后，会通过一个`CallBack`调用`callback.invalidateDrawable(this)`.此时就可以`updateDrawable`对应起来了，从它的源码可以看到它会把传过来的有效的drawable通过`setCallBack`把`CallBack`设置到Drawable里面。

在我以为雨过天晴，一切都将要顺风顺水的时候。我重新编译运行后发现，依然如故。就像一杯老酒，给人的挫败依然浓烈。不过，我们再看一下CallBack的实现的地方(View继承了那个`CallBack`)就可以知道问题了。先看源码:

```Java
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
```

在这里我们就看到了熟悉的`invalidate`，啊哈哈哈。也就是说如果没有刷新界面，那就是`invalidate`没有执行到。所以问题就出在了`verifyDrawable(drawable)`这个地方，源码如下:

```Java
protected boolean verifyDrawable(Drawable who) {
    return who == mBackground || (mScrollCache != null && mScrollCache.scrollBar == who)
            || (mForegroundInfo != null && mForegroundInfo.mDrawable == who);
}
```
这里其实就是校验了一下，传入的drawable是不是有效的。因此解决方案就是让这里返回`true`即可，但是未免也太简单粗暴了点。下面是我的解决方案:

```Java
@Override
protected boolean verifyDrawable(Drawable who) {
    // when Drawable.invalidateSelf is invoked, view need to check if the drawable is valid, make it valid
    return who == mVividDrawable || super.verifyDrawable(who);
}
```

