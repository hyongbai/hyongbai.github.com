---
layout: post
title: "Android输入事件0: 上下层通信"
description: "Android输入事件0: 上下层通信"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-03-17 21:03:57+00:00
---

> android-8.1.0_r60
>
> 为求简洁，代码已删除大量细枝末节。

这里的输入事件不仅仅是指字符输入，还包括按键输入以及触摸事件等等。

## 初始化

众知在Activity的DecorView加入到WindowManager时，会实例化ViewRootImpl同时调用其`setView()`函数。

而`setView()`函数本身除了与VSYNC同步以外，还有做其他的一些初始化行为。比如输入事件，如下：

```java
// android/view/ViewRootImpl.java
public void setView(View view, WindowManager.LayoutParams attrs, View panelParentView) {
    // ...
    if ((mWindowAttributes.inputFeatures
            & WindowManager.LayoutParams.INPUT_FEATURE_NO_INPUT_CHANNEL) == 0) {
        mInputChannel = new InputChannel();
    }
    // ...
        res = mWindowSession.addToDisplay(mWindow, mSeq, mWindowAttributes,
                getHostVisibility(), mDisplay.getDisplayId(),
                mAttachInfo.mContentInsets, mAttachInfo.mStableInsets,
                mAttachInfo.mOutsets, mInputChannel);
    // ...
    if (mInputChannel != null) {
        if (mInputQueueCallback != null) {
            mInputQueue = new InputQueue();
            mInputQueueCallback.onInputQueueCreated(mInputQueue);
        }
        mInputEventReceiver = new WindowInputEventReceiver(mInputChannel, Looper.myLooper());
    }
    // ...
    // Set up the input pipeline.
    CharSequence counterSuffix = attrs.getTitle();
    mSyntheticInputStage = new SyntheticInputStage();
    InputStage viewPostImeStage = new ViewPostImeInputStage(mSyntheticInputStage);
    InputStage nativePostImeStage = new NativePostImeInputStage(viewPostImeStage,
            "aq:native-post-ime:" + counterSuffix);
    InputStage earlyPostImeStage = new EarlyPostImeInputStage(nativePostImeStage);
    InputStage imeStage = new ImeInputStage(earlyPostImeStage,
            "aq:ime:" + counterSuffix);
    InputStage viewPreImeStage = new ViewPreImeInputStage(imeStage);
    InputStage nativePreImeStage = new NativePreImeInputStage(viewPreImeStage,
            "aq:native-pre-ime:" + counterSuffix);

    mFirstInputStage = nativePreImeStage;
    mFirstPostImeInputStage = earlyPostImeStage;
    mPendingInputEventQueueLengthCounterName = "aq:pending:" + counterSuffix;
}
```

这里主要初始化三件事：

### # 初始化InputChannel

创建一个InputChannel并将其注册到InputManagerService。Activity在每次handleResumeActivity时都需要ViewRootImpl的setView都会绑定一个InputChannel对象。

```java
// android/view/ViewRootImpl.java
public void setView(View view, WindowManager.LayoutParams attrs, View panelParentView) {
    // ...
    if ((mWindowAttributes.inputFeatures
            & WindowManager.LayoutParams.INPUT_FEATURE_NO_INPUT_CHANNEL) == 0) {
        mInputChannel = new InputChannel();
    }
    // ...
    mWindowSession.addToDisplay(..., mInputChannel);
    // ...
}
```

其中addToDisplay至关重要。主要原因在于后面注册InputReceiver时Native需要持有InputChannel对应的JNI对象，而这个JNI对象存储在`InputChannel.mPtr`中。而默认情况下这个值是0。

继续`addToDisplay`最终经过`WindowManagerService`到达`WindowState`的`openInputChannel`函数：

```java
// frameworks/base/services/core/java/com/android/server/wm/Session.java
@Override
public int addToDisplay(..., InputChannel outInputChannel) {
    return mService.addWindow(..., outInputChannel);
}

// frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java
public int addWindow(..., InputChannel outInputChannel) {
    // ...
    final boolean openInputChannels = (outInputChannel != null
            && (attrs.inputFeatures & INPUT_FEATURE_NO_INPUT_CHANNEL) == 0);
    if  (openInputChannels) {
        win.openInputChannel(outInputChannel);
    }
    // ...
}
```

`WindowState.openInputChannel()`函数如下：

```java
// frameworks/base/services/core/java/com/android/server/wm/WindowState.java
void openInputChannel(InputChannel outInputChannel) {
    if (mInputChannel != null) {
        throw new IllegalStateException("Window already has an input channel.");
    }
    String name = getName();
    InputChannel[] inputChannels = InputChannel.openInputChannelPair(name);
    mInputChannel = inputChannels[0];
    mClientChannel = inputChannels[1];
    mInputWindowHandle.inputChannel = inputChannels[0];
    if (outInputChannel != null) {
        mClientChannel.transferTo(outInputChannel);
        mClientChannel.dispose();
        mClientChannel = null;
    } else {
        // If the window died visible, we setup a dummy input channel, so that taps
        // can still detected by input monitor channel, and we can relaunch the app.
        // Create dummy event receiver that simply reports all events as handled.
        mDeadWindowEventReceiver = new DeadWindowEventReceiver(mClientChannel);
    }
    mService.mInputManager.registerInputChannel(mInputChannel, mInputWindowHandle);
}
```

这里也主要是三个行为：

#### - openInputChannelPair(nativeOpenInputChannelPair)

这个函数在native分别创建了一个`serverChannel`和`clientChannel`的native对象，并且生成了对应的jobject对象。使之得以传递到Java层并持有之。其中`mInputChannel`为Server，而`mClientChannel`则为Client，最终这个Client通过transferTo等行为最终让ViewRootImpl中的`mInputChannel`持有。

具体实现如下(有删改)：

```cpp
// frameworks/base/core/jni/android_view_InputChannel.cpp
static jobjectArray android_view_InputChannel_nativeOpenInputChannelPair(JNIEnv* env,
        jclass clazz, jstring nameObj) {
    // ...
    status_t result = InputChannel::openInputChannelPair(name, serverChannel, clientChannel);
    // ...
    jobject serverChannelObj = android_view_InputChannel_createInputChannel(env,
            std::make_unique<NativeInputChannel>(serverChannel));
    jobject clientChannelObj = android_view_InputChannel_createInputChannel(env,
            std::make_unique<NativeInputChannel>(clientChannel));
    // ...
    return channelPair;
}
```

- openInputChannelPair

这步主要是创建一对[双向管道(IBM文章传送)](http://j.mp/39UhHd3)，分别用于Server和Client，也就是Java最后获取到的Pair。这一步：

```cpp
// frameworks/native/libs/input/InputTransport.cpp
status_t InputChannel::openInputChannelPair(const String8& name,
        sp<InputChannel>& outServerChannel, sp<InputChannel>& outClientChannel) {
    int sockets[2];
    socketpair(AF_UNIX, SOCK_SEQPACKET, 0, sockets)
    // ...
    int bufferSize = SOCKET_BUFFER_SIZE;
    setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &bufferSize, sizeof(bufferSize));
    setsockopt(sockets[0], SOL_SOCKET, SO_RCVBUF, &bufferSize, sizeof(bufferSize));
    setsockopt(sockets[1], SOL_SOCKET, SO_SNDBUF, &bufferSize, sizeof(bufferSize));
    setsockopt(sockets[1], SOL_SOCKET, SO_RCVBUF, &bufferSize, sizeof(bufferSize));

    String8 serverChannelName = name;
    serverChannelName.append(" (server)");
    outServerChannel = new InputChannel(serverChannelName, sockets[0]);

    String8 clientChannelName = name;
    clientChannelName.append(" (client)");
    outClientChannel = new InputChannel(clientChannelName, sockets[1]);
    return OK;
}
```

`new InputChannel()`如下：

```cpp
// frameworks/native/libs/input/InputTransport.cpp
InputChannel::InputChannel(const String8& name, int fd) :mName(name), mFd(fd) {
    // ...
    int result = fcntl(mFd, F_SETFL, O_NONBLOCK);
}
```

这里将每个文件描述符设定为`O_NONBLOCK`即`非阻塞式IO`。

- android_view_InputChannel_createInputChannel

这个函数其实就是native对象同java对象转化的过程。这里其实并非是转化，只是在native层创建了java对象。并通过`android_view_InputChannel_setNativeInputChannel`反射java对象，让java对象只有native对象的`内存地址`。

```cpp
// frameworks/base/core/jni/android_view_InputChannel.cpp
static jobject android_view_InputChannel_createInputChannel(JNIEnv* env,
        std::unique_ptr<NativeInputChannel> nativeInputChannel) {
    jobject inputChannelObj = env->NewObject(gInputChannelClassInfo.clazz,
            gInputChannelClassInfo.ctor);
    if (inputChannelObj) {
        android_view_InputChannel_setNativeInputChannel(env, inputChannelObj,
                 nativeInputChannel.release());
    }
    return inputChannelObj;
}
```

`android_view_InputChannel_setNativeInputChannel`就是反射java对象获取其内部的`mPtr`字段。

下面分别展示cpp和java的代码片段：

```cpp
// frameworks/base/core/jni/android_view_InputChannel.cpp
static void android_view_InputChannel_setNativeInputChannel(JNIEnv* env, jobject inputChannelObj,
        NativeInputChannel* nativeInputChannel) {
    env->SetLongField(inputChannelObj, gInputChannelClassInfo.mPtr,
             reinterpret_cast<jlong>(nativeInputChannel));
}
```

```java
// android/view/InputChannel.java
public final class InputChannel implements Parcelable {
    // ...
    private long mPtr; // used by native code
    // ...
}
```

#### - transferTo

简单来讲就是即将上一步获取的pair中的mClientChannel通过反射 “最终” 传递给ViewRootImpl的`mInputChannel`对象。

```cpp
// frameworks/base/core/jni/android_view_InputChannel.cpp
static void android_view_InputChannel_nativeTransferTo(JNIEnv* env, jobject obj,
        jobject otherObj) {
    if (android_view_InputChannel_getNativeInputChannel(env, otherObj) != NULL) {
        jniThrowException(env, "java/lang/IllegalStateException",
                "Other object already has a native input channel.");
        return;
    }

    NativeInputChannel* nativeInputChannel =
            android_view_InputChannel_getNativeInputChannel(env, obj);
    android_view_InputChannel_setNativeInputChannel(env, otherObj, nativeInputChannel);
    android_view_InputChannel_setNativeInputChannel(env, obj, NULL);
}
```

可以看到反射InputChannel拿到mPtr，之后强转为NativeInputChannel：

```cpp
// frameworks/base/core/jni/android_view_InputChannel.cpp
static NativeInputChannel* android_view_InputChannel_getNativeInputChannel(JNIEnv* env,
        jobject inputChannelObj) {
    jlong longPtr = env->GetLongField(inputChannelObj, gInputChannelClassInfo.mPtr);
    return reinterpret_cast<NativeInputChannel*>(longPtr);
}
```

最后通过android_view_InputChannel_setNativeInputChannel分别修改from(obj)和to(otherObj)的mPtr值。

#### - registerInputChannel

注意：这里的inputChannel为上面提到的Server。

```java
// com/android/server/input/InputManagerService.java
public void registerInputChannel(InputChannel inputChannel,
        InputWindowHandle inputWindowHandle) {
    // ...
    nativeRegisterInputChannel(mPtr, inputChannel, inputWindowHandle, false);
}
```

jni层实现：

```cpp
// frameworks/base/services/core/jni/com_android_server_input_InputManagerService.cpp
static void nativeRegisterInputChannel(JNIEnv* env, jclass /* clazz */,
        jlong ptr, jobject inputChannelObj, jobject inputWindowHandleObj, jboolean monitor) {
    NativeInputManager* im = reinterpret_cast<NativeInputManager*>(ptr);
    sp<InputChannel> inputChannel = android_view_InputChannel_getInputChannel(env,
            inputChannelObj);
    // ...
    sp<InputWindowHandle> inputWindowHandle =
            android_server_InputWindowHandle_getHandle(env, inputWindowHandleObj);
    status_t status = im->registerInputChannel(
            env, inputChannel, inputWindowHandle, monitor);
    // ...
    if (! monitor) {
        android_view_InputChannel_setDisposeCallback(env, inputChannelObj,
                handleInputChannelDisposed, im);
    }
}
```

最终执行到`registerInputChannel`：

```cpp
// frameworks/base/services/core/jni/com_android_server_input_InputManagerService.cpp
status_t NativeInputManager::registerInputChannel(JNIEnv* /* env */,
        const sp<InputChannel>& inputChannel,
        const sp<InputWindowHandle>& inputWindowHandle, bool monitor) {
    ATRACE_CALL();
    return mInputManager->getDispatcher()->registerInputChannel(
            inputChannel, inputWindowHandle, monitor);
}
```

其中的`getDispatcher()`为`frameworks/native/services/inputflinger/InputDispatcher.cpp`

这里的文件在`frameworks/native/services`下，这个目录中除了inputflinger还有surfaceflinger以及audiomanager / batteryservice / displayservice / nativeperms / powermanager / schedulerservice / sensorservice / thermalservice / vr等等。也就是说这里其实已经接近 ~~硬件~~（核心逻辑） 了。

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
status_t InputDispatcher::registerInputChannel(const sp<InputChannel>& inputChannel,
        const sp<InputWindowHandle>& inputWindowHandle, bool monitor) {
// ...
    { // acquire lock
        AutoMutex _l(mLock);
        // ...
        sp<Connection> connection = new Connection(inputChannel, inputWindowHandle, monitor);

        int fd = inputChannel->getFd();
        mConnectionsByFd.add(fd, connection);

        if (monitor) {
            mMonitoringChannels.push(inputChannel);
        }

        mLooper->addFd(fd, 0, ALOOPER_EVENT_INPUT, handleReceiveCallback, this);
    } // release lock

    // Wake the looper because some connections have changed.
    mLooper->wake();
    return OK;
}
```

这里会将所有参数用于生成一个`InputDispatcher::Connection`对象，并以文件描述符(fd)为key存储起来。

最后将fd添加到`mLooper中去`([Looper逻辑略, 源码:system/core/include/utils/Looper.h](http://j.mp/2IKNAZP)。

其中`handleReceiveCallback`则是`ALOOPER_EVENT_INPUT`类型消息的回调函数，输入事件与这个回调关联。

#### - InputChannel技术总结

- InputChannel调用`(native)openInputChannelPair`创建Server和Client。
- Client传递给ViewRootImpl的`mInputChannel`对象备用。
- `InputManagerService`将Server注册到`inputflinger`的`InputDispatcher`(及其对应的`InputDispatcherThread`的Looper)用于接收来自client的处理结果。
- InputDispatcher在register同时生成Connection，用于接收并发送来自`InputReader` enqueue的NotifyArgs。

### # 向Native注册InputEventReceiver

`WindowInputEventReceiver`继承自`InputEventReceiver`，而`InputEventReceiver`的构造函数中就包含了Java层同Native层通信的代码：

```java
// android/view/InputEventReceiver.java
public InputEventReceiver(InputChannel inputChannel, Looper looper) {
    // ...
    mInputChannel = inputChannel;
    mMessageQueue = looper.getQueue();
    mReceiverPtr = nativeInit(new WeakReference<InputEventReceiver>(this), inputChannel, mMessageQueue);
    mCloseGuard.open("dispose");
}
```

接着来到jni层：

```cpp
// frameworks/base/core/jni/android_view_InputEventReceiver.cpp
static jlong nativeInit(JNIEnv* env, jclass clazz, jobject receiverWeak,
        jobject inputChannelObj, jobject messageQueueObj) {
    sp<InputChannel> inputChannel = android_view_InputChannel_getInputChannel(env,
            inputChannelObj);
    // ...
    sp<MessageQueue> messageQueue = android_os_MessageQueue_getMessageQueue(env, messageQueueObj);
    // ...
    sp<NativeInputEventReceiver> receiver = new NativeInputEventReceiver(env,
            receiverWeak, inputChannel, messageQueue);
    status_t status = receiver->initialize();
    // ...
    receiver->incStrong(gInputEventReceiverClassInfo.clazz); // retain a reference for the object
    return reinterpret_cast<jlong>(receiver.get());
}
```

略过jobject的转换。这里会生成一个NativeInputEventReceiver对象，并调用其`initialize()函数`。

++**注意**++: 这里的inputChannel是`openInputChannelPair`中的Client。

#### - NativeInputEventReceiver构造函数

```
// frameworks/base/core/jni/android_view_InputEventReceiver.cpp
NativeInputEventReceiver::NativeInputEventReceiver(JNIEnv* env,
        jobject receiverWeak, const sp<InputChannel>& inputChannel,
        const sp<MessageQueue>& messageQueue) :
        mReceiverWeakGlobal(env->NewGlobalRef(receiverWeak)),
        mInputConsumer(inputChannel), mMessageQueue(messageQueue),
        mBatchedInputEventPending(false), mFdEvents(0) {
    if (kDebugDispatchCycle) {
        ALOGD("channel '%s' ~ Initializing input event receiver.", getInputChannelName());
    }
}
```

这里主要将`receiverWeak`即`WindowInputEventReceiver`注册到`mReceiverWeakGlobal`中去。

而其中的`inputChannel`将会被标记为`mInputConsumer`，即消费方。


当Looper监听到来自fd的消息之后通过`mReceiverWeakGlobal`获取对jobject引用，传递到java层InputEventReceiver的`dispatchInputEvent`函数。从而进入到ViewRootImpl及整个DecorView树中。

#### - NativeInputEventReceiver.initialize

```cpp
// frameworks/base/core/jni/android_view_InputEventReceiver.cpp
status_t NativeInputEventReceiver::initialize() {
    setFdEvents(ALOOPER_EVENT_INPUT);
    return OK;
}
void NativeInputEventReceiver::setFdEvents(int events) {
    if (mFdEvents != events) {
        mFdEvents = events;
        int fd = mInputConsumer.getChannel()->getFd();
        if (events) {
            mMessageQueue->getLooper()->addFd(fd, 0, events, this, NULL);
        } else {
            mMessageQueue->getLooper()->removeFd(fd);
        }
    }
}
```

主要是向Looper注册fd的对ALOOPER_EVENT_INPUT事件的监听。这里的回调函数为`this`，对应的实现为其中的`handleEvent`函数。

可以看到这里的消息类型同上面Server一样都是`ALOOPER_EVENT_INPUT`。

#### - InputEventReceiver技术总结

- nativeInit时创建`NativeInputEventReceiver`并在native持有java层InputEventReceiver的弱引用。以及存储Client InputChannel等。
- `NativeInputEventReceiver`的`initialize()`向Looper监听同Server一致的fd以及events(ALOOPER_EVENT_INPUT)，用于接收Server端pulish(::send)过来的消息并进行分发。

### # 生成InputStage管道

大概流程如下：

```
graph LR
NativePreImeInputStage-->OTHERS
OTHERS-->SyntheticInputStage
```

各个管道接受到输入消息后各司其职: 控制是否向下传递以及如何传递。

所有管道的先后顺序如下：

```log
NativePreImeInputStage
--> ViewPreImeInputStage
 --> ImeInputStage
  --> EarlyPostImeInputStage
   --> NativePostImeInputStage
    --> ViewPostImeInputStage
     --> SyntheticInputStage
```

略过。

## 接收输入消息

当Server端publish消息之后，作为Client端的InputEventReceiver，会收到消息。

接收消息的handleEvent函数如下:

```cpp
// frameworks/base/core/jni/android_view_InputEventReceiver.cpp
int NativeInputEventReceiver::handleEvent(int receiveFd, int events, void* data) {
    ...
    if (events & ALOOPER_EVENT_INPUT) {
        JNIEnv* env = AndroidRuntime::getJNIEnv();
        status_t status = consumeEvents(env, false /*consumeBatches*/, -1, NULL);
        mMessageQueue->raiseAndClearException(env, "handleReceiveCallback");
        return status == OK || status == NO_MEMORY ? 1 : 0;
    }
    if (events & ALOOPER_EVENT_OUTPUT) {
        ...
    }
    ...
    return 1;
}
```

这里分为ALOOPER_EVENT_INPUT和ALOOPER_EVENT_OUTPUT两种消息类型。主要看输入即ALOOPER_EVENT_INPUT。

可以看到consumeEvents函数调用时，并没有接收多少参数。也就是说消息的读取、解析、分发都是这个函数做的。

### # consumeEvents

consumeEvents是Client的核心函数之一：

```cpp
// frameworks/base/core/jni/android_view_InputEventReceiver.cpp
status_t NativeInputEventReceiver::consumeEvents(JNIEnv* env,
        bool consumeBatches, nsecs_t frameTime, bool* outConsumedBatch) {
    ...
    ScopedLocalRef<jobject> receiverObj(env, NULL);
    bool skipCallbacks = false;
    for (;;) {
        uint32_t seq;
        InputEvent* inputEvent;
        int32_t displayId;
        status_t status = mInputConsumer.consume(&mInputEventFactory,
                consumeBatches, frameTime, &seq, &inputEvent, &displayId);
        if (status) {
            if (status == WOULD_BLOCK) {
                if (!skipCallbacks && !mBatchedInputEventPending
                        && mInputConsumer.hasPendingBatch()) {
                    // There is a pending batch.  Come back later.
                    if (!receiverObj.get()) {
                        receiverObj.reset(jniGetReferent(env, mReceiverWeakGlobal));
                        if (!receiverObj.get()) {
                            ALOGW("channel '%s' ~ Receiver object was finalized "
                                    "without being disposed.", getInputChannelName());
                            return DEAD_OBJECT;
                        }
                    }
                    env->CallVoidMethod(receiverObj.get(),
                            gInputEventReceiverClassInfo.dispatchBatchedInputEventPending);
                    ...
                }
                return OK;
            }
            return status;
        }
        assert(inputEvent);

        if (!skipCallbacks) {
            ...
            jobject inputEventObj;
            switch (inputEvent->getType()) {
            case AINPUT_EVENT_TYPE_KEY:
                ...
                inputEventObj = android_view_KeyEvent_fromNative(env,
                        static_cast<KeyEvent*>(inputEvent));
                break;

            case AINPUT_EVENT_TYPE_MOTION: {
                ...
                MotionEvent* motionEvent = static_cast<MotionEvent*>(inputEvent);
                if ((motionEvent->getAction() & AMOTION_EVENT_ACTION_MOVE) && outConsumedBatch) {
                    *outConsumedBatch = true;
                }
                inputEventObj = android_view_MotionEvent_obtainAsCopy(env, motionEvent);
                break;
            }
            ...
            }

            if (inputEventObj) {
                ..
                env->CallVoidMethod(receiverObj.get(),
                        gInputEventReceiverClassInfo.dispatchInputEvent, seq, inputEventObj,
                        displayId);
            } else {
                skipCallbacks = true;
            }
        }

        if (skipCallbacks) {
            mInputConsumer.sendFinishedSignal(seq, false);
        }
    }
}
```

这里主要是三个行为：

- consume: 消费Server的消息即从socket读取消息
- dispatchInputEvent: 反射java代码，发送消息到InputEventReceiver即(WindowInputEventReceiver)
- sendFinishedSignal: 发送结束singal给Server(InputDispatcher)
> dispatchBatchedInputEventPending 略过

#### - consume

这一步就是读取消息并实例化对应的InputEvent(包括KeyEvent和MotionEvent):

```cpp
// frameworks/native/libs/input/InputTransport.cpp
status_t InputConsumer::consume(...) {
    ...
    while (!*outEvent) {
        if (mMsgDeferred) {
            mMsgDeferred = false;
        } else {
            status_t result = mChannel->receiveMessage(&mMsg);
            ...
        }
        switch (mMsg.header.type) {
        case InputMessage::TYPE_KEY: {
            KeyEvent* keyEvent = factory->createKeyEvent();
            initializeKeyEvent(keyEvent, &mMsg);
            *outSeq = mMsg.body.key.seq;
            *outEvent = keyEvent;
            break;
        }

        case AINPUT_EVENT_TYPE_MOTION: {
            ...
            MotionEvent* motionEvent = factory->createMotionEvent();
            ...
            break;
        }
        ...
    }
    return OK;
}
```

略过!

其中receiveMessage就是调用socket的`::recv`函数：

```cpp
// frameworks/native/libs/input/InputTransport.cpp
status_t InputChannel::receiveMessage(InputMessage* msg) {
    ssize_t nRead;
    do {
        nRead = ::recv(mFd, msg, sizeof(InputMessage), MSG_DONTWAIT);
    } while (nRead == -1 && errno == EINTR);

    if (nRead < 0) {
        int error = errno;
        if (error == EAGAIN || error == EWOULDBLOCK) {
            return WOULD_BLOCK;
        }
        if (error == EPIPE || error == ENOTCONN || error == ECONNREFUSED) {
            return DEAD_OBJECT;
        }
        return -error;
    }

    if (nRead == 0) { // check for EOF
        return DEAD_OBJECT;
    }

    if (!msg->isValid(nRead)) {
        return BAD_VALUE;
    }

    return OK;
}
```

### # dispatchInputEvent

在调用dispatchInputEvent之前，会将`inputEvent`转化成对应的jobject即`android_view_KeyEvent`和`android_view_MotionEvent`。逻辑如下：

```cpp
// frameworks/base/core/jni/android_view_InputEventReceiver.cpp
status_t NativeInputEventReceiver::consumeEvents(JNIEnv* env,
        bool consumeBatches, nsecs_t frameTime, bool* outConsumedBatch) {
    ...
    jobject inputEventObj;
    switch (inputEvent->getType()) {
    case AINPUT_EVENT_TYPE_KEY:
        if (kDebugDispatchCycle) {
            ALOGD("channel '%s' ~ Received key event.", getInputChannelName());
        }
        inputEventObj = android_view_KeyEvent_fromNative(env,
                static_cast<KeyEvent*>(inputEvent));
        break;
    
    case AINPUT_EVENT_TYPE_MOTION: {
        if (kDebugDispatchCycle) {
            ALOGD("channel '%s' ~ Received motion event.", getInputChannelName());
        }
        MotionEvent* motionEvent = static_cast<MotionEvent*>(inputEvent);
        if ((motionEvent->getAction() & AMOTION_EVENT_ACTION_MOVE) && outConsumedBatch) {
            *outConsumedBatch = true;
        }
        inputEventObj = android_view_MotionEvent_obtainAsCopy(env, motionEvent);
        break;
    }
    ...
}
```

如何生成的过程可以看`KeyEvent.java`的fromNative()函数和`MotionEvent.java`的`obtainAsCopy()`函数。

真正开始往java层dispatch是通过这一步实现的:

```cpp
env->CallVoidMethod(receiverObj.get(),
                        gInputEventReceiverClassInfo.dispatchInputEvent, seq, inputEventObj,
                        displayId);
```


### # sendFinishedSignal

这一步其实就是告知Server即InputDispatcher那边，这里以及处理完了。

包括java层会调用到的finishInputEvent函数，最终也到达这里。

而sendFinishedSignal函数最终也是通过socket发送消息，如同Server端往Client端发送消息一样：

```cpp
status_t InputChannel::sendMessage(const InputMessage* msg) {
    size_t msgLength = msg->size();
    ssize_t nWrite;
    do {
        nWrite = ::send(mFd, msg, msgLength, MSG_DONTWAIT | MSG_NOSIGNAL);
    } while (nWrite == -1 && errno == EINTR);
    ...
}
```

### # 分发消息总结

- InputReceiver收到消息之后回调handleEvent函数。
- 首先会去socket中接收Server端发送过来的数据，并生成InputEvent。
- 之后发生Java层的InputEventReceiver的`dispatchInputEvent`函数，向上层发送函数。
- 如果传递失败，比如抛异常则Client(Consumer)回向Server(InputDispather)发送结束信号。

## Java层分发消息

上面提到的native最后一步是反射`InputEventReceiver`的`dispatchInputEvent`如下：

```java
// android/view/InputEventReceiver.java
// Called from native code.
@SuppressWarnings("unused")
private void dispatchInputEvent(int seq, InputEvent event, int displayId) {
    mSeqMap.put(event.getSequenceNumber(), seq);
    onInputEvent(event, displayId);
}
```

这里会调用到`onInputEvent`，而ViewRootImpl里面InputEventReceiver的子类WindowInputEventReceiver就是通过重写这个函数实现消息的获取的:

```cpp
// android/view/ViewRootImpl.java
final class WindowInputEventReceiver extends InputEventReceiver {
    public WindowInputEventReceiver(InputChannel inputChannel, Looper looper) {
        super(inputChannel, looper);
    }

    @Override
    public void onInputEvent(InputEvent event, int displayId) {
        enqueueInputEvent(event, this, 0, true);
    }
    ...
}
```

可以看到重写之后会调用一个`enqueueInputEvent`函数。

### # enqueueInputEvent

这里会将InputEvent转化成QueuedInputEvent:

```java
// android/view/ViewRootImpl.java
void enqueueInputEvent(InputEvent event,
        InputEventReceiver receiver, int flags, boolean processImmediately) {
    adjustInputEventForCompatibility(event);
    QueuedInputEvent q = obtainQueuedInputEvent(event, receiver, flags);

    // Always enqueue the input event in order, regardless of its time stamp.
    // We do this because the application or the IME may inject key events
    // in response to touch events and we want to ensure that the injected keys
    // are processed in the order they were received and we cannot trust that
    // the time stamp of injected events are monotonic.
    QueuedInputEvent last = mPendingInputEventTail;
    if (last == null) {
        mPendingInputEventHead = q;
        mPendingInputEventTail = q;
    } else {
        last.mNext = q;
        mPendingInputEventTail = q;
    }
    mPendingInputEventCount += 1;
    Trace.traceCounter(Trace.TRACE_TAG_INPUT, mPendingInputEventQueueLengthCounterName,
            mPendingInputEventCount);

    if (processImmediately) {
        doProcessInputEvents();
    } else {
        scheduleProcessInputEvents();
    }
}
```

这里会将消息加入到`mPendingInputEventTail`的队尾(本身就是)，之后调用`doProcessInputEvents()`遍历整个链表：

```java
// android/view/ViewRootImpl.java
void doProcessInputEvents() {
    // Deliver all pending input events in the queue.
    while (mPendingInputEventHead != null) {
        QueuedInputEvent q = mPendingInputEventHead;
        mPendingInputEventHead = q.mNext;
        if (mPendingInputEventHead == null) {
            mPendingInputEventTail = null;
        }
        q.mNext = null;

        mPendingInputEventCount -= 1;
        Trace.traceCounter(Trace.TRACE_TAG_INPUT, mPendingInputEventQueueLengthCounterName,
                mPendingInputEventCount);

        long eventTime = q.mEvent.getEventTimeNano();
        long oldestEventTime = eventTime;
        if (q.mEvent instanceof MotionEvent) {
            MotionEvent me = (MotionEvent)q.mEvent;
            if (me.getHistorySize() > 0) {
                oldestEventTime = me.getHistoricalEventTimeNano(0);
            }
        }
        mChoreographer.mFrameInfo.updateInputEventTime(eventTime, oldestEventTime);

        deliverInputEvent(q);
    }

    // We are done processing all input events that we can process right now
    // so we can clear the pending flag immediately.
    if (mProcessInputEventsScheduled) {
        mProcessInputEventsScheduled = false;
        mHandler.removeMessages(MSG_PROCESS_INPUT_EVENTS);
    }
}
```

这里主要是进行链表遍历，而每个`QueuedInputEvent`都交给`deliverInputEvent`处理:

```java
// android/view/ViewRootImpl.java
private void deliverInputEvent(QueuedInputEvent q) {
    Trace.asyncTraceBegin(Trace.TRACE_TAG_VIEW, "deliverInputEvent",
            q.mEvent.getSequenceNumber());
    if (mInputEventConsistencyVerifier != null) {
        mInputEventConsistencyVerifier.onInputEvent(q.mEvent, 0);
    }

    InputStage stage;
    if (q.shouldSendToSynthesizer()) {
        stage = mSyntheticInputStage;
    } else {
        stage = q.shouldSkipIme() ? mFirstPostImeInputStage : mFirstInputStage;
    }

    if (stage != null) {
        stage.deliver(q);
    } else {
        finishInputEvent(q);
    }
}
```

这里就用到setView的时候创建的管道了。经过一系列的撸过，到达倒数第二个Stage，如下：

```java
// android/view/ViewRootImpl.java
final class ViewPostImeInputStage extends InputStage {
    public ViewPostImeInputStage(InputStage next) {
        super(next);
    }

    @Override
    protected int onProcess(QueuedInputEvent q) {
        if (q.mEvent instanceof KeyEvent) {
            return processPointerEvent(q);
        } else {
            final int source = q.mEvent.getSource();
            if ((source & InputDevice.SOURCE_CLASS_POINTER) != 0) {
                return processPointerEvent(q);
            } else if ((source & InputDevice.SOURCE_CLASS_TRACKBALL) != 0) {
                return processTrackballEvent(q);
            } else {
                return processGenericMotionEvent(q);
            }
        }
    }
}
```

中间过程省略。

[![android-viewrootimpl-InputEventReceiver-DecorView-dispatchInputEvent.png](https://j.mp/2U0bXsT)](https://j.mp/2x1Jbiy)

> 截图是MotionEvent，不是KeyEvent。

### # DecorView

来看DecorView如何处理:

```java
// com/android/internal/policy/DecorView.java
    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        final int keyCode = event.getKeyCode();
        final int action = event.getAction();
        final boolean isDown = action == KeyEvent.ACTION_DOWN;

        if (isDown && (event.getRepeatCount() == 0)) {
            // First handle chording of panel key: if a panel key is held
            // but not released, try to execute a shortcut in it.
            if ((mWindow.mPanelChordingKey > 0) && (mWindow.mPanelChordingKey != keyCode)) {
                boolean handled = dispatchKeyShortcutEvent(event);
                if (handled) {
                    return true;
                }
            }

            // If a panel is open, perform a shortcut on it without the
            // chorded panel key
            if ((mWindow.mPreparedPanel != null) && mWindow.mPreparedPanel.isOpen) {
                if (mWindow.performPanelShortcut(mWindow.mPreparedPanel, keyCode, event, 0)) {
                    return true;
                }
            }
        }

        if (!mWindow.isDestroyed()) {
            final Window.Callback cb = mWindow.getCallback();
            final boolean handled = cb != null && mFeatureId < 0 ? cb.dispatchKeyEvent(event)
                    : super.dispatchKeyEvent(event);
            if (handled) {
                return true;
            }
        }

        return isDown ? mWindow.onKeyDown(mFeatureId, event.getKeyCode(), event)
                : mWindow.onKeyUp(mFeatureId, event.getKeyCode(), event);
    }
```

这里会拿到Window的Callback，如果存在则交给Callback处理。

其中这里的Window是PhoneWindow，而PhoneWindow是Activity的attach函数创建的，如下：

```java
// android/app/Activity.java
final void attach(Context context, ActivityThread aThread,
        Instrumentation instr, IBinder token, int ident,
        Application application, Intent intent, ActivityInfo info,
        CharSequence title, Activity parent, String id,
        NonConfigurationInstances lastNonConfigurationInstances,
        Configuration config, String referrer, IVoiceInteractor voiceInteractor,
        Window window, ActivityConfigCallback activityConfigCallback) {
    attachBaseContext(context);

    mFragments.attachHost(null /*parent*/);

    mWindow = new PhoneWindow(this, window, activityConfigCallback);
    mWindow.setWindowControllerCallback(this);
    mWindow.setCallback(this);
    ...
}
```

也就是说这个Callback就是Activity本身。

```java
// android/app/Activity.java
public boolean dispatchKeyEvent(KeyEvent event) {
    onUserInteraction();

    // Let action bars open menus in response to the menu key prioritized over
    // the window handling it
    final int keyCode = event.getKeyCode();
    if (keyCode == KeyEvent.KEYCODE_MENU &&
            mActionBar != null && mActionBar.onMenuKeyEvent(event)) {
        return true;
    }

    Window win = getWindow();
    if (win.superDispatchKeyEvent(event)) {
        return true;
    }
    View decor = mDecor;
    if (decor == null) decor = win.getDecorView();
    return event.dispatch(this, decor != null
            ? decor.getKeyDispatcherState() : null, this);
}
```

这里Activity会通过再次调用window的superDispatchKeyEvent，这时就会进入到View的`dispatchKeyEvent`。

之后就是View树上面的传递了。如果View并不拦截KeyEvnet。那么就跑到KeyEvent的dispatch函数中：

```java
// android/view/KeyEvent
public final boolean dispatch(Callback receiver, DispatcherState state,
        Object target) {
    switch (mAction) {
        case ACTION_DOWN: {
            mFlags &= ~FLAG_START_TRACKING;
            if (DEBUG) Log.v(TAG, "Key down to " + target + " in " + state
                    + ": " + this);
            boolean res = receiver.onKeyDown(mKeyCode, this);
            if (state != null) {
                if (res && mRepeatCount == 0 && (mFlags&FLAG_START_TRACKING) != 0) {
                    if (DEBUG) Log.v(TAG, "  Start tracking!");
                    state.startTracking(this, target);
                } else if (isLongPress() && state.isTracking(this)) {
                    try {
                        if (receiver.onKeyLongPress(mKeyCode, this)) {
                            if (DEBUG) Log.v(TAG, "  Clear from long press!");
                            state.performedLongPress(this);
                            res = true;
                        }
                    } catch (AbstractMethodError e) {
                    }
                }
            }
            return res;
        }
        case ACTION_UP:
            if (DEBUG) Log.v(TAG, "Key up to " + target + " in " + state
                    + ": " + this);
            if (state != null) {
                state.handleUpEvent(this);
            }
            return receiver.onKeyUp(mKeyCode, this);
        case ACTION_MULTIPLE:
            final int count = mRepeatCount;
            final int code = mKeyCode;
            if (receiver.onKeyMultiple(code, count, this)) {
                return true;
            }
            if (code != KeyEvent.KEYCODE_UNKNOWN) {
                mAction = ACTION_DOWN;
                mRepeatCount = 0;
                boolean handled = receiver.onKeyDown(code, this);
                if (handled) {
                    mAction = ACTION_UP;
                    receiver.onKeyUp(code, this);
                }
                mAction = ACTION_MULTIPLE;
                mRepeatCount = count;
                return handled;
            }
            return false;
    }
    return false;
}
```

其中receiver也是Activity本身。根据KeyEvent的Action回调Activity的onKeyDown/Up等。

### # Java层分发总结

- InputEventReceiver收到消息即`dispatchInputEvent`调用onInputEvent等等子类重写。
- ViewRootImpl的WindowInputEventReceiver重写后将消息加入QueuedInputEvent。
- 遍历链表交给InputStage的管道流处理。
- 最后`ViewPostImeInputStage`的`onProcess`函数根据InputEvent实例进行分发。
- DecorView会第一个收到InputEvent(KeyEvent/MotionEvent)之后交给PhoneWindow的Callback(Activity)处理。
- Activity收到消息后再经过PhoneWindow调到View树(DecorView的super)里面。
- 经过View树再回到Activity
