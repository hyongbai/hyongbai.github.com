---
layout: post
title: "Fresco使用姿势及基本加载逻辑"
category: all-about-tech
tags: 
- Android
- Facebook
- Fresco
- Image
date: 2017-03-26 23:50:57+00:00
---

## 介绍

Fresco的出现，让我们可以更简单用来加载图片了。本文主要是自己读Fresco源码时的一点点记录。

Fresco github项目地址：<https://github.com/facebook/fresco/>

本文着重介绍的是Fresco的调用和加载的流程。各种缓存以及各种策略等未涉及。以后会慢慢整理。

## 基本使用

### 依赖

```groovy
compile 'com.facebook.fresco:fresco:1.2.0'
```

### 使用姿势

#### 布局文件

使用SimpleDraweeView即可

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="@dimen/activity_horizontal_margin">

    <com.facebook.drawee.view.SimpleDraweeView
        android:id="@id/image"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        app:placeholderImage="@drawable/ic_launcher"
        />
</LinearLayout>
```

#### Java代码

```java
public class FrescoFragment extends BNFragment {
    static {
        Fresco.initialize(App.sContext);
    }

    @BindView(R.id.image)
    SimpleDraweeView image;

    public FrescoFragment() {
        setLayoutId(R.layout.frag_fresco);
    }

    @Override
    public void onResume() {
        super.onResume();
        image.setImageURI(URL_IMG);//设定图片地址
        image.setAspectRatio(1 / 0.618f);//设定长宽比
//        GenericDraweeHierarchy hierarchy = image.getHierarchy();
//        hierarchy.setPlaceholderImage(R.drawable.ic_launcher);//修改占位图
//        hierarchy.setFailureImage(new ColorDrawable(Color.RED));//图片载入失败图
//        hierarchy.setProgressBarImage(new CircleProgressDrawable());//进度条
//        hierarchy.setRoundingParams(new RoundingParams().setCornersRadius(dp2px(2)).setBorder(Color.BLACK, DimenUtil.dp2px(2)));//设定圆角、边缘等
    }
}
```

想使用Fresco，首先需要初始化它。

默认的初始化方式很简单，使用Fresco.initialize(Context)即可(你也不用关心传入的context是Activity还是Application，它都会使用applicationContext)。初始化的时候会加入各种配置，包括但不限于网络请求模块、内存管理、磁盘管理、解码模块等。

想看更多的API文档的话，可以移步这里: <https://www.fresco-cn.org/>，还有英文文档: <http://frescolib.org/docs/index.html/>。

不着重介绍API的使用。

## 内部实现逻辑

#### 初始化

我们知道Fresco初始化的时候调用了其中的initialize函数。这里面会对Fresco启动所必须的东西进行处理。

下面是起核心代码:

```java
 public static void initialize(
      Context context,
      @Nullable ImagePipelineConfig imagePipelineConfig,
      @Nullable DraweeConfig draweeConfig) {
    //...省略
    context = context.getApplicationContext();
    if (imagePipelineConfig == null) {
      ImagePipelineFactory.initialize(context);
    } else {
      ImagePipelineFactory.initialize(imagePipelineConfig);
    }
    initializeDrawee(context, draweeConfig);
  }
  
  private static void initializeDrawee(
      Context context,
      @Nullable DraweeConfig draweeConfig) {
    sDraweeControllerBuilderSupplier = 
    	new PipelineDraweeControllerBuilderSupplier(context, draweeConfig);
    SimpleDraweeView.initialize(sDraweeControllerBuilderSupplier);
  }
```

其实它只初始化了两个东西，分别是`ImagePipelineFactory`和`PipelineDraweeControllerBuilderSupplier`

- **ImagePipelineFactory**

这里做了很多事，基本上所有的模块全部都是在这里进行初始化的。

- **PipelineDraweeControllerBuilderSupplier** 

PipelineDraweeControllerBuilderSupplier是Fresco里面最核心的一个组件。在这里主要做了两件事：生成ImagePipeline和PipelineDraweeControllerFactory。

下面是它的构造函数，关键的代码就在这里：

```java
 public PipelineDraweeControllerBuilderSupplier(
      Context context,
      ImagePipelineFactory imagePipelineFactory,
      Set<ControllerListener> boundControllerListeners,
      @Nullable DraweeConfig draweeConfig) {
    mContext = context;
    mImagePipeline = imagePipelineFactory.getImagePipeline();

    final AnimatedFactory animatedFactory = imagePipelineFactory.getAnimatedFactory();
    AnimatedDrawableFactory animatedDrawableFactory = null;
    if (animatedFactory != null) {
      animatedDrawableFactory = animatedFactory.getAnimatedDrawableFactory(context);
    }
    if (draweeConfig != null && draweeConfig.getPipelineDraweeControllerFactory() != null) {
      mPipelineDraweeControllerFactory = draweeConfig.getPipelineDraweeControllerFactory();
    } else {
      mPipelineDraweeControllerFactory = new PipelineDraweeControllerFactory();
    }
    mPipelineDraweeControllerFactory.init(
        context.getResources(),
        DeferredReleaser.getInstance(),
        animatedDrawableFactory,
        UiThreadImmediateExecutorService.getInstance(),
        mImagePipeline.getBitmapMemoryCache(),
        draweeConfig != null
            ? draweeConfig.getCustomDrawableFactories()
            : null,
        draweeConfig != null
            ? draweeConfig.getDebugOverlayEnabledSupplier()
            : null);
    mBoundControllerListeners = boundControllerListeners;
  }
