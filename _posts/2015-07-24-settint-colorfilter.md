---
layout: post
title: "SetTint或者ColorFilter改变图片的颜色"
category: all-about-tech
tags: 
- ColorFilter
- Drawable
- setTint

date: 2015-07-24 17:23:57+08:00
--- 

Android中也可以通过利用代码来搞定是图片变成另外一种颜色的效果。特别是多主题的时候。

通常的做法是如果你想要各种颜色，就需要每个种主题都对应着一个图片，神烦！！！而且会是包的体积变很大(这里说的是非SVG的情况)。

如果可以通过代码来让图片变色是不是萌萌哒呢？！

答案显而易见是必须的。

下面通过两种方式来达到上面所说的效果。


### SetTint

```
	BitmapDrawable drawable = new BitmapDrawable(bitmap);
	drawable.setTintMode(PorterDuff.Mode.SRC_ATOP);
	drawable.set(Color.RED);
	//drawable.setTintList(colorStateList);
```

其中通过setTint来设置颜色(也可以通过setTintList来设置colorStateList), 通过setTintMode来设置转换模式(PorterDuff.Mode对着应16种模式)。在这里我使用的是PorterDuff.Mode.SRC_ATOP。

也可以在xml中进行设置 `android:tint` `android:tintMode`.

不过缺点是只能在Lollipop上面使用，而且只有`BitmapDrawable`和`NinePatchDrawable`支持，可见谷歌官文档[Working with Drawables](https://developer.android.com/training/material/drawables.html)。
上面也提到了支持 `setTintList` ，也就是说理论上可以支持根据不同状态显示不同颜色。

### ColorFilter

其实查看下BitmapDrawable的源码就可以知道在`setTint`的时候`Drawable`里面调用了`setTintList(ColorStateList.valueOf(tint))`,再打开`BitmapDrawable.setTintList`就可以看到如下:

```
    @Override
    public void setTintList(ColorStateList tint) {
        mBitmapState.mTint = tint;
        mTintFilter = updateTintFilter(mTintFilter, tint, mBitmapState.mTintMode);
        invalidateSelf();
    }
```

其中`mTintFilter`就是一个`PorterDuffColorFilter`，因此我们可以直接通过设置`ColorFilter`即可完成 setTint 的操作。方法很简单:

```
	PorterDuffColorFilter filter = new PorterDuffColorFilter(color, mode);
    Drawable drawable = getDrawable(R.mipmap.ic_launcher);
    drawable.setColorFilter(filter);
```

优点是在低于lollipop的Android版本上面也可以运行，且只要是Drawable都可以支持。但是还不能支持`ColorStateList`

### 下面放上效果图

![](http://7xkm4a.com1.z0.glb.clouddn.com/ascreenshot-20150724-165307.png)
