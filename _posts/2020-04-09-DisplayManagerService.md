---
layout: post
title: "DisplayManagerService概述"
description: "DisplayManagerService概述"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-04-09 21:03:57+00:00
---

> 基于 android-8.1.0_r60
>
> 为求简洁，代码已删除大量细枝末节。

## getDisplay

### # 启动Activity

此时只是启动调用到attach和onCreate而已

```java
// frameworks/base/core/java/android/app/ActivityThread.java
private Activity performLaunchActivity(ActivityClientRecord r, Intent customIntent) {
    ...
    // 创建baseContext。这是一个ContextImpl的实例。
    ContextImpl appContext = createBaseContextForActivity(r);
    Activity activity = null;
    try {
        java.lang.ClassLoader cl = appContext.getClassLoader();
        // 实例化activity
        activity = mInstrumentation.newActivity( cl, component.getClassName(), r.intent);
    }
    try {
        ...
        // 将activity attach 到 baseContext中去。此时Activity的base context就是最上面创建的ContextImpl
        activity.attach(appContext, this, getInstrumentation(), r.token,
            r.ident, app, r.intent, r.activityInfo, title, r.parent,
            r.embeddedID, r.lastNonConfigurationInstances, config,
            r.referrer, r.voiceInteractor, window, r.configCallback);
        ...
    }
    ...
}
```

实例化一个ContextImpl对象，最后将其当作BaseContext将attach到activity中去。其中`createBaseContextForActivity`如下：

```java
// frameworks/base/core/java/android/app/ActivityThread.java
private ContextImpl createBaseContextForActivity(ActivityClientRecord r) {
    final int displayId;
    try {
        // ActivityManagerService返回的默认值为DEFAULT_DISPLAY
        displayId = ActivityManager.getService().getActivityDisplayId(r.token);
    } catch (RemoteException e) {
        throw e.rethrowFromSystemServer();
    }

    // 真正创建ContextImpl的地方。这里针对不同的类型，比如Activity/Application等等会有不同的实现方式。即不同类型则调用不同的接口。这里是Activity，因此使用`createActivityContext`。
    ContextImpl appContext = ContextImpl.createActivityContext(
            this, r.packageInfo, r.activityInfo, r.token, displayId, r.overrideConfig);

    final DisplayManagerGlobal dm = DisplayManagerGlobal.getInstance();
    // 从系统属性中获取"debug.second-display.pkg"的值，如果这个属性中的值跟当前一致。那么从DisplayManagerService中获取一个不为`DEFAULT_DISPLAY`的Display（即其他屏幕）展示当前app。
    // 这段逻辑可以忽略。可以看到这里会通过createDisplayContext创建带有Display的ContextImpl。实现应用在不用屏幕的切换。
    String pkgName = SystemProperties.get("debug.second-display.pkg");
    if (pkgName != null && !pkgName.isEmpty()
            && r.packageInfo.mPackageName.contains(pkgName)) {
        for (int id : dm.getDisplayIds()) {
            if (id != Display.DEFAULT_DISPLAY) {
                Display display = dm.getCompatibleDisplay(id, appContext.getResources());
                appContext = (ContextImpl) appContext.createDisplayContext(display);
                break;
            }
        }
    }
    return appContext;
}
```

`displayId` 为 `ActivityManagerService` 返回的默认值为 `DEFAULT_DISPLAY` 。

`ContextImpl`会针对不同的类型实例化 `ContextImpl`，比如 `Activity` / `Application` 等等会有不同的实现方式。即不同类型则调用不同的接口。这里是Activity，因此使用 `createActivityContext（）` 。

从系统属性中获取"debug.second-display.pkg"的值，如果这个属性中的值跟当前一致。那么从DisplayManagerService中获取一个不为`DEFAULT_DISPLAY`的Display（即其他屏幕）展示当前app。这段逻辑可以忽略。可以看到这里会通过`createDisplayContext`创建带有Display的ContextImpl。实现应用在不用屏幕的切换。

### # 创建 ContextImpl

```java
// frameworks/base/core/java/android/app/ContextImpl.java
static ContextImpl createActivityContext(ActivityThread mainThread,
        LoadedApk packageInfo, ActivityInfo activityInfo, IBinder activityToken, int displayId,
        Configuration overrideConfiguration) {
    if (packageInfo == null) throw new IllegalArgumentException("packageInfo");

    String[] splitDirs = packageInfo.getSplitResDirs();
    ClassLoader classLoader = packageInfo.getClassLoader();

    // SplitDependencies
    if (packageInfo.getApplicationInfo().requestsIsolatedSplitLoading()) {
        try {
            classLoader = packageInfo.getSplitClassLoader(activityInfo.splitName);
            splitDirs = packageInfo.getSplitPaths(activityInfo.splitName);
        }
    }

    // 直接创建一个ContextImpl对象。
    ContextImpl context = new ContextImpl(null, mainThread, packageInfo, activityInfo.splitName,
            activityToken, null, 0, classLoader);

    // Clamp display ID to DEFAULT_DISPLAY if it is INVALID_DISPLAY.
    displayId = (displayId != Display.INVALID_DISPLAY) ? displayId : Display.DEFAULT_DISPLAY;

    final CompatibilityInfo compatInfo = (displayId == Display.DEFAULT_DISPLAY)
            ? packageInfo.getCompatibilityInfo()
            : CompatibilityInfo.DEFAULT_COMPATIBILITY_INFO;

    final ResourcesManager resourcesManager = ResourcesManager.getInstance();

    // 很多插件化解决资源加载的问题都同这里类似。在这拿到通过上面拿到的资源文件地址。之后将资源文件通过addApkAssets添加到AssetManager的资源列表 `mApkAssets` 当中。具体可以去ResourceManager的`createAssetManager`以及AssetManager$Builder.build()查看详情。
    context.setResources(resourcesManager.createBaseActivityResources(activityToken,
            packageInfo.getResDir(),
            splitDirs,
            packageInfo.getOverlayDirs(),
            packageInfo.getApplicationInfo().sharedLibraryFiles,
            displayId,
            overrideConfiguration,
            compatInfo,
            classLoader));
    // 从ResourcesManager（client，最终调到的Server为DisplayManagerService）为当前Context分配id为displayId的Display实例。
    context.mDisplay = resourcesManager.getAdjustedDisplay(displayId,
            context.getResources());
    return context;
}
```

