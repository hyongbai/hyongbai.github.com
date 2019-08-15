---
layout: post
title: "ReactNative在Android上的启动过程"
description: "RNA launch"
category: all-about-tech
tags: -[react-native, hybrid]
date: 2019-08-01 16:39:57+00:00
---

> 基于 com.facebook.react:react-native:0.60.4

通过如下方式：

```
react-native init AwesomeProject
```

创建了一个react-native的helloword工程。可以看到

```
-rw-r--r--   1 xxx staff   2791 Jul 31 15:12 App.js
drwxr-xr-x   3 xxx staff    102 Jul 31 15:12 __tests__
drwxr-xr-x  13 xxx staff    442 Jul 31 17:02 android
-rw-r--r--   1 xxx staff     65 Jul 31 15:12 app.json
-rw-r--r--   1 xxx staff     77 Jul 31 15:12 babel.config.js
-rw-r--r--   1 xxx staff    183 Jul 31 15:12 index.js
drwxr-xr-x   9 xxx staff    306 Jul 31 15:12 ios
-rw-r--r--   1 xxx staff    300 Jul 31 15:12 metro.config.js
drwxr-xr-x 651 xxx staff  22134 Jul 31 15:12 node_modules
-rw-r--r--   1 xxx staff    599 Jul 31 15:12 package.json
-rw-r--r--   1 xxx staff 260680 Jul 31 15:12 yarn.lock
```

其中`android`目录就是android工程目录。下面来看看ReactNative是如何跟Android交互。

```java
public class MainActivity extends ReactActivity {
    /**
     * Returns the name of the main component registered from JavaScript.
     * This is used to schedule rendering of the component.
     */
    @Override
    protected String getMainComponentName() {
        return "AwesomeProject";
    }
}
```

这个是默认工程自动创建的Launch Activity，而它本身没有任何代码。所有的逻辑都隐藏在ReactActivity中。

## ReactActivity

ReactActivity是react-native用于Android页面交互入口，只要Activity集成自ReactActivity就可以显示react native的逻辑。但它本身只是一个壳子，所有的逻辑都存在于ReactActiivtyDelegate中。

## ReactActiivtyDelegate

根据onCreate的逻辑，大致可以知道ReactActivity在启动的过程中大致满足如下的时序图：

[![ReactActivity Launch Sequence](https://t.cn/AiYi0Svo)](https://github.com/hyongbai/resources)

可以看到代理类的onCreate中主要是调用了loadApp。如下：

#### loadApp

这里处理了Activity启动时的全部逻辑。

首先，会创建一个RootView。

其次通过其`startReactApplication`完成RootView的一系列初始化行为。

最终通过调用Activity的`setContentView`将RootView设置为显示的根View。

代码如下：

```java
// com/facebook/react/ReactActivityDelegate.java
  protected void loadApp(String appKey) {
    if (mReactRootView != null) {
      throw new IllegalStateException("Cannot loadApp while app is already running.");
    }
    mReactRootView = createRootView();
    mReactRootView.startReactApplication(
      getReactNativeHost().getReactInstanceManager(),
      appKey,
      getLaunchOptions());
    getPlainActivity().setContentView(mReactRootView);
  }
```

其中，在startReactApplication之前会通过ReactNativeHost生成的`ReactInstanceManager`并传递下去。

#### startReactApplication

RootView是一个集成自FrameLayout的自定义View。

来自ViewRootImpl的事件，如：TouchEvent/KeyEvent等，都是在这里进行处理的。

下面接着看`startReactApplication`：

```java
// com/facebook/react/ReactRootView.java
  public void startReactApplication(
      ReactInstanceManager reactInstanceManager,
      String moduleName,
      @Nullable Bundle initialProperties,
      @Nullable String initialUITemplate) {
      // ...
      mReactInstanceManager = reactInstanceManager;
      // ...
      if (!mReactInstanceManager.hasStartedCreatingInitialContext()) {
        mReactInstanceManager.createReactContextInBackground();
      }
      attachToReactInstanceManager();
      // ...
  }
```

核心逻辑只有两个。

一个是通过调用`ReactInstanceManager`的createReactContextInBackground以异步的方式创建ReactContext，这里后面再说。

#### attachToReactInstanceManager

另一个是把自己attach到ReactInstanceManager中(`attachRootView`)，并向ViewTrewwObserver注册一个GlobalLayoutListener，同时标注为Attached(即mIsAttachedToInstance=true)。

这一部分的逻辑封装在attachToReactInstanceManager函数中，如下：

```java
// com/facebook/react/ReactRootView.java
  private void attachToReactInstanceManager() {
    Systrace.beginSection(TRACE_TAG_REACT_JAVA_BRIDGE, "attachToReactInstanceManager");
    try {
      if (mIsAttachedToInstance) {
        return;
      }

      mIsAttachedToInstance = true;
      Assertions.assertNotNull(mReactInstanceManager).attachRootView(this);
      getViewTreeObserver().addOnGlobalLayoutListener(getCustomGlobalLayoutListener());
    } finally {
      Systrace.endSection(TRACE_TAG_REACT_JAVA_BRIDGE);
    }
  }
```

下面展开一下ReactInstanceManager和ReactContext.

## ReactNativeHost

ReactNativeHost一个同Application绑定的入口，用于提供初始化/提供ReactInstanceManager/JS相关配置以及载入ReactPackage等。

比如getReactInstanceManager()，可用于全局获取ReactInstanceManager：

```java
// com/facebook/react/ReactNativeHost.java
  public ReactInstanceManager getReactInstanceManager() {
    if (mReactInstanceManager == null) {
      ReactMarker.logMarker(ReactMarkerConstants.GET_REACT_INSTANCE_MANAGER_START);
      mReactInstanceManager = createReactInstanceManager();
      ReactMarker.logMarker(ReactMarkerConstants.GET_REACT_INSTANCE_MANAGER_END);
    }
    return mReactInstanceManager;
  }
```

如果是第一次调用，则会先创建一个新的。如下：

#### 创建ReactInstanceManager

下面是ReactInstanceManager在初始化的时候的时序图。

[![rn-initialiazation-ReactInstanceManager.jpg](https://t.cn/AiYBlCcj)](https://j.mp/2KimavX)

可以看出，在创建的时候是通过Builder来进行的。具体代码如下：

```java
// com/facebook/react/ReactNativeHost.java
  protected ReactInstanceManager createReactInstanceManager() {
    ReactMarker.logMarker(ReactMarkerConstants.BUILD_REACT_INSTANCE_MANAGER_START);
    ReactInstanceManagerBuilder builder = ReactInstanceManager.builder()
      .setApplication(mApplication)
      .setJSMainModulePath(getJSMainModuleName())
      .setUseDeveloperSupport(getUseDeveloperSupport())
      .setRedBoxHandler(getRedBoxHandler())
      .setJavaScriptExecutorFactory(getJavaScriptExecutorFactory())
      .setUIImplementationProvider(getUIImplementationProvider())
      .setJSIModulesPackage(getJSIModulePackage())
      .setInitialLifecycleState(LifecycleState.BEFORE_CREATE);

    for (ReactPackage reactPackage : getPackages()) {
      builder.addPackage(reactPackage);
    }

    String jsBundleFile = getJSBundleFile();
    if (jsBundleFile != null) {
      builder.setJSBundleFile(jsBundleFile);
    } else {
      builder.setBundleAssetName(Assertions.assertNotNull(getBundleAssetName()));
    }
    ReactInstanceManager reactInstanceManager = builder.build();
    ReactMarker.logMarker(ReactMarkerConstants.BUILD_REACT_INSTANCE_MANAGER_END);
    return reactInstanceManager;
  }
```

结合时序图以及上面代码，在创建的时候会有2点很重要的信息：

- 添加MainReactPackage。

`MainReactPackage`提供了一系列的NativeModule和ViewManager(本身也是NativeModule)。

前者提供了给js调用Native的API的能力，比如ClipboardModule提供js对Android剪切板的读写操作。

后者提供了给js调用Native View的能力，比如ReactCheckBoxManager提供给js直接修改CheckBox状态的操作。

- 确定RN需要加载的js代码的路径。

RN默认情况下是使用打包时插入到assets中的js代码，位于 assets://index.android.bundle。
既然是直接执行js代码来抽离组件和逻辑，那么更多情况下开发者还是需要加载外部js的方式来实现业务代码的更新。因此RN也提供了getJSBundleFile来允许开发者自定义需要加载的js文件。

注意：DEBUG模式下的加载是另外一种方式：

```
 @ThreadConfined(UI)
  private void recreateReactContextInBackgroundInner() {
    // ...
    if (mUseDeveloperSupport && mJSMainModulePath != null) {
      final DeveloperSettings devSettings = mDevSupportManager.getDevSettings();
      // If remote JS debugging is enabled, load from dev server.
      if (mDevSupportManager.hasUpToDateJSBundleInCache() &&
          !devSettings.isRemoteJSDebugEnabled()) {
        // If there is a up-to-date bundle downloaded from server,
        // with remote JS debugging disabled, always use that.
        onJSBundleLoadedFromServer(null);
        return;
      }
        // ...
        return;
      }
    }

    recreateReactContextInBackgroundFromBundleLoader();
  }
  @ThreadConfined(UI)
  private void onJSBundleLoadedFromServer(@Nullable NativeDeltaClient nativeDeltaClient) {
    Log.d(ReactConstants.TAG, "ReactInstanceManager.onJSBundleLoadedFromServer()");

    JSBundleLoader bundleLoader = nativeDeltaClient == null
        ? JSBundleLoader.createCachedBundleFromNetworkLoader(
            mDevSupportManager.getSourceUrl(),
            mDevSupportManager.getDownloadedJSBundleFile())
        : JSBundleLoader.createDeltaFromNetworkLoader(
            mDevSupportManager.getSourceUrl(), nativeDeltaClient);

    recreateReactContextInBackground(mJavaScriptExecutorFactory, bundleLoader);
  }
```

这里可以看出其实最终会通过上面的JSMainModulePath创建一个NetworkLoader，通过网络的方式进行加载js bundle，具体可见com.facebook.react.devsupport.DevSupportManagerImpl。

在ReactInstanceManagerBuilder.build时，上面说到的setJSBundleFile其实就是这里的mJSBundleLoader，而mJSBundleAssetUrl其实最终也是会被抽象成JSBundleLoader。

## ReactInstanceManager

ReactInstanceManager是React Android中一个很重要的类，用于对外暴露处理ReactContext/管理ReactRootView/管理生命周期等等。

比如，绑定Activity生命周期:

```java
// com/facebook/react/ReactActivityDelegate.java
  protected void onPause() {
    if (getReactNativeHost().hasInstance()) {
      getReactNativeHost().getReactInstanceManager().onHostPause(getPlainActivity());
    }
  }

  public void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (getReactNativeHost().hasInstance()) {
      getReactNativeHost().getReactInstanceManager()
        .onActivityResult(getPlainActivity(), requestCode, resultCode, data);
    }
  }
```

上面分别是Activity在Pause/ActivityResult。可以看到Activity的生命周期变动时都会跟ReactInstanceManager交互。

再来看看，RootView初始化时调用到ReactInstanceManager的attach函数：

#### 构造函数

```java
  /* package */ ReactInstanceManager(...);
    initializeSoLoaderIfNecessary(applicationContext);
    // ...
    synchronized (mPackages) {
      PrinterHolder.getPrinter()
          .logMessage(ReactDebugOverlayTags.RN_CORE, "RNCore: Use Split Packages");
      mPackages.add(
          new CoreModulesPackage(
              this,
              new DefaultHardwareBackBtnHandler() {
                @Override
                public void invokeDefaultOnBackPressed() {
                  ReactInstanceManager.this.invokeDefaultOnBackPressed();
                }
              },
              mUIImplementationProvider,
              lazyViewManagersEnabled,
              minTimeLeftInFrameForNonBatchedOperationMs));
      if (mUseDeveloperSupport) {
        mPackages.add(new DebugCorePackage());
      }
      mPackages.addAll(packages);
    }
    // ...
  }
```

其中initializeSoLoaderIfNecessary用于加载RN的so文件。

并且这里会在mPackages添加CoreModulesPackage，可知它是RN中必不可少的模块，比如下面提到的UIManagerModule就是它提供的。结合上面的MainReactPackage，在Manager对象生成之初就会有2到3个ReactPackage。

#### attachRootView

代码如下：

```java
  @ThreadConfined(UI)
  public void attachRootView(ReactRoot reactRoot) {
    UiThreadUtil.assertOnUiThread();
    mAttachedReactRoots.add(reactRoot);
    // ...
    clearReactRoot(reactRoot);
    // ...
    ReactContext currentContext = getCurrentReactContext();
    if (mCreateReactContextThread == null && currentContext != null) {
      attachRootViewToInstance(reactRoot);
    }
  }
```

- 首先插入到mAttachedReactRoots，持有所有的RootView。
- 其次清空RootView所有的子View，以及将其id设置为`View.NO_ID`。
- 调用attachRootViewToInstance。**第一次**进入时，这里其实并不会执行。因为ReactContext是异步生成的，此时currentContext必然为空。但是不要紧最终，reactContext初始化完成之后这里还是会执行的。

```java
  private void attachRootViewToInstance(final ReactRoot reactRoot) {
    UIManager uiManagerModule = UIManagerHelper.getUIManager(mCurrentReactContext, reactRoot.getUIManagerType());
    @Nullable Bundle initialProperties = reactRoot.getAppProperties();
    final int rootTag = uiManagerModule.addRootView(
      reactRoot.getRootViewGroup(),
      initialProperties == null ? new WritableNativeMap() : Arguments.fromBundle(initialProperties),
      reactRoot.getInitialUITemplate());
    reactRoot.setRootViewTag(rootTag);
    reactRoot.runApplication();
    UiThreadUtil.runOnUiThread(
        new Runnable() {
          @Override
          public void run() {
            reactRoot.onStage(ReactStage.ON_ATTACH_TO_INSTANCE);
          }
        });
  }
```

`reactRoot.runApplication`才是真正**启动的关键代码**，最终会通过CatalystInstance的jniCallJSFunction执行到js层的runApplication函数。最后onStage方法，初始化JSTouchDispatcher，之后js就能够收到Android的触摸事件了。

思考，为何ReactContext是异步处理的呢？下面继续分析。

## ReactContext

ReactContext的创建过程，如下图：

[![rn-initialiazation-ReactContext.png](https://t.cn/AiYiOyWo)](https://github.com/hyongbai/resources)

ReactContext是RN的核心类，js端和native端(Android)都需要依赖与它。

#### createReactContext

基于上面的ReactActivityDelegate的时序图可以看到ReactContext的创建是在runCreateReactContextOnNewThread中，开启新线程进行的。

过程如下：

```java
// com/facebook/react/ReactInstanceManager.java
  private ReactApplicationContext createReactContext(
      JavaScriptExecutor jsExecutor,
      JSBundleLoader jsBundleLoader) {
    final ReactApplicationContext reactContext = new ReactApplicationContext(mApplicationContext);
    NativeModuleCallExceptionHandler exceptionHandler = mNativeModuleCallExceptionHandler != null
        ? mNativeModuleCallExceptionHandler
        : mDevSupportManager;
    reactContext.setNativeModuleCallExceptionHandler(exceptionHandler);
    NativeModuleRegistry nativeModuleRegistry = processPackages(reactContext, mPackages, false);
    CatalystInstanceImpl.Builder catalystInstanceBuilder = new CatalystInstanceImpl.Builder()
      .setReactQueueConfigurationSpec(ReactQueueConfigurationSpec.createDefault())
      .setJSExecutor(jsExecutor)
      .setRegistry(nativeModuleRegistry)
      .setJSBundleLoader(jsBundleLoader)
      .setNativeModuleCallExceptionHandler(exceptionHandler);
    final CatalystInstance catalystInstance;
    try {
      catalystInstance = catalystInstanceBuilder.build();
    } finally {
    }
    if (mJSIModulePackage != null) {
      catalystInstance.addJSIModules(mJSIModulePackage
        .getJSIModules(reactContext, catalystInstance.getJavaScriptContextHolder()));
    }
    if (mBridgeIdleDebugListener != null) {
      catalystInstance.addBridgeIdleDebugListener(mBridgeIdleDebugListener);
    }
    catalystInstance.runJSBundle();
    reactContext.initializeWithInstance(catalystInstance);
    return reactContext;
  }
```

这里主要是两回事：

#### 创建NativeModuleRegistry

这一步是处理在Manager初始化时加入的ReactPackage，每个Package中包含了各种NativeModule。并返回一个NativeModuleRegistry。

```java
  private NativeModuleRegistry processPackages(
    ReactApplicationContext reactContext,
    List<ReactPackage> packages,
    boolean checkAndUpdatePackageMembership) {
    NativeModuleRegistryBuilder nativeModuleRegistryBuilder = new NativeModuleRegistryBuilder(reactContext,this);
    // TODO(6818138): Solve use-case of native modules overriding
    synchronized (mPackages) {
      for (ReactPackage reactPackage : packages) {
        // ...
          processPackage(reactPackage, nativeModuleRegistryBuilder);
      }
    }
    NativeModuleRegistry nativeModuleRegistry;
    try {
      nativeModuleRegistry = nativeModuleRegistryBuilder.build();
    }
    return nativeModuleRegistry;
  }
```

上面就是遍历一边mPackages，之后进入调用NativeModuleRegistryBuilder的processPackage分别处理每个ReactPackage：

```
// com/facebook/react/NativeModuleRegistryBuilder.java
  public void processPackage(ReactPackage reactPackage) {
    Iterable<ModuleHolder> moduleHolders;
    if (reactPackage instanceof LazyReactPackage) {
      moduleHolders = ((LazyReactPackage) reactPackage).getNativeModuleIterator(mReactApplicationContext);
    } else if (reactPackage instanceof TurboReactPackage) {
      moduleHolders = ((TurboReactPackage) reactPackage).getNativeModuleIterator(mReactApplicationContext);
    } else {
      moduleHolders = ReactPackageHelper.getNativeModuleIterator(reactPackage, mReactApplicationContext, mReactInstanceManager);
    }

    for (ModuleHolder moduleHolder : moduleHolders) {
      String name = moduleHolder.getName();
        // ...
      mModules.put(name, moduleHolder);
    }
  }
```

NativeModuleRegistryBuilder中会根据不同类型的ReactPackage分别调用不同的函数，获取当当前ReactPackage提供的NativeModule。最终将所有ReactPackage支持的NativeModule加入到同一个列表中。

#### 创建CatalystInstance

Catalyst意为催化剂，这个类的含义不言而喻：它是js和native的催化剂。最后所有nativemodule已经js层函数的调用都是在这里实现。

在CatalystInstance中，会持有并真正使用ReactInstanceManage的jsBundleLoader和NativeRegistry。

最后执行runJSBundle，将js代码加载起来。

#### 小结

开启新线程初始化Context主要原因在于jsBundle的加载过程涉及到了IO，必然是不适合在主线程操作的。

## 总结

ReactRootView相当于RN的ViewRootImpl，用于同Activity绑定。

ReactContext等同于Android上面的Context，并且它本身也是ContextWrapper的子类。

ReactInstanceManager用于处理所有RootView、生命周期以及ReactContext的初始化等行为。

ReactActivityDelegate同ReactActivity绑定，用于接受KeyEvent以及生命周期等等Activity中的交互逻辑。

CatalystInstance为js和native的催化剂，用于js和native的反应(通信)，同时NativeModuleRegistry和JavaScriptModuleRegistry分别用于管理所有native模块以及js模块。

ReactNativeHost负责RN相关的所有配置，比如js bundle，native模块引入以及提供ReactInstanceManager等。