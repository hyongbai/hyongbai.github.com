---
layout: post
title: "Resource通过resId获取Drawable的流程"
category: all-about-tech
tags: -[Android] -[Resource] -[AssetManager]
date: 2017-03-24 16:00:57+00:00
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

- string : 图片的完整路径，比如“res/drawable-xhdpi-v4/ic_launcher.png”(这里描述不准确，当type为String的时候string会String值。这里仅仅说type为Drawable的时候)
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

完整的列表如下：

```java
private Drawable inflateFromTag(@NonNull String name) {
    switch (name) {
        case "selector":
            return new StateListDrawable();
        case "animated-selector":
            return new AnimatedStateListDrawable();
        case "level-list":
            return new LevelListDrawable();
        case "layer-list":
            return new LayerDrawable();
        case "transition":
            return new TransitionDrawable();
        case "ripple":
            return new RippleDrawable();
        case "color":
            return new ColorDrawable();
        case "shape":
            return new GradientDrawable();
        case "vector":
            return new VectorDrawable();
        case "animated-vector":
            return new AnimatedVectorDrawable();
        case "scale":
            return new ScaleDrawable();
        case "clip":
            return new ClipDrawable();
        case "rotate":
            return new RotateDrawable();
        case "animated-rotate":
            return new AnimatedRotateDrawable();
        case "animation-list":
            return new AnimationDrawable();
        case "inset":
            return new InsetDrawable();
        case "bitmap":
            return new BitmapDrawable();
        case "nine-patch":
            return new NinePatchDrawable();
        default:
            return null;
    }
}
```

然后各个Drawable实例自己去解析里面对应的属性。

我们以BitmapDrawable为例：

```java
@Override
public void inflate(Resources r, XmlPullParser parser, AttributeSet attrs, Theme theme)
        throws XmlPullParserException, IOException {
    super.inflate(r, parser, attrs, theme);

    final TypedArray a = obtainAttributes(r, theme, attrs, R.styleable.BitmapDrawable);
    updateStateFromTypedArray(a);
    verifyRequiredAttributes(a);
    a.recycle();

    // Update local properties.
    updateLocalState(r);
}
```

其中updateStateFromTypedArray是核心的代码，这里完成了从xml文件中读取各种属性。其中最主要的是获取里面的src, 具体如下：

```java
private void updateStateFromTypedArray(TypedArray a) throws XmlPullParserException {
    //...省略
    final int srcResId = a.getResourceId(R.styleable.BitmapDrawable_src, 0);
    if (srcResId != 0) {
        final Bitmap bitmap = BitmapFactory.decodeResource(r, srcResId);
        if (bitmap == null) {
            throw new XmlPullParserException(a.getPositionDescription() +
                    ": <bitmap> requires a valid 'src' attribute");
        }

        state.mBitmap = bitmap;
    }
    //...省略
}
```

继续看，貌似又是拿到一个resId，然后继续用这个resId，去获取对应的bitmap。这里其实跟后面直接加载图片就会有交集了。

继续看:

```java
//BitmapFactory中
public static Bitmap decodeResource(Resources res, int id, Options opts) {
    Bitmap bm = null;
    InputStream is = null; 
    
    try {
        final TypedValue value = new TypedValue();
        is = res.openRawResource(id, value);

        bm = decodeResourceStream(res, value, is, null, opts);
    } catch (Exception e) {
        /*  do nothing.
            If the exception happened on open, bm will be null.
            If it happened on close, bm is still valid.
        */
    } finally {
        try {
            if (is != null) is.close();
        } catch (IOException e) {
            // Ignore
        }
    }

    if (bm == null && opts != null && opts.inBitmap != null) {
        throw new IllegalArgumentException("Problem decoding into existing bitmap");
    }

    return bm;
}

// Resources中

public InputStream openRawResource(@RawRes int id, TypedValue value)
        throws NotFoundException {
    return mResourcesImpl.openRawResource(id, value);
}

//ResoucesImpl中
InputStream openRawResource(@RawRes int id, TypedValue value) throws NotFoundException {
    getValue(id, value, true);
    try {
        return mAssets.openNonAsset(value.assetCookie, value.string.toString(),
                AssetManager.ACCESS_STREAMING);
    } catch (Exception e) {
        // Note: value.string might be null
        NotFoundException rnf = new NotFoundException("File "
                + (value.string == null ? "(null)" : value.string.toString())
                + " from drawable resource ID #0x" + Integer.toHexString(id));
        rnf.initCause(e);
        throw rnf;
    }
}
```

看到最后又通过AssetManager调用`InputStream openNonAsset(int cookie, String fileName, int accessMode)`返回一个InputStream，之后BitmapFactory读取这个InputStream并Decode成bitmap。

但是，openNonAsset的实现不打算继续将下去了。因为下面加载图片资源的时候也会用到。

#### 加载图片资源

上面如果缓存中以及preload中都没有发现缓存过的话，会跟上面加载BitmapDrawable一样，调用openNonAsset拿到一个InputStream实例。看下面的具体实现就可以知道，其实这是一个AssetInputStream的对象。

```java
public final InputStream openNonAsset(int cookie, String fileName, int accessMode)
    throws IOException {
    synchronized (this) {
        if (!mOpen) {
            throw new RuntimeException("Assetmanager has been closed");
        }
        long asset = openNonAssetNative(cookie, fileName, accessMode);
        if (asset != 0) {
            AssetInputStream res = new AssetInputStream(asset);
            incRefsLocked(res.hashCode());
            return res;
        }
    }
    throw new FileNotFoundException("Asset absolute file: " + fileName);
}
```

其中openNonAssetNative是一个native函数，底层处理完之后返回一个内存地址。然后将这个地址传递给。生成一个InputStream对象。

```java
public final class AssetInputStream extends InputStream {
    /**
     * @hide
     */
    public final int getAssetInt() {
        throw new UnsupportedOperationException();
    }
    /**
     * @hide
     */
    public final long getNativeAsset() {
        return mAsset;
    }
    private AssetInputStream(long asset)
    {
        mAsset = asset;
        mLength = getAssetLength(asset);
    }
    public final int read() throws IOException {
        return readAssetChar(mAsset);
    }
    public final boolean markSupported() {
        return true;
    }
    public final int available() throws IOException {
        long len = getAssetRemainingLength(mAsset);
        return len > Integer.MAX_VALUE ? Integer.MAX_VALUE : (int)len;
    }
    public final void close() throws IOException {
        synchronized (AssetManager.this) {
            if (mAsset != 0) {
                destroyAsset(mAsset);
                mAsset = 0;
                decRefsLocked(hashCode());
            }
        }
    }
    public final void mark(int readlimit) {
        mMarkPos = seekAsset(mAsset, 0, 0);
    }
    public final void reset() throws IOException {
        seekAsset(mAsset, mMarkPos, -1);
    }
    public final int read(byte[] b) throws IOException {
        return readAsset(mAsset, b, 0, b.length);
    }
    public final int read(byte[] b, int off, int len) throws IOException {
        return readAsset(mAsset, b, off, len);
    }
    public final long skip(long n) throws IOException {
        long pos = seekAsset(mAsset, 0, 0);
        if ((pos+n) > mLength) {
            n = mLength-pos;
        }
        if (n > 0) {
            seekAsset(mAsset, n, 0);
        }
        return n;
    }

    protected void finalize() throws Throwable
    {
        close();
    }

    private long mAsset;
    private long mLength;
    private long mMarkPos;
}
```

可以看到当需要读取数据的时候，通过这个内存地址调用底层数据返回即可。但是我拿到的其实是一个Drawable对象啊。继续看BitmapFactory的loadDrawableForCookie里面关于图片的加载。接下来会使用刚才拿到的InputStream调用Drawable里面的createFromResourceStream生成Drawable。

看源码:

```java
//Drawable中
public static Drawable createFromResourceStream(Resources res, TypedValue value,
        InputStream is, String srcName, BitmapFactory.Options opts) {
    if (is == null) {
        return null;
    }

    /*  ugh. The decodeStream contract is that we have already allocated
        the pad rect, but if the bitmap does not had a ninepatch chunk,
        then the pad will be ignored. If we could change this to lazily
        alloc/assign the rect, we could avoid the GC churn of making new
        Rects only to drop them on the floor.
    */
    Rect pad = new Rect();

    // Special stuff for compatibility mode: if the target density is not
    // the same as the display density, but the resource -is- the same as
    // the display density, then don't scale it down to the target density.
    // This allows us to load the system's density-correct resources into
    // an application in compatibility mode, without scaling those down
    // to the compatibility density only to have them scaled back up when
    // drawn to the screen.
    if (opts == null) opts = new BitmapFactory.Options();
    opts.inScreenDensity = Drawable.resolveDensity(res, 0);
    Bitmap  bm = BitmapFactory.decodeResourceStream(res, value, is, pad, opts);
    if (bm != null) {
        byte[] np = bm.getNinePatchChunk();
        if (np == null || !NinePatch.isNinePatchChunk(np)) {
            np = null;
            pad = null;
        }

        final Rect opticalInsets = new Rect();
        bm.getOpticalInsets(opticalInsets);
        return drawableFromBitmap(res, bm, np, pad, opticalInsets, srcName);
    }
    return null;
}

private static Drawable drawableFromBitmap(Resources res, Bitmap bm, byte[] np,
        Rect pad, Rect layoutBounds, String srcName) {

    if (np != null) {
        return new NinePatchDrawable(res, bm, np, pad, layoutBounds, srcName);
    }

    return new BitmapDrawable(res, bm);
}
```

这里其实就是通过将前面的InputStream解码生成bitmap对象。不过，这里会查看一下文件到底是不是`.9.png`文件，如果存在NinePatchChunk则生成NinePatchDrawable，否则(又)生成一个BitmapDrawable。

文件加载完了之后会放到前面所有的caches中，留着下次使用。

#### 预加载逻辑


这部分逻辑其实可以略过。应该加载的过程与上面是一模一样的。想看的可以移步到 [系统资源预加载的来龙去脉]({%  post_url 2017-03-25-resources-preloading %})

## 总结

其实Drawable资源的整个加载流程很清晰：读缓存，读预加载，是否是ColorDrawable，处理xml(读取文件流，解析，生成对应对象，读取属性，填充)，处理图片(通过底层读取文件流，解析Bitmap，生成Drawable)

注：其中底层的实现本文无涉及。