```

构造函数一开始就通过Fresco启动时的ImagePipelineFactory生成了一个ImagePipeline。其实到此为止ImagePipelineFactory就结束了它短暂而辉煌的一生。

后部分主要是PipelineDraweeControllerFactory的初始化过程。

下面着重讲讲ImagePipeline的初始化过程以便后面试用。

- **ImagePipeline** 

上面初始化的ImagePipelineFactory的主要作用就是生成ImagePipeline。那么不妨先来看看ImagePipeline的构造函数，看看它里面到底有什么东西

```java
  public ImagePipeline(
      ProducerSequenceFactory producerSequenceFactory,
      Set<RequestListener> requestListeners,
      Supplier<Boolean> isPrefetchEnabledSupplier,
      MemoryCache<CacheKey, CloseableImage> bitmapMemoryCache,
      MemoryCache<CacheKey, PooledByteBuffer> encodedMemoryCache,
      BufferedDiskCache mainBufferedDiskCache,
      BufferedDiskCache smallImageBufferedDiskCache,
      CacheKeyFactory cacheKeyFactory,
      ThreadHandoffProducerQueue threadHandoffProducerQueue,
      Supplier<Boolean> suppressBitmapPrefetchingSupplier) {
    mIdCounter = new AtomicLong();
    mProducerSequenceFactory = producerSequenceFactory;
    mRequestListener = new ForwardingRequestListener(requestListeners);
    mIsPrefetchEnabledSupplier = isPrefetchEnabledSupplier;
    mBitmapMemoryCache = bitmapMemoryCache;
    mEncodedMemoryCache = encodedMemoryCache;
    mMainBufferedDiskCache = mainBufferedDiskCache;
    mSmallImageBufferedDiskCache = smallImageBufferedDiskCache;
    mCacheKeyFactory = cacheKeyFactory;
    mThreadHandoffProducerQueue = threadHandoffProducerQueue;
    mSuppressBitmapPrefetchingSupplier = suppressBitmapPrefetchingSupplier;
  }
```

```java
//ImagePipelineFactory.java

  public ImagePipeline getImagePipeline() {
    if (mImagePipeline == null) {
      mImagePipeline =
          new ImagePipeline(
              getProducerSequenceFactory(),
              mConfig.getRequestListeners(),
              mConfig.getIsPrefetchEnabledSupplier(),
              getBitmapMemoryCache(),
              getEncodedMemoryCache(),
              getMainBufferedDiskCache(),
              getSmallImageBufferedDiskCache(),
              mConfig.getCacheKeyFactory(),
              mThreadHandoffProducerQueue,
              Suppliers.of(false));
    }
    return mImagePipeline;
  }


  private ProducerSequenceFactory getProducerSequenceFactory() {
    if (mProducerSequenceFactory == null) {
      mProducerSequenceFactory =
          new ProducerSequenceFactory(
              getProducerFactory(),
              mConfig.getNetworkFetcher(),
              mConfig.isResizeAndRotateEnabledForNetwork(),
              mConfig.getExperiments().isWebpSupportEnabled(),
              mThreadHandoffProducerQueue,
              mConfig.getExperiments().getUseDownsamplingRatioForResizing());
    }
    return mProducerSequenceFactory;
  }


  private ProducerFactory getProducerFactory() {
    if (mProducerFactory == null) {
      mProducerFactory =
          new ProducerFactory(
              mConfig.getContext(),
              mConfig.getPoolFactory().getSmallByteArrayPool(),
              getImageDecoder(),
              mConfig.getProgressiveJpegConfig(),
              mConfig.isDownsampleEnabled(),
              mConfig.isResizeAndRotateEnabledForNetwork(),
              mConfig.getExperiments().isDecodeCancellationEnabled(),
              mConfig.getExecutorSupplier(),
              mConfig.getPoolFactory().getPooledByteBufferFactory(),
              getBitmapMemoryCache(),
              getEncodedMemoryCache(),
              getMainBufferedDiskCache(),
              getSmallImageBufferedDiskCache(),
              getMediaVariationsIndex(),
              mConfig.getExperiments().getMediaIdExtractor(),
              mConfig.getCacheKeyFactory(),
              getPlatformBitmapFactory(),
              mConfig.getExperiments().getForceSmallCacheThresholdBytes());
    }
    return mProducerFactory;
  }
```


#### 启动加载

从上面的Sample可以知道只要setImageURI就可以进行图片的加载了。那么我们来看看setImageURI做了什么:

```java
//SimpleDraweeView.java
public void setImageURI(Uri uri, @Nullable Object callerContext) {
	DraweeController controller = mSimpleDraweeControllerBuilder
	    .setCallerContext(callerContext)
	    .setUri(uri)
	    .setOldController(getController())
	    .build();
	setController(controller);
}

