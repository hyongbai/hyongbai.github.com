---
layout: post
title: "Android系统的启动过程"
description: "Android系统的启动过程"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-03-20 19:03:57+00:00
---

> 基于 android-8.1.0_r60
>
> 为求简洁，代码已删除大量细枝末节。

关键词：init/zygote/system_server/SystemUI/Launcher

## init

> 这里没有设计init进程是如何被启动的。
> 所有init.rc文件都在设备的根目录`/`下面。这里列出aosp源码的目录。

```sh
// system/core/rootdir/init.rc
# Copyright (C) 2012 The Android Open Source Project
#
# IMPORTANT: Do not create world writable files or directories.
# This is a common source of Android security bugs.
#

import /init.environ.rc
import /init.usb.rc
import /init.${ro.hardware}.rc
import /vendor/etc/init/hw/init.${ro.hardware}.rc
import /init.usb.configfs.rc
import /init.${ro.zygote}.rc

...

on property:ro.debuggable=1
    # Give writes to anyone for the trace folder on debug builds.
    # The folder is used to store method traces.
    chmod 0773 /data/misc/trace
    start console

service flash_recovery /system/bin/install-recovery.sh
    class main
    oneshot
```

[>>> system/core/rootdir/init.rc源码传送门 <<<](https://j.mp/3dff6fX)

其中`${ro.hardware}`和`${ro.zygote}`分别表示当前的设备代号以及使用默认平台。都是系统属性(参数)。可以通过getprop获取:

> 以安装了Android8.1的Nexus 5x为例

```sh
➜  ~ adb shell getprop | egrep 'ro\.(hardware|zygote)'
[ro.hardware]: [bullhead]
[ro.zygote]: [zygote64_32]
```

其中`zygote64_32`猜测是当前系统为64位架构，需要兼容32位。因此是64在前32在后。这两个其实对应的是两个zygote进程，如下：

```sh
➜  ~ adb shell ps | egrep 'zygote|zygote64'
USER PID PPID   VSZ      RSS   WCHAN    ADDR S NAME
root 1   0      68536    6772  0        0 S init
root 773 1      5466964  38660 0        0 S zygote64
root 774 1      1788116  27928 0        0 S zygote
```

### # init.zygote64_32.rc

以zygote64_32为例：

```sh
// system/core/rootdir/init.zygote64_32.rc
service zygote /system/bin/app_process64 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote
    class main
    priority -20
    user root
    group root readproc
    socket zygote stream 660 root system
    onrestart write /sys/android_power/request_state wake
    onrestart write /sys/power/state on
    onrestart restart audioserver
    onrestart restart cameraserver
    onrestart restart media
    onrestart restart netd
    onrestart restart wificond
    writepid /dev/cpuset/foreground/tasks

service zygote_secondary /system/bin/app_process32 -Xzygote /system/bin --zygote --socket-name=zygote_secondary --enable-lazy-preload
    class main
    priority -20
    user root
    group root readproc
    socket zygote_secondary stream 660 root system
    onrestart restart zygote
    writepid /dev/cpuset/foreground/tasks
```

这里分别创建了两个进程，对应的就是`zygote64`和`zygote`。都是调用`app_process`命令传入相应参数启动的。

### # 所有的init.${ro.zygote}.rc文件

这里列出所有的init.${ro.zygote}.rc文件，用于对比。

- system/core/rootdir/init.zygote64_32.rc

```sh
service zygote_secondary /system/bin/app_process64 -Xzygote /system/bin --zygote --socket-name=zygote_secondary
...
service zygote /system/bin/app_process32 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote
...
```

- system/core/rootdir/init.zygote32_64.rc

```sh
service zygote /system/bin/app_process32 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote
...
service zygote_secondary /system/bin/app_process64 -Xzygote /system/bin --zygote --socket-name=zygote_secondary
...
```

- system/core/rootdir/init.zygote64.rc

```sh
service zygote_secondary /system/bin/app_process64 -Xzygote /system/bin --zygote --socket-name=zygote_secondary
...
```

- system/core/rootdir/init.zygote32.rc

```sh
service zygote /system/bin/app_process32 -Xzygote /system/bin --zygote --start-system-server --socket-name=zygote
...
```

可以看到这个文件的名称表示了对应启动zygote进程的顺序。

## 启动Zygote(32/64)进程

app_process用法：

```sh
Usage: app_process [java-options] cmd-dir start-class-name [options]
```

看看app_process是如何处理:

```cpp
// frameworks/base/cmds/app_process/app_main.cpp
int main(int argc, char* const argv[])
{
    ...
    AppRuntime runtime(argv[0], computeArgBlockSize(argc, argv));
    // ignore argv[0]
    argc--;
    argv++;
    ...
    // Parse runtime arguments.  Stop at first unrecognized option.
    bool zygote = false;
    bool startSystemServer = false;
    bool application = false;
    String8 niceName;
    String8 className;

    ++i;  // Skip unused "parent dir" argument.
    while (i < argc) {
        const char* arg = argv[i++];
        if (strcmp(arg, "--zygote") == 0) {
            zygote = true;
            niceName = ZYGOTE_NICE_NAME;
        } else if (strcmp(arg, "--start-system-server") == 0) {
            startSystemServer = true;
        } else if (strcmp(arg, "--application") == 0) {
            application = true;
        } else if (strncmp(arg, "--nice-name=", 12) == 0) {
            niceName.setTo(arg + 12);
        } else if (strncmp(arg, "--", 2) != 0) {
            className.setTo(arg);
            break;
        } else {
            --i;
            break;
        }
    }

    Vector<String8> args;
    if (!className.isEmpty()) {
        ...
        args.add(application ? String8("application") : String8("tool"));
        runtime.setClassNameAndArgs(className, argc - i, argv + i);
        ...
    } else {
        // We're in zygote mode.
        maybeCreateDalvikCache();

        if (startSystemServer) {
            args.add(String8("start-system-server"));
        }

        char prop[PROP_VALUE_MAX];
        if (property_get(ABI_LIST_PROPERTY, prop, NULL) == 0) {
            return 11;
        }

        String8 abiFlag("--abi-list=");
        abiFlag.append(prop);
        args.add(abiFlag);

        // In zygote mode, pass all remaining arguments to the zygote
        // main() method.
        for (; i < argc; ++i) {
            args.add(String8(argv[i]));
        }
    }

    if (!niceName.isEmpty()) {
        runtime.setArgv0(niceName.string(), true /* setProcName */);
    }

    if (zygote) {
        runtime.start("com.android.internal.os.ZygoteInit", args, zygote);
    } else if (className) {
        runtime.start("com.android.internal.os.RuntimeInit", args, zygote);
    }
}
```

这里有一些解析参数的过程，总结下来其中：

- `--zygote` 表示使用zygote孵化进程。
- `--start-system-server` 表示启动(使用zygote孵化)system_server进程
- `--socket-name` 表示Zygote进程内部对应的socket通信的名称。用于`AMS`启动进程`startProcessLock`时ZygoteProcess向ZygoteInit发送消息时使用。
- `--{ClassName}`表示ClassName，即直接运行某个类的main函数。

最后调用AppRuntime(AndroidRuntime的子类)的start函数，并将解析好的参数传递，启动AndroidRuntime。

其中init.rc设定了zygote标识，因此使用的下面的语句:

```cpp
// frameworks/base/cmds/app_process/app_main.cpp
runtime.start("com.android.internal.os.ZygoteInit", args, zygote);
```

注意：从上面`init.zygote64_32.rc`源码可以看到，只有第一个zygote进程才会孵化出system_server进程。这里的system_server进程的父进程就是zygote64(上面的ps信息也能看出来)。


### # AppRuntime

到这里就开始启动Zygote进程的Runtime了。

```cpp
// frameworks/base/core/jni/AndroidRuntime.cpp
/*
 * Start the Android runtime.  This involves starting the virtual machine
 * and calling the "static void main(String[] args)" method in the class
 * named by "className".
 *
 * Passes the main function two arguments, the class name and the specified
 * options string.
 */
void AndroidRuntime::start(const char* className, const Vector<String8>& options, bool zygote)
{
    ...
    const char* rootDir = getenv("ANDROID_ROOT");
    ...
    /* start the virtual machine */
    JniInvocation jni_invocation;
    jni_invocation.Init(NULL);
    JNIEnv* env;
    if (startVm(&mJavaVM, &env, zygote) != 0) {
        return;
    }
    onVmCreated(env);
    ...
    jclass stringClass;
    jobjectArray strArray;
    jstring classNameStr;

    stringClass = env->FindClass("java/lang/String");
    strArray = env->NewObjectArray(options.size() + 1, stringClass, NULL);
    classNameStr = env->NewStringUTF(className);
    env->SetObjectArrayElement(strArray, 0, classNameStr);

    for (size_t i = 0; i < options.size(); ++i) {
        jstring optionsStr = env->NewStringUTF(options.itemAt(i).string());
        env->SetObjectArrayElement(strArray, i + 1, optionsStr);
    }

    /*
     * Start VM.  This thread becomes the main thread of the VM, and will
     * not return until the VM exits.
     */
    char* slashClassName = toSlashClassName(className != NULL ? className : "");
    jclass startClass = env->FindClass(slashClassName);
    if (startClass == NULL) {
    } else {
        jmethodID startMeth = env->GetStaticMethodID(startClass, "main",
            "([Ljava/lang/String;)V");
        env->CallStaticVoidMethod(startClass, startMeth, strArray);
    }
    free(slashClassName);

    ALOGD("Shutting down VM\n");
    if (mJavaVM->DetachCurrentThread() != JNI_OK)
        ALOGW("Warning: unable to detach main thread\n");
    if (mJavaVM->DestroyJavaVM() != 0)
        ALOGW("Warning: VM did not shut down cleanly\n");
}
```

这里分为两一个部分：

第一个部分通过startVm启动VM，实例化真正的Runtime并启动一系列初始化，比如启动(java.lang.Daemons/Trace等等)。这部分展开大概要一周以上，略过。

第二部分为调用startClass的main函数。这里的startClass主要就是com.android.internal.os.ZygoteInit。其中args包含`start-system-server`。

最后如果JAVA层运行结束直接销毁AndroidRuntime(Runtime)。

### # ZygoteInit

```java
// frameworks/base/core/java/com/android/internal/os/ZygoteInit.java
public static void main(String argv[]) {
    ZygoteServer zygoteServer = new ZygoteServer();
    ...
    final Runnable caller;
    try {
        ...
        RuntimeInit.enableDdms();
        boolean startSystemServer = false;
        String socketName = "zygote";
        String abiList = null;
        boolean enableLazyPreload = false;
        for (int i = 1; i < argv.length; i++) {
            if ("start-system-server".equals(argv[i])) {
                startSystemServer = true;
            } else if ("--enable-lazy-preload".equals(argv[i])) {
                enableLazyPreload = true;
            } else if (argv[i].startsWith(ABI_LIST_ARG)) {
                abiList = argv[i].substring(ABI_LIST_ARG.length());
            } else if (argv[i].startsWith(SOCKET_NAME_ARG)) {
                socketName = argv[i].substring(SOCKET_NAME_ARG.length());
            } else {
                throw new RuntimeException("Unknown command line argument: " + argv[i]);
            }
        }
        ...
        zygoteServer.registerServerSocket(socketName);
        if (!enableLazyPreload) {
            preload(bootTimingsTraceLog);
        } else {
            Zygote.resetNicePriority();
        }
       ...
        if (startSystemServer) {
            Runnable r = forkSystemServer(abiList, socketName, zygoteServer);
            if (r != null) {
                r.run();
                return;
            }
        }
        caller = zygoteServer.runSelectLoop(abiList);
    } catch (Throwable ex) {
        Log.e(TAG, "System zygote died with exception", ex);
        throw ex;
    } finally {
        zygoteServer.closeServerSocket();
    }
    if (caller != null) {
        caller.run();
    }
}
```

这里首先解析数据。关键是socketName/startSystemServer等等。

#### - registerServerSocket

并且这里会通过registerServerSocket创建一个ServerSocket。用于接收AMS发送过来的Socket信息，从而fork新进程并启动App。

- 如果是startSystemServer则进入创建SystemServer的逻辑。

- 否则通过zygoteServer创建一个loop，不断接收来自Client的消息。

#### - preload

同时，其中的`preload()`函数则包含了一系列预加载的逻辑：

- preloadClasses()
- preloadResources()
- nativePreloadAppProcessHALs()
- preloadOpenGL()
- preloadSharedLibraries()
- preloadTextResources()

其中`preloadClasses()`会去`/system/etc/preloaded-classes`文件读取其全部内容，并一一将其Class载入到内存当中。

这样，在子进程被fork完之后，这些预加载的内容则可以直接被使用了。

> [预加载类列表: frameworks/base/config/preloaded-classes](https://j.mp/2wpECyE)

#### - MethodAndArgsCaller

注意：不论是fork出system_server还是子进程。当前逻辑(这一个语句)都会同时运行在当前进程和其子进程。linux系统在fork之后，会根据父子进程返回不同的pid。

- 如果拿到的pid为0，则表示当前是子进程。这时子进程里面会返回一个run，用于子进程后面的逻辑。主要是一个`RuntimeInit$MethodAndArgsCaller`对象。
- 如果拿到是pid不为0，则表示当前是父进程。Server Socket会将当前的pid等信息::send给Client Socket(ZygoteProcess)。

> 如何记忆pid对应什么进程其实非常好记。你只要记住一点，父进程需要知道子进程的pid用于后续处理。所以，pid不为0就一定是父进程。

### # forkSystemServer

下面来看看system_server进程如何被fork:

```java
// frameworks/base/core/java/com/android/internal/os/ZygoteInit.java
private static Runnable forkSystemServer(String abiList, String socketName,
        ZygoteServer zygoteServer) {
    long capabilities = posixCapabilitiesAsBits(
        OsConstants.CAP_IPC_LOCK,
        OsConstants.CAP_KILL,
        OsConstants.CAP_NET_ADMIN,
        OsConstants.CAP_NET_BIND_SERVICE,
        OsConstants.CAP_NET_BROADCAST,
        OsConstants.CAP_NET_RAW,
        OsConstants.CAP_SYS_MODULE,
        OsConstants.CAP_SYS_NICE,
        OsConstants.CAP_SYS_PTRACE,
        OsConstants.CAP_SYS_TIME,
        OsConstants.CAP_SYS_TTY_CONFIG,
        OsConstants.CAP_WAKE_ALARM
    );
    /* Containers run without this capability, so avoid setting it in that case */
    if (!SystemProperties.getBoolean(PROPERTY_RUNNING_IN_CONTAINER, false)) {
        capabilities |= posixCapabilitiesAsBits(OsConstants.CAP_BLOCK_SUSPEND);
    }
    /* Hardcoded command line to start the system server */
    String args[] = {
        "--setuid=1000",
        "--setgid=1000",
        "--setgroups=1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1018,1021,1023,1032,3001,3002,3003,3006,3007,3009,3010",
        "--capabilities=" + capabilities + "," + capabilities,
        "--nice-name=system_server",
        "--runtime-args",
        "com.android.server.SystemServer",
    };
    ZygoteConnection.Arguments parsedArgs = null;

    int pid;

    try {
        parsedArgs = new ZygoteConnection.Arguments(args);
        ZygoteConnection.applyDebuggerSystemProperty(parsedArgs);
        ZygoteConnection.applyInvokeWithSystemProperty(parsedArgs);

        /* Request to fork the system server process */
        pid = Zygote.forkSystemServer(
                parsedArgs.uid, parsedArgs.gid,
                parsedArgs.gids,
                parsedArgs.debugFlags,
                null,
                parsedArgs.permittedCapabilities,
                parsedArgs.effectiveCapabilities);
    } catch (IllegalArgumentException ex) {
        throw new RuntimeException(ex);
    }

    /* For child process */
    if (pid == 0) {
        if (hasSecondZygote(abiList)) {
            waitForSecondaryZygote(socketName);
        }

        zygoteServer.closeServerSocket();
        return handleSystemServerProcess(parsedArgs);
    }

    return null;
}
```

注意：

生成的args最后一行就是startClass：即`com.android.server.SystemServer`。


- applyDebuggerSystemProperty: 用于是否可以给system_server开启debug。`getprop ro.debuggable`，可以在/default.prop文件中修改(未成功)。
- Zygote.forkSystemServer: 真正fork进程的地方。
- handleSystemServerProcess：返回MethodAndArgsCaller实例化`SystemServer.java`。


最后回到这里：

```java
// frameworks/base/core/java/com/android/internal/os/ZygoteInit.java
Runnable r = forkSystemServer(abiList, socketName, zygoteServer);
if (r != null) {
    r.run();
    return;
}
```

运行MethodAndArgsCaller的run函数:

```java
// frameworks/base/core/java/com/android/internal/os/RuntimeInit$MethodAndArgsCaller.java
public void run() {
    try {
        mMethod.invoke(null, new Object[] { mArgs });
    } catch (IllegalAccessException ex) {
        throw new RuntimeException(ex);
    } catch (InvocationTargetException ex) {
        Throwable cause = ex.getCause();
        if (cause instanceof RuntimeException) {
            throw (RuntimeException) cause;
        } else if (cause instanceof Error) {
            throw (Error) cause;
        }
        throw new RuntimeException(ex);
    }
}
```

其中的mMethod就是startClass的main函数。

### # fork子进程

同forkSystemServer类似。不同点在于:

- 接受AMS消息的地方在zygoteServer.runSelectLoop里面。不是由app_process向main函数直接传递过来的。

- App的进程默认的startClass都是`android.app.ActivityThread`类。通过这个类跑到Application/Service/Activity/Provider等。

## 启动SystemServer

上面提到forkSystemServer最后是运行SystemServer的main函数:

```
// frameworks/base/services/java/com/android/server/SystemServer.java
public static void main(String[] args) {
    new SystemServer().run();
}
```

> SystemServer牛逼到在`frameworks/base/services`中，单独有个java目录，里面只有SystemServer这个类。而其他类都在`frameworks/base/services`下面的core/jva中。


### # SystemServer.run

```java
// frameworks/base/services/java/com/android/server/SystemServer.java
private void run() {
    try {
        ...
        Looper.prepareMainLooper();

        // Initialize native services.
        System.loadLibrary("android_servers");

        // Check whether we failed to shut down last time we tried.
        // This call may not return.
        performPendingShutdown();

        // Initialize the system context.
        createSystemContext();

        // Create the system service manager.
        mSystemServiceManager = new SystemServiceManager(mSystemContext);
        mSystemServiceManager.setRuntimeRestarted(mRuntimeRestart);
        LocalServices.addService(SystemServiceManager.class, mSystemServiceManager);
        // Prepare the thread pool for init tasks that can be parallelized
        SystemServerInitThreadPool.get();
    } finally {
        traceEnd();  // InitBeforeStartServices
    }

    // Start services.
    try {
        traceBeginAndSlog("StartServices");
        startBootstrapServices();
        startCoreServices();
        startOtherServices();
        SystemServerInitThreadPool.shutdown();
    }
    ...
    // Loop forever.
    Looper.loop();
    throw new RuntimeException("Main thread loop unexpectedly exited");
}
```

此时会先prepareLooper，以便后续启动的Service中使用Handler。比如AMS的UIHandler等。

之后loader对应的native代码，即android_servers这个库。

之后调用`startBootstrapServices()` `startCoreServices()` `startOtherServices()`分别启动各种系统的Service。

最后进行loop，让整个进程继续执行。否则底层在AndroidRuntime中就要释放vm了。

### # 启动SystemServices

#### - startBootstrapServices

用于启动非常重要的系统级别的SystemServices。

比如：

- ActivityManagerService
- PowerManagerService
- LightsService
- DisplayManagerService
- PackageManagerService

#### - startCoreServices

- BatteryService
- UsageStatsService

#### - startOtherServices

- AccountManagerService
- AlarmManagerService
- InputManagerService
- WindowManagerService
- AccessibilityManagerService
- LocationManagerService
- WallpaperManagerService
- **SystemUI**

可以看到System是在基本上所有的Service启动之后才会启动的。虽然列在这里，但是SystemUI跟其他SystemService不太一样，它完完全全是一个完整的app。

### # systemReady

在startOtherServices的最后阶段会调用各个Service告知systemReady。其中最后一个是AMS。调用如下:

```java
// frameworks/base/services/java/com/android/server/SystemServer.java
private void startOtherServices() {
    ...
    mActivityManagerService.systemReady(() -> {
        mSystemServiceManager.startBootPhase(
                SystemService.PHASE_ACTIVITY_MANAGER_READY);
        try {
            mActivityManagerService.startObservingNativeCrashes();
        } catch (Throwable e) {
        }
        ...
        try {
            startSystemUi(context, windowManagerF);
        } catch (Throwable e) {
        }
        ...
    }, BOOT_TIMINGS_TRACE_LOG);
}
```

上面的callback会在AMS启动Launcher之前被回调到。因此到这里就是正常启动各种UI界面的逻辑了。

## 启动UI

先来看看，在启动Launcher之前，zygote进程到底fork了多少个子进程出来。

```log
USER           PID  PPID     VSZ    RSS WCHAN            ADDR S NAME
root          3291     1 4227404  62776 poll_schedule_timeout 0 S zygote64
system        3737  3291 4659372 271100 SyS_epoll_wait      0 S system_server
bluetooth     4008  3291 4356608  55408 SyS_epoll_wait      0 S com.android.bluetooth
u0_a42        4065  3291 4474600 143560 SyS_epoll_wait      0 S com.android.systemui
radio         4227  3291 4358484  68404 SyS_epoll_wait      0 S com.android.phone
u0_a19        4649  3291 4579476 176252 SyS_epoll_wait      0 S com.google.android.gms.persistent
u0_a19        6746  3291 4308280  39596 SyS_epoll_wait      0 S com.google.process.gservices
u0_a48        6763  3291 4426896  62524 SyS_epoll_wait      0 S com.google.android.googlequicksearchbox:interactor
system        6777  3291 4305780  39808 SyS_epoll_wait      0 S com.quicinc.cne.CNEService
nfc           6790  3291 4336104  50232 SyS_epoll_wait      0 S com.android.nfc
radio         6795  3291 4300484  34416 SyS_epoll_wait      0 S com.qualcomm.qti.rcsbootstraputil
radio         6813  3291 4299584  32520 SyS_epoll_wait      0 S com.qualcomm.qti.rcsimsbootstraputil
u0_a48        6880  3291 4491440  99936 SyS_epoll_wait      0 S com.google.android.googlequicksearchbox
```

> 其中`com.google.android.googlequicksearchbox`就是Nexus手机默认的Launcher。

可以看到在system_server启动之后紧接着启动了bluetooth进程，之后的是SystemUI以及phone还有nfc等等，最后是Launcher。

此时用户就可以正常把玩手机了。

无论是SystemUI还是Launcher都会通过AMS，最后AMS发现对应进程并没有起动。其实会调用其内部的`startProcessLocked`最后进入ZygoteProcess中创建client并同Zygote进程通信(就是上面的一坨)。

### # 启动SystemUI

通过SystemServer的startSystemUi函数开始的。

```java
// frameworks/base/services/java/com/android/server/SystemServer.java
static final void startSystemUi(Context context, WindowManagerService windowManager) {
    Intent intent = new Intent();
    intent.setComponent(new ComponentName("com.android.systemui",
                "com.android.systemui.SystemUIService"));
    intent.addFlags(Intent.FLAG_DEBUG_TRIAGED_MISSING);
    //Slog.d(TAG, "Starting service: " + intent);
    context.startServiceAsUser(intent, UserHandle.SYSTEM);
    windowManager.onSystemUiStarted();
}
```

SystemUIService.java在源码中的位置为:

```
frameworks/base/packages/SystemUI/src/com/android/systemui/SystemUIService.java
```

#### - SystemUIService

可以看到这就已经是一个完整的package了：

```java
// frameworks/base/packages/SystemUI/src/com/android/systemui/SystemUIService.java
public class SystemUIService extends Service {

    @Override
    public void onCreate() {
        super.onCreate();
        ((SystemUIApplication) getApplication()).startServicesIfNeeded();

        // For debugging RescueParty
        if (Build.IS_DEBUGGABLE && SystemProperties.getBoolean("debug.crash_sysui", false)) {
            throw new RuntimeException();
        }
    }
}
```

可以看到这里的启动过程还是交给SystemUIApplication来处理的：

```java
// frameworks/base/packages/SystemUI/src/com/android/systemui/SystemUIApplication.java
/**
 * The classes of the stuff to start.
 */
private final Class<?>[] SERVICES = new Class[] {
        Dependency.class,
        NotificationChannels.class,
        CommandQueue.CommandQueueStart.class,
        KeyguardViewMediator.class,
        Recents.class,
        VolumeUI.class,
        Divider.class,
        SystemBars.class,
        StorageNotification.class,
        PowerUI.class,
        RingtonePlayer.class,
        KeyboardUI.class,
        PipUI.class,
        ShortcutKeyDispatcher.class,
        VendorServices.class,
        GarbageMonitor.Service.class,
        LatencyTester.class,
        GlobalActionsComponent.class,
        RoundedCorners.class,
};

public void startServicesIfNeeded() {
    startServicesIfNeeded(SERVICES);
}
```

这些类都继承自`com.android.systemui.System`这个类。

可以看到SystemUIApplication其中了一组Service。包括StatusBar/VolumeUI/Notification等等。

#### - SystemUIApplication

下面来看看startServicesIfNeeded是如何其中这一系列的SystemUI的:

```java
// frameworks/base/packages/SystemUI/src/com/android/systemui/SystemUIApplication.java
private void startServicesIfNeeded(Class<?>[] services) {
    ...
    final int N = services.length;
    for (int i = 0; i < N; i++) {
        Class<?> cl = services[i];
        long ti = System.currentTimeMillis();
        try {
            Object newService = SystemUIFactory.getInstance().createInstance(cl);
            mServices[i] = (SystemUI) ((newService == null) ? cl.newInstance() : newService);
        }

        mServices[i].mContext = this;
        mServices[i].mComponents = mComponents;
        mServices[i].start();

        // Warn if initialization of component takes too long
        ti = System.currentTimeMillis() - ti;
        if (ti > 1000) {
            Log.w(TAG, "Initialization of " + cl.getName() + " took " + ti + " ms");
        }
        if (mBootCompleted) {
            mServices[i].onBootCompleted();
        }
    }
    Dependency.get(PluginManager.class).addPluginListener(
            new PluginListener<OverlayPlugin>() {
                private ArraySet<OverlayPlugin> mOverlays;

                @Override
                public void onPluginConnected(OverlayPlugin plugin, Context pluginContext) {
                    StatusBar statusBar = getComponent(StatusBar.class);
                    if (statusBar != null) {
                        plugin.setup(statusBar.getStatusBarWindow(),
                                statusBar.getNavigationBarView());
                    }
                    // Lazy init.
                    if (mOverlays == null) mOverlays = new ArraySet<>();
                    if (plugin.holdStatusBarOpen()) {
                        mOverlays.add(plugin);
                        Dependency.get(StatusBarWindowManager.class).setStateListener(b ->
                                mOverlays.forEach(o -> o.setCollapseDesired(b)));
                        Dependency.get(StatusBarWindowManager.class).setForcePluginOpen(
                                mOverlays.size() != 0);

                    }
                }
            }, OverlayPlugin.class, true /* Allow multiple plugins */);

    mServicesStarted = true;
}
```

可以看到启动过程比较简单(抽象)：

- 遍历整个列表，使用SystemUIFactory实例化每一个类。将其加入`mServices`数组，并调用其start方法。
- 如果单个SystemUI启动超过1000ms则会将其暴尸。最后调用`onBootCompleted`表示启动完成。
- 从Dependency中获取PluginManager实例并向其注册监听。当新OverlayPlugin注册进来时可以配合StatusBar等进行UI的适配。

> PluginManager逻辑略。

注意：

在SystemUIApplication运行时，会创建如下SystemUI:

```java
private final Class<?>[] SERVICES_PER_USER = new Class[] {
        Dependency.class,
        NotificationChannels.class,
        Recents.class
};
```

其中的Recents就是最近任务列表。

下面来看看SystemBars是如何启动的。

#### - SystemUI之SystemBars启动过程

SystemBars其实只是一个套着另一个`SystemUI`的壳子：

```java
public class SystemBars extends SystemUI {
    private static final String TAG = "SystemBars";
    private static final boolean DEBUG = false;
    private static final int WAIT_FOR_BARS_TO_DIE = 500;

    // in-process fallback implementation, per the product config
    private SystemUI mStatusBar;

    @Override
    public void start() {
        createStatusBarFromConfig();
    }

    private void createStatusBarFromConfig() {
        final String clsName = mContext.getString(R.string.config_statusBarComponent);
        Class<?> cls = null;
        try {
            cls = mContext.getClassLoader().loadClass(clsName);
        }
        try {
            mStatusBar = (SystemUI) cls.newInstance();
        }
        mStatusBar.mContext = mContext;
        mStatusBar.mComponents = mComponents;
        mStatusBar.start();
    }
}
```

这个内部的mStatusBar才是正在的SystemBar。

config_statusBarComponent的值其实`com.android.systemui.statusbar.phone.StatusBar`这个类如下：


```xml
// frameworks/base/packages/SystemUI/res/values/config.xml
<!-- Component to be used as the status bar service.  Must implement the IStatusBar
 interface.  This name is in the ComponentName flattened format (package/class)  -->
<string name="config_statusBarComponent" translatable="false">com.android.systemui.statusbar.phone.StatusBar</string>
```

```java
// frameworks/base/packages/SystemUI/src/com/android/systemui/statusbar/phone/StatusBar.java
...
```

用过Android手机的开发者都应该知道StatusBar是整个系统的大杂烩。所有的一切这里都有一个坑，所以逻辑多而杂。略过。

> [>>> phone/StatusBar.java源码传送门 <<<](https://j.mp/2whCf0K)
>
> [>>> super_status_bar.xml布局文件源码传送门 <<<](https://j.mp/3beTZsa)
>
> [>>> frameworks/base/packages/SystemUI/res/values/config.xml完整文件传送门 <<<](https://j.mp/3bh9pwm)

注意：config_statusBarComponent的值在不同的设备上面对应是不同的。上面的是手机模式。还有Android TV以及Android Car模式。

```xml
<!--/device/google/atv/overlay/frameworks/base/packages/SystemUI/res/values/config.xml-->
<string name="config_statusBarComponent" translatable="false">com.android.systemui.statusbar.tv.TvStatusBar</string>

<!--/packages/services/Car/car_product/overlay/frameworks/base/packages/SystemUI/res/values/config.xml-->
<string name="config_statusBarComponent" translatable="false">com.android.systemui.statusbar.car.CarStatusBar</string>
```

### # 启动Launcher

启动Launcher是由SystemServer调用AMS的systemReady完成的。

#### - systemReady

函数如下:

```java
// frameworks/base/core/service/java/android/server/am/ActivityManagerService.java
public void systemReady(final Runnable goingCallback, TimingsTraceLog traceLog) {
    traceLog.traceBegin("PhaseActivityManagerReady");
    synchronized(this) {
        if (mSystemReady) {
            if (goingCallback != null) {
                goingCallback.run();
            }
            return;
        }
        ...
        mSystemReady = true;
    }
    ...
    ArrayList<ProcessRecord> procsToKill = null;
    synchronized(mPidsSelfLocked) {
        for (int i=mPidsSelfLocked.size()-1; i>=0; i--) {
            ProcessRecord proc = mPidsSelfLocked.valueAt(i);
            if (!isAllowedWhileBooting(proc.info)){
                if (procsToKill == null) {
                    procsToKill = new ArrayList<ProcessRecord>();
                }
                procsToKill.add(proc);
            }
        }
    }
    synchronized(this) {
        if (procsToKill != null) {
            for (int i=procsToKill.size()-1; i>=0; i--) {
                ProcessRecord proc = procsToKill.get(i);
                removeProcessLocked(proc, true, false, "system update done");
            }
        }
        mProcessesReady = true;
    }
    ...
    retrieveSettings();
    final int currentUserId;
    synchronized (this) {
        currentUserId = mUserController.getCurrentUserIdLocked();
        readGrantedUriPermissionsLocked();
    }

    if (goingCallback != null) goingCallback.run(); // 来自SystemServer
    ...
    mSystemServiceManager.startUser(currentUserId);
    synchronized (this) {
        startPersistentApps(PackageManager.MATCH_DIRECT_BOOT_AWARE);
        mBooting = true;
        if (UserManager.isSplitSystemUser() &&
                Settings.Secure.getInt(mContext.getContentResolver(),
                     Settings.Secure.USER_SETUP_COMPLETE, 0) != 0) {
            ComponentName cName = new ComponentName(mContext, SystemUserHomeActivity.class);
            try {
                AppGlobals.getPackageManager().setComponentEnabledSetting(cName,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED, 0,
                        UserHandle.USER_SYSTEM);
            }
        }
        startHomeActivityLocked(currentUserId, "systemReady");
        ...
        try {
            Intent intent = new Intent(Intent.ACTION_USER_STARTED);
            intent.addFlags(Intent.FLAG_RECEIVER_REGISTERED_ONLY | Intent.FLAG_RECEIVER_FOREGROUND);
            intent.putExtra(Intent.EXTRA_USER_HANDLE, currentUserId);
            broadcastIntentLocked(...);
            intent = new Intent(Intent.ACTION_USER_STARTING);
            intent.addFlags(Intent.FLAG_RECEIVER_REGISTERED_ONLY);
            intent.putExtra(Intent.EXTRA_USER_HANDLE, currentUserId);
            broadcastIntentLocked(...);
        } finally {
            Binder.restoreCallingIdentity(ident);
        }
        mStackSupervisor.resumeFocusedStackTopActivityLocked();
        mUserController.sendUserSwitchBroadcastsLocked(-1, currentUserId);
    }
}
```

可以看到这里有如下逻辑：

- 过滤出不符合isAllowedWhileBooting的进程，并将其杀死。ApplicationInfo不包含FLAG_PERSISTENT标识。
- 回调goingCallback。告知SystemServer启动SystemUI等。
- 最后调用startHomeActivityLocked启动Home(Launcher)。
- 发送ACTION_USER_STARTED和ACTION_USER_STARTING广播。

#### - startHomeActivityLocked

Launcher启动如下:

```java
// frameworks/base/core/service/java/android/server/am/ActivityManagerService.java
Intent getHomeIntent() {
    Intent intent = new Intent(mTopAction, mTopData != null ? Uri.parse(mTopData) : null);
    intent.setComponent(mTopComponent);
    intent.addFlags(Intent.FLAG_DEBUG_TRIAGED_MISSING);
    if (mFactoryTest != FactoryTest.FACTORY_TEST_LOW_LEVEL) {
        intent.addCategory(Intent.CATEGORY_HOME);
    }
    return intent;
}
    
boolean startHomeActivityLocked(int userId, String reason) {
    if (mFactoryTest == FactoryTest.FACTORY_TEST_LOW_LEVEL
            && mTopAction == null) {
        return false;
    }
    Intent intent = getHomeIntent();
    ActivityInfo aInfo = resolveActivityInfo(intent, STOCK_PM_FLAGS, userId);
    if (aInfo != null) {
        intent.setComponent(new ComponentName(aInfo.applicationInfo.packageName, aInfo.name));
        // Don't do this if the home app is currently beinginstrumented.
        aInfo = new ActivityInfo(aInfo);
        aInfo.applicationInfo = getAppInfoForUser(aInfo.applicationInfo, userId);
        ProcessRecord app = getProcessRecordLocked(aInfo.processName,
                aInfo.applicationInfo.uid, true);
        if (app == null || app.instr == null) {
            intent.setFlags(intent.getFlags() | Intent.FLAG_ACTIVITY_NEW_TASK);
            final int resolvedUserId = UserHandle.getUserId(aInfo.applicationInfo.uid);
            // For ANR debugging to verify if the user activity is the one that actuallylaunched.
            final String myReason = reason + ":" + userId + ":" + resolvedUserId;
            mActivityStarter.startHomeActivityLocked(intent, aInfo, myReason);
        }
    } else {
        Slog.wtf(TAG, "No home screen found for " + intent, new Throwable());
    }

    return true;
}
```

可见是使用Intent.CATEGORY_HOME过滤出Launcher的Activity的。

过滤出来之后，会判断当前目标进程是否已经有坑位。如果没有，则表示还没有启动。通过调用ActivityStarter的startHomeActivityLocked函数启动Launcher。

## 总结

- 系统启动时创建init进程。进程id为`1`。
- init进程启动后通过app_process启动 `zygote` (zygote64/zygote32)进程。
- zygote启动时会携带`start-system-server`参数，用于在ZygoteInit中fork一个进程用于启动SystemServer进程。
- 之后ZygoteInit会创建一个loop，不断接收client消息创造自进程。(接收来自AMS的启动指令`startProcessLock`)
- ZygoteInit接收到指令后用Zygote类fork子进程并通过RuntimeInit运行启动类的main函数，比如android.app.ActivityThread运行App逻辑。
- SystemServer在启动之后会启动一系列的Service，最后调用AMS告知systemReady。
- AMS回调SystemServer的goingCallback。此时SystemServer启动SystemUI等。
- 之后AMS启动Launcher。