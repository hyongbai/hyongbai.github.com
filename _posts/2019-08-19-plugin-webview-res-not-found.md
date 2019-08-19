---
layout: post
title: "解决WebView插件化找不到资源问题"
description: "解决WebView插件化找不到资源问题"
category: all-about-tech
tags: -[android，webview, plugin]
date: 2019-08-19 13:13:57+00:00
---


## 日志

后台反馈用户在浏览器插件长按输入框会出现崩溃。日志如下：

```
android.content.res.Resources$NotFoundException: Resource ID #0x3080005
     at android.content.res.ResourcesImpl.getValue(ResourcesImpl.java:292)
     at android.content.res.Resources.getInteger(Resources.java:1273)
     at org.chromium.ui.base.DeviceFormFactor.a(PG:4)
     at It.onCreateActionMode(PG:5)
     at com.android.internal.policy.DecorView$ActionModeCallback2Wrapper.onCreateActionMode(DecorView.java:2638)
     at com.android.internal.policy.DecorView.startActionMode(DecorView.java:1014)
     at com.android.internal.policy.DecorView.startActionModeForChild(DecorView.java:970)
     at android.view.ViewGroup.startActionModeForChild(ViewGroup.java:990)
     at android.view.ViewGroup.startActionModeForChild(ViewGroup.java:990)
     at android.view.View.startActionMode(View.java:6859)
     at Is.a(PG:15)
     at org.chromium.content.browser.selection.SelectionPopupControllerImpl.s(PG:147)
     at org.chromium.content.browser.selection.SelectionPopupControllerImpl.showSelectionMenu(PG:124)
     at android.os.MessageQueue.nativePollOnce(Native Method)
     at android.os.MessageQueue.next(MessageQueue.java:386)
     at android.os.Looper.loop(Looper.java:169)
     at android.app.ActivityThread.main(ActivityThread.java:7470)
     at java.lang.reflect.Method.invoke(Native Method)
     at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:524)
     at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:958)
```

看到这个`Resource ID #0x3080005`第一反映跟插件自身逻辑关联不大。正常情况下0x7开头的才是apk自己的资源id。而崩溃日志中0x3必定是系统本身的资源找不到，apk不背这个锅。

后来仔细查看Webview源码发现了如下问题：

## 解决方案

在WebView初始化时调用[WebViewResourceHelper](http://t.cn/AijzG85y)#addChromeResourceIfNeeded，手动给自己的Context添加Asset路径(即Webview的路径)。

## 原因

在Android之前系统是将Webview当作一个单独的组建放在Framework中，因此webview的资源无论如何都是可以加载到的。

而Android后来的版本上，修改了Webview的方式，系统需要达到使用第三方apk无缝替换内置Webview。换句人话就是，第三方Browser也可以提供Webview供系统使用。

因此，Webview并不会集成在Framework中，加载Webview自带资源时并不会原生就能得到。

## 修改方式

Webview本身是一个非常庞大的小型操作系统。而在Android中开发者看到的Webview本身只是一个壳子。翻开源码可以发现所有的实现都是通过WebViewProvider实现的。

![android-framework-webview-view.png](http://t.cn/Aij7BYE3)

下面来看Provider是如何获取的。

#### ensureProviderCreated


```java
// framework/core/base/java/android/webkit/Webview.java
private void ensureProviderCreated() {
    checkThread();
    if (mProvider == null) {
        // As this can get called during the base class constructor chain, pass the minimum
        // number of dependencies here; the rest are deferred to init().
        mProvider = getFactory().createWebView(this, new PrivateAccess());
    }
}

private static WebViewFactoryProvider getFactory() {
    return WebViewFactory.getProvider();
}
```

#### getProvider

```java
// framework/core/base/java/android/webkit/WebviewFactory.java
static WebViewFactoryProvider getProvider() {
    synchronized (sProviderLock) {
        // ...
            Class<WebViewFactoryProvider> providerClass = getProviderClass();
            Method staticFactory = null;
            try {
                staticFactory = providerClass.getMethod(
                    CHROMIUM_WEBVIEW_FACTORY_METHOD, WebViewDelegate.class);
            }
            // ...
            try {
                sProviderInstance = (WebViewFactoryProvider)
                        staticFactory.invoke(null, new WebViewDelegate());
                if (DEBUG) Log.v(LOGTAG, "Loaded provider: " + sProviderInstance);
                return sProviderInstance;
            }
            // ...
    }
}
```

#### getProviderClass


```java
// framework/core/base/java/android/webkit/WebviewFactory.java
private static Class<WebViewFactoryProvider> getProviderClass() {
    Context webViewContext = null;
    Application initialApplication = AppGlobals.getInitialApplication();
    // ...
        try {
            webViewContext = getWebViewContextAndSetProvider();
        }
        // ...
        try {
            initialApplication.getAssets().addAssetPathAsSharedLibrary(
                    webViewContext.getApplicationInfo().sourceDir);
            ClassLoader clazzLoader = webViewContext.getClassLoader();
            Trace.traceBegin(Trace.TRACE_TAG_WEBVIEW, "WebViewFactory.loadNativeLibrary()");
            WebViewLibraryLoader.loadNativeLibrary(clazzLoader, sPackageInfo);
            // ...
            try {
                return getWebViewProviderClass(clazzLoader);
            }
        // ...
}
```

这里最关键的一步就是将Webview的路径放到assetManager中去。

其中AppGlobals.getInitialApplication()返回的是当前app(也就是宿主)的Application对象。

webViewContext.getApplicationInfo().sourceDir就是提供这个Webview的Context对应的源码路径(apk/dex路径)。

最后通过initialApplication.getAssets().addAssetPathAsSharedLibrary将当前webview的源码路径(包含了实际Webview资源)插入到宿主的assetManager中去。

## 总结

因此，在宿主中使用Webview是不会出现类似的资源的。而在插件中，即使这里做了一步骤，也是在位宿主的assetManager做嫁衣。而宿主和插件本身asset是隔离的，因而在插件中是必然会存在类似找不到资源的问题。