//DraweeView.java
public void setController(@Nullable DraweeController draweeController) {
	mDraweeHolder.setController(draweeController);
	super.setImageDrawable(mDraweeHolder.getTopLevelDrawable());
}
```

可以看到这里主要是拿到了SimpleDraweeView初始化的时候mSimpleDraweeControllerBuilder，用这个DraweeControllerBuilder来生成一个DraweeController。

然后将这个DraweeController放入DraweeHolder中去，下面是DraweeHolder的实现：

```java
//DraweeHolder.java
public void setController(@Nullable DraweeController draweeController) {
	boolean wasAttached = mIsControllerAttached;
	if (wasAttached) {
	  detachController();
	}

	// Clear the old controller
	if (isControllerValid()) {
	  mEventTracker.recordEvent(Event.ON_CLEAR_OLD_CONTROLLER);
	  mController.setHierarchy(null);
	}
	mController = draweeController;
	if (mController != null) {
	  mEventTracker.recordEvent(Event.ON_SET_CONTROLLER);
	  mController.setHierarchy(mHierarchy);
	} else {
	  mEventTracker.recordEvent(Event.ON_CLEAR_CONTROLLER);
	}

	if (wasAttached) {
	  attachController();
	}
}

private void attachController() {
	if (mIsControllerAttached) {
	  return;
	}
	mEventTracker.recordEvent(Event.ON_ATTACH_CONTROLLER);
	mIsControllerAttached = true;
	if (mController != null &&
	    mController.getHierarchy() != null) {
	  mController.onAttach();
	}
}
```
基本上这段代码就是在ViewHolder被attach之后，调用controller里面的onAttach。所有的逻辑都是在onAttach里面实现的。所以onAttach的逻辑还是非常关键的。

这里需要说的是，当setController之后，会先执行了一次detachController，跟onAttach相对，不难理解这里的主要作用是释放内存取消加载等等。

还有，如果wasAttached为FALSE的时候是不是就以为着不会加载了呢？这里我们插入一下加载时机的逻辑。其实这也不难理解，如果view没有被attach的话，完全没有必要去执行加载的逻辑。比如当我们初始化一端代码之后，如果这端代码相关的逻辑没有显示给用户，但也会去加载图片的话，很没有必要了。所以Facebook为什么弄了一个DraweeView的主要目的就是监听View的attach动作。看看是怎么实现的：

```java

  @Override
  protected void onAttachedToWindow() {
    super.onAttachedToWindow();
    onAttach();
  }

  @Override
  protected void onDetachedFromWindow() {
    super.onDetachedFromWindow();
    onDetach();
  }

  @Override
  public void onStartTemporaryDetach() {
    super.onStartTemporaryDetach();
    onDetach();
  }

  @Override
  public void onFinishTemporaryDetach() {
    super.onFinishTemporaryDetach();
    onAttach();
  }

  /** Called by the system to attach. Subclasses may override. */
  protected void onAttach() {
    doAttach();
  }

  /**  Called by the system to detach. Subclasses may override. */
  protected void onDetach() {
    doDetach();
  }

  /**
   * Does the actual work of attaching.
   *
   * Non-test subclasses should NOT override. Use onAttach for custom code.
   */
  protected void doAttach() {
    mDraweeHolder.onAttach();
  }

  /**
   * Does the actual work of detaching.
   *
   * Non-test subclasses should NOT override. Use onDetach for custom code.
   */
  protected void doDetach() {
    mDraweeHolder.onDetach();
  }

```

这段逻辑的主要作用就是观察view的attach/detach行为。其中`onAttachedToWindow`和`onDetachedFromWindow`分别是指view被加载到window里面和从window里面移除掉。`onStartTemporaryDetach`是指被parentRemove调的时候调用的。它的源码如下：

```java
    /**
     * This is called when a container is going to temporarily detach a child, with
     * {@link ViewGroup#detachViewFromParent(View) ViewGroup.detachViewFromParent}.
     * It will either be followed by {@link #onFinishTemporaryDetach()} or
     * {@link #onDetachedFromWindow()} when the container is done.
     */
    public void onStartTemporaryDetach() {
        removeUnsetPressCallback();
        mPrivateFlags |= PFLAG_CANCEL_NEXT_UP_EVENT;
    }
```

可以看到，onFinishTemporaryDetach或者onDetachedFromWindow之后会被调用的。

其实DraweeHolder还会观察view的可见性，如有变动则也会进行attach/detach相关的逻辑。它主要是实现了VisibilityCallback接口，然后注册给Hierarchy。如下：

```java
//DraweeHolder.java
  public void setHierarchy(DH hierarchy) {
    mEventTracker.recordEvent(Event.ON_SET_HIERARCHY);
    final boolean isControllerValid = isControllerValid();

    setVisibilityCallback(null);
    mHierarchy = Preconditions.checkNotNull(hierarchy);
    Drawable drawable = mHierarchy.getTopLevelDrawable();
    onVisibilityChange(drawable == null || drawable.isVisible());
    setVisibilityCallback(this);

    if (isControllerValid) {
      mController.setHierarchy(hierarchy);
    }
  }
  
  /**
   * Sets the visibility callback to the current top-level-drawable.
   */
  private void setVisibilityCallback(@Nullable VisibilityCallback visibilityCallback) {
    Drawable drawable = getTopLevelDrawable();
    if (drawable instanceof VisibilityAwareDrawable) {
      ((VisibilityAwareDrawable) drawable).setVisibilityCallback(visibilityCallback);
    }
  }
```

这里的逻辑就不讲了。具体的可以去`RootDrawable`里面看看相关的实现。

总之我们如果要设计图片缓存的话很重要的一点就是想方设法地找到最合适的加载时机和最准确的释放时机。

时机的问题讲完了。接下来讲讲那个Controller是哪里来的，这样我们才能够知道去哪里看onAttach和onDetach的逻辑。

#### DraweeController实例化

但是，我们DraweeHolder里面使用的是DraweeController这个接口。那么这个Controller是从哪里实现的呢？这一小节的目的就是讲讲这个DraweeController是如何实例化的。


下面看看PipelineDraweeController的构造函数:

```java
//PipelineDraweeController.java
  public PipelineDraweeController(
      Resources resources,
      DeferredReleaser deferredReleaser,
      AnimatedDrawableFactory animatedDrawableFactory,
      Executor uiThreadExecutor,
      MemoryCache<CacheKey, CloseableImage> memoryCache,
      Supplier<DataSource<CloseableReference<CloseableImage>>> dataSourceSupplier,
      String id,
      CacheKey cacheKey,
      Object callerContext,
      @Nullable ImmutableList<DrawableFactory> drawableFactories) {
    super(deferredReleaser, uiThreadExecutor, id, callerContext);
    mResources = resources;
    mAnimatedDrawableFactory = animatedDrawableFactory;
    mMemoryCache = memoryCache;
    mCacheKey = cacheKey;
    mDrawableFactories = drawableFactories;
    init(dataSourceSupplier);
  }

    public void initialize(
      Supplier<DataSource<CloseableReference<CloseableImage>>> dataSourceSupplier,
      String id,
      CacheKey cacheKey,
      Object callerContext) {
    super.initialize(id, callerContext);
    init(dataSourceSupplier);
    mCacheKey = cacheKey;
  }

  public void setDrawDebugOverlay(boolean drawDebugOverlay) {
    mDrawDebugOverlay = drawDebugOverlay;
  }

  private void init(Supplier<DataSource<CloseableReference<CloseableImage>>> dataSourceSupplier) {
    mDataSourceSupplier = dataSourceSupplier;

    maybeUpdateDebugOverlay(null);
  }
```
这里提供的很重要的两个是`memoryCache`和`dataSourceSupplier`。一个是用来提供内存缓存的，一个是用来进行图像加载的。这两个东西，在后面讲到onAttach的时候会提到。

在上面setImageURI的时候，我们知道它其实是通过mSimpleDraweeControllerBuilder直接生成的。而这个Builder是Fresco初始化时生成的最重要的`sDraweeControllerBuilderSupplier`得来的。

而sDraweeControllerBuilderSupplier其实是`PipelineDraweeControllerBuilderSupplier`的实例。具体可以看初始化部分。

下面是PipelineDraweeControllerBuilderSupplier实现Supplier的部分：

```java
  @Override
  public PipelineDraweeControllerBuilder get() {
    return new PipelineDraweeControllerBuilder(
        mContext,
        mPipelineDraweeControllerFactory,
        mImagePipeline,
        mBoundControllerListeners);
  }
```

这里其实返回的是PipelineDraweeControllerBuilder，而不是PipelineDraweeController本身。不过既然它是一个Builder，我们只要调用它的build()即可。在SimpleDraweeView的setImageURI也是这样处理的。所以再回头去看SimpleDraweeView里面setURI的时候，会往DraweeControllerBuilder里面设置URI，此时会在Builder中生成一个`ImageRequest`，这个ImageRequest在下面讲到DataSourceSupplier的时候就会用到了。

注意：仔细看PipelineDraweeControllerBuilder里面在这里就拿到了`mPipelineDraweeControllerFactory`和`ImagePipeline`。

下面看看build()的发生了什么。

但PipelineDraweeControllerBuilder本身并没有重写build()，所以我们去看它的父类AbstractDraweeController的实现：

```java
//AbstractDraweeController.java
  @Override
  public AbstractDraweeController build() {
    validate();

    // if only a low-res request is specified, treat it as a final request.
    if (mImageRequest == null && mMultiImageRequests == null && mLowResImageRequest != null) {
      mImageRequest = mLowResImageRequest;
      mLowResImageRequest = null;
    }
    return buildController();
  }

    protected AbstractDraweeController buildController() {
    AbstractDraweeController controller = obtainController();
    controller.setRetainImageOnFailure(getRetainImageOnFailure());
    controller.setContentDescription(getContentDescription());
    controller.setControllerViewportVisibilityListener(getControllerViewportVisibilityListener());
    maybeBuildAndSetRetryManager(controller);
    maybeAttachListeners(controller);
    return controller;
  }

//PipelineDraweeControllerBuilder.java
  @Override
  protected PipelineDraweeController obtainController() {
    DraweeController oldController = getOldController();
    PipelineDraweeController controller;
    if (oldController instanceof PipelineDraweeController) {
      controller = (PipelineDraweeController) oldController;
      controller.initialize(
          obtainDataSourceSupplier(),
          generateUniqueControllerId(),
          getCacheKey(),
          getCallerContext());
    } else {
      controller = mPipelineDraweeControllerFactory.newController(
          obtainDataSourceSupplier(),
          generateUniqueControllerId(),
          getCacheKey(),
          getCallerContext());
    }
    return controller;
  }
```

注意: 这里在创建新的PipelineDraweeController的时候就用到了PipelineDraweeControllerBuilderSupplier里面生成的`PipelineDraweeControllerFactory`。

`mPipelineDraweeControllerFactory.newController`其实只是讲初始化之时生成的各种东西带入进PipelineDraweeController而已。但是，除此之外PipelineDraweeControllerBuilder还传入了`dataSourceSupplier`和CacheKey等，后者是memoryCache的key。下面看看`DataSourceSupplier`是如何产生的。

#### DataSourceSupplier是谁从哪里来

PipelineDraweeController里面的DataSourceSupplier是用来连接下载、解码、存储最重要的一环。

上面我们提到DataSourceSupplier是来自AbstractDraweeControllerBuilder中的obtainDataSourceSupplier()。上源码：

```java
//AbstractDraweeControllerBuilder.java
  protected Supplier<DataSource<IMAGE>> obtainDataSourceSupplier() {
    if (mDataSourceSupplier != null) {
      return mDataSourceSupplier;
    }

    Supplier<DataSource<IMAGE>> supplier = null;

    // final image supplier;
    if (mImageRequest != null) {
      supplier = getDataSourceSupplierForRequest(mImageRequest);
    } else if (mMultiImageRequests != null) {
      supplier = getFirstAvailableDataSourceSupplier(mMultiImageRequests, mTryCacheOnlyFirst);
    }

    // increasing-quality supplier; highest-quality supplier goes first
    if (supplier != null && mLowResImageRequest != null) {
      List<Supplier<DataSource<IMAGE>>> suppliers = new ArrayList<>(2);
      suppliers.add(supplier);
      suppliers.add(getDataSourceSupplierForRequest(mLowResImageRequest));
      supplier = IncreasingQualityDataSourceSupplier.create(suppliers);
    }

    // no image requests; use null data source supplier
    if (supplier == null) {
      supplier = DataSources.getFailedDataSourceSupplier(NO_REQUEST_EXCEPTION);
    }

    return supplier;
  }
```

在obtainDataSourceSupplier()的时候会根据ImageRequest生成不同的Supplier，这里我们就以单张图为例说明生成DataSourceSupplier的过程。

```java
  /** Creates a data source supplier for the given image request. */
  protected Supplier<DataSource<IMAGE>> getDataSourceSupplierForRequest(REQUEST imageRequest) {
    return getDataSourceSupplierForRequest(imageRequest, CacheLevel.FULL_FETCH);
  }

  /** Creates a data source supplier for the given image request. */
  protected Supplier<DataSource<IMAGE>> getDataSourceSupplierForRequest(
      final REQUEST imageRequest,
      final CacheLevel cacheLevel) {
    final Object callerContext = getCallerContext();
    return new Supplier<DataSource<IMAGE>>() {
      @Override
      public DataSource<IMAGE> get() {
        return getDataSourceForRequest(imageRequest, callerContext, cacheLevel);
      }
      @Override
      public String toString() {
        return Objects.toStringHelper(this)
            .add("request", imageRequest.toString())
            .toString();
      }
    };
  }
```

其实就是实例化了一个Supplier而已。好了, 这下我们知道mDataSourceSupplier是如何获取到的了。后面我们会继续讲到它是如何实现DataSource的。

到此为止，我们知道了Controller是谁从哪里来的，那么接下来就回到上面讲到的DraweeController里面去，它在onAttach里面干了啥。

#### DraweeController如何onAttach

从上面我们知道了DraweeController其实就是`PipelineDraweeController`。所以接来下迫不及待马不停蹄地看看onAttach了。其实PipelineDraweeController继承自`AbstractDraweeController`，没有去重新onAttach的逻辑，所以我们还是转道去AbstractDraweeController里面看看。

```java
//AbstractDraweeController.java
  @Override
  public void onAttach() {
    if (FLog.isLoggable(FLog.VERBOSE)) {
      FLog.v(
          TAG,
          "controller %x %s: onAttach: %s",
          System.identityHashCode(this),
          mId,
          mIsRequestSubmitted ? "request already submitted" : "request needs submit");
    }
    mEventTracker.recordEvent(Event.ON_ATTACH_CONTROLLER);
    Preconditions.checkNotNull(mSettableDraweeHierarchy);
    mDeferredReleaser.cancelDeferredRelease(this);
    mIsAttached = true;
    if (!mIsRequestSubmitted) {
      submitRequest();
    }
  }

protected void submitRequest() {
	final T closeableImage = getCachedImage();
	if (closeableImage != null) {
	  mDataSource = null;
	  mIsRequestSubmitted = true;
	  mHasFetchFailed = false;
	  mEventTracker.recordEvent(Event.ON_SUBMIT_CACHE_HIT);
	  getControllerListener().onSubmit(mId, mCallerContext);
	  onNewResultInternal(mId, mDataSource, closeableImage, 1.0f, true, true);
	  return;
	}
	mEventTracker.recordEvent(Event.ON_DATASOURCE_SUBMIT);
	getControllerListener().onSubmit(mId, mCallerContext);
	mSettableDraweeHierarchy.setProgress(0, true);
	mIsRequestSubmitted = true;
	mHasFetchFailed = false;
	mDataSource = getDataSource();
	if (FLog.isLoggable(FLog.VERBOSE)) {
	  FLog.v(
	      TAG,
	      "controller %x %s: submitRequest: dataSource: %x",
	      System.identityHashCode(this),
	      mId,
	      System.identityHashCode(mDataSource));
	}
	final String id = mId;
	final boolean wasImmediate = mDataSource.hasResult();
	final DataSubscriber<T> dataSubscriber =
	    new BaseDataSubscriber<T>() {
	      @Override
	      public void onNewResultImpl(DataSource<T> dataSource) {
	        // isFinished must be obtained before image, otherwise we might set intermediate result
	        // as final image.
	        boolean isFinished = dataSource.isFinished();
	        float progress = dataSource.getProgress();
	        T image = dataSource.getResult();
	        if (mInitTrace != null && image instanceof CloseableReference) {
	          ((CloseableReference) image).setUnclosedRelevantTrance(mInitTrace);
	        }
	        if (image != null) {
	          onNewResultInternal(id, dataSource, image, progress, isFinished, wasImmediate);
	        } else if (isFinished) {
	          onFailureInternal(id, dataSource, new NullPointerException(), /* isFinished */ true);
	        }
	      }
	      @Override
	      public void onFailureImpl(DataSource<T> dataSource) {
	        onFailureInternal(id, dataSource, dataSource.getFailureCause(), /* isFinished */ true);
	      }
	      @Override
	      public void onProgressUpdate(DataSource<T> dataSource) {
	        boolean isFinished = dataSource.isFinished();
	        float progress = dataSource.getProgress();
	        onProgressUpdateInternal(id, dataSource, progress, isFinished);
	      }
	    };
	mDataSource.subscribe(dataSubscriber, mUiThreadImmediateExecutor);
}
```

- **读取内存缓存**

如果内存里面存在有效的缓存的话，那么就直接调用`onNewResultInternal`将其显示出来，这部分逻辑待会再说。

下面看下怎样获取内存缓存的：

```java
  @Override
  protected CloseableReference<CloseableImage> getCachedImage() {
    if (mMemoryCache == null || mCacheKey == null) {
      return null;
    }
    // We get the CacheKey
    CloseableReference<CloseableImage> closeableImage = mMemoryCache.get(mCacheKey);
    if (closeableImage != null && !closeableImage.get().getQualityInfo().isOfFullQuality()) {
      closeableImage.close();
      return null;
    }
    return closeableImage;
  }
```

这部分逻辑不多，就是用controller初始化时候传入的CacheKey去传入的MemoryCache读取缓存。

- **重新加载**

这里才是重点!

这里最重要的是DataSource了，因为通过`getDataSource`拿到DataSource，之后所有的操作都在这个DataSource里面进行的了。

getDataSource在PipelineDraweeController中实现，下面是如何获取到DataSource的方式，很简单，由于它是一个Supplier只要get()即可。

```java
//PipelineDraweeController.java
  @Override
  protected DataSource<CloseableReference<CloseableImage>> getDataSource() {
    if (FLog.isLoggable(FLog.VERBOSE)) {
      FLog.v(TAG, "controller %x: getDataSource", System.identityHashCode(this));
    }
    return mDataSourceSupplier.get();
  }
```

而这个`mDataSourceSupplier`就是上面在DraweeController初始化时拿到的DataSourceSupplier了。

拿到DataSource后调用subscribe注册一个观察者DataSubscriber，在观察者中实现更新进度、更新图片、以及处理错误。这样就“算是”成功加载图片了。

不过讲到这里其实还没有说DataSource是啥。

#### DataSource是谁从哪里来到哪里去

从上面实例化DataSourceSupplier我们可以知道，实现Supplier的时候其实是调用了`getDataSourceForRequest`而已。

它其实是AbstractDraweeControllerBuilder里面的一个抽象方法，目的是把处理的逻辑交给不同的继承者。

这个方法的实现在PipelineDraweeControllerBuilder中:

```java
//PipelineDraweeControllerBuilder.java
  @Override
  protected DataSource<CloseableReference<CloseableImage>> getDataSourceForRequest(
      ImageRequest imageRequest,
      Object callerContext,
      CacheLevel cacheLevel) {
    return mImagePipeline.fetchDecodedImage(
        imageRequest,
        callerContext,
        convertCacheLevelToRequestLevel(cacheLevel));
  }
```

看到了`mImagePipeline.fetchDecodedImage`没，看名字大概就能知道，这里其实就是去加载decode之后的图像了。所以关键的代码还是要继续查看ImagePipeline里面是如何实现的。

继续进ImagePipeline里面看看如何进行fetchDecodedImage的:

```java
//ImagePipeline.java
  public DataSource<CloseableReference<CloseableImage>> fetchDecodedImage(
      ImageRequest imageRequest,
      Object callerContext,
      ImageRequest.RequestLevel lowestPermittedRequestLevelOnSubmit) {
    try {
      Producer<CloseableReference<CloseableImage>> producerSequence =
          mProducerSequenceFactory.getDecodedImageProducerSequence(imageRequest);
      return submitFetchRequest(
          producerSequence,
          imageRequest,
          lowestPermittedRequestLevelOnSubmit,
          callerContext);
    } catch (Exception exception) {
      return DataSources.immediateFailedDataSource(exception);
    }
  }
  
  private <T> DataSource<CloseableReference<T>> submitFetchRequest(
      Producer<CloseableReference<T>> producerSequence,
      ImageRequest imageRequest,
      ImageRequest.RequestLevel lowestPermittedRequestLevelOnSubmit,
      Object callerContext) {
    final RequestListener requestListener = getRequestListenerForRequest(imageRequest);

    try {
      ImageRequest.RequestLevel lowestPermittedRequestLevel =
          ImageRequest.RequestLevel.getMax(
              imageRequest.getLowestPermittedRequestLevel(),
              lowestPermittedRequestLevelOnSubmit);
      SettableProducerContext settableProducerContext = new SettableProducerContext(
          imageRequest,
          generateUniqueFutureId(),
          requestListener,
          callerContext,
          lowestPermittedRequestLevel,
        /* isPrefetch */ false,
          imageRequest.getProgressiveRenderingEnabled() ||
              imageRequest.getMediaVariations() != null ||
              !UriUtil.isNetworkUri(imageRequest.getSourceUri()),
          imageRequest.getPriority());
      return CloseableProducerToDataSourceAdapter.create(
          producerSequence,
          settableProducerContext,
          requestListener);
    } catch (Exception exception) {
      return DataSources.immediateFailedDataSource(exception);
    }
  }
```

到这里就可以拿到了Datasource，它的实现是在CloseableProducerToDataSourceAdapter这里面。

在fetchDecodedImage里面最重要的一步就是通过mProducerSequenceFactory拿到producer，它是CloseableProducerToDataSourceAdapter里面最关键的成员之一。因为Producer负责了网络加载、decode、memoryCache、diskCache等等。

上面我们可以知道PipelineDraweeControllerBuilder里面的mImagePipeline其实是在PipelineDraweeControllerBuilder初始化的时候就从
`PipelineDraweeControllerBuilderSupplier`传入进来了。它就是PipelineDraweeControllerBuilderSupplier中的mImagePipeline。

所以接下来就要看CloseableProducerToDataSourceAdapter(DataSource)里面处理的加载逻辑就可以了。

### DataSource处理逻辑

CloseableProducerToDataSourceAdapter继承自`AbstractProducerToDataSourceAdapter`，我们主要看AbstractProducerToDataSourceAdapter的代码。

下面看看它的构造函数：

```java
//AbstractProducerToDataSourceAdapter.java
  protected AbstractProducerToDataSourceAdapter(
      Producer<T> producer,
      SettableProducerContext settableProducerContext,
      RequestListener requestListener) {
    mSettableProducerContext = settableProducerContext;
    mRequestListener = requestListener;
    mRequestListener.onRequestStart(
        settableProducerContext.getImageRequest(),
        mSettableProducerContext.getCallerContext(),
        mSettableProducerContext.getId(),
        mSettableProducerContext.isPrefetch());
    producer.produceResults(createConsumer(), settableProducerContext);
  }
```
一上来就调用Producer并且内部生成一个Consumer，用来监听Producer的处理结果。先忽略Producer的内部实现，因为非常之复杂。

```java
 private Consumer<T> createConsumer() {
    return new BaseConsumer<T>() {
      @Override
      protected void onNewResultImpl(@Nullable T newResult, boolean isLast) {
        AbstractProducerToDataSourceAdapter.this.onNewResultImpl(newResult, isLast);
      }

      @Override
      protected void onFailureImpl(Throwable throwable) {
        AbstractProducerToDataSourceAdapter.this.onFailureImpl(throwable);
      }

      @Override
      protected void onCancellationImpl() {
        AbstractProducerToDataSourceAdapter.this.onCancellationImpl();
      }

      @Override
      protected void onProgressUpdateImpl(float progress) {
        AbstractProducerToDataSourceAdapter.this.setProgress(progress);
      }
    };
  }
```

可以看到，主要是有4个状态，即成功/失败/取消/进度。分别调用对应的处理函数。下面我们就来看看`setProgress`是如何处理的。

```java
//AbstractDataSource.java中
  protected boolean setProgress(float progress) {
    boolean result = setProgressInternal(progress);
    if (result) {
      notifyProgressUpdate();
    }
    return result;
  }
  
  protected void notifyProgressUpdate() {
    for (Pair<DataSubscriber<T>, Executor> pair : mSubscribers) {
      final DataSubscriber<T> subscriber = pair.first;
      Executor executor = pair.second;
      executor.execute(
          new Runnable() {
            @Override
            public void run() {
              subscriber.onProgressUpdate(AbstractDataSource.this);
            }
          });
    }
  }
```

当有setProgress被调用的时候，会获取到所有的DataSubscriber。然后通过DataSubscriber订阅时传入的executor，将DataSource给分发出去。

顺便我们在看看DataSource.subscribe的时候做了什么：

```java
public void subscribe(final DataSubscriber<T> dataSubscriber, final Executor executor) {
    Preconditions.checkNotNull(dataSubscriber);
    Preconditions.checkNotNull(executor);
    boolean shouldNotify;

    synchronized(this) {
      if (mIsClosed) {
        return;
      }

      if (mDataSourceStatus == DataSourceStatus.IN_PROGRESS) {
        mSubscribers.add(Pair.create(dataSubscriber, executor));
      }

      shouldNotify = hasResult() || isFinished() || wasCancelled();
    }

    if (shouldNotify) {
      notifyDataSubscriber(dataSubscriber, executor, hasFailed(), wasCancelled());
    }
  }
```

其实就是将dataSubscriber和executor放入到mSubscribers中去，然后等等被notify。

好了，让我们回到AbstractDraweeController的submitRequest中去看DataSubscriber的实现：

```java
  protected void submitRequest() {
    //...省略
    mDataSource = getDataSource();
    //...省略
    final DataSubscriber<T> dataSubscriber =
        new BaseDataSubscriber<T>() {
          @Override
          public void onNewResultImpl(DataSource<T> dataSource) {
            // isFinished must be obtained before image, otherwise we might set intermediate result
            // as final image.
            boolean isFinished = dataSource.isFinished();
            float progress = dataSource.getProgress();
            T image = dataSource.getResult();
            if (mInitTrace != null && image instanceof CloseableReference) {
              ((CloseableReference) image).setUnclosedRelevantTrance(mInitTrace);
            }
            if (image != null) {
              onNewResultInternal(id, dataSource, image, progress, isFinished, wasImmediate);
            } else if (isFinished) {
              onFailureInternal(id, dataSource, new NullPointerException(), /* isFinished */ true);
            }
          }
          @Override
          public void onFailureImpl(DataSource<T> dataSource) {
            onFailureInternal(id, dataSource, dataSource.getFailureCause(), /* isFinished */ true);
          }
          @Override
          public void onProgressUpdate(DataSource<T> dataSource) {
            boolean isFinished = dataSource.isFinished();
            float progress = dataSource.getProgress();
            onProgressUpdateInternal(id, dataSource, progress, isFinished);
          }
        };
    mDataSource.subscribe(dataSubscriber, mUiThreadImmediateExecutor);
  }
```

当Consumer发出更新的时候`onNewResultInternal`会被调到，并且实在主线程被调到。为什么是主线程呢？因为注册的时候代入了mUiThreadImmediateExecutor，通过上面我们知道回调是会使用这个executor。

#### Producer的实现逻辑


在说之前我们先来看看`AbstractProducerToDataSourceAdapter`的构造函数中的Producer的dump信息。如下：

![fresco-producer-inheritance](/media/imgs/fresco-producer-inheritance.gif)

是不是很头晕，是的。不过每个Producer我都看了一边之后，整理了一下这些Producer具体都是干啥的：

- **BitmapMemoryCacheGetProducer** 就是BitmapMemoryCacheProducer，不同的地方在于wrapConsumer的时候返回的是原Consumer
- **ThreadHandoffProducer** 主要作用就是把下一个Producer放到ThreadHandoffProducerQueue里面的线程池里面去处理，也就是说用来切换线程。
- **BitmapMemoryCacheProducer** 主要作用是从内存(mBitmapMemoryCache)中加载。如果内存中存在则结束。这里会设定代理Consumer，现将解码的Image存入内存当中
- **BitmapMemoryCacheKeyMultiplexProducer** 将相同的请求合并成同一个请求的Producer
- **DecodeProducer** 主要的作用是用来decode，通过设定代理Consumer`NetworkImagesProgressiveDecoder`或者`LocalImagesProgressiveDecoder`先解码然后在分发出去。
- **ResizeAndRotateProducer** 主要作用是Resize和Rotate，通过设定代理Consumer`TransformingConsumer`做处理然后分发。
- **AddImageTransformMetaDataProducer** 主要作用就是为ResizeAndRotateProducer做好Size、Rotate相关的数据解析工作，通过代理Consumer`AddImageTransformMetaDataConsumer`处理的。所以解析图片大小还有EXIF等都是在这里操作的。
- **EncodedCacheKeyMultiplexProducer** 与BitmapMemoryCacheKeyMultiplexProducer类似，CacheKeyFactory都是同一个对象。区别在于这里的key使用的是`getEncodedCacheKey`,后者使用的是`getBitmapCacheKey`
- **EncodedMemoryCacheProducer** 与BitmapMemoryCacheProducer相对。Fresco做的二级内存缓存中的另一级(`mEncodedMemoryCache`)，如果有缓存的话则直接返回。这里会设定代理Consumer`EncodedMemoryCacheConsumer`, 在解码之前将数据存储在mEncodedMemoryCache中。
- **DiskCacheReadProducer** 如果DiskCache没有开启的话，直接进入下一个Producer。否则会处理通过SplitCachesByImageSizeDiskCachePolicy.createAndStartCacheReadTask生成一个Read DiskCache的Task。如果读取成功的话，直接截断所有的Producer，返回数据(可以查看SmallCacheIfRequestedDiskCachePolicy里面的实现，）。否则进入下一个Producer。
- **MediaVariationsFallbackProducer** 也是一个DiskCache Read相关的Producer，根据注释发现主要功能是从disk上面找到相似的图片。//TODO
- **DiskCacheWriteProducer** 主要功能是将下载好的图片写入到磁盘。设置一个代理Consumer`DiskCacheWriteConsumer`下载成功之后先将文件写入磁盘之后才会返回给原Consumer。
- **NetworkFetchProducer** 主要功能就是从网络下载图片。

通过这些Producer的层层调用，就可以实现传说中的两级内存缓存一级磁盘缓存。


ImagePipeline在fetchDecodedImage中调用`ProducerSequenceFactory.getDecodedImageProducerSequence(imageRequest)`获取Producer的流程这里就不说了，总之就是层层嵌套上图中的Producer列表。

## 总结

