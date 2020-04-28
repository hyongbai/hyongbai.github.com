---
layout: post
title: "Android ANR 源码分析"
description: "Android ANR 源码分析"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-03-18 19:03:57+00:00
---

> 基于 android-8.1.0_r60
>
> 为求简洁，代码已删除大量细枝末节。

## AppErrors

所有的ANR最终都会调用到AppErrors的appNotResponding中：

```java
// frameworks/base/services/core/java/com/android/server/am/AppErrors.java
final void appNotResponding(ProcessRecord app, ActivityRecord activity,
        ActivityRecord parent, boolean aboveSystem, final String annotation) {
    ...
    // For background ANRs, don't pass the ProcessCpuTracker to
    // avoid spending 1/2 second collecting stats to rank lastPids.
    File tracesFile = ActivityManagerService.dumpStackTraces(
            true, firstPids,
            (isSilentANR) ? null : processCpuTracker,
            (isSilentANR) ? null : lastPids,
            nativePids);
    ...
    synchronized (mService) {
        mService.mBatteryStatsService.noteProcessAnr(app.processName, app.uid);

        if (isSilentANR) {
            app.kill("bg anr", true);
            return;
        }

        // Set the app's notResponding state, and look up the errorReportReceiver
        makeAppNotRespondingLocked(app,
                activity != null ? activity.shortComponentName : null,
                annotation != null ? "ANR " + annotation : "ANR",
                info.toString());

        // Bring up the infamous App Not Responding dialog
        Message msg = Message.obtain();
        HashMap<String, Object> map = new HashMap<String, Object>();
        msg.what = ActivityManagerService.SHOW_NOT_RESPONDING_UI_MSG;
        msg.obj = map;
        msg.arg1 = aboveSystem ? 1 : 0;
        map.put("app", app);
        if (activity != null) {
            map.put("activity", activity);
        }

        mService.mUiHandler.sendMessage(msg);
    }
}
```

这里列出了其中的两个主要行为：

- 调用ANS的dumpStackTraces将当前进程的所有消息dump到/data/anr
- 向AMS的mUiHandler发送一个SHOW_NOT_RESPONDING_UI_MSG的Message用于弹出dialog。

SHOW_NOT_RESPONDING_UI_MSG最后调会到AppErrors的`handleShowAnrUi`函数：

```java
// frameworks/base/services/core/java/com/android/server/am/AppErrors.java
void handleShowAnrUi(Message msg) {
    Dialog d = null;
    synchronized (mService) {
        HashMap<String, Object> data = (HashMap<String, Object>) msg.obj;
        ProcessRecord proc = (ProcessRecord)data.get("app");
        if (proc != null && proc.anrDialog != null) {
            Slog.e(TAG, "App already has anr dialog: " + proc);
            MetricsLogger.action(mContext, MetricsProto.MetricsEvent.ACTION_APP_ANR,
                    AppNotRespondingDialog.ALREADY_SHOWING);
            return;
        }

        Intent intent = new Intent("android.intent.action.ANR");
        if (!mService.mProcessesReady) {
            intent.addFlags(Intent.FLAG_RECEIVER_REGISTERED_ONLY
                    | Intent.FLAG_RECEIVER_FOREGROUND);
        }
        mService.broadcastIntentLocked(null, null, intent,
                null, null, 0, null, null, null, AppOpsManager.OP_NONE,
                null, false, false, MY_PID, Process.SYSTEM_UID, 0 /* TODO: Verify */);

        boolean showBackground = Settings.Secure.getInt(mContext.getContentResolver(),
                Settings.Secure.ANR_SHOW_BACKGROUND, 0) != 0;
        if (mService.canShowErrorDialogs() || showBackground) {
            d = new AppNotRespondingDialog(mService,
                    mContext, proc, (ActivityRecord)data.get("activity"),
                    msg.arg1 != 0);
            proc.anrDialog = d;
        } else {
            MetricsLogger.action(mContext, MetricsProto.MetricsEvent.ACTION_APP_ANR,
                    AppNotRespondingDialog.CANT_SHOW);
            // Just kill the app if there is no dialog to be shown.
            mService.killAppAtUsersRequest(proc, null);
        }
    }
    // If we've created a crash dialog, show it without the lock held
    if (d != null) {
        d.show();
    }
}
```

这里会实例化一个AppNotRespondingDialog并show()。

## Service

调用线路图:

```java
bumpServiceExecutingLocked
 -> scheduleServiceTimeoutLocked
  -> AMS.post(SERVICE_TIMEOUT_MSG)
   -> ActiveServices.serviceTimeout
    -> AppErrors.appNotResponding
```

### # bumpServiceExecutingLocked

这个函数会被很多地方调用。每个调用的地方都对应着Service的一个生命周期:

```java
// frameworks/base/services/core/java/com/android/server/am/ActiveServices.java
private final void bumpServiceExecutingLocked(ServiceRecord r, boolean fg, String why) {
    ...
    long now = SystemClock.uptimeMillis();
    if (r.executeNesting == 0) {
        r.executeFg = fg;
        ServiceState stracker = r.getTracker();
        if (stracker != null) {
            stracker.setExecuting(true, mAm.mProcessStats.getMemFactorLocked(), now);
        }
        if (r.app != null) {
            r.app.executingServices.add(r);
            r.app.execServicesFg |= fg;
            if (r.app.executingServices.size() == 1) {
                scheduleServiceTimeoutLocked(r.app);
            }
        }
    } else if (r.app != null && fg && !r.app.execServicesFg) {
        r.app.execServicesFg = true;
        scheduleServiceTimeoutLocked(r.app);
    }
    r.executeFg |= fg;
    r.executeNesting++;
    r.executingStart = now;
}
```

这里会在ServiceRecord的`executingStart`成员中记录当前的执行时间。同时在这之前会通过`scheduleServiceTimeoutLocked`发送超时消息。

这个函数被调用的地方：

- `requestServiceBindingLocked`: bindService时AMS调用bindServiceLocked至此函数。
- `realStartServiceLocked`：bind/start/restartService时调用bringUpServiceLocked至此函数。
- `sendServiceArgsLocked`：realStartServiceLocked和bringUpServiceLocked都会调用此函数。
- `bringDownServiceLocked`：简单来说就是service被关闭的时候会调用到这里。
- `removeConnectionLocked`：unbind/killService会调用这里。

简单来说就是Service的每个生命周期开始时都会调用到`scheduleServiceTimeoutLocked`用于监听Service运行的时间。

```java
// frameworks/base/services/core/java/com/android/server/am/ActiveServices.java
void scheduleServiceTimeoutLocked(ProcessRecord proc) {
    if (proc.executingServices.size() == 0 || proc.thread == null) {
        return;
    }
    Message msg = mAm.mHandler.obtainMessage(
            ActivityManagerService.SERVICE_TIMEOUT_MSG);
    msg.obj = proc;
    mAm.mHandler.sendMessageDelayed(msg,
            proc.execServicesFg ? SERVICE_TIMEOUT : SERVICE_BACKGROUND_TIMEOUT);
}
```

这个就是通过AMS的UiHandler发送一个延时消息。消息的ID为`SERVICE_TIMEOUT_MSG`，时间为：`SERVICE_TIMEOUT`或者`SERVICE_BACKGROUND_TIMEOUT`。

- `SERVICE_TIMEOUT`为前台Service超时时间: 20秒
- `SERVICE_BACKGROUND_TIMEOUT`为后台Service超时时间: 10个SERVICE_TIMEOUT为200秒。

```java
// services/core/java/com/android/server/am/ActiveServices.java
// How long we wait for a service to finish executing.
static final int SERVICE_TIMEOUT = 20*1000;

// How long we wait for a service to finish executing.
static final int SERVICE_BACKGROUND_TIMEOUT = SERVICE_TIMEOUT * 10;
```

这一步主要是记录`executingService`并发送消息。下面来看ActiveServices是如何处理的。

### # serviceTimeout

```java
// frameworks/base/services/core/java/com/android/server/am/ActiveServices.java
void serviceTimeout(ProcessRecord proc) {
    String anrMessage = null;
    synchronized(mAm) {
        if (proc.executingServices.size() == 0 || proc.thread == null) {
            return;
        }
        final long now = SystemClock.uptimeMillis();
        final long maxTime =  now -
                (proc.execServicesFg ? SERVICE_TIMEOUT : SERVICE_BACKGROUND_TIMEOUT);
        ServiceRecord timeout = null;
        long nextTime = 0;
        for (int i=proc.executingServices.size()-1; i>=0; i--) {
            ServiceRecord sr = proc.executingServices.valueAt(i);
            if (sr.executingStart < maxTime) {
                timeout = sr;
                break;
            }
            if (sr.executingStart > nextTime) {
                nextTime = sr.executingStart;
            }
        }
        if (timeout != null && mAm.mLruProcesses.contains(proc)) {
            Slog.w(TAG, "Timeout executing service: " + timeout);
            // ...
            anrMessage = "executing service " + timeout.shortName;
        } else {
            Message msg = mAm.mHandler.obtainMessage(
                    ActivityManagerService.SERVICE_TIMEOUT_MSG);
            msg.obj = proc;
            mAm.mHandler.sendMessageAtTime(msg, proc.execServicesFg
                    ? (nextTime+SERVICE_TIMEOUT) : (nextTime + SERVICE_BACKGROUND_TIMEOUT));
        }
    }

    if (anrMessage != null) {
        mAm.mAppErrors.appNotResponding(proc, null, null, false, anrMessage);
    }
}
```
简单逻辑就是先post一个delay的runnable，等runnable被执行之后会检测一下本次消息的`executingStart`是不是小于`now - TIMEOUT`之前。

这句话可以这么理解：`executingStart + TIMEOUT < now`，那么换算下来就是说EXECUTION的时间 超过了设定的TIMEOUT了。正常来说，如果当前线程没被堵塞，那么now一定是等于 `executingStart + TIMEOUT` 即`>= executingStart + EXECUTION`的。

如果发现超时，就会调用到AMS中AppErrors变量的`appNotResponding`函数，弹出ANR的Dialog。

## Broadcast

发送广播最终会走到ActivityManagerService的`broadcasatIntentLocker`函数中，最后通过Intent找到相应的BroadcastRecord将其加入到BroadcastQueue之后，调用`scheduleBroadcastsLocked()`发送一个处理广播的Message。

```java
// frameworks/base/services/core/java/com/android/server/am/BroadcastQueue.java
public void scheduleBroadcastsLocked() {
    if (mBroadcastsScheduled) {
        return;
    }
    mHandler.sendMessage(mHandler.obtainMessage(BROADCAST_INTENT_MSG, this));
    mBroadcastsScheduled = true;
}
```

下面来看看BroadcastHandler如何处理。

### # BroadcastHandler

BroadcastHandler主要用于处理用户广播以及处理广播超时(类似于ActiveServices)。

```java
// frameworks/base/services/core/java/com/android/server/am/BroadcastQueue.java
private final class BroadcastHandler extends Handler {
    public BroadcastHandler(Looper looper) {
        super(looper, null, true);
    }

    @Override
    public void handleMessage(Message msg) {
        switch (msg.what) {
            case BROADCAST_INTENT_MSG: {
                if (DEBUG_BROADCAST) Slog.v(
                        TAG_BROADCAST, "Received BROADCAST_INTENT_MSG");
                processNextBroadcast(true);
            } break;
            case BROADCAST_TIMEOUT_MSG: {
                synchronized (mService) {
                    broadcastTimeoutLocked(true);
                }
            } break;
        }
    }
}
```

这里只有两种消息：

- BROADCAST_INTENT_MSG： 处理并发送广播(performReceiveLock)
- BROADCAST_TIMEOUT_MSG：监控广播是否超时。

### # processNextBroadcast

processNextBroadcast用于处理广播。

这里会有两个链表，一个是sticky广播，另一个是正常广播。

> 下面为极简版的代码，sticky广播已忽略。

```java
// frameworks/base/services/core/java/com/android/server/am/BroadcastQueue.java
final void processNextBroadcast(boolean fromMsg) {
    synchronized(mService) {
        BroadcastRecord r;
        ...
        if (fromMsg) {
            mBroadcastsScheduled = false;
        }
        ... // sticky broadcast
        boolean looped = false;
        do {
            if (mOrderedBroadcasts.size() == 0) {
                ...
                return;
            }
            r = mOrderedBroadcasts.get(0);
            boolean forceReceive = false;
            ...
            if (mService.mProcessesReady && r.dispatchTime > 0) {
                long now = SystemClock.uptimeMillis();
                if ((numReceivers > 0) &&  (now > r.dispatchTime + (2*mTimeoutPeriod*numReceivers))) {
                    // 如果当前的时间已超dispatchTime加上2倍receivers数目与mTimeoutPeriod的乘积，则标记为dispatch超时。
                    // 其中dispatchTime为当前这个Intent第一次performRecive时标记。下面的代码会有。
                    broadcastTimeoutLocked(false); // forcibly finish this broadcast
                    forceReceive = true;
                    r.state = BroadcastRecord.IDLE;
                }
            }
            if (r.state != BroadcastRecord.IDLE) {
                return;
            }
            if (r.receivers == null || r.nextReceiver >= numReceivers
                    || r.resultAbort || forceReceive) {
                if (r.resultTo != null) {
                    try {
                        performReceiveLocked(r.callerApp, r.resultTo,
                            new Intent(r.intent), r.resultCode,
                            r.resultData, r.resultExtras, false, false, r.userId);
                        r.resultTo = null;
                    }
                }
                cancelBroadcastTimeoutLocked();
                ...
                mOrderedBroadcasts.remove(0);
                r = null;
                looped = true;
                continue;
            }
        } while (r == null);
        // 当前Receiver在Intent已发送所有目标Receiver的位置。
        int recIdx = r.nextReceiver++;
        r.receiverTime = SystemClock.uptimeMillis();
        if (recIdx == 0) {
        // 为0表示这个Receiver是这个Intent所分发对象的第一个，这里记录分发时间。
            r.dispatchTime = r.receiverTime;
            r.dispatchClockTime = System.currentTimeMillis();
        }
        if (! mPendingBroadcastTimeoutMessage) {
            long timeoutTime = r.receiverTime + mTimeoutPeriod;
            setBroadcastTimeoutLocked(timeoutTime);
        }

        final BroadcastOptions brOptions = r.options;
        final Object nextReceiver = r.receivers.get(recIdx);
        
        // 来自用户注册的广播
        if (nextReceiver instanceof BroadcastFilter) {
            BroadcastFilter filter = (BroadcastFilter)nextReceiver;
            // 发送广播
            deliverToRegisteredReceiverLocked(r, filter, r.ordered, recIdx);
            ...
            return;
        }
        // Hard case: need to instantiate the receiver, possibly starting its application process to host it.
        ...
    }
}
```

每次只会处理一个Receiver，下一次就等待`scheduleBroadcastsLocked()`发送的`BROADCAST_INTENT_MSG`消息(或者其他地方调用...)。

这里主要是两部分逻辑：

#### - dispatch超时

while循环中：如果当前的时间已超dispatchTime加上2倍receivers数目与mTimeoutPeriod的乘积，则标记为超时。

其中dispatchTime为当前这个Intent第一次performRecive时标记。下面的代码会有。

这里如果超时则直接跳过Handler调用`broadcastTimeoutLocked(false)`。注意，这里的参数为false，意为不用再通过`receiverTime`计算是否超时。因为已经**dispatch超时**。

mTimeoutPeriod为AMS实例化BroadcastQueque时传递过来，具体值为：

```java
// frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java
static final int BROADCAST_FG_TIMEOUT = 10*1000;
static final int BROADCAST_BG_TIMEOUT = 60*1000;
```

即：

- BROADCAST_FG_TIMEOUT 前台广播 10秒
- BROADCAST_BG_TIMEOUT 后台广播 60秒

#### - 单条消息超时

其中`deliverToRegisteredReceiverLocked`会performReceiveLock即告知客户端发送广播。

在这之前会记录receiverTime，这个时间往每个Receiver发送消息都会记录。而dispatchTime只会在index为0时才会设置。也就是说receiverTime相对于Receiver而言，用户记录Reciver发送消息的时间；dispatchTime相对于整条广播消息而言(一条广播包含多个Receiver)，记录的是消息初次被处理时的时间。

向BroadcastHandler发送BROADCAST_TIMEOUT_MSG的Message是下面这一句：

```java
// frameworks/base/services/core/java/com/android/server/am/BroadcastQueue.java
long timeoutTime = r.receiverTime + mTimeoutPeriod;
setBroadcastTimeoutLocked(timeoutTime);
```

setBroadcastTimeoutLocked函数：

```java
// frameworks/base/services/core/java/com/android/server/am/BroadcastQueue.java
final void setBroadcastTimeoutLocked(long timeoutTime) {
    if (! mPendingBroadcastTimeoutMessage) {
        Message msg = mHandler.obtainMessage(BROADCAST_TIMEOUT_MSG, this);
        mHandler.sendMessageAtTime(msg, timeoutTime);
        mPendingBroadcastTimeoutMessage = true;
    }
}
```

其中timeoutTime就是receiverTime加上超时时间(mTimeoutPeriod)。

### # broadcastTimeoutLocked

当超时信号执行后，broadcastTimeoutLocked会被调用：

```java
// frameworks/base/services/core/java/com/android/server/am/BroadcastQueue.java
final void broadcastTimeoutLocked(boolean fromMsg) {
    if (fromMsg) {
        mPendingBroadcastTimeoutMessage = false;
    }

    if (mOrderedBroadcasts.size() == 0) {
        return;
    }

    long now = SystemClock.uptimeMillis();
    BroadcastRecord r = mOrderedBroadcasts.get(0);
    if (fromMsg) {
        ...
        long timeoutTime = r.receiverTime + mTimeoutPeriod;
        if (timeoutTime > now) {
            ...
            setBroadcastTimeoutLocked(timeoutTime);
            return;
        }
    }

    BroadcastRecord br = mOrderedBroadcasts.get(0);
    if (br.state == BroadcastRecord.WAITING_SERVICES) {
        ...
        br.curComponent = null;
        br.state = BroadcastRecord.IDLE;
        processNextBroadcast(false);
        return;
    }
    ...
    r.receiverTime = now;
    r.anrCount++;

    ProcessRecord app = null;
    String anrMessage = null;

    Object curReceiver;
    if (r.nextReceiver > 0) {
        curReceiver = r.receivers.get(r.nextReceiver-1);
        r.delivery[r.nextReceiver-1] = BroadcastRecord.DELIVERY_TIMEOUT;
    } else {
        curReceiver = r.curReceiver;
    }
    Slog.w(TAG, "Receiver during timeout of " + r + " : " + curReceiver);
    logBroadcastReceiverDiscardLocked(r);
    if (curReceiver != null && curReceiver instanceof BroadcastFilter) {
        BroadcastFilter bf = (BroadcastFilter)curReceiver;
        if (bf.receiverList.pid != 0
                && bf.receiverList.pid != ActivityManagerService.MY_PID) {
            synchronized (mService.mPidsSelfLocked) {
                app = mService.mPidsSelfLocked.get(
                        bf.receiverList.pid);
            }
        }
    } else {
        app = r.curApp;
    }

    if (app != null) {
        anrMessage = "Broadcast of " + r.intent.toString();
    }

    if (mPendingBroadcast == r) {
        mPendingBroadcast = null;
    }

    // Move on to the next receiver.
    finishReceiverLocked(r, r.resultCode, r.resultData,
            r.resultExtras, r.resultAbort, false);
    scheduleBroadcastsLocked();

    if (anrMessage != null) {
        // Post the ANR to the handler since we do not want to process ANRs while
        // potentially holding our lock.
        mHandler.post(new AppNotResponding(app, anrMessage));
    }
}
```

如果参数fromMsg为true(表示来自BroadcastHandler)，会通过ReceiverTime判断是否超时：`r.receiverTime + mTimeoutPeriod`小于now。即：表示最终超时消息执行时已经被堵塞，所以now会被原定时间大。

当满足条件之后，会根据当前的BroadcastRecord(即mOrderedBroadcasts的第一个)拿到对应的Client的ProcessRecord。之后post一个AppNotResponding消息。

为什么是使用mOrderedBroadcasts的第一个呢？

其实上面的processNextBroadcast已经说了，每次只执行第一个Record的一个Receiver，当所有的Receiver都处理完这条Record才会被移除。

### # AppNotResponding

这里同ActiveServices一样了。如下：

```java
// frameworks/base/services/core/java/com/android/server/am/BroadcastQueue.java
private final class AppNotResponding implements Runnable {
    private final ProcessRecord mApp;
    private final String mAnnotation;

    public AppNotResponding(ProcessRecord app, String annotation) {
        mApp = app;
        mAnnotation = annotation;
    }

    @Override
    public void run() {
        mService.mAppErrors.appNotResponding(mApp, null, null, false, mAnnotation);
    }
}
```

还是调用AppErrors.appNotResponding这个函数，弹出ANR的Dialog。

## Provider

理论上来说provider是允许当前线程做耗时行为的（比如IO）。

但是系统提供了另外一种检测provider的ANR的方法。

只需要在acquireProvider的时候，换成acquireContentProviderClient即可。不过ContentProviderClient不是ContentProvider的子类，它其实只是一个代理类。

```java
// ContentResolver.java
protected abstract IContentProvider acquireProvider(Context c, String name);

    /**
 * Returns a {@link ContentProviderClient} that is associated with the {@link ContentProvider}
 * with the authority of name, starting the provider if necessary. Returns
 * null if there is no provider associated wih the uri. The caller must indicate that they are
 * done with the provider by calling {@link ContentProviderClient#release} which will allow
 * the system to release the provider it it determines that there is no other reason for
 * keeping it active.
 * @param name specifies which provider should be acquired
 * @return a {@link ContentProviderClient} that is associated with the {@link ContentProvider}
 * with the authority of name or null if there isn't one.
 */
public final @Nullable ContentProviderClient acquireContentProviderClient(
        @NonNull String name) {
    Preconditions.checkNotNull(name, "name");
    IContentProvider provider = acquireProvider(name);
    if (provider != null) {
        return new ContentProviderClient(this, provider, true);
    }

    return null;
}
```

### # 接口调用

当通过ContentProviderClient调用ContentProvider的接口时，ContentProviderClient都会插入一对`beforeRemote`和`afterRemote`。用于监听ContentProvider的处理时间：

```java
// frameworks/base/core/java/android/content/ContentProviderClient.java
/** See {@link ContentProvider#insert ContentProvider.insert} */
public @Nullable Uri insert(@NonNull Uri url, @Nullable ContentValues initialValues)
        throws RemoteException {
    Preconditions.checkNotNull(url, "url");
    beforeRemote();
    try {
        return mContentProvider.insert(mPackageName, url, initialValues);
    } catch (DeadObjectException e) {
        if (!mStable) {
            mContentResolver.unstableProviderDied(mContentProvider);
        }
        throw e;
    } finally {
        afterRemote();
    }
}
```

可以看到这里其实只是一个代理，最终还是原本的ContentProvider完成。来看看`beforeRemote`和`afterRemote`做了啥：

```java
// frameworks/base/core/java/android/content/ContentProviderClient.java
private void beforeRemote() {
    if (mAnrRunnable != null) {
        sAnrHandler.postDelayed(mAnrRunnable, mAnrTimeout);
    }
}

private void afterRemote() {
    if (mAnrRunnable != null) {
        sAnrHandler.removeCallbacks(mAnrRunnable);
    }
}
```

before为post一个NotRespondingRunnable，而after则在ANR之前将其删除。


### # appNotRespondingViaProvider

NotRespondingRunnable里面还是熟悉的配方：

```java
// frameworks/base/core/java/android/content/ContentProviderClient.java
private class NotRespondingRunnable implements Runnable {
    @Override
    public void run() {
        Log.w(TAG, "Detected provider not responding: " + mContentProvider);
        mContentResolver.appNotRespondingViaProvider(mContentProvider);
    }
}
```

调用mContentResolver对应的方法，而mContentResolver是实现类为，android.app.ContextImpl$ApplicationContentResolver

```java
// frameworks/base/core/java/android/app/ContextImpl$ApplicationContentResolver.java
@Override
public void appNotRespondingViaProvider(IContentProvider icp) {
    mMainThread.appNotRespondingViaProvider(icp.asBinder());
}
```

接着来到ActivityThread：

```java
// frameworks/base/core/java/android/app/ActivityThread.java
final void appNotRespondingViaProvider(IBinder provider) {
    synchronized (mProviderMap) {
        ProviderRefCount prc = mProviderRefCountMap.get(provider);
        if (prc != null) {
            try {
                ActivityManager.getService()
                        .appNotRespondingViaProvider(prc.holder.connection);
            } catch (RemoteException e) {
                throw e.rethrowFromSystemServer();
            }
        }
    }
}
```

这里最终还是熟悉的ActivityManager：

```java
// frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java
@Override
public void appNotRespondingViaProvider(IBinder connection) {
    enforceCallingPermission(
            android.Manifest.permission.REMOVE_TASKS, "appNotRespondingViaProvider()");

    final ContentProviderConnection conn = (ContentProviderConnection) connection;
    if (conn == null) {
        Slog.w(TAG, "ContentProviderConnection is null");
        return;
    }

    final ProcessRecord host = conn.provider.proc;
    if (host == null) {
        Slog.w(TAG, "Failed to find hosting ProcessRecord");
        return;
    }

    mHandler.post(new Runnable() {
        @Override
        public void run() {
            mAppErrors.appNotResponding(host, null, null, false,
                    "ContentProvider not responding");
        }
    });
}
```

还是调用AppErrors.appNotResponding这个函数，弹出ANR的Dialog。

## UI

只要用户不产生输入，UI界面其实并“不会发生ANR”。如果用户点开APP，APP刚好又遇到类瓶颈，正常的用户行为肯定会是手指乱戳屏幕，必然产生了输入事件。

这样底层的InputDisptcher在dispatch 给当前InputChannel InputEvent的同时，掐表记录分发时间等待超时，通知上层InputManagerService上报的AMS，轻松抓抛出ANR。


### # 输入源头

InputDispatcher在分发事件时分别会通过dispatchKeyLocked和dispatchMotionLocked来分发KeyEvent和MotionEvent:

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
bool InputDispatcher::dispatchKeyLocked(nsecs_t currentTime, KeyEntry* entry,
        DropReason* dropReason, nsecs_t* nextWakeupTime) {
    ...
    // Identify targets.
    Vector<InputTarget> inputTargets;
    int32_t injectionResult = findFocusedWindowTargetsLocked(currentTime,
            entry, inputTargets, nextWakeupTime);
    if (injectionResult == INPUT_EVENT_INJECTION_PENDING) {
        return false;
    }

    setInjectionResultLocked(entry, injectionResult);
    if (injectionResult != INPUT_EVENT_INJECTION_SUCCEEDED) {
        return true;
    }

    addMonitoringTargetsLocked(inputTargets);

    // Dispatch the key.
    dispatchEventLocked(currentTime, entry, inputTargets);
    return true;
}

bool InputDispatcher::dispatchMotionLocked(
        nsecs_t currentTime, MotionEntry* entry, DropReason* dropReason, nsecs_t* nextWakeupTime) {
    // Preprocessing.
    ...
    int32_t injectionResult;
    if (isPointerEvent) {
        // Pointer event.  (eg. touchscreen)
        injectionResult = findTouchedWindowTargetsLocked(currentTime,
                entry, inputTargets, nextWakeupTime, &conflictingPointerActions);
    } else {
        // Non touch event.  (eg. trackball)
        injectionResult = findFocusedWindowTargetsLocked(currentTime,
                entry, inputTargets, nextWakeupTime);
    }
    if (injectionResult == INPUT_EVENT_INJECTION_PENDING) {
        return false;
    }
    ...
    dispatchEventLocked(currentTime, entry, inputTargets);
    return true;
}
```

以Keyevent为例，这里会经过findFocusedWindowTargetsLocked，中间会监听当前的窗口是否是在等待更多的输入：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
int32_t InputDispatcher::findFocusedWindowTargetsLocked(nsecs_t currentTime,
        const EventEntry* entry, Vector<InputTarget>& inputTargets, nsecs_t* nextWakeupTime) {
    int32_t injectionResult;
    String8 reason;
    ...
    // Check whether the window is ready for more input.
    reason = checkWindowReadyForMoreInputLocked(currentTime, mFocusedWindowHandle, entry, "focused");
    if (!reason.isEmpty()) {
        injectionResult = handleTargetsNotReadyLocked(currentTime, entry,
                mFocusedApplicationHandle, mFocusedWindowHandle, nextWakeupTime, reason.string());
        goto Unresponsive;
    }
    ...
Failed:
Unresponsive:
    nsecs_t timeSpentWaitingForApplication = getTimeSpentWaitingForApplicationLocked(currentTime);
    updateDispatchStatisticsLocked(currentTime, entry,
            injectionResult, timeSpentWaitingForApplication);
    return injectionResult;
}
```

然后进入`handleTargetsNotReadyLocked`监听上一次输入事件是否超时：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
int32_t InputDispatcher::handleTargetsNotReadyLocked(nsecs_t currentTime,
        const EventEntry* entry,
        const sp<InputApplicationHandle>& applicationHandle,
        const sp<InputWindowHandle>& windowHandle,
        nsecs_t* nextWakeupTime, const char* reason) {
    ...
    if (currentTime >= mInputTargetWaitTimeoutTime) {
        onANRLocked(currentTime, applicationHandle, windowHandle,
                entry->eventTime, mInputTargetWaitStartTime, reason);

        // Force poll loop to wake up immediately on next iteration once we get the
        // ANR response back from the policy.
        *nextWakeupTime = LONG_LONG_MIN;
        return INPUT_EVENT_INJECTION_PENDING;
    } else {
        // Force poll loop to wake up when timeout is due.
        if (mInputTargetWaitTimeoutTime < *nextWakeupTime) {
            *nextWakeupTime = mInputTargetWaitTimeoutTime;
        }
        return INPUT_EVENT_INJECTION_PENDING;
    }
}
```

当有超时则通过onANRLocked函数post一个command，在下次looper事件的时候向InputManager发送一个ANR的事件。其中timeout的算法如下:

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
if (windowHandle != NULL) {
    timeout = windowHandle->getDispatchingTimeout(DEFAULT_INPUT_DISPATCHING_TIMEOUT);
} else if (applicationHandle != NULL) {
    timeout = applicationHandle->getDispatchingTimeout(
            DEFAULT_INPUT_DISPATCHING_TIMEOUT);
} else {
    timeout = DEFAULT_INPUT_DISPATCHING_TIMEOUT;
}
```

其中DEFAULT_INPUT_DISPATCHING_TIMEOUT的默认值为5秒，如下:

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
namespace android {

// Default input dispatching timeout if there is no focused application or paused window
// from which to determine an appropriate dispatching timeout.
const nsecs_t DEFAULT_INPUT_DISPATCHING_TIMEOUT = 5000 * 1000000LL; // 5 sec
```

java层设置的值来自AMS：

```java
// frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java
// How long we wait until we timeout on key dispatching.
static final int KEY_DISPATCHING_TIMEOUT = 5*1000;

// How long we wait until we timeout on key dispatching during instrumentation.
static final int INSTRUMENTATION_KEY_DISPATCHING_TIMEOUT = 60*1000;

public static long getInputDispatchingTimeoutLocked(ActivityRecord r) {
    return r != null ? getInputDispatchingTimeoutLocked(r.app) : KEY_DISPATCHING_TIMEOUT;
}

public static long getInputDispatchingTimeoutLocked(ProcessRecord r) {
    if (r != null && (r.instr != null || r.usingWrapper)) {
        return INSTRUMENTATION_KEY_DISPATCHING_TIMEOUT;
    }
    return KEY_DISPATCHING_TIMEOUT;
}
```

> 当前进程的instr或usingWrapper有值时，ANR可以被修改为`INSTRUMENTATION_KEY_DISPATCHING_TIMEOUT`即60秒。ZygoteConnecetion的`handleParentProc`有对usingWrapper的处理。

### # onANRLocked

onANRLocked被调用后会往CommandQueue里面enqueue一个Command：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::onANRLocked(
        nsecs_t currentTime, const sp<InputApplicationHandle>& applicationHandle,
        const sp<InputWindowHandle>& windowHandle,
        nsecs_t eventTime, nsecs_t waitStartTime, const char* reason) {
   ...
    CommandEntry* commandEntry = postCommandLocked(
            & InputDispatcher::doNotifyANRLockedInterruptible);
    commandEntry->inputApplicationHandle = applicationHandle;
    commandEntry->inputWindowHandle = windowHandle;
    commandEntry->reason = reason;
}
```

其中doNotifyANRLockedInterruptible为Command的回调函数。如下：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::doNotifyANRLockedInterruptible(
        CommandEntry* commandEntry) {
    mLock.unlock();

    nsecs_t newTimeout = mPolicy->notifyANR(
            commandEntry->inputApplicationHandle, commandEntry->inputWindowHandle,
            commandEntry->reason);

    mLock.lock();

    resumeAfterTargetsNotReadyTimeoutLocked(newTimeout,
            commandEntry->inputWindowHandle != NULL
                    ? commandEntry->inputWindowHandle->getInputChannel() : NULL);
}
```

这里调用到mPolicy的notifyANR函数，其中mPolicy为NativeInputManager，如下：

```
// frameworks/base/service/core/jni/com_android_server_input_InputManagerService.cpp
nsecs_t NativeInputManager::notifyANR(const sp<InputApplicationHandle>& inputApplicationHandle,
        const sp<InputWindowHandle>& inputWindowHandle, const String8& reason) {
    ATRACE_CALL();

    JNIEnv* env = jniEnv();

    jobject inputApplicationHandleObj =
            getInputApplicationHandleObjLocalRef(env, inputApplicationHandle);
    jobject inputWindowHandleObj =
            getInputWindowHandleObjLocalRef(env, inputWindowHandle);
    jstring reasonObj = env->NewStringUTF(reason.string());

    jlong newTimeout = env->CallLongMethod(mServiceObj,
                gServiceClassInfo.notifyANR, inputApplicationHandleObj, inputWindowHandleObj,
                reasonObj);
    ...
    return newTimeout;
}
```

这里主要是反射java层InputManagerService的notifyANR函数。Java层的调用如下:


[![ActivityManager-inputDispatchingTimedOut.png](https://j.mp/2wggChj)](https://j.mp/2J3QDfH)

最终会执行到AMS的`inputDispatchingTimedOut`函数：

```java
// frameworks/base/services/core/java/com/android/server/am/ActivityManagerService.java
public boolean inputDispatchingTimedOut(final ProcessRecord proc,
        final ActivityRecord activity, final ActivityRecord parent,
        final boolean aboveSystem, String reason) {
    ...
    final String annotation;
    if (reason == null) {
        annotation = "Input dispatching timed out";
    } else {
        annotation = "Input dispatching timed out (" + reason + ")";
    }

    if (proc != null) {
        ...
        mHandler.post(new Runnable() {
            @Override
            public void run() {
                mAppErrors.appNotResponding(proc, activity, parent, aboveSystem, annotation);
            }
        });
    }

    return true;
}
```

接着就来到AppErrors.appNotResponding函数，同上面一样。最后会弹出ANR弹框。


## 总结

- `SERVICE_TIMEOUT`为前台Service超时时间: 20秒
- `SERVICE_BACKGROUND_TIMEOUT`为后台Service超时时间: 10个SERVICE_TIMEOUT为200秒。
- `BROADCAST_FG_TIMEOUT` 前台广播超时时间: 10秒
- `BROADCAST_BG_TIMEOUT` 后台广播超时时间: 60秒
- `KEY_DISPATCHING_TIMEOUT`或者`DEFAULT_INPUT_DISPATCHING_TIMEOUT` 输入事件的超时时间为: 5秒。