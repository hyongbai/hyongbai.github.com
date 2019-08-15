---
layout: post
title: "ReactNative Android自定义NativeModule"
description: "ReactNative Java NativeModule"
category: all-about-tech
tags: -[react-native, hybrid]
date: 2019-08-15 16:44:57+00:00
---

> com.facebook.react:react-native:0.60.4

## 创建NativeModule

```java
@ReactModule(name = AndroidLogcat.NAME)
public class AndroidLogcat extends ContextBaseJavaModule {
    public static final String NAME = "AndroidLogcat";

    public AndroidLogcat(Context context) {
        super(context);
    }

    @Override
    public String getName() {
        return NAME;
    }

    @ReactMethod
    public void log(String name) {
        Log.d(getName(), "log >>> " + name);
    }
}
```

如上创建了一个叫做“AndroidLogcat”的自定义模块，其中getName的返回值是js中直接调用当前模块的模块名。

需要在class上面添加@ReactModule的注解，并在其中设定name字段。

@ReactModule是RNA中用于标注NativeModule的注解。提供了设定name以及isCxxModule等接口。解析过程示例如下：

```java
// ReactAndroid/src/main/java/com/facebook/react/CoreModulesPackage.java
  public ReactModuleInfoProvider getReactModuleInfoProvider() {
    try {
      Class<?> reactModuleInfoProviderClass =
          Class.forName("com.facebook.react.CoreModulesPackage$$ReactModuleInfoProvider");
      return (ReactModuleInfoProvider) reactModuleInfoProviderClass.newInstance();
    } catch (ClassNotFoundException e) {
      // In OSS case, the annotation processor does not run. We fall back on creating this byhand
      Class<? extends NativeModule>[] moduleList =
          new Class[] {
            AndroidInfoModule.class,
            DeviceEventManagerModule.class,
            DeviceInfoModule.class,
            ExceptionsManagerModule.class,
            HeadlessJsTaskSupportModule.class,
            SourceCodeModule.class,
            Timing.class,
            UIManagerModule.class
          };

      final Map<String, ReactModuleInfo> reactModuleInfoMap = new HashMap<>();
      for (Class<? extends NativeModule> moduleClass : moduleList) {
        ReactModule reactModule = moduleClass.getAnnotation(ReactModule.class);

        reactModuleInfoMap.put(
            reactModule.name(),
            new ReactModuleInfo(
                reactModule.name(),
                moduleClass.getName(),
                reactModule.canOverrideExistingModule(),
                reactModule.needsEagerInit(),
                reactModule.hasConstants(),
                reactModule.isCxxModule(),
                false));
      }

      return new ReactModuleInfoProvider() {
        @Override
        public Map<String, ReactModuleInfo> getReactModuleInfos() {
          return reactModuleInfoMap;
        }
      };
    // ...
  }
```

#### 注意

自定义模块中对js层暴露的函数，一定需要添加@ReactMethod注解。作用是，告知RNA这个接口是需要暴露给js。否则js将无法访问到这个接口。

RNA中对于@ReactMethod的解析过程如下：

```java
  private void findMethods() {
    // ...
    Method[] targetMethods = classForMethods.getDeclaredMethods();
    for (Method targetMethod : targetMethods) {
      ReactMethod annotation = targetMethod.getAnnotation(ReactMethod.class);
      if (annotation != null) {
        String methodName = targetMethod.getName();
        if (methodNames.contains(methodName)) {
          throw new IllegalArgumentException("Java Module " + getName() + " method name already registered: " + methodName);
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
  }
```

## 自定义一个ReactPackage

熟悉RNA启动过程可知，RNA中所有的NativeModule都是以RactPackage为组在ReactNativeHost中注册的。因此，还需要两件事：

- 创建一个Package

- 将新的ReactPackage加入到ReactNativeHost

#### 自定义Package

集成自ReactPackage即可。

```java
@ReactModuleList(nativeModules = {
        AndroidLogcat.class
})
public class TestReactPackage implements ReactPackage {

    @Override
    public List<NativeModule> createNativeModules(@Nonnull ReactApplicationContext reactContext) {
        return Arrays.<NativeModule>asList(new AndroidLogcat(reactContext));
    }

    @Override
    public List<ViewManager> createViewManagers(@Nonnull ReactApplicationContext reactContext) {
        return Collections.emptyList();
    }
}
```

在抽象函数createNativeModules中返回的列表添加刚才创建的`AndroidLogcat`即可。

#### 注册自定义ReactPackage

在ReactNativeHost的getPackages中添加新建的模块：

```java
  private final ReactNativeHost mReactNativeHost = new ReactNativeHost(this) {
    @Override
    public boolean getUseDeveloperSupport() {
      return BuildConfig.DEBUG;
    }

    @Override
    protected List<ReactPackage> getPackages() {
      return Arrays.<ReactPackage>asList(
          new MainReactPackage(), new TestReactPackage()
      );
    }

    @Override
    protected String getJSMainModuleName() {
      return "index";
    }
  };
```

## 在JS代码中使用自定义NativeModule

注意，上面NativeModule的getName返回值为：“AndroidLogcat”。因此在js中可以直接通过NativeModules.AndroidLogcat即可调用，如下：

```js
import {NativeModules} from 'react-native';

NativeModules.AndroidLogcat.log('Hello from index.js');
```

效果图：

 [![rn-native2js-sample-native-module-androidlogcat.png](https://t.cn/AiHKWFzw)](https://j.mp/2KimavX)