- 直接创建一个ContextImpl对象。
- 通过传入的displayId去ResourcesManager拿到DisplayManagerService的Display对象。(为什么把这个接口放在ResourcesManager中呢？)
- 并将获取到的Display对象让ContextImpl的mDisplay引用。

### # getAdjustedDisplay

ResourcesManager的getAdjustedDisplay其实只是一个门面：

```java
// ResourcesManager
public Display getAdjustedDisplay(final int displayId, Resources resources) {
    synchronized (this) {
        final DisplayManagerGlobal dm = DisplayManagerGlobal.getInstance();
        if (dm == null) {
            // may be null early in system startup
            return null;
        }
        return dm.getCompatibleDisplay(displayId, resources);
    }
}
```

这里获得当前进程的DisplayManagerService的client，即DisplayManagerGlobal。让它调用Remote接口拿到`DisplayInfo`。如下：

```java
// DisplayManagerGlobal.java
public Display getCompatibleDisplay(int displayId, DisplayAdjustments daj) {
    DisplayInfo displayInfo = getDisplayInfo(displayId);
    if (displayInfo == null) {
        return null;
    }
    return new Display(this, displayId, displayInfo, daj);
}

public DisplayInfo getDisplayInfo(int displayId) {
    try {
        synchronized (mLock) {
            DisplayInfo info;
            info = mDm.getDisplayInfo(displayId);
            if (info == null) {
                return null;
            }
            registerCallbackIfNeededLocked();
            return info;
        }
    } catch (RemoteException ex) {
        throw ex.rethrowFromSystemServer();
    }
}
```

可以看到`DisplayManagerService`返回的是一个`DisplayInfo`。然后由DisplayManagerGlobal实例化一个对应的Display对象返回给调用方。

下面来看看DisplayManagerService是如何响应的。DisplayManagerService对应的 `BinderService` 收到 `getDisplayInfo` 调用后，最后调用到 `getDisplayInfoInternal`，如下：

```java
// frameworks/base/services/core/java/com/android/server/display/DisplayManagerService.java
private DisplayInfo getDisplayInfoInternal(int displayId, int callingUid) {
    synchronized (mSyncRoot) {
        LogicalDisplay display = mLogicalDisplays.get(displayId);
        if (display != null) {
            DisplayInfo info = display.getDisplayInfoLocked();
            if (info.hasAccess(callingUid)
                    || isUidPresentOnDisplayInternal(callingUid, displayId)) {
                return info;
            }
        }
        return null;
    }
}
```

可以看到在`DisplayManagerService`内部保存了一个 `mLogicalDisplays`对象，用于映射displayId和LogicalDisplay对象。而 `LogicalDisplay` 则是所有类型的Display的统称。

Android里面目前支持的方式有：

- LocalDisplay：Android设备自带的显示器，由SurfaceFlinger管理。
- WifiDisplay：顾名思义通过Wifi(Miracast协议)投屏的显示器。
- OverlayDisplay：浮层显示器，以悬浮窗的心事模拟第二屏以供开发使用。类似与电脑，Android也支持多屏显示。
- VirtualDisplay：虚拟显示器。主要是Presentation在使用，比如Flutter的PlatformView就是通过这种方式支持在Flutter中嵌入原生View。

**OverlayDisplay**

```
System Settings > Developer options > Simulate secondary displays
```

[![aosp-displaymanagerservice-overlaydisplay-sample.png](https://j.mp/2JTGsKW)](https://j.mp/3c6HcIJ)

## LogicalDisplay的初始化过程

SystemServer启动时在`startBootstrapServices()`函数会调起DisplayManagerService。

### # DisplayManagerService启动

最终通过`SystemServiceManager.startService(DisplayManagerService.class)`实例化DisplayManagerService并调用其onStart():

```java
// frameworks/base/services/core/java/com/android/server/display/DisplayManagerService.java
@Override
public void onStart() {
	synchronized(mSyncRoot) {
	    // 加载Display缓存的配置信息。存储在文件`/data/system/display-manager-state.xml`中。
		mPersistentDataStore.loadIfNeeded();
		// 加载屏幕尺寸。如果本地没有缓存着有效值，则从stableDeviceDisplayWidth/Height读取屏幕配置信息。
		loadStableDisplayValuesLocked();
    }
    // 在DisplayThread(即`android.display`)的Looper对应的MessageQueue中发送一个`MSG_REGISTER_DEFAULT_DISPLAY_ADAPTERS`。用于异步获取所有的Display信息。Android中Display由DisplayAdapter提供。
    mHandler.sendEmptyMessage(MSG_REGISTER_DEFAULT_DISPLAY_ADAPTERS);
    // 向ServiceManager注册名为DISPLAY_SERVICE的Remote端。用于同子进程通信。
    publishBinderService(Context.DISPLAY_SERVICE, new BinderService(), true /*allowIsolated*/);
    // LocalService注册对应的Local实现。即不通过Binder，仅在SystemServer(system_process)进程内部同进程内使用。
    publishLocalService(DisplayManagerInternal.class, new LocalService());
    publishLocalService(DisplayTransformManager.class, new DisplayTransformManager());
}
```

可以看到在DisplayManagerService启动过程中：

-  加载Display缓存的配置信息。

存储在文件`/data/system/display-manager-state.xml`中。

以Nexus5X(8.1)为例：

```xml
<!--bullhead:/ # cat /data/system/display-manager-state.xml-->
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<display-manager-state>
    <remembered-wifi-displays />
    <display-states />
    <stable-device-values>
        <stable-display-width>1080</stable-display-width>
        <stable-display-height>1920</stable-display-height>
    </stable-device-values>
</display-manager-state>
```

可以看到stable-display-width和stable-display-height字段分别是1080p的宽高信息。

-  获取屏幕尺寸。

如果本地没有缓存着有效值，则从stableDeviceDisplayWidth/Height读取屏幕配置信息。

-  异步加载所有Display。

向DisplayThread(即`android.display`)的Looper发送一个`MSG_REGISTER_DEFAULT_DISPLAY_ADAPTERS`消息。

用于异步获取所有的Display信息。Android中Display由DisplayAdapter提供。

消息的处理函数为，registerDefaultDisplayAdapters()。

-  注册Service。

分别注册了跨进程和同进程通信的Server。

`publishBinderService`是向ServiceManager注册名为DISPLAY_SERVICE的Remote端。用于同子进程通信。

`LocalService`里面注册的是对应的Local实现。即不通过Binder，不跨进程，仅在SystemServer(system_process)进程内部同进程内使用。

### # DisplayManagerHandler

mHandler即是`WindowManagerService$DisplayManagerHandler`：

```java
// frameworks/base/services/core/java/com/android/server/display/DisplayManagerService.java
private final class DisplayManagerHandler extends Handler {
    public DisplayManagerHandler(Looper looper) {
        super(looper, null, true /*async*/);
    }

    @Override
    public void handleMessage(Message msg) {
        switch (msg.what) {
            // 初始化默认的Display
            case MSG_REGISTER_DEFAULT_DISPLAY_ADAPTERS:
                registerDefaultDisplayAdapters();
                break;

            // 注册额外的Display，比如WifiDisplay/OverLayDisplay
            case MSG_REGISTER_ADDITIONAL_DISPLAY_ADAPTERS:
                registerAdditionalDisplayAdapters();
                break;

            ...
        }
    }
}
```

这里其实有多种消息类型。

总之，与Display相关的异步信息都是在这里完成的。主要关注`MSG_REGISTER_DEFAULT_DISPLAY_ADAPTERS`：

```java
// frameworks/base/services/core/java/com/android/server/display/DisplayManagerService.java
private void registerDefaultDisplayAdapters() {
    synchronized (mSyncRoot) {
        // 注册LocalDisplay，即Android设备的DEFAULT_DISPLAY。
        registerDisplayAdapterLocked(new LocalDisplayAdapter(mSyncRoot, mContext, mHandler, mDisplayAdapterListener));

        // 注册VirtualDisplay适配器，用于创建VirtualDisplay。
        mVirtualDisplayAdapter = mInjector.getVirtualDisplayAdapter(mSyncRoot, mContext, mHandler, mDisplayAdapterListener);
        if (mVirtualDisplayAdapter != null) {
            registerDisplayAdapterLocked(mVirtualDisplayAdapter);
        }
    }
}

private void registerDisplayAdapterLocked(DisplayAdapter adapter) {
    mDisplayAdapters.add(adapter);
    adapter.registerLocked();
}
```

这里创建了两种类型的DisplayAdapter：

- 注册LocalDisplay，即Android设备的DEFAULT_DISPLAY。
- 注册VirtualDisplay适配器，用于创建VirtualDisplay。

registerDisplayAdapterLocked中将当前的adapter加入到mDisplayAdapters队列。同时调用DisplayAdapter本身的`registerLocked()`函数。用于其注册所提供的DisplayDevice(Logical Device)。其中VirtualDisplay用于子进程的需要实时创建不同的Display，因此registerLocked并不执行具体代码。

主要来看看`LocalDisplayAdapter`，上面的参数可以看到接收了mHandler和mDisplayAdapterListener对象。后者为DisplayManagerService的一个Calback，供LocalDisplayAdapter回调。

#### - LocalDisplayAdapter

来看看`LocalDisplayAdapter`的初始化过程以及`registerLocked()`逻辑。如下：

```java
// frameworks/base/services/core/java/com/android/server/display/LocalDisplayAdapter.java
private static final int[] BUILT_IN_DISPLAY_IDS_TO_SCAN = new int[] {
        SurfaceControl.BUILT_IN_DISPLAY_ID_MAIN,
        SurfaceControl.BUILT_IN_DISPLAY_ID_HDMI,
};

@Override
public void registerLocked() {
    super.registerLocked();

    // 监听热插拔消息，实时获取新的Display消息。
    mHotplugReceiver = new HotplugDisplayEventReceiver(getHandler().getLooper());

    // 遍历`BUILT_IN_DISPLAY_IDS_TO_SCAN`数组，封闭对每个Display Id进行初始化和注册。这里包含了MAIN和HDMI，上面热插拔也主要是监HDMI等接口。其中MAIN则是DEFAULT_DISPLAY。
    for (int builtInDisplayId : BUILT_IN_DISPLAY_IDS_TO_SCAN) {
        tryConnectDisplayLocked(builtInDisplayId);
    }
}

```

registerLocked中注册热插拔监听以及遍历BUILT_IN_DISPLAY_IDS_TO_SCAN以连接对应类型的display。

- HotplugDisplayEventReceiver

`HotplugDisplayEventReceiver`是监听显示器热插拔的接口：

```java
// frameworks/base/services/core/java/com/android/server/display/LocalDisplayAdapter.java
private final class HotplugDisplayEventReceiver extends DisplayEventReceiver {
    public HotplugDisplayEventReceiver(Looper looper) {
        // 注册自己。
        super(looper, VSYNC_SOURCE_APP);
    }

    @Override
    public void onHotplug(long timestampNanos, int builtInDisplayId, boolean connected) {
    // 接收回调。
        synchronized (getSyncRoot()) {
            if (connected) {
                // 新设备已连接
                tryConnectDisplayLocked(builtInDisplayId);
            } else {
                // 设备断开
                tryDisconnectDisplayLocked(builtInDisplayId);
            }
        }
    }
}
```

当新显示器连接时同初始化一样，调用`tryConnectDisplayLocked`初始化。

```java
// frameworks/base/core/java/android/view/DisplayEventReceiver.java
public DisplayEventReceiver(Looper looper, int vsyncSource) {
    ...
    mMessageQueue = looper.getQueue();
    // 在native注册当前的DisplayEventReceiver回调。
    mReceiverPtr = nativeInit(new WeakReference<DisplayEventReceiver>(this), mMessageQueue, vsyncSource);
    mCloseGuard.open("dispose");
}
```

DisplayEventReceiver在native层注册当前的DisplayEventReceiver回调。

- tryConnectDisplayLocked

```java
// frameworks/base/services/core/java/com/android/server/display/LocalDisplayAdapter.java
private void tryConnectDisplayLocked(int builtInDisplayId) {
    // 通过displayId到Native层查询对应的Remote。(SurfaceFlingger)
    IBinder displayToken = SurfaceControl.getBuiltInDisplay(builtInDisplayId);
    if (displayToken != null) {
        ...
        // 从缓存中读取对应id的LocalDisplayDevice对象。如无则直接实例化并缓存起来，以便下次使用。
        LocalDisplayDevice device = mDevices.get(builtInDisplayId);
        if (device == null) {
            device = new LocalDisplayDevice(displayToken, builtInDisplayId, configs, activeConfig, colorModes, activeColorMode);
            mDevices.put(builtInDisplayId, device);
            // 发送新设备创建的消息到DisplayManagerService。
            sendDisplayDeviceEventLocked(device, DISPLAY_DEVICE_EVENT_ADDED);
        } else if (device.updatePhysicalDisplayInfoLocked(configs, activeConfig, colorModes, activeColorMode)) {
            // 发送Display信息变动的消息到DisplayManagerService。
            sendDisplayDeviceEventLocked(device, DISPLAY_DEVICE_EVENT_CHANGED);
        }
    }
}

protected final void sendDisplayDeviceEventLocked(
        final DisplayDevice device, final int event) {
    // 发送消息在DisplayThread现在中运行。
    mHandler.post(new Runnable() {
        @Override
        public void run() {
            // 回调上面说的mDisplayAdapterListener的onDisplayDeviceEvent接口。
            mListener.onDisplayDeviceEvent(device, event);
        }
    });
}
```

可以看到Display也是通过binder同SurfaceFlingger(Server)通信的。本地会缓存每个displayid对应的`LocalDisplayDevice`，如果没有则直接创建新的DisplayDevice，并在DisplayThread线程回调DisplayManagerService内部mDisplayAdapterListener的`onDisplayDeviceEvent`函数的DISPLAY_DEVICE_EVENT_ADDED事件。

同时如果已有缓存，则发送DISPLAY_DEVICE_EVENT_CHANGED事件。

如果设备被移除，则移除缓存并发送DISPLAY_DEVICE_EVENT_REMOVED事件。

#### - handleDisplayDeviceAdded

DisplayAdapterListener这个回调的主要函数为`onDisplayDeviceEvent`，如下：

```java
// frameworks/base/services/core/java/com/android/server/display/DisplayManagerService.java
private final class DisplayAdapterListener implements DisplayAdapter.Listener {
    @Override
    public void onDisplayDeviceEvent(DisplayDevice device, int event) {
        switch (event) {
            case DisplayAdapter.DISPLAY_DEVICE_EVENT_ADDED:
                handleDisplayDeviceAdded(device);
                break;

            case DisplayAdapter.DISPLAY_DEVICE_EVENT_CHANGED:
                handleDisplayDeviceChanged(device);
                break;

            case DisplayAdapter.DISPLAY_DEVICE_EVENT_REMOVED:
                handleDisplayDeviceRemoved(device);
                break;
        }
    }

    @Override
    public void onTraversalRequested() {
        synchronized (mSyncRoot) {
            scheduleTraversalLocked(false);
        }
    }
}
```

上面提到的所有事件，在这里都有对应的处理。

其中 `DISPLAY_DEVICE_EVENT_ADDED` 消息对应的是`handleDisplayDeviceAdded`：

```java
// frameworks/base/services/core/java/com/android/server/display/DisplayManagerService.java
private void handleDisplayDeviceAdded(DisplayDevice device) {
    synchronized (mSyncRoot) {
        handleDisplayDeviceAddedLocked(device);
    }
}

private void handleDisplayDeviceAddedLocked(DisplayDevice device) {
    DisplayDeviceInfo info = device.getDisplayDeviceInfoLocked();
    if (mDisplayDevices.contains(device)) {
        return;
    }
    device.mDebugLastLoggedDeviceInfo = info;
    // 加入设备列表。
    mDisplayDevices.add(device);
    // 使用device创建一个LogicalDisplay对象，并加入mLogicalDisplays列表。
    LogicalDisplay display = addLogicalDisplayLocked(device);
    // 设置device的状态以及亮度等信息。
    Runnable work = updateDisplayStateLocked(device);
    if (work != null) {
        work.run();
    }
    scheduleTraversalLocked(false);
}
```

- 加入设备列表mDisplayDevices。
- 使用device创建一个LogicalDisplay对象，并加入mLogicalDisplays列表。
- 设置device的状态以及亮度等信息。

到这里DisplayManagerService初始化过程就结束了。

## 显示(addToDisplay)

注意，WindowManagerService虽然是在SystemServer中启动的。当时其实例化过程是在DisplayThread中实现的。

```java
// frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java
private static WindowManagerService sInstance;
static WindowManagerService getInstance() {
    return sInstance;
}

public static WindowManagerService main(final Context context, final InputManagerService im,
        final boolean haveInputMethods, final boolean showBootMsgs, final boolean onlyCore,
        WindowManagerPolicy policy) {
    DisplayThread.getHandler().runWithScissors(() ->
            sInstance = new WindowManagerService(context, im, haveInputMethods, showBootMsgs,
                    onlyCore, policy), 0);
    return sInstance;
}
```

可以看到`WindowManagerService`在Remote端是一个单例，其实例化运行在`DisplayThread`的Looper中。其中`runWithScissors`是Handler的一个异步转同步的方法，同步等待异步操作的结果，即当前block当前线程等待工作线程释放锁。

[>>> Handler#runWithScissors(final Runnable r, long timeout) 函数源码 <<<](https://j.mp/2XAurCh)

### # WindowManager

```java
// frameworks/base/core/java/android/view/WindowManagerImpl.java
@Override
public void addView(@NonNull View view, @NonNull ViewGroup.LayoutParams params) {
    applyDefaultToken(params);
    mGlobal.addView(view, params, mContext.getDisplay(), mParentWindow);
}
```

可以看到在addView的时候，会将Context中的Display取出。这里的mContext，就是ContextImpl类本身。

以Activity为例，这个ContextImpl是通过上面的`createActivityContext`创建而来。Display则为DEFAULT_DISPLAY。

以Presentation为例，那么ContextImpl就是通过`createDisplayContext`创建。这个Display则是构建VirtualDisplay时DisplayManagerService创建的虚拟Display。

不论是Activity或者是Presentation还是Dialog，如果需要显示则一定得调用WindowManager的addView函数（如上所示）。

接着会走到`WindowManagerGlobal`中：

```java
// frameworks/base/core/java/android/view/WindowManagerGlobal.java
public void addView(View view, ViewGroup.LayoutParams params,
        Display display, Window parentWindow) {
    ...
    ViewRootImpl root;
    ...
    root = new ViewRootImpl(view.getContext(), display);
    view.setLayoutParams(wparams);
    mViews.add(view);
    mRoots.add(root);
    mParams.add(wparams);
    try {
        root.setView(view, wparams, panelParentView);
    }
    ...
}
}
```

这里实例化ViewRootImpl类，并执行其setView。用于将ViewRootImpl初始化。包括但不限于：持有DecorView，同windowManager交互，想InputManagerService注册InputChannel用于接收输入事件，想Choreographer注册Traversal消息等等。

下面仅看同WindowManagerService是如何交互的：

```java
// ViewRootImpl.java
public void setView(View view, WindowManager.LayoutParams attrs, View panelParentView) {
    ...
    try {
        // 这里的mDisplay来自ContextImpl的getDisplay
        res = mWindowSession.addToDisplay(mWindow, mSeq, mWindowAttributes,
                getHostVisibility(), mDisplay.getDisplayId(), mWinFrame,
                mAttachInfo.mContentInsets, mAttachInfo.mStableInsets,
                mAttachInfo.mOutsets, mAttachInfo.mDisplayCutout, mInputChannel);
    }
    ...
}
```

其中mWindow则是一个AIDL接口(即client)，用于接收来自WindowState的消息。而`mDisplay.getDisplayId`则是创建DisplayContent等过程。

最终Session的 [`addToDisplay()`](https://j.mp/34tmjos) 函数，直接调用了 `WindowManagerService` 的 `addWindow`，如下：

```java
// frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java
public int addWindow(Session session, IWindow client, int seq,
        LayoutParams attrs, int viewVisibility, int displayId, Rect outFrame,
        Rect outContentInsets, Rect outStableInsets, Rect outOutsets,
        DisplayCutout.ParcelableWrapper outDisplayCutout, InputChannel outInputChannel) {
    ...
    synchronized(mWindowMap) {
        ...
        // 创建DisplayContent，持有指定的Display对象。
        final DisplayContent displayContent = getDisplayContentOrCreate(displayId);
        ...
        WindowToken token = displayContent.getWindowToken( hasParent ? parentWindow.mAttrs.token : attrs.token);
        ...
        if (token == null) {
            ...
            return WindowManagerGlobal.ADD_BAD_APP_TOKEN;
        }
        ...
        // 每个ViewRootImpl都对应一个WindowState对象。用于记录当前ViewRootImpl的一切信息。比如输入等等。
        final WindowState win = new WindowState(this, session, client, token, parentWindow,
                appOp[0], seq, attrs, viewVisibility, session.mUid,
                session.mCanAddInternalSystemWindow);
        ...
        // 在InputManagerService注册InputChannel，用于当前接收输入事件。
        final boolean openInputChannels = (outInputChannel != null && (attrs.inputFeatures & INPUT_FEATURE_NO_INPUT_CHANNEL) == 0);
        if  (openInputChannels) {
            win.openInputChannel(outInputChannel);
        }
        ...
        // 缓存对象。
        mWindowMap.put(client.asBinder(), win);
        ...
    }
    ...
}
```

这里主要是创建了一个`WindowState`对象，用于同Client绑定起来。当Client拿到VSYNC后，会通过Session将Client的Surface同WindowManagerService缓存的WindowState中的Display绑定起来，实现绘制到Surface最终显示到Display的过程。

注意：DisplayContent只于Display(Id)有关，也就是说很有可能是所有的Client(ViewRootImpl的mDisplay)共用同一个DisplayContent对象。

### # Surface同Display绑定

Surface同Display绑定如下：

`performTraversals()` 在 `mFirst || windowShouldResize` 时会 `relayoutWindow` ，此时WindowManagerService会拿到缓存的WindowState并将ViewRootImpl中的mSurface对象指定一个Native的SurfaceObject。从个实现Surface对象和Display的绑定。

[WindowManagerService.relayoutWindow()](https://j.mp/2VlolDb)

最后Surface的readFromParcel被回调，完成当前这个Surface对象同Native的Surface对象的映射。

简单来说，Surface同Display的关系为：

WindowManager在relayoutWindow时将Client(ViewRootImpl)的Surface同Display映射起来。

在Client绘制的时候，ViewRootImpl将Surface同Canvas绑定起来。从而实现将Canvas的内容绘制到Display。

如果是软件绘制，那么Surface.lockCanvas创建的SkiaBitmap本身就来自同Surface绑定。

如果是硬件加速，那么这个Surface对传递给ThreadedRenderer的`updateSurface`或者`initialize`函数。将`RenderProxy`同`Surface`绑定。

注意：实际过程要比这个复杂地多，这里并没有深入研究具体实现过程，**++存疑++**。

## Resized

在分析performTraversal的时候，可以发现DecorView在绘制之前会经历至少三次的Measure。

其中前两次是mFirst，关键的最后一次主要是有WindowManaged的resized事件触发。当ViewRootImpl收到`resized`事件后，此时可以拿到一系列数据。比如，frame以及displayId(如无变化同ContextImpl的display一致)等等。

Debug发现其调用栈如下：

[![aosp-SystemServer-handleResizingWindows-demo.png](https://j.mp/34D3OOD)](https://j.mp/2V4Gvdq)

可以看到源头是Session的relayout消息，即上面提到的ViewRootImpl的relayoutWindow。不同的是，这里是Server端(即SystemSever/system_process进程)。

```java
// frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java
public int relayoutWindow(Session session, IWindow client, int seq,
        WindowManager.LayoutParams attrs, int requestedWidth,
        int requestedHeight, int viewVisibility, int flags,
        Rect outFrame, Rect outOverscanInsets, Rect outContentInsets,
        Rect outVisibleInsets, Rect outStableInsets, Rect outOutsets, Rect outBackdropFrame,
        MergedConfiguration mergedConfiguration, Surface outSurface) {
    ...
    long origId = Binder.clearCallingIdentity();
    final int displayId;
    synchronized(mWindowMap) {
        WindowState win = windowForClientLocked(session, client, false);
        if (win == null) {
            return 0;
        }
        displayId = win.getDisplayId();
        WindowStateAnimator winAnimator = win.mWinAnimator;
        ...
        // We should only relayout if the view is visible, it is a starting window, or the
        // associated appToken is not hidden.
        final boolean shouldRelayout = viewVisibility == View.VISIBLE &&
            (win.mAppToken == null || win.mAttrs.type == TYPE_APPLICATION_STARTING
                || !win.mAppToken.isClientHidden());

        if (shouldRelayout) {
            ...
            try {
            // 设定outSurface(即ViewRootImpl的mSurface)的nativeObject
                result = createSurfaceControl(outSurface, result, win, winAnimator);
            }
            ...
        }
        ...
        // 这里会通知所有需要resize的Client。向Client分发resized消息。
        mWindowPlacerLocked.performSurfacePlacement(true /* force */);
        ...
    }
    ...
    return result;
}
```

- 设定outSurface(即ViewRootImpl的mSurface)的mNativeObject(即底层对应的Surface对象)
- 通知所有需要resize的Client，向Client分发resized消息。

下面是分发过程：

```java
// frameworks/services/core/java/com/android/server/wm/WindowSurfacePlacer.java
final void performSurfacePlacement(boolean force) {
    if (mDeferDepth > 0 && !force) {
        return;
    }
    int loopCount = 6;
    do {
        mTraversalScheduled = false;
        performSurfacePlacementLoop();
        mService.mAnimationHandler.removeCallbacks(mPerformSurfacePlacement);
        loopCount--;
    } while (mTraversalScheduled && loopCount > 0);
    mService.mRoot.mWallpaperActionPending = false;
}

private void performSurfacePlacementLoop() {
    ...
    try {
        mService.mRoot.performSurfacePlacement(recoveringMemory);
        ...
    }
    ...
}
```


```java
// frameworks/services/core/java/com/android/server/wm/RootWindowContainer.java
void performSurfacePlacement(boolean recoveringMemory) {
    ...
    try {
        // 遍历将所有适合的WindowState加入到mResizingWindows列表中去。
        applySurfaceChangesTransaction(recoveringMemory, defaultDw, defaultDh);
    } finally {
        mService.closeSurfaceTransaction();
    }
    ...
    // 遍历mResizingWindows列表中的WindowState，调用其reportResized函数。
    final ArraySet<DisplayContent> touchExcludeRegionUpdateDisplays = handleResizingWindows();
    ...
}
```

`applySurfaceChangesTransaction`过程涉及到遍历如下WindowList的过程：

[![aosp-DisplayContent-forAllWindows-mChildren-1.png](https://j.mp/2wEYBcG)](https://j.mp/2VpetZ5)


[![aosp-DisplayContent-forAllWindows-mChildren-till-demo-lldb.png](https://j.mp/3b5ZutL)](https://j.mp/2RvnQFq)

```java
// frameworks/services/core/java/com/android/server/wm/RootWindowContainer.java
private ArraySet<DisplayContent> handleResizingWindows() {
    ArraySet<DisplayContent> touchExcludeRegionUpdateSet = null;
    // mService为WindowManagerService
    for (int i = mService.mResizingWindows.size() - 1; i >= 0; i--) {
        WindowState win = mService.mResizingWindows.get(i);
        ...
        // 调用WindowState的reportResized函数。
        win.reportResized();
        ...
    }
    return touchExcludeRegionUpdateSet;
}
```

### # WindowState

上面可知WindowState其实是每个ViewRootImpl对应的一个Server端的对象，用于记录当前ViewRootImpl对应的`mDisplay`、`mWindow`等等信息。

注意：WindowState的数量与进程数量没有关系。只要实例化ViewRootImpl就会在绘制的时候在WindowManagerService创建一个对应的WindowState。比如一个Activity弹出一个Dialog，那么在WindowManagerService中至少有两个WindowState。

其中，ViewRootImpl在WindowManagerGlobal的 [`addView()方法`](https://j.mp/3b4MMvp) 创建。

```java
// frameworks/services/core/java/com/android/server/wm/WindowState.java
void reportResized() {
    try {
        final MergedConfiguration mergedConfiguration =
                new MergedConfiguration(mService.mRoot.getConfiguration(),
                getMergedOverrideConfiguration());
        setLastReportedMergedConfiguration(mergedConfiguration);
        final Rect frame = mFrame;
        final Rect overscanInsets = mLastOverscanInsets;
        final Rect contentInsets = mLastContentInsets;
        final Rect visibleInsets = mLastVisibleInsets;
        final Rect stableInsets = mLastStableInsets;
        final Rect outsets = mLastOutsets;
        final boolean reportDraw = mWinAnimator.mDrawState == DRAW_PENDING;
        final boolean reportOrientation = mReportOrientationChanged;
        final int displayId = getDisplayId();
        final DisplayCutout displayCutout = mDisplayCutout.getDisplayCutout();
        if (mAttrs.type != WindowManager.LayoutParams.TYPE_APPLICATION_STARTING
                && mClient instanceof IWindow.Stub) {
            // To prevent deadlock simulate one-way call if win.mClient is a local object.
            mService.mH.post(new Runnable() {
                @Override
                public void run() {
                    try {
                        dispatchResized(frame, overscanInsets, contentInsets, visibleInsets,
                                stableInsets, outsets, reportDraw, mergedConfiguration,
                                reportOrientation, displayId, displayCutout);
                    }
                }
            });
        } else {
            dispatchResized(frame, overscanInsets, contentInsets, visibleInsets, stableInsets,
                    outsets, reportDraw, mergedConfiguration, reportOrientation, displayId,
                    displayCutout);
        }
        if (mService.mAccessibilityController != null && getDisplayId() == DEFAULT_DISPLAY) {
            mService.mAccessibilityController.onSomeWindowResizedOrMovedLocked();
        }

        mOverscanInsetsChanged = false;
        mContentInsetsChanged = false;
        mVisibleInsetsChanged = false;
        mStableInsetsChanged = false;
        mOutsetsChanged = false;
        mFrameSizeChanged = false;
        mDisplayCutoutChanged = false;
        mWinAnimator.mSurfaceResized = false;
        mReportOrientationChanged = false;
    }
    ...
}
```

这里获取来一系列WindowState中的参数，通过dispatchResized将其发送到Client。

```java
// frameworks/services/core/java/com/android/server/wm/WindowState.java
private void dispatchResized(Rect frame, Rect overscanInsets, Rect contentInsets,
        Rect visibleInsets, Rect stableInsets, Rect outsets, boolean reportDraw,
        MergedConfiguration mergedConfiguration, boolean reportOrientation, int displayId,
        DisplayCutout displayCutout)
        throws RemoteException {
    final boolean forceRelayout = isDragResizeChanged() || reportOrientation;
    // 调用当前WindowState的mClient。通过上面的addToDisplay可知。这个mClient其实就是ViewRootImpl的mWindow。
    mClient.resized(frame, overscanInsets, contentInsets, visibleInsets, stableInsets, outsets,
            reportDraw, mergedConfiguration, getBackdropFrame(frame), forceRelayout,
            mPolicy.isNavBarForcedShownLw(this), displayId,
            new DisplayCutout.ParcelableWrapper(displayCutout));
    mDragResizingChangeReported = true;
}
```

调用当前WindowState的mClient。通过上面的addToDisplay可知。这个mClient其实就是ViewRootImpl的mWindow。

此时`ViewRootImpl$W` (`extends IWindow.Stub`) 的 `resized()` 函数将被回调。

### # ViewRootImpl

#### - IWindow.Stub

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
static class W extends IWindow.Stub {
    private final WeakReference<ViewRootImpl> mViewAncestor;
    private final IWindowSession mWindowSession;
...
    @Override
    public void resized(Rect frame, Rect overscanInsets, Rect contentInsets,
            Rect visibleInsets, Rect stableInsets, Rect outsets, boolean reportDraw,
            MergedConfiguration mergedConfiguration, Rect backDropFrame, boolean forceLayout,
            boolean alwaysConsumeNavBar, int displayId,
            DisplayCutout.ParcelableWrapper displayCutout) {
        final ViewRootImpl viewAncestor = mViewAncestor.get();
        if (viewAncestor != null) {
            viewAncestor.dispatchResized(frame, overscanInsets, contentInsets,
                    visibleInsets, stableInsets, outsets, reportDraw, mergedConfiguration,
                    backDropFrame, forceLayout, alwaysConsumeNavBar, displayId, displayCutout);
        }
    }
...
}
```

调用了ViewRootImpl的`dispatchResized`函数：

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
    private void dispatchResized(Rect frame, Rect overscanInsets, Rect contentInsets,
            Rect visibleInsets, Rect stableInsets, Rect outsets, boolean reportDraw,
            MergedConfiguration mergedConfiguration, Rect backDropFrame, boolean forceLayout,
            boolean alwaysConsumeNavBar, int displayId,
            DisplayCutout.ParcelableWrapper displayCutout) {
        if (mDragResizing && mUseMTRenderer) {
            boolean fullscreen = frame.equals(backDropFrame);
            synchronized (mWindowCallbacks) {
                for (int i = mWindowCallbacks.size() - 1; i >= 0; i--) {
                   mWindowCallbacks.get(i).onWindowSizeIsChanging(backDropFrame, fullscreen,
                            visibleInsets, stableInsets);
                }
            }
        }
        Message msg = mHandler.obtainMessage(reportDraw ? MSG_RESIZED_REPORT : MSG_RESIZED);
        if (mTranslator != null) {
            mTranslator.translateRectInScreenToAppWindow(frame);
            mTranslator.translateRectInScreenToAppWindow(overscanInsets);
            mTranslator.translateRectInScreenToAppWindow(contentInsets);
            mTranslator.translateRectInScreenToAppWindow(visibleInsets);
        }
        SomeArgs args = SomeArgs.obtain();
        final boolean sameProcessCall = (Binder.getCallingPid() == android.os.Process.myPid());
        args.arg1 = sameProcessCall ? new Rect(frame) : frame;
        args.arg2 = sameProcessCall ? new Rect(contentInsets) : contentInsets;
        args.arg3 = sameProcessCall ? new Rect(visibleInsets) : visibleInsets;
        args.arg4 = sameProcessCall && mergedConfiguration != null
                ? new MergedConfiguration(mergedConfiguration) : mergedConfiguration;
        args.arg5 = sameProcessCall ? new Rect(overscanInsets) : overscanInsets;
        args.arg6 = sameProcessCall ? new Rect(stableInsets) : stableInsets;
        args.arg7 = sameProcessCall ? new Rect(outsets) : outsets;
        args.arg8 = sameProcessCall ? new Rect(backDropFrame) : backDropFrame;
        args.arg9 = displayCutout.get(); // DisplayCutout is immutable.
        args.argi1 = forceLayout ? 1 : 0;
        args.argi2 = alwaysConsumeNavBar ? 1 : 0;
        args.argi3 = displayId;
        msg.obj = args;
        mHandler.sendMessage(msg);
    }
```

第一次允许，reportDraw为true，因此发送的是`MSG_RESIZED_REPORT`消息：

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
final class ViewRootHandler extends Handler {
    ...
    @Override
    public void handleMessage(Message msg) {
        switch (msg.what) {
        case MSG_RESIZED_REPORT:
            if (mAdded) {
                SomeArgs args = (SomeArgs) msg.obj;

                final int displayId = args.argi3;
                MergedConfiguration mergedConfiguration = (MergedConfiguration) args.arg4;
                // display通常情况下不会变化。
                final boolean displayChanged = mDisplay.getDisplayId() != displayId;

                if (!mLastReportedMergedConfiguration.equals(mergedConfiguration)) {
                    // If configuration changed - notify about that and, maybe, about move to
                    // display.
                    performConfigurationChange(mergedConfiguration, false /* force */,
                            displayChanged ? displayId : INVALID_DISPLAY /* same display */);
                } else if (displayChanged) {
                    // Moved to display without config change - report last applied one.
                    onMovedToDisplay(displayId, mLastConfigurationFromResources);
                }

                final boolean framesChanged = !mWinFrame.equals(args.arg1)
                        || !mPendingOverscanInsets.equals(args.arg5)
                        || !mPendingContentInsets.equals(args.arg2)
                        || !mPendingStableInsets.equals(args.arg6)
                        || !mPendingVisibleInsets.equals(args.arg3)
                        || !mPendingOutsets.equals(args.arg7);

                mWinFrame.set((Rect) args.arg1);
                mPendingOverscanInsets.set((Rect) args.arg5);
                mPendingContentInsets.set((Rect) args.arg2);
                mPendingStableInsets.set((Rect) args.arg6);
                mPendingVisibleInsets.set((Rect) args.arg3);
                mPendingOutsets.set((Rect) args.arg7);
                mPendingBackDropFrame.set((Rect) args.arg8);
                mForceNextWindowRelayout = args.argi1 != 0;
                mPendingAlwaysConsumeNavBar = args.argi2 != 0;

                args.recycle();

                if (msg.what == MSG_RESIZED_REPORT) {
                    reportNextDraw(); // 标记mReportNextDraw为true
                }

                if (mView != null && framesChanged) {
                    // 所有View的mPrivateFlags标记上PFLAG_FORCE_LAYOUT和PFLAG_INVALIDATED
                    forceLayout(mView);
                }
                // 向Choreographer注册TRAVERSAL消息。
                requestLayout();
            }
            break;
        }
    }
    ...
}
```

- Display在通常情况下并不会改变。
- 调用`reportNextDraw`，标记mReportNextDraw为true。
- 调用`forceLayout`，将所有View的mPrivateFlags标记上PFLAG_FORCE_LAYOUT和PFLAG_INVALIDATED
- 调用`requestLayout`，向Choreographer注册TRAVERSAL消息。等到下次VSYNC消息进行measure/layout/draw。

### # VirtualDisplay

Flutter提供的嵌入PlatformView能力，就是将Android原生的View嵌入到Flutter的View当中去。

其中用到的就是VirtualDisplay。VirtualDisplayController调用DisplayManagerService创建了一个VirtualDisplay。之后通过Presentation(继承自Dialog)，持有VirtualDisplay中的Display对象(同时将Surface对象传递到Flutter底层持有)生成新的ContextImpl，这样在Presentation中的View(即PlatformView)就直接绘制到Surface上了，同时Flutter也可以管理这些Surface。

#### - 创建

```java
// frameworks/base/services/core/java/com/android/server/display/DisplayManagerService.java
@Override // Binder call
public int createVirtualDisplay(IVirtualDisplayCallback callback,
        IMediaProjection projection, String packageName, String name,
        int width, int height, int densityDpi, Surface surface, int flags,
        String uniqueId) {
    final int callingUid = Binder.getCallingUid();
    ...

    final long token = Binder.clearCallingIdentity();
    try {
        return createVirtualDisplayInternal(callback, projection, callingUid, packageName,
                name, width, height, densityDpi, surface, flags, uniqueId);
    } finally {
        Binder.restoreCallingIdentity(token);
    }
}

private int createVirtualDisplayInternal(IVirtualDisplayCallback callback,
    IMediaProjection projection, int callingUid, String packageName, String name, int width,
    int height, int densityDpi, Surface surface, int flags, String uniqueId) {
    synchronized (mSyncRoot) {
        ...
        DisplayDevice device = mVirtualDisplayAdapter.createVirtualDisplayLocked(
                callback, projection, callingUid, packageName, name, width, height, densityDpi,
                surface, flags, uniqueId);
        if (device == null) {
            return -1;
        }
        handleDisplayDeviceAddedLocked(device);
        LogicalDisplay display = findLogicalDisplayForDeviceLocked(device);
        if (display != null) {
            return display.getDisplayIdLocked();
        }
        ...
        mVirtualDisplayAdapter.releaseVirtualDisplayLocked(callback.asBinder());
        handleDisplayDeviceRemovedLocked(device);
    }
    return -1;
}
```

由`VirtualDisplayAdapter`创建。

#### - 释放

Client:


```java
// frameworks/base/core/java/android/hardware/display/VirtualDisplay.java
public void release() {
    if (mToken != null) {
        mGlobal.releaseVirtualDisplay(mToken);
        mToken = null;
    }
}

// frameworks/base/core/java/android/hardware/display/DisplayManagerGlobal.java
public void releaseVirtualDisplay(IVirtualDisplayCallback token) {
    try {
        mDm.releaseVirtualDisplay(token);
    } catch (RemoteException ex) {
        throw ex.rethrowFromSystemServer();
    }
}
```

Server:

```java
// frameworks/base/services/core/java/com/android/server/display/DisplayManagerService.java
@Override // Binder call
public void releaseVirtualDisplay(IVirtualDisplayCallback callback) {
    final long token = Binder.clearCallingIdentity();
    try {
        releaseVirtualDisplayInternal(callback.asBinder());
    } finally {
        Binder.restoreCallingIdentity(token);
    }
}
```
