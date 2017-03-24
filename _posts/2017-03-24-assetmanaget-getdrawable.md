---
layout: post
title: "Resource通过resId获取Drawable的流程"
category: all-about-tech
tags: -[Android] -[Resource] -[AssetManager]
date: 2017-03-24 14:55:57+00:00
---

今天被问到，Android是怎么做到通过ResId获取Drawable的。以前看过，但是记不清楚了。

于是赶紧梳理一下。

首先，姿势。Android是通过Context拿到Resource然后调用里面的Drawable获取的。其中`getDrawable(@DrawableRes int id)`在Lollipop已经被废弃了，所以我们最好使用如下代码：

```java
public static Drawable drawable(@DrawableRes int id) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        return mThemeContext.getResources().getDrawable(id, mThemeContext.getTheme());
    }
    return mThemeContext.getResources().getDrawable(id);
}
```
接着我们来看getDrawable里面的实现：

```java
public Drawable getDrawable(@DrawableRes int id, @Nullable Theme theme)
        throws NotFoundException {
    final TypedValue value = obtainTempTypedValue();
    try {
        final ResourcesImpl impl = mResourcesImpl;
        impl.getValue(id, value, true);
        return impl.loadDrawable(this, value, id, theme, true);
    } finally {
        releaseTempTypedValue(value);
    }
}
```

我们可以看到其实是通过`ResourcesImpl`来实现的。这段代码首先通过`impl.getValue(id, value, true)`拿到了一个`TypedValue`, 这个过程是在AssertManager里面通过底层实现的。这里拿到了TypedValue，主要包含了:

- string : 图片的完整路径，比如“res/drawable-xhdpi-v4/ic_launcher.png”
- assetCookie : 这个貌似是给底层使用的，用来标记资源。
- type : int表示资源的类型，比如是图片还是Layout还是drawable等等，TypeValue里面会列出每个值对应的意思。后面会用到它来区别是不是ColorDrawable。
- data : 数据，如果是ColorDrawable的话，它表示对应的颜色值。

继续往下：

```java
@Nullable
Drawable loadDrawable(Resources wrapper, TypedValue value, int id, Resources.Theme theme,
        boolean useCache) throws NotFoundException {
    try {
        if (TRACE_FOR_PRELOAD) {
            // Log only framework resources
            if ((id >>> 24) == 0x1) {
                final String name = getResourceName(id);
                if (name != null) {
                    Log.d("PreloadDrawable", name);
                }
            }
        }

        // 这里根据type来判断是不是colorDrawable
        final boolean isColorDrawable;
        final DrawableCache caches;
        final long key;
        if (value.type >= TypedValue.TYPE_FIRST_COLOR_INT
                && value.type <= TypedValue.TYPE_LAST_COLOR_INT) {
            isColorDrawable = true;
            caches = mColorDrawableCache;
            key = value.data;
        } else {
            isColorDrawable = false;
            caches = mDrawableCache;
            key = (((long) value.assetCookie) << 32) | value.data;
        }

        // First, check whether we have a cached version of this drawable
        // that was inflated against the specified theme. Skip the cache if
        // we're currently preloading or we're not using the cache.
        if (!mPreloading && useCache) {
            final Drawable cachedDrawable = caches.getInstance(key, wrapper, theme);
            if (cachedDrawable != null) {
                return cachedDrawable;
            }
        }

        // Next, check preloaded drawables. Preloaded drawables may contain
        // unresolved theme attributes.
        final Drawable.ConstantState cs;
        if (isColorDrawable) {
            cs = sPreloadedColorDrawables.get(key);
        } else {
            cs = sPreloadedDrawables[mConfiguration.getLayoutDirection()].get(key);
        }

        Drawable dr;
        if (cs != null) {
            dr = cs.newDrawable(wrapper);
        } else if (isColorDrawable) {
            dr = new ColorDrawable(value.data);
        } else {
            dr = loadDrawableForCookie(wrapper, value, id, null);
        }

        // Determine if the drawable has unresolved theme attributes. If it
        // does, we'll need to apply a theme and store it in a theme-specific
        // cache.
        final boolean canApplyTheme = dr != null && dr.canApplyTheme();
        if (canApplyTheme && theme != null) {
            dr = dr.mutate();
            dr.applyTheme(theme);
            dr.clearMutated();
        }

        // If we were able to obtain a drawable, store it in the appropriate
        // cache: preload, not themed, null theme, or theme-specific. Don't
        // pollute the cache with drawables loaded from a foreign density.
        if (dr != null && useCache) {
            dr.setChangingConfigurations(value.changingConfigurations);
            cacheDrawable(value, isColorDrawable, caches, theme, canApplyTheme, key, dr);
        }

        return dr;
    } catch (Exception e) {
        String name;
        try {
            name = getResourceName(id);
        } catch (NotFoundException e2) {
            name = "(missing name)";
        }

        // The target drawable might fail to load for any number of
        // reasons, but we always want to include the resource name.
        // Since the client already expects this method to throw a
        // NotFoundException, just throw one of those.
        final NotFoundException nfe = new NotFoundException("Drawable " + name
                + " with resource ID #0x" + Integer.toHexString(id), e);
        nfe.setStackTrace(new StackTraceElement[0]);
        throw nfe;
    }
}
```

首先他会从内存里面获取缓存，这里会通过前面讲到的type来判断是不是colorDrawable，如果是的话，去`mColorDrawableCache`里面获取缓存，如果不是的话通过`mDrawableCache`来获取(后面统一用caches代替，不区分了)。如果内存里面有的话，就直接返回。如果内存没有的话，会从preload里面取(这里也会区分是不是color, preload后面再讲)。如果还是没有缓存，那么就会查看到底是不是color，如果是color的话，就从TypeValue里面获取data(即color)生成一个新的，如果不是color的话就调用`loadDrawableForCookie`继续加载。加载完了之后放到上面提到的caches缓存起来，然后再返回给用户。

下面来看loadDrawableForCookie

```java
private Drawable loadDrawableForCookie(Resources wrapper, TypedValue value, int id,
        Resources.Theme theme) {
    //...
    final Drawable dr;

    Trace.traceBegin(Trace.TRACE_TAG_RESOURCES, file);
    try {
        if (file.endsWith(".xml")) {
            final XmlResourceParser rp = loadXmlResourceParser(
                    file, id, value.assetCookie, "drawable");
            dr = Drawable.createFromXml(wrapper, rp, theme);
            rp.close();
        } else {
            final InputStream is = mAssets.openNonAsset(
                    value.assetCookie, file, AssetManager.ACCESS_STREAMING);
            dr = Drawable.createFromResourceStream(wrapper, value, is, file, null);
            is.close();
        }
    } catch (Exception e) {
        Trace.traceEnd(Trace.TRACE_TAG_RESOURCES);
        final NotFoundException rnf = new NotFoundException(
                "File " + file + " from drawable resource ID #0x" + Integer.toHexString(id));
        rnf.initCause(e);
        throw rnf;
    }
    Trace.traceEnd(Trace.TRACE_TAG_RESOURCES);

    return dr;
}
```

这里的file就是前面说到的typevalue中的string哈。这里会继续比较到底是xml还是非xml文件(比如png等)。

继续。

#### 加载xml文件

```java
XmlResourceParser loadXmlResourceParser(@NonNull String file, @AnyRes int id, int assetCookie,
        @NonNull String type)
        throws NotFoundException {
    if (id != 0) {
        try {
            synchronized (mCachedXmlBlocks) {
                final int[] cachedXmlBlockCookies = mCachedXmlBlockCookies;
                final String[] cachedXmlBlockFiles = mCachedXmlBlockFiles;
                final XmlBlock[] cachedXmlBlocks = mCachedXmlBlocks;
                // First see if this block is in our cache.
                final int num = cachedXmlBlockFiles.length;
                for (int i = 0; i < num; i++) {
                    if (cachedXmlBlockCookies[i] == assetCookie && cachedXmlBlockFiles[i] != null
                            && cachedXmlBlockFiles[i].equals(file)) {
                        return cachedXmlBlocks[i].newParser();
                    }
                }

                // Not in the cache, create a new block and put it at
                // the next slot in the cache.
                final XmlBlock block = mAssets.openXmlBlockAsset(assetCookie, file);
                if (block != null) {
                    final int pos = (mLastCachedXmlBlockIndex + 1) % num;
                    mLastCachedXmlBlockIndex = pos;
                    final XmlBlock oldBlock = cachedXmlBlocks[pos];
                    if (oldBlock != null) {
                        oldBlock.close();
                    }
                    cachedXmlBlockCookies[pos] = assetCookie;
                    cachedXmlBlockFiles[pos] = file;
                    cachedXmlBlocks[pos] = block;
                    return block.newParser();
                }
            }
        } catch (Exception e) {
            final NotFoundException rnf = new NotFoundException("File " + file
                    + " from xml type " + type + " resource ID #0x" + Integer.toHexString(id));
            rnf.initCause(e);
            throw rnf;
        }
    }

    throw new NotFoundException("File " + file + " from xml type " + type + " resource ID #0x"
            + Integer.toHexString(id));
}
```

这里主要是拿到XmlResourceParser，首先从内存里面遍历看是不是有加载过（其中mCachedXmlBlockCookies里面存储的是TypeValue中的assetCookie，mCachedXmlBlockFiles用来存储文件路径也就是string, cachedXmlBlocks用来存储XmlBlock，这三个数组是一一对应的）。如果没有的话，会调用AssetManager里面的openXmlBlockAsset。参数分别是前面的cookie和string。

```java
/*package*/ final XmlBlock openXmlBlockAsset(int cookie, String fileName)
    throws IOException {
    synchronized (this) {
        if (!mOpen) {
            throw new RuntimeException("Assetmanager has been closed");
        }
        long xmlBlock = openXmlAssetNative(cookie, fileName);
        if (xmlBlock != 0) {
            XmlBlock res = new XmlBlock(this, xmlBlock);
            incRefsLocked(res.hashCode());
            return res;
        }
    }
    throw new FileNotFoundException("Asset XML file: " + fileName);
}
```

往下走就是通过底层拿到了XmlBlock然后得到xmlParser.之后回到`ResouecesImpl`调用`Drawable.createFromXml(wrapper, rp, theme)`，如下：

```java
public static Drawable createFromXml(Resources r, XmlPullParser parser, Theme theme)
        throws XmlPullParserException, IOException {
    AttributeSet attrs = Xml.asAttributeSet(parser);

    int type;
    //noinspection StatementWithEmptyBody
    while ((type=parser.next()) != XmlPullParser.START_TAG
            && type != XmlPullParser.END_DOCUMENT) {
        // Empty loop.
    }

    if (type != XmlPullParser.START_TAG) {
        throw new XmlPullParserException("No start tag found");
    }

    Drawable drawable = createFromXmlInner(r, parser, attrs, theme);

    if (drawable == null) {
        throw new RuntimeException("Unknown initial tag: " + parser.getName());
    }

    return drawable;
}
```

主要看createFromXmlInner里面的实现，它其实是拿到Resource里面的`DrawableInflater`。下面我们看看inflateFromXml的实现：

```java
public Drawable inflateFromXml(@NonNull String name, @NonNull XmlPullParser parser,
        @NonNull AttributeSet attrs, @Nullable Theme theme)
        throws XmlPullParserException, IOException {
    // Inner classes must be referenced as Outer$Inner, but XML tag names
    // can't contain $, so the <drawable> tag allows developers to specify
    // the class in an attribute. We'll still run it through inflateFromTag
    // to stay consistent with how LayoutInflater works.
    if (name.equals("drawable")) {
        name = attrs.getAttributeValue(null, "class");
        if (name == null) {
            throw new InflateException("<drawable> tag must specify class attribute");
        }
    }

    Drawable drawable = inflateFromTag(name);
    if (drawable == null) {
        drawable = inflateFromClass(name);
    }
    drawable.inflate(mRes, parser, attrs, theme);
    return drawable;
}
```
其中inflateFromTag主要是通过name生成对应的Drawable对象(空的)。

然后各个Drawable实例自己去解析里面对应的属性。


#### 加载png文件


-未完待续-
