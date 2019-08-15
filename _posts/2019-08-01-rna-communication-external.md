---
layout: post
title: "ReactNative在Android上的通信机制"
description: "ReactNative comunication in android between js and native modules"
category: all-about-tech
tags: -[react-native, hybrid]
date: 2019-08-01 16:40:57+00:00
---

> com.facebook.react:react-native:0.60.4

## CatalystInstance

CatalystInstance为js和native的催化剂，用于js和native的反应(通信).

`NativeModuleRegistry`和`JavaScriptModuleRegistry`分别用于管理所有native模块以及js模块。

在RNA中，CatalystInstanceImpl是它的实现。

在RNA启动过程中通过CoreModulesPackage和MainReactPackage向NativeModuleRegistry注入RNA支持的native接口，以便js端调用。

而js接口并不会在初始化时载入，js接口是在调用时在JavaScriptModuleRegistry的getJavaScriptModule中使用动态代理实现的。因此无需要事先注册，随用随取即可。

同时，对于Native模块，如果我们动态添加接口怎么办呢？在CatalystInstanceImpl中提供了`extendNativeModules`接口用于拓展native模块。

代码如下：

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/CatalystInstanceImpl.java
  @Override
  public void extendNativeModules(NativeModuleRegistry modules) {
    //Extend the Java-visible registry of modules
    mNativeModuleRegistry.registerModules(modules);
    Collection<JavaModuleWrapper> javaModules = modules.getJavaModules(this);
    Collection<ModuleHolder> cxxModules = modules.getCxxModules();
    //Extend the Cxx-visible registry of modules wrapped in appropriate interfaces
    jniExtendNativeModules(javaModules, cxxModules);
  }

  private native void jniExtendNativeModules(
    Collection<JavaModuleWrapper> javaModules,
    Collection<ModuleHolder> cxxModules);
```

下面来分别看看Native和JS层的相互调用过程：

## NATIVE 2 JS

native是相对于js而言，并非Android中c/c++/jni等模块实现的native。在RNA中，native到js的通信并没有使用传统的loadurl等方式。而是使用c++实现了一套跨平台的解决方案。

下面结合RNA启动过程来看RNA中native到js的通信。

#### runJSBundle

我们知道在ReactInstanceManager创建ReactContext时，会一并初始化CatalystInstance：

```java
// ReactAndroid/src/main/java/com/facebook/react/ReactInstanceManager.java
  private ReactApplicationContext createReactContext(
      JavaScriptExecutor jsExecutor,
      JSBundleLoader jsBundleLoader) {
    // ...
    final CatalystInstance catalystInstance;
    try {
      catalystInstance = catalystInstanceBuilder.build();
    }
    // ...
    catalystInstance.runJSBundle();
    // ...
    return reactContext;
  }
```

通过以上代码可知，在CatalystInstance创世之处会首先调用runJSBundle。用于加载jsBundle。

如下：

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/CatalystInstanceImpl.java
  @Override
  public void runJSBundle() {
    Log.d(ReactConstants.TAG, "CatalystInstanceImpl.runJSBundle()");
    Assertions.assertCondition(!mJSBundleHasLoaded, "JS bundle was already loaded!");
    // incrementPendingJSCalls();
    mJSBundleLoader.loadScript(CatalystInstanceImpl.this);

    synchronized (mJSCallsPendingInitLock) {

      // Loading the bundle is queued on the JS thread, but may not have
      // run yet.  It's safe to set this here, though, since any work it
      // gates will be queued on the JS thread behind the load.
      mAcceptCalls = true;

      for (PendingJSCall function : mJSCallsPendingInit) {
        function.call(this);
      }
      mJSCallsPendingInit.clear();
      mJSBundleHasLoaded = true;
    }

    // This is registered after JS starts since it makes a JS call
    Systrace.registerListener(mTraceListener);
  }
```

这里会通过mJSBundleLoader.loadScript加载js。通过 ReactAndroid/src/main/java/com/facebook/react/bridge/JSBundleLoader.java 的逻辑可以发现这里其实最终通过对应的jniLoadScriptFromXXX进入c++层。

之后会将初始化完成之前缓存的js函数调用遍历一遍一一调用。同时mAcceptCalls设置为true，表示运行call js。

#### RNA启动

RNA启动的最后一部是runApplication，如下：

```java
 public void runApplication() {
    catalystInstance.getJSModule(AppRegistry.class).
      runApplication(jsAppModuleName, appParams);
}
```

下面是这一系列调用的时序图：

[![rn-native2js-seq.jpg](https://t.cn/AiTh0meC)](https://j.mp/2KimavX)

#### JavaScriptModuleRegistry

上图可以看出获取js模块的入口最终是在JavaScriptModuleRegistry中：

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/JavaScriptModuleRegistry.java
  public synchronized <T extends JavaScriptModule> T getJavaScriptModule(
      CatalystInstance instance,
      Class<T> moduleInterface) {
    JavaScriptModule module = mModuleInstances.get(moduleInterface);
    if (module != null) {
      return (T) module;
    }

    JavaScriptModule interfaceProxy = (JavaScriptModule) Proxy.newProxyInstance(
        moduleInterface.getClassLoader(),
        new Class[]{moduleInterface},
        new JavaScriptModuleInvocationHandler(instance, moduleInterface));
    mModuleInstances.put(moduleInterface, interfaceProxy);
    return (T) interfaceProxy;
  }
```

getJavaScriptModule函数中，首先会读取缓存，确保之前存在过对应的js模块，如果不存在那么通过动态代理实例化一个代理类，并将这个代理类加入到缓存。而在动态代理的过程中通过JavaScriptModuleInvocationHandler来实现对代理类内部接口的调用。

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/JavaScriptModuleRegistry.java
  private static class JavaScriptModuleInvocationHandler implements InvocationHandler {
  // ...
    @Override
    public @Nullable Object invoke(Object proxy, Method method, @Nullable Object[] args) throws Throwable {
      NativeArray jsArgs = args != null
        ? Arguments.fromJavaArgs(args)
        : new WritableNativeArray();
      mCatalystInstance.callFunction(getJSModuleName(), method.getName(), jsArgs);
      return null;
    }
  }
```

JavaScriptModuleInvocationHandler的回调函数invoke主要是调用CatalystInstance的callFunction函数，完成调用。

#### callFunction

因此，我们进入CatalystInstanceImpl中来看callFunction的实现：

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/CatalystInstanceImpl.java
  @Override
  public void callFunction(
      final String module,
      final String method,
      final NativeArray arguments) {
    callFunction(new PendingJSCall(module, method, arguments));
  }
// com/facebook/react/bridge/CatalystInstanceImpl.java
  public void callFunction(PendingJSCall function) {
    if (mDestroyed) {
      final String call = function.toString();
      FLog.w(ReactConstants.TAG, "Calling JS function after bridge has been destroyed: " + call);
      return;
    }
    if (!mAcceptCalls) {
      // Most of the time the instance is initialized and we don't need to acquire the lock
      synchronized (mJSCallsPendingInitLock) {
        if (!mAcceptCalls) {
          mJSCallsPendingInit.add(function);
          return;
        }
      }
    }
    function.call(this);
  }
```

这里同上面的`runJSBundle`就有关系了，如果没有初始化完成，那么所有的js call都会加入到mJSCallsPendingInit当中去。等待初始化时统一处理。

否则就调用PendingJSCall.call最终通过`jniCallJSFunction`进入cxxreact的JSExecutor最终在js runtime中执行js，从而完成对js代码的访问。

## JS 2 NATIVE

通信是RNA中的核心，因此在CatalystInstance初始化的时候就必须初始化Bridge。这发生在CatalystInstanceImpl的构造函数中。

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/CatalystInstanceImpl.java
  private CatalystInstanceImpl(
      final ReactQueueConfigurationSpec reactQueueConfigurationSpec,
      final JavaScriptExecutor jsExecutor,
      final NativeModuleRegistry nativeModuleRegistry,
      final JSBundleLoader jsBundleLoader,
      NativeModuleCallExceptionHandler nativeModuleCallExceptionHandler) {
    // ...
    initializeBridge(
      new BridgeCallback(this),
      jsExecutor,
      mReactQueueConfiguration.getJSQueueThread(),
      mNativeModulesQueueThread,
      mNativeModuleRegistry.getJavaModules(this),
      mNativeModuleRegistry.getCxxModules());
  }
  private native void initializeBridge(
      ReactCallback callback,
      JavaScriptExecutor jsExecutor,
      MessageQueueThread jsQueue,
      MessageQueueThread moduleQueue,
      Collection<JavaModuleWrapper> javaModules,
      Collection<ModuleHolder> cxxModules);
```

#### Java层初始化

整个过程以时序图形式表现如下：

[![rn-js2native-seq.jpg](https://t.cn/AiT4d75f)](https://j.mp/2KimavX)

在初始化的过程中，会向底层传递一系列运行时必须的环境。主要是运行线程以及NativeModule。

其中线程包括js线程以及native线程。

而Native模块还被分为java模块和cxx模块。在RN中Native是相对于js来说的，因此这里使用了cxx字样来表示通常意义上的Native模块。

- ReactCallback

来自底层的回调。

每一次native对js层调用都伴随着一次incrementPendingJSCalls和一次decrementPendingJSCalls，并进行计数。

```java
// ReactAndroid/src/main/java/com/facebook/react/CatalystInstanceImpl.java
  private static class BridgeCallback implements ReactCallback {
    @Override
    public void incrementPendingJSCalls() {
      CatalystInstanceImpl impl = mOuter.get();
      if (impl != null) {
        impl.incrementPendingJSCalls();
      }
    }
  }
  private void incrementPendingJSCalls() {
    int oldPendingCalls = mPendingJSCalls.getAndIncrement();
    // ...
  }
```

- JavaScriptExecutor

```java
// ReactAndroid/src/main/java/com/facebook/react/ReactInstanceManagerBuilder.java
  private JavaScriptExecutorFactory getDefaultJSExecutorFactory(String appName, String deviceName) {
    try {
      // If JSC is included, use it as normal
      SoLoader.loadLibrary("jscexecutor");
      return new JSCExecutorFactory(appName, deviceName);
    } catch(UnsatisfiedLinkError jscE) {
      // Otherwise use Hermes
      return new HermesExecutorFactory();
    }
  }
```

- 线程

ReactQueueConfigurationImpl负责RNA中各环境的运行线程。

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/queue/ReactQueueConfigurationImpl.java
  private final MessageQueueThreadImpl mUIQueueThread;
  private final MessageQueueThreadImpl mNativeModulesQueueThread;
  private final MessageQueueThreadImpl mJSQueueThread;
```

>- mUIQueueThread 就是ui线程，持有的是mainLooper。
>- mJSQueueThread 是js的运行线程。js的逻辑都是这个线程中运行的。
>- mJSQueueThread 是native module运行线程。具体在JavaModuleWrapper.cpp和CxxNativeModule.cpp的invoke函数会将任务扔到这个线程做异步执行操作。

#### JavaModules

从RNA的初始化流程可知，RNA中NativeModule是通过ReactPackge注册进来的。Java实现的NativeModule都是BaseJavaModule类实现的，比如ReactCheckBoxManager。

在CatalystInstanceImpl调用getJavaModules其实就是遍历其中的NativeModuleRegistry所有模块，并过滤出非CxxModule，并生成JavaModuleWrapper。过程如下：

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/NativeModuleRegistry.java
  /* package */ Collection<JavaModuleWrapper> getJavaModules(JSInstance jsInstance) {
    ArrayList<JavaModuleWrapper> javaModules = new ArrayList<>();
    for (Map.Entry<String, ModuleHolder> entry : mModules.entrySet()) {
      if (!entry.getValue().isCxxModule()) {
        javaModules.add(new JavaModuleWrapper(jsInstance, entry.getValue()));
      }
    }
    return javaModules;
  }
```

底层在初始化的时候所有Native模块时，会调到JavaModuleWrapper的findMethods函数，用于构建所有method的索引。java层面的构建过程很简单：

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/JavaModuleWrapper.java
  private void findMethods() {
    Systrace.beginSection(TRACE_TAG_REACT_JAVA_BRIDGE, "findMethods");
    Set<String> methodNames = new HashSet<>();

    Class<? extends NativeModule> classForMethods = mModuleHolder.getModule().getClass();
    Class<? extends NativeModule> superClass = (Class<? extends NativeModule>) classForMethods.getSuperclass();
    if (ReactModuleWithSpec.class.isAssignableFrom(superClass)) {
      // For java module that is based on generated flow-type spec, inspect the
      // spec abstract class instead, which is the super class of the given java
      // module.
      classForMethods = superClass;
    }
    Method[] targetMethods = classForMethods.getDeclaredMethods();
    for (Method targetMethod : targetMethods) {
      ReactMethod annotation = targetMethod.getAnnotation(ReactMethod.class);
      if (annotation != null) {
        String methodName = targetMethod.getName();
        if (methodNames.contains(methodName)) {
          throw new IllegalArgumentException( "Java Module " + getName() + " method name already registered: " + methodName);
        }
        MethodDescriptor md = new MethodDescriptor();
        JavaMethodWrapper method = new JavaMethodWrapper(this, targetMethod, annotation.isBlockingSynchronousMethod());
        md.name = methodName;
        md.type = method.getType();
        if (md.type == BaseJavaModule.METHOD_TYPE_SYNC) {
          md.signature = method.getSignature();
          md.method = targetMethod;
        }
        mMethods.add(method);
        mDescs.add(md);
      }
    }
    Systrace.endSection(TRACE_TAG_REACT_JAVA_BRIDGE);
  }
```

注意，这里的Method不是正常的反射，是JavaMethodWrapper封装类。

底层在接受到js消息之后，会从JavaModuleWrapper.cpp中调用到JavaModuleWrapper.java的invoke方法，从而实现js对java方法的调用。invoke方法如下：

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/JavaModuleWrapper.java
@DoNotStrip
public void invoke(int methodId, ReadableNativeArray parameters) {
  if (mMethods == null || methodId >= mMethods.size()) {
     return;
  }
  mMethods.get(methodId).invoke(mJSInstance, parameters);
}
```

`JavaMethodWrapper`中主要是处理了来自js层的参数，比如函数签名/参数校验，同时将抽象数据转化为对应的java对象。最终反射执行对应函数。比如通过调用ReactCheckBoxManager的setOn方法即可修改CheckBox的enable状态。

#### CxxModules

RN当然也是支持C++层面的Moudle的。而C++层的Module也是需要从Java层进行接入。不同的是C++的NativeModule是在C++层实现的。因此在涉及到CxxModule的函数调用的时候，是与Java层完全不同的。

`getCxxModules()`如下：

```java
// ReactAndroid/src/main/java/com/facebook/react/bridge/NativeModuleRegistry.java
  /* package */ Collection<ModuleHolder> getCxxModules() {
    ArrayList<ModuleHolder> cxxModules = new ArrayList<>();
    for (Map.Entry<String, ModuleHolder> entry : mModules.entrySet()) {
      if (entry.getValue().isCxxModule()) {
        cxxModules.add(entry.getValue());
      }
    }
    return cxxModules;
  }
```

可以看到与`getJavaModules()`不同的是，这里给底层的就只是ModuleHolder而已。

并且初始化的时候CxxModule和JavaModule在底层是分开进行的，不变的是他们都是NativeModule.h抽象出来的invoke方法。js层使用时无差别调用即可。

当调用到CxxModule时才会lazyInit，这时候会直接访问真实的CxxModule中的getMethods并缓存，通过methodId找到最终的CxxModule::Method的func即可。

> 需要吐槽一下，RNA文件命名容易致幻。比如javaModule的基类是BaseJavaModule，对外暴露函数调用入口的封装叫JavaModuleWrapper，但是C++Module(CxxModule)的基类是CxxModuleWrapper。容易混淆。在底层，JavaNativeModule在JavaModuleWrapper.h中，而CxxNativeModule在CxxNativeModule.h中。


## Reference

<https://segmentfault.com/a/1190000004586390>
<https://juejin.im/post/5c4468356fb9a04a006f50a8>

