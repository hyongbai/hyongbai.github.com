---
layout: post
title: "Android通信之Handler-MessageQueue-Looper"
description: "Android通信之Handler-MessageQueue-Looper"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-03-31 19:03:57+00:00
---

Handler是Android开发中十分常用并且十分核心的类。

主要用于消息传递以及跨线程进行通信。

## Handler

构造函数如下：

```java
// frameworks/base/core/java/android/os/Handler.java
    public Handler(Callback callback, boolean async) {
        if (FIND_POTENTIAL_LEAKS) {
            final Class<? extends Handler> klass = getClass();
            if ((klass.isAnonymousClass() || klass.isMemberClass() || klass.isLocalClass()) &&
                    (klass.getModifiers() & Modifier.STATIC) == 0) {
                Log.w(TAG, "The following Handler class should be static or leaks might occur: " +
                    klass.getCanonicalName());
            }
        }

        mLooper = Looper.myLooper();
        if (mLooper == null) {
            throw new RuntimeException(
                "Can't create handler inside thread that has not called Looper.prepare()");
        }
        mQueue = mLooper.mQueue;
        mCallback = callback;
        mAsynchronous = async;
    }
```

这里接收了四个参数。

- mLooper： Handler能够运行的基础。线程需要prepare，才能被 Looper进行block。Looper等等MessageQueue发来的Message，从而完成消息的处理。
- mQueue：即MessageQueue，这个对象由Looper提供。MessageQueue用于接收来自Handler的消息，并根据触发时间唤起Looper持有Handler发去的消息并处理。
- mCallback：Looper最终通过调用Message中的handler的dispatchMessagee进行消息的分发。而mCallback可以将dispatchMessage进行拦截（Message本身不包含callback的前提下）。
- mAsynchronous：默认为false。即是否为异步消息。这里可能会有点看不明白。按照常规理解，Handler本身就是异步消息。其实在MessageQueue中，还有一个同步障碍的概念。也就是说，我们可以在MessageQueue中插入一个同步障碍的Message。当这个事件被触发之后，紧接着就会把这个事件后的异步事件前置，即让标记为`mAsynchronous`的Message往前插队。

注意：在Handler的构造函数中有一段检测潜在内存泄漏的逻辑。

### # 创建消息

推荐使用以下两种方式创建Message：

- Message.obtain
- Handler.obtainMessage

最终都会调用到`obtain()`函数：

```java
// frameworks/base/core/java/android/os/Message.java
public static Message obtain() {
    synchronized (sPoolSync) {
        if (sPool != null) {
            Message m = sPool;
            sPool = m.next;
            m.next = null;
            m.flags = 0; // clear in-use flag
            sPoolSize--;
            return m;
        }
    }
    return new Message();
}
```

这个函数使用已回收了的Message消息，并存储在 `sPool` 中。其实Message也可以看成一个单向的链表，每次把链表的头从 `sPool` 中取出来即可。

当消息被从 `MessageQueue` 中移除时以及 `Looper` (见 `looper` 函数for循环结尾处)分发一次消息之后，`recycleUnchecked()` 会被触发：

```java
// frameworks/base/core/java/android/os/Message.java
void recycleUnchecked() {
    flags = FLAG_IN_USE;
    what = 0;
    arg1 = 0;
    arg2 = 0;
    obj = null;
    replyTo = null;
    sendingUid = -1;
    when = 0;
    target = null;
    callback = null;
    data = null;

    synchronized (sPoolSync) {
        if (sPoolSize < MAX_POOL_SIZE) {
            next = sPool;
            sPool = this;
            sPoolSize++;
        }
    }
}
```

这个函数中会清除 `Message` 的一切信息，并将其加入到 `sPool` 的头部。

即 `Message.next=sPool; sPool=Message.this;`。

原则上来说，每一个创建过的 `Message` 都有可能会缓存起来。

注意：缓存是有上限的，即 `MAX_POOL_SIZE` (默认为 `50`)。

### # 发送消息

Handler提供了一系列接口：

```java
post(...) {}
postAtTime(...) {}
postAtTime(...) {}
postDelayed(...) {}
postAtFrontOfQueue(...) {}
sendMessage(...) {}
sendEmptyMessage(...) {}
sendEmptyMessageDelayed(...) {}
sendEmptyMessageAtTime(...) {}
sendMessageDelayed(...) {}
sendMessageAtTime(...) {}
sendMessageAtFrontOfQueue(...) {}
```

- postXXX

可以接收一个runnable对象

```
// frameworks/base/core/java/android/os/Handler.java
public final boolean post(Runnable r) {
   return  sendMessageDelayed(getPostMessage(r), 0);
}
```

最终会通过`getPostMessage(r)`将其封装成一个Message对象。

```java
// frameworks/base/core/java/android/os/Handler.java
private static Message getPostMessage(Runnable r) {
    Message m = Message.obtain();
    m.callback = r;
    return m;
}
```

可见通过obtain()生成一个Message对象，并将runnable对象设置到其callback中去。

最后同其他直接发送Message一样，调用到`sendMessageAtTime`。

- sendMessageAtTime
 
可以设定触发时间，默认为当前时间。

```java
// frameworks/base/core/java/android/os/Handler.java
public boolean sendMessageAtTime(Message msg, long uptimeMillis) {
    MessageQueue queue = mQueue;
    if (queue == null) {
        RuntimeException e = new RuntimeException(
                this + " sendMessageAtTime() called with no mQueue");
        Log.w("Looper", e.getMessage(), e);
        return false;
    }
    return enqueueMessage(queue, msg, uptimeMillis);
}
```

这里的`uptimeMillis`默认是`SystemClock.uptimeMillis() + delayMillis`。

- sendMessageAtFrontOfQueue

与其他方式不同的地方在于，它可以将Message插入到MessageQueue的Head。

```java
// frameworks/base/core/java/android/os/Handler.java
public final boolean sendMessageAtFrontOfQueue(Message msg) {
    MessageQueue queue = mQueue;
    if (queue == null) {
        RuntimeException e = new RuntimeException(
            this + " sendMessageAtTime() called with no mQueue");
        Log.w("Looper", e.getMessage(), e);
        return false;
    }
    return enqueueMessage(queue, msg, 0);
}
```

这里的`enqueueMessage`接收的`uptimeMillis`为0。以为MessageQueue是以when(即uptimeMillis)正序的，因此uptimeMillis越小则越靠前。

`enqueueMessage` 本身则是调用构造函数持有的mQueue的enqueueMessage函数。

```java
// frameworks/base/core/java/android/os/Handler.java
private boolean enqueueMessage(MessageQueue queue, Message msg, long uptimeMillis) {
    msg.target = this;
    if (mAsynchronous) {
        msg.setAsynchronous(true);
    }
    return queue.enqueueMessage(msg, uptimeMillis);
}
```

通过Handler发送过去的消息，每个message的target都会被赋值为发送方(Handler)。

同时，如果当前的Handler标记为`mAsynchronous`，则会强制把Message全部标记`FLAG_ASYNCHRONOUS`。

这里需要注意的是，如果Handler不是`mAsynchronous`，那么Message的`FLAG_ASYNCHRONOUS`并不会被修改。

因此，可以单独将Message独立于Handler之外标记为`FLAG_ASYNCHRONOUS`，而无需关心Handler，反之则不行。

### # 处理消息

Looper的loop函数中，拿到Message消息之后，则会调用其target(即Handler)的`dispatchMessage`函数。

```java
// frameworks/base/core/java/android/os/Handler.java
public void handleMessage(Message msg) {
}

public void dispatchMessage(Message msg) {
    if (msg.callback != null) {
        handleCallback(msg);
    } else {
        if (mCallback != null) {
            if (mCallback.handleMessage(msg)) {
                return;
            }
        }
        handleMessage(msg);
    }
}
```

可以看到，如果message本身就有callback(即post一个runnable)那么将不用经过handler本身的callback以及其handleMessage函数。

否则，如果Handler的Callback截获类对应的Message，那么handleMessage将不会被触发。

### # Handler 总结

- mAsynchronous：Handler可以标记`FLAG_ASYNCHRONOUS`，这样则可以在MessageQueue中插入同步屏障屏障，然后标记为异步的消息往前插队。
- sendMessageAtFrontOfQueue：Handler可以直接发送一个插入在MessageQueue头部的消息。
- Handler设置Callback可以截获非Runnable消息。

## MessageQueue

MessageQueue是Android中Looper的消息队列。其阻塞和唤醒都是native实现的。

```java
// frameworks/base/core/java/android/os/MessageQueue.java
MessageQueue(boolean quitAllowed) {
    mQuitAllowed = quitAllowed;
    mPtr = nativeInit();
}
```

MessageQueue的构造函数通过jni函数`nativeInit()`创建一个native实例，并交给java层持有。

### # 消息入列

```java
// frameworks/base/core/java/android/os/MessageQueue.java
boolean enqueueMessage(Message msg, long when) {
    if (msg.target == null) {
        throw new IllegalArgumentException("Message must have a target.");
    }
    if (msg.isInUse()) {
        throw new IllegalStateException(msg + " This message is already in use.");
    }

    synchronized (this) {
        if (mQuitting) {
            IllegalStateException e = new IllegalStateException(msg.target + " sending message to a Handler on a dead thread");
            msg.recycle();
            return false;
        }

        msg.markInUse();
        msg.when = when;
        Message p = mMessages;
        boolean needWake;
        if (p == null || when == 0 || when < p.when) {
            // 新消息触发时间较小，则插在前面。
            msg.next = p;
            mMessages = msg;
            needWake = mBlocked;
        } else {
            needWake = mBlocked && p.target == null && msg.isAsynchronous();
            Message prev;
            for (;;) {
                prev = p;
                p = p.next;
                if (p == null || when < p.when) {
                    break;
                }
                if (needWake && p.isAsynchronous()) {
                    needWake = false;
                }
            }
            // 找到比当前消息小的Message，插入在中间。
            msg.next = p; // invariant: p == prev.next
            prev.next = msg;
        }

        if (needWake) {
            // 如果当前已经不是block状态，则不会调用nativeWake
            nativeWake(mPtr);
        }
    }
    return true;
}
```

- 新消息触发时间较小，则插在前面。
- 找到比当前消息小的Message，插入在中间。
- 如果不是block状态或者当前消息的前面有标记为异步的消息，则不唤起MessageQueue。

### # 同步障碍 - PostSyncBarrier

上面说到Handler的`mAsynchronous`可以用来标记Message为`FLAG_ASYNCHRONOUS`。下面来看看这个属性到底是如何工作的。

```java
// frameworks/base/core/java/android/os/MessageQueue.java
public int postSyncBarrier() {
    return postSyncBarrier(SystemClock.uptimeMillis());
}

private int postSyncBarrier(long when) {
    // Enqueue a new sync barrier token.
    // We don't need to wake the queue because the purpose of a barrier is to stall it.
    synchronized (this) {
        final int token = mNextBarrierToken++;
        final Message msg = Message.obtain();
        msg.markInUse();
        msg.when = when;
        msg.arg1 = token;

        Message prev = null;
        Message p = mMessages;
        if (when != 0) {
            while (p != null && p.when <= when) {
                prev = p;
                p = p.next;
            }
        }
        if (prev != null) { // invariant: p == prev.next
            msg.next = p;
            prev.next = msg;
        } else {
            msg.next = p;
            mMessages = msg;
        }
        return token;
    }
}
```

这段代码主要是根据when，在原有的链表中插入一个不包含target的Message。不包含target这个信息很重要。

因为后面再消费消息的时候，就是通过是否包含target来判断当前消息是不是同步障碍的Message。

如果，当前链表中不存在异步消息，那么插入同步障碍就是浪费。它本身没有任何意义。

最后返回一个唯一的token(这个token是自曾的)，如果你后悔插入同步障碍则可以通过这个token将其移除掉。

> 注：同步障碍这个api默认是隐藏 `@hide` 的。

### # 消费消息

当消费者(Looper)消费Message的时候，MessageQueue的next()函数是一直阻塞状态的。知道有新的消息满足了之后，才会吐出消息。

> 这同普通生产者消费者模式一致。

```java
// frameworks/base/core/java/android/os/MessageQueue.java
Message next() {
    ...
    int pendingIdleHandlerCount = -1; // -1 only during first iteration
    int nextPollTimeoutMillis = 0;
    for (;;) {
        if (nextPollTimeoutMillis != 0) {
            Binder.flushPendingCommands();
        }

        nativePollOnce(ptr, nextPollTimeoutMillis);

        synchronized (this) {
            // Try to retrieve the next message.  Return if found.
            final long now = SystemClock.uptimeMillis();
            Message prevMsg = null;
            Message msg = mMessages;
            if (msg != null && msg.target == null) {
                // 遇到同步障碍，则将后面的第一个异步消息拎出来插队。
                do {
                    prevMsg = msg;
                    msg = msg.next;
                } while (msg != null && !msg.isAsynchronous());
            }
            if (msg != null) {
                if (now < msg.when) {
                    // 当前消息的触发时间并不满足，那么让它MessageQueue直接阻塞到目标事件。这里计算差值即nextPollTimeoutMillis表示阻塞时间。
                    nextPollTimeoutMillis = (int) Math.min(msg.when - now, Integer.MAX_VALUE);
                } else {
                    // 正常可用的消息。则将其从链表中抹去，并返回给Looper
                    mBlocked = false;
                    if (prevMsg != null) {
                        prevMsg.next = msg.next;
                    } else {
                        mMessages = msg.next;
                    }
                    msg.next = null;
                    msg.markInUse();
                    return msg;
                }
            } else {
                // 如果没有消息，则无限阻塞。知道enqueue新消息的时候，被唤醒。
                nextPollTimeoutMillis = -1;
            }

            // Process the quit message now that all pending messages have been handled.
            if (mQuitting) {
                dispose();
                return null;
            }
            ...
            if (pendingIdleHandlerCount < 0
                    && (mMessages == null || now < mMessages.when)) {
                // 如果没有消息或者header并没有被触发，那么唤起IdelHandler回调。
                pendingIdleHandlerCount = mIdleHandlers.size();
            }
            if (pendingIdleHandlerCount <= 0) {
                // No idle handlers to run.  Loop and wait some more.
                mBlocked = true;
                continue;
            }

            if (mPendingIdleHandlers == null) {
                mPendingIdleHandlers = new IdleHandler[Math.max(pendingIdleHandlerCount, 4)];
            }
            mPendingIdleHandlers = mIdleHandlers.toArray(mPendingIdleHandlers);
        }

        // Run the idle handlers.
        // We only ever reach this code block during the first iteration.
        for (int i = 0; i < pendingIdleHandlerCount; i++) {
            final IdleHandler idler = mPendingIdleHandlers[i];
            mPendingIdleHandlers[i] = null; // release the reference to the handler

            boolean keep = false;
            try {
                keep = idler.queueIdle();
            } catch (Throwable t) {
                Log.wtf(TAG, "IdleHandler threw exception", t);
            }

            if (!keep) {
                synchronized (this) {
                    mIdleHandlers.remove(idler);
                }
            }
        }

        // Reset the idle handler count to 0 so we do not run them again.
        pendingIdleHandlerCount = 0;

        // 这里会重置阻塞时间。这里的逻辑是认为，如果IdleHandler被回调了，那么其观察者一定是做了什么事。所以给一次机会下次直接重新读取当前消息链表。
        nextPollTimeoutMillis = 0;
    }
}
```

- 遇到同步障碍，则将后面的第一个异步消息拎出来插队。
- 当前消息的触发时间并不满足，那么让它MessageQueue直接阻塞到目标事件。这里计算差值即nextPollTimeoutMillis表示阻塞时间。
- 如果当前消息满足触发时间。则将其从链表中抹去，并返回给Looper
- 如果没有消息，则无限阻塞(没有IdelHandler的情况下)。知道enqueue新消息的时候，被唤醒。
- 如果没有消息或者header并没有被触发，并且有注册拎IdelHandler。那么唤起IdelHandler回调。这里会重置阻塞时间。这里的逻辑是认为，如果IdleHandler被回调了，那么其观察者一定是做了什么事。所以给一次机会下次直接重新读取当前消息链表。


### # MessageQueue的Native实现

上面说到MessageQueue的构造函数中直接调用jni获取一个native对象的内存地址，存储在`mPtr`中。

```cpp
// frameworks/base/code/jni/android_os_MessageQueue.cpp
static jlong android_os_MessageQueue_nativeInit(JNIEnv* env, jclass clazz) {
    NativeMessageQueue* nativeMessageQueue = new NativeMessageQueue();
    if (!nativeMessageQueue) {
        jniThrowRuntimeException(env, "Unable to allocate native queue");
        return 0;
    }

    nativeMessageQueue->incStrong(env);
    return reinterpret_cast<jlong>(nativeMessageQueue);
}
```

nativeInit其实创建了一个NativeMessageQueue对象。

```cpp
// frameworks/base/code/jni/android_os_MessageQueue.cpp
NativeMessageQueue::NativeMessageQueue() :
        mPollEnv(NULL), mPollObj(NULL), mExceptionObj(NULL) {
    mLooper = Looper::getForThread();
    if (mLooper == NULL) {
        mLooper = new Looper(false);
        Looper::setForThread(mLooper);
    }
}
```

而NativeMessageQueue的构造函数中持有拎当前线程的一个Looper对象。

这个获取或者创建Looper的过程相当于prepare的过程，即获取当前线程的Looper对象。


其中Looper的构造函数中会通过`epoll_create`创建一个epoll对象。用于epoll的相关操作。

#### - NativeMessageQueue.wake

当enqueue时，如果需要wate。那么最终是通过nativeWake完成的：

```cpp
// frameworks/base/code/jni/android_os_MessageQueue.cpp
static void android_os_MessageQueue_nativeWake(JNIEnv* env, jclass clazz, jlong ptr) {
    NativeMessageQueue* nativeMessageQueue = reinterpret_cast<NativeMessageQueue*>(ptr);
    nativeMessageQueue->wake();
}

void NativeMessageQueue::wake() {
    mLooper->wake();
}
```

nativeWake的参数最终会重新转化为NativeMessageQueue。最终其wake实现也是调用Looper的wake函数。

#### - NativeMessageQueue.pollOnce

MessageQueue产生Message时，通过nativePollOnce来进行阻塞。

```cpp
// frameworks/base/code/jni/android_os_MessageQueue.cpp
void NativeMessageQueue::pollOnce(JNIEnv* env, jobject pollObj, int timeoutMillis) {
    mPollEnv = env;
    mPollObj = pollObj;
    mLooper->pollOnce(timeoutMillis);
    mPollObj = NULL;
    mPollEnv = NULL;

    if (mExceptionObj) {
        env->Throw(mExceptionObj);
        env->DeleteLocalRef(mExceptionObj);
        mExceptionObj = NULL;
    }
}
```

Looper的pollOnce最终通过`epoll_wait`进行超时阻塞。或者等待enqueue时的wake。

### # MessageQueue总结

- Handler持有Looper的MessageQueue对象。通过enqueue直接往MessageQueue插入Message。
- MessageQueu里面维护了一个Message链表。这个链表是通过Messsage的when，即触发时间排序的。
- 标记为`FLAG_ASYNCHRONOUS`的Message可以通过插入一个同步障碍进行消费插队。
- MessageQueue不处理消息的时候，允许注册IdleHandler进行监控。

## Looper

Looper在使用之前都需要prepare，使其内部的ThreadLocal对象持有当前线程的Looper对象。这样才能通过getLooper这一静态函数拿到全局的Looper对象。

### # 启动

应用被ZygoteInit中fork出来之后，都会调用ActivityThread的main函数。如下：

```java
// frameworks/base/core/java/android/app/ActivityThread.java
public static void main(String[] args) {
    ...
    Looper.prepareMainLooper();
    ActivityThread thread = new ActivityThread();
    thread.attach(false);
    ...
    Looper.loop();
    throw new RuntimeException("Main thread loop unexpectedly exited");
}
```

可以看见在ActivityThread实例化之前Looper就`prepareMainLooper`。保证ActivityThread中能顺利拿到MainLooper，从而创建对应的Handler处理UI事件。

经过一系列初始化之后，loop()函数被调用。如果loop()函数一旦停止阻塞，那么整个引用就会抛出Runtime的异常。紧接着AppRunTime就会删除VM等。

### # loop

```java
// frameworks/base/core/java/android/os/Looper.java
public static void loop() {
    final Looper me = myLooper();
    if (me == null) {
        throw new RuntimeException("No Looper; Looper.prepare() wasn't called on this thread.");
    }
    final MessageQueue queue = me.mQueue;

    // Make sure the identity of this thread is that of the local process,
    // and keep track of what that identity token actually is.
    Binder.clearCallingIdentity();
    final long ident = Binder.clearCallingIdentity();

    for (;;) {
        // 从MessageQueue获取Message，如果没有消息那么MessageQueue会一致阻塞着。除非MessageQueue被quit了。
        Message msg = queue.next(); // might block
        if (msg == null) {
            // No message indicates that the message queue is quitting.
            return;
        }

        // This must be in a local variable, in case a UI event sets the logger
        final Printer logging = me.mLogging;
        if (logging != null) {
            logging.println(">>>>> Dispatching to " + msg.target + " " +
                    msg.callback + ": " + msg.what);
        }
        ...
        try {
            // 拿到message之后，获取其target(即Handler)进行消息的分发。完成一个loop。
            msg.target.dispatchMessage(msg);
            end = (slowDispatchThresholdMs == 0) ? 0 : SystemClock.uptimeMillis();
        }
        ...
        if (logging != null) {
            logging.println("<<<<< Finished to " + msg.target + " " + msg.callback);
        }
        ...
        // 回收当前的Message，是其加入到Message的sPool中。供obtain时再次使用。
        msg.recycleUnchecked();
    }
}
```

这个looper函数本身是一个不会结束的死循环，为UI等提供一个文件的消息系统。

- 从MessageQueue获取Message，如果没有消息那么MessageQueue会一致阻塞着。除非MessageQueue被quit了。
- 拿到message之后，获取其target(即Handler)进行消息的分发。完成一个loop。
- 回收当前的Message，是其加入到Message的sPool中。供obtain时再次使用。

注意：每次在进行一个loop即往handler发送消息的前后，Looper会拿到当前的mLogging通过其打印行日志。这两个日志是一次handleMessage最完整的时间。因此有的APM项目会通过调用MainLooper的`setMessageLogging`函数，替换掉这里的mLogging。根据着两个有特点的日志做数据统计。

## Messenger

Messenger是android的Framework层封装的一个简单的基于Handler的轻量级跨进程通信方式。


```java
// frameworks/base/core/java/android/os/Messenger.java
public final class Messenger implements Parcelable {
    private final IMessenger mTarget;

    public Messenger(Handler target) {
        mTarget = target.getIMessenger();
    }
    ...   
}
```

可以看到其构造函数中获取了来自target的一个IMessage对象。这个IMessage本身就是Handler的一个AIDL的接口。

```java
// frameworks/base/core/java/android/os/Handler.java
final IMessenger getIMessenger() {
    synchronized (mQueue) {
        if (mMessenger != null) {
            return mMessenger;
        }
        mMessenger = new MessengerImpl();
        return mMessenger;
    }
}

private final class MessengerImpl extends IMessenger.Stub {
    public void send(Message msg) {
        msg.sendingUid = Binder.getCallingUid();
        Handler.this.sendMessage(msg);
    }
}
```

可以看到IMessage对象来自于`MessengerImpl`继承自`IMessenger.Stub`。抽象接口定义文件位于aosp源码frameworks/base/core/java/android/os/IMessenger.aidl处。

原文如下：

```aidl
// frameworks/base/core/java/android/os/IMessenger.aidl
package android.os;

import android.os.Message;

/** @hide */
oneway interface IMessenger {
    void send(in Message msg);
}
```

当我们获取到另外一个进程的Messenger对象之后，就可以通过调用其内部的send函数发送Message到原进程的Handler中了。

```java
// frameworks/base/core/java/android/os/Messenger.java
public void send(Message message) throws RemoteException {
    mTarget.send(message);
}
```

不过在实际开发中，Messenger存在感比较低。

## 总结

### # Handler可能引发的内存泄漏

如果Handler为静态类，则Handler本身并不是直接导致内存泄漏的直接原因。

以下都是非静态的前提下：

- 匿名内部类。
- 成员类。
- 局部类。

原因在于通过这些情况下，handler所在的上下文或者其本身会持有外部对象。而handler有可能一直被MessageQueue持有，导致handler持有的对象，比如Activity/View等不会释放。从而导致泄漏。

## # Handler跨线程同步调用

```java
// frameworks/base/core/java/android/os/Handler.java
public final boolean runWithScissors(final Runnable r, long timeout) {
    if (r == null) {
        throw new IllegalArgumentException("runnable must not be null");
    }
    if (timeout < 0) {
        throw new IllegalArgumentException("timeout must be non-negative");
    }

    if (Looper.myLooper() == mLooper) {
        r.run();
        return true;
    }

    BlockingRunnable br = new BlockingRunnable(r);
    return br.postAndWait(this, timeout);
}

private static final class BlockingRunnable implements Runnable {
    private final Runnable mTask;
    private boolean mDone;

    public BlockingRunnable(Runnable task) {
        mTask = task;
    }

    @Override
    public void run() {
        try {
            mTask.run();
        } finally {
            synchronized (this) {
                mDone = true;
                notifyAll();
            }
        }
    }

    public boolean postAndWait(Handler handler, long timeout) {
        if (!handler.post(this)) {
            return false;
        }

        synchronized (this) {
            if (timeout > 0) {
                final long expirationTime = SystemClock.uptimeMillis() + timeout;
                while (!mDone) {
                    long delay = expirationTime - SystemClock.uptimeMillis();
                    if (delay <= 0) {
                        return false; // timeout
                    }
                    try {
                        wait(delay);
                    } catch (InterruptedException ex) {
                    }
                }
            } else {
                while (!mDone) {
                    try {
                        wait();
                    } catch (InterruptedException ex) {
                    }
                }
            }
        }
        return true;
    }
}
```

这是一个@hide标记的函数，看看就好。

引申阅读：

- [epoll 或者 kqueue 的原理是什么？](https://www.zhihu.com/question/20122137/answer/14049112)
- [Linux IO模式及 select、poll、epoll详解](https://segmentfault.com/a/1190000003063859)