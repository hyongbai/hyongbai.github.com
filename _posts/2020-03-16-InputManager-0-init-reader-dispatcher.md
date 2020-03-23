---
layout: post
title: "Android输入事件0: 底层初始化与读取和分发"
description: "Android输入事件0: 底层初始化与读取和分发"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-03-16 23:03:57+00:00
---

> 基于 android-8.1.0_r60
>
> 为求简洁，代码已删除大量细枝末节。

## 启动

### # 初始化

Android中所有的系统Service都是在SystemServer中启动和管理的。其中InputManagerService也不例外。

在SystemServer的run方法中将InputManagerService放到startOtherServices函数中运行。如下：

```java
// frameworks/base/services/java/com/android/server/SystemServer.java
/** The main entry point from zygote. */
public static void main(String[] args) {
    new SystemServer().run();
}

private void run() {
    ...
    traceBeginAndSlog("StartServices");
    startBootstrapServices();
    startCoreServices();
    startOtherServices();
    SystemServerInitThreadPool.shutdown();
    ...
}

private void startOtherServices() {
    ...
    inputManager = new InputManagerService(context);
    ...
    inputManager.setWindowManagerCallbacks(wm.getInputMonitor());
    inputManager.start();
}
```  

可以看到`startOtherServices()`中实例化了一个`InputManagerService`对象inputManager，后面执行了inputManager的start()方法。

注意: InputManagerService内部的mWindowManagerCallbacks来自`wm.getInputMonitor()`。

先来看看`InputManagerService`的构造函数：

```java
// frameworks/base/services/core/java/com/android/server/input/InputManagerService.java
public InputManagerService(Context context) {
    ...
    mPtr = nativeInit(this, mContext, mHandler.getLooper().getQueue());
    ...
    LocalServices.addService(InputManagerInternal.class, new LocalService());
}
```

`InputManagerService`构造函数直接带着当前的context以及MessageQueue运行到jni层对应的nativeInit函数：

```cpp
// frameworks/base/services/core/jni/com_android_server_intput_InputManagerService.cpp
static jlong nativeInit(JNIEnv* env, jclass /* clazz */,
        jobject serviceObj, jobject contextObj, jobject messageQueueObj) {
    sp<MessageQueue> messageQueue = android_os_MessageQueue_getMessageQueue(env, messageQueueObj);
    ...
    NativeInputManager* im = new NativeInputManager(contextObj, serviceObj,
            messageQueue->getLooper());
    im->incStrong(0);
    return reinterpret_cast<jlong>(im);
}
```

jni层会创建一个NativeInputManager的c++对象，获取其内存地址并转化成jlong，交给InputManagerService的java层引用。

而NativeInputManager的构造函数同时也会实例化并持有一个InputManager的c++对象:

```cpp
// frameworks/base/services/core/jni/com_android_server_intput_InputManagerService.cpp
NativeInputManager::NativeInputManager(jobject contextObj,
        jobject serviceObj, const sp<Looper>& looper) :
        mLooper(looper), mInteractive(true) {
    JNIEnv* env = jniEnv();
    ...
    sp<EventHub> eventHub = new EventHub();
    mInputManager = new InputManager(eventHub, this, this);
}
```

而在InputManager内部会分别创建一个`InputDispatcher`和`InputReader`，及分别持有他们的对应的线程: `InputDispatcherThread`和`InputReaderThread`。

```cpp
// frameworks/native/services/inputflinger/InputManager.cpp
InputManager::InputManager(
        const sp<EventHubInterface>& eventHub,
        const sp<InputReaderPolicyInterface>& readerPolicy,
        const sp<InputDispatcherPolicyInterface>& dispatcherPolicy) {
    mDispatcher = new InputDispatcher(dispatcherPolicy);
    mReader = new InputReader(eventHub, readerPolicy, mDispatcher);
    initialize();
}

void InputManager::initialize() {
    mReaderThread = new InputReaderThread(mReader);
    mDispatcherThread = new InputDispatcherThread(mDispatcher);
}
```

其中:

- InputReader：用于读取输入事件，并将其发送给InputDispatcher。

- InputDispatcher：用于接收InputReader发来的输入事件，并将输入事件通过InputChannel的Server发送给Client，并在Client的handleEvent中发送到java层的InputEventReceiver。


### # (Native)InputManager启动

SystemServer启动之后在startOtherServices()实例化InputManagerService，紧接着之后在这个方法里面调用InputManagerService的start()方法：

```java
// frameworks/base/services/core/java/com/android/server/input/InputManagerService.java
public void start() {
    nativeStart(mPtr);
    ...
}
```

之后来到jni层com_android_server_intput_InputManagerService.cpp的`nativeStart`方法：

```cpp
// frameworks/base/services/core/jni/com_android_server_intput_InputManagerService.cpp
static void nativeStart(JNIEnv* env, jclass /* clazz */, jlong ptr) {
    NativeInputManager* im = reinterpret_cast<NativeInputManager*>(ptr);
    status_t result = im->getInputManager()->start();
    ...
}
```

这里会将ptr转化为NativeInputManager(即InputManagerService.java的jni实现)获取并启动InputManager.cpp，即调用`start()`方法。

```cpp
// frameworks/native/services/inputflinger/InputManager.cpp
status_t InputManager::start() {
    status_t result = mDispatcherThread->run("InputDispatcher", PRIORITY_URGENT_DISPLAY);
    ...
    result = mReaderThread->run("InputReader", PRIORITY_URGENT_DISPLAY);
    ...
    return OK;
}
```

这里会分别启动`InputDispatcherThread`和`InputReaderThread`线程，让InputDispatcher和InputReader工作。

### # InputManagerService启动过程总结

- 在SystemServer初始化时实例化InputManagerService。
- InputManagerService构造函数创建jni层的NativeInputManager。
- NativeInputManager里创建了InputManager。
- InputManager创建InputDispather和InputReader的实例，及InputReaderThread和InputDispatherThread。
- 最后SystemServer启动InputManagerService及对应nativeStart，将InputDispatherThread和InputReaderThread启动。实现对输入设备的读取和分发。

## Native读取输入事件(InputReader)

这里的逻辑特别多，简单说。

```cpp
// frameworks/native/services/inputflinger/InputReader.cpp
bool InputReaderThread::threadLoop() {
    mReader->loopOnce();
    return true;
}
```

每次InputReader线程都会调用`InputReader::loopOnce()`读取输入流，并flush到QueueInputListener。而QueueInputListener会持有上面构造函数的InputDispatcher。

`loopOnce`如下:

```cpp
// frameworks/native/services/inputflinger/InputReader.cpp
void InputReader::loopOnce() {
    size_t count = mEventHub->getEvents(timeoutMillis, mEventBuffer, EVENT_BUFFER_SIZE);
    { // acquire lock
        AutoMutex _l(mLock);
        mReaderIsAliveCondition.broadcast();
        if (count) {
            processEventsLocked(mEventBuffer, count);
        }
        ...
    } // release lock
    ...
    mQueuedListener->flush();
}
```

### # EventHub

`getEvents`函数会去/dev/input目录下面去找当前的输入设备。之后读取其内容，并解析成RawEvents。

### # 处理原始事件(RawEvent)

```cpp
// frameworks/native/services/inputflinger/InputReader.cpp
void InputReader::processEventsLocked(const RawEvent* rawEvents, size_t count) {
    for (const RawEvent* rawEvent = rawEvents; count;) {
        int32_t type = rawEvent->type;
        size_t batchSize = 1;
        if (type < EventHubInterface::FIRST_SYNTHETIC_EVENT) {
            ...
            processEventsForDeviceLocked(deviceId, rawEvent, batchSize);
        } else {
            switch (rawEvent->type) {
            case EventHubInterface::DEVICE_ADDED:
                addDeviceLocked(rawEvent->when, rawEvent->deviceId);
                break;
            case EventHubInterface::DEVICE_REMOVED:
                removeDeviceLocked(rawEvent->when, rawEvent->deviceId);
                break;
            case EventHubInterface::FINISHED_DEVICE_SCAN:
                handleConfigurationChangedLocked(rawEvent->when);
                break;
        ...
    }
}
```

#### - 添加设备(addDeviceLocked)：

通过classes(类似于flag)，确定device支持的类型。在这里Device对于输入方式/类型的支持叫做Mapper，可以理解成不同的映射。

比如:

- 键盘对应`KeyboardInputMapper`
- 多点触摸对应`MultiTouchInputMapper`
- 单点触摸对应`SingleTouchInputMapper`
- 鼠标或者追踪球对应`CursorInputMapper`
- 其他

具体见：`createDeviceLocked` 函数。

#### - processEventsForDeviceLocked

这里是device处理原始输入事件的地方。这里的直接逻辑很简单：

```cpp
// frameworks/native/services/inputflinger/InputReader.cpp
void InputReader::processEventsForDeviceLocked(int32_t deviceId,
        const RawEvent* rawEvents, size_t count) {
    ...
    InputDevice* device = mDevices.valueAt(deviceIndex);
    ...
    device->process(rawEvents, count);
}

void InputDevice::process(const RawEvent* rawEvents, size_t count) {
    ...
    size_t numMappers = mMappers.size();
    for (const RawEvent* rawEvent = rawEvents; count--; rawEvent++) {
        ...
        } else {
            for (size_t i = 0; i < numMappers; i++) {
                InputMapper* mapper = mMappers[i];
                mapper->process(rawEvent);
            }
        }
    }
}
```

遍历其中所有的Mapper，并调用每个Mapper的process函数。

以`KeyboardInputMapper`为例：

```cpp
// frameworks/native/services/inputflinger/InputReader.cpp
void KeyboardInputMapper::process(const RawEvent* rawEvent) {
    switch (rawEvent->type) {
    case EV_KEY: {
        int32_t scanCode = rawEvent->code;
        int32_t usageCode = mCurrentHidUsage;
        mCurrentHidUsage = 0;
        if (isKeyboardOrGamepadKey(scanCode)) {
            processKey(rawEvent->when, rawEvent->value != 0, scanCode, usageCode);
        }
        break;
    }
    ...
}
bool KeyboardInputMapper::isKeyboardOrGamepadKey(int32_t scanCode) {
    return scanCode < BTN_MOUSE
        || scanCode >= KEY_OK
        || (scanCode >= BTN_MISC && scanCode < BTN_MOUSE)
        || (scanCode >= BTN_JOYSTICK && scanCode < BTN_DIGI);
}
```

如果是Keyboard或者Gamepad则进入`processKey`函数：


```cpp
// frameworks/native/services/inputflinger/InputReader.cpp
void KeyboardInputMapper::processKey(nsecs_t when, bool down, int32_t scanCode,
        int32_t usageCode) {
    int32_t keyCode;
    int32_t keyMetaState;
    uint32_t policyFlags;

    if (getEventHub()->mapKey(getDeviceId(), scanCode, usageCode, mMetaState,
                              &keyCode, &keyMetaState, &policyFlags)) {
        keyCode = AKEYCODE_UNKNOWN;
        keyMetaState = mMetaState;
        policyFlags = 0;
    }

    if (down) {
        // Rotate key codes according to orientation if needed.
        if (mParameters.orientationAware && mParameters.hasAssociatedDisplay) {
            keyCode = rotateKeyCode(keyCode, mOrientation);
        }

        // Add key down.
        ssize_t keyDownIndex = findKeyDown(scanCode);
        if (keyDownIndex >= 0) {
            // key repeat, be sure to use same keycode as before in case of rotation
            keyCode = mKeyDowns.itemAt(keyDownIndex).keyCode;
        } else {
            // key down
            if ((policyFlags & POLICY_FLAG_VIRTUAL)
                    && mContext->shouldDropVirtualKey(when,
                            getDevice(), keyCode, scanCode)) {
                return;
            }
            if (policyFlags & POLICY_FLAG_GESTURE) {
                mDevice->cancelTouch(when);
            }

            mKeyDowns.push();
            KeyDown& keyDown = mKeyDowns.editTop();
            keyDown.keyCode = keyCode;
            keyDown.scanCode = scanCode;
        }

        mDownTime = when;
    } else {
        // Remove key down.
        ssize_t keyDownIndex = findKeyDown(scanCode);
        if (keyDownIndex >= 0) {
            // key up, be sure to use same keycode as before in case of rotation
            keyCode = mKeyDowns.itemAt(keyDownIndex).keyCode;
            mKeyDowns.removeAt(size_t(keyDownIndex));
        } else {
            ...
            return;
        }
    }
    ...
    if (down && getDevice()->isExternal() && !isMediaKey(keyCode)) {
        policyFlags |= POLICY_FLAG_WAKE;
    }
    if (mParameters.handlesKeyRepeat) {
        policyFlags |= POLICY_FLAG_DISABLE_KEY_REPEAT;
    }
    NotifyKeyArgs args(when, getDeviceId(), mSource, policyFlags,
            down ? AKEY_EVENT_ACTION_DOWN : AKEY_EVENT_ACTION_UP,
            AKEY_EVENT_FLAG_FROM_SYSTEM, keyCode, scanCode, keyMetaState, downTime);
    getListener()->notifyKey(&args);
}
```

前面的逻辑是将所有的输入事件的down行为全部缓存起来的，从而记录当前所有正在发生的事件。

基于RawEvent的各种信息包括when/keyCode/mSource等创建一个`NotifyKeyArgs`。最终调用`QueueInputListener`的`notifyKey`将当前的操作放入其内部的队列(mArgsQueue)中，等待flush。


### # QueueInputListener

下面来看看最终是如何flush到InputDispather中去的。

flush函数:

```cpp
// frameworks/native/services/inputflinger/QueuedInputListener.cpp
void QueuedInputListener::notifyKey(const NotifyKeyArgs* args) {
    mArgsQueue.push(new NotifyKeyArgs(*args));
}

void QueuedInputListener::notifyMotion(const NotifyMotionArgs* args) {
    mArgsQueue.push(new NotifyMotionArgs(*args));
}

void QueuedInputListener::flush() {
    size_t count = mArgsQueue.size();
    for (size_t i = 0; i < count; i++) {
        NotifyArgs* args = mArgsQueue[i];
        args->notify(mInnerListener);
        delete args;
    }
    mArgsQueue.clear();
}
```

这里分别调用queue中每一个NotifyArgs的notify函数，
其中的mInnerListener就是InputDispatcher。还是以上面的NotifyKeyArgs为例。

```cpp
// frameworks/native/services/inputflinger/QueuedInputListener.cpp
void NotifyKeyArgs::notify(const sp<InputListenerInterface>& listener) const {
    listener->notifyKey(this);
}
```

可以看到NotifyKeyArgs最近进入了listener(`InputDispatcher`:`InputListenerInterface`)的`notifyKey`函数。


### # 加入InputDispatcher队列

以KeyEvent为例, 下来进入InputDispatcher的notifyKey函数:

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::notifyKey(const NotifyKeyArgs* args) {
    ...
    KeyEvent event;
    event.initialize(args->deviceId, args->source, args->action,
            flags, keyCode, args->scanCode, metaState, 0,
            args->downTime, args->eventTime);

    mPolicy->interceptKeyBeforeQueueing(&event, /*byref*/ policyFlags);

    bool needWake;
    { // acquire lock
        mLock.lock();

        if (shouldSendKeyToInputFilterLocked(args)) {
            mLock.unlock();

            policyFlags |= POLICY_FLAG_FILTERED;
            if (!mPolicy->filterInputEvent(&event, policyFlags)) {
                return; // event was consumed by the filter
            }

            mLock.lock();
        }

        int32_t repeatCount = 0;
        KeyEntry* newEntry = new KeyEntry(args->eventTime,
                args->deviceId, args->source, policyFlags,
                args->action, flags, keyCode, args->scanCode,
                metaState, repeatCount, args->downTime);

        needWake = enqueueInboundEventLocked(newEntry);
        mLock.unlock();
    } // release lock

    if (needWake) {
        mLooper->wake();
    }
}
```

这里一开始会交由Java层InputManagerService的`interceptKeyBeforeQueueing`函数处理，用于拦截某些系统行为。

不被拦截的输入事件则通过`enqueueInboundEventLocked`加入到`mInboundQueue`的队尾。

之后唤起Looper，进入InputDispatcher的分发环节。

#### - 拦截输入事件(interceptKeyBeforeQueueing)

这一步需要将NotifyKeyArgs转化成KeyEvent，因为接下来需要交给Java层处理。经过这里拦截的事件，都不会进入到InputDispatcher的队列，更不会分发到应用层。

上面的mPolicy就是NativeInputManager。

```cpp
// frameworks/base/services/core/jni/com_android_server_intput_InputManagerService.cpp
void NativeInputManager::interceptKeyBeforeQueueing(const KeyEvent* keyEvent,
        uint32_t& policyFlags) {
    ...
        JNIEnv* env = jniEnv();
        jobject keyEventObj = android_view_KeyEvent_fromNative(env, keyEvent);
        jint wmActions;
        if (keyEventObj) {
            wmActions = env->CallIntMethod(mServiceObj,
                    gServiceClassInfo.interceptKeyBeforeQueueing,
                    keyEventObj, policyFlags);
            ...
}
```

这里关键的一步就是`env->CallIntMethod`，其中`mServiceObj`就是Java层的`InputManagerService`。这句函数意思就是调用`InputManagerService`的`interceptKeyBeforeQueueing`函数：

```java
// frameworks/base/services/core/java/com/android/server/input/InputManagerService.java
private int interceptKeyBeforeQueueing(KeyEvent event, int policyFlags) {
    return mWindowManagerCallbacks.interceptKeyBeforeQueueing(event, policyFlags);
}
```

在SystemServer中可以知道InputManagerService中的mWindowManagerCallbacks其实就是WindowManagerService里面的`mInputMonitor`：

```java
// frameworks/base/services/core/java/com/android/server/vm/InputMonitor.java
@Override
public int interceptKeyBeforeQueueing(KeyEvent event, int policyFlags) {
    return mService.mPolicy.interceptKeyBeforeQueueing(event, policyFlags);
}
```

其中的mService为WindowManagerService，mPolicy为其构造函数中`PhoneWindowManager()`。如下为WindowManagerService创建过程：

```java
// frameworks/base/services/java/com/android/server/SystemServer.java
private void startOtherServices() {
    wm = WindowManagerService.main(context, inputManager,
            mFactoryTestMode != FactoryTest.FACTORY_TEST_LOW_LEVEL,
            !mFirstBoot, mOnlyCore, new PhoneWindowManager());
}
```

[PhoneWindowManager的interceptKeyBeforeQueueing函数纯语句就有300多行(点击查看源码)](https://j.mp/3d2Ggqb)。

总之这里就是一些与系统行为相关的拦截，比如电源键、休眠键、通话键、ASSIST等等。都是在这一步进行拦截的。这也是应用层永远无法对这些按键事件进行拦截的原因。

#### - 加入队列(enqueueInboundEventLocked)

进入这一步之前KeyNotifyArgs会转化成`KeyEntry`对象。

下面是加入Dispatcher队列的过程：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
bool InputDispatcher::enqueueInboundEventLocked(EventEntry* entry) {
    bool needWake = mInboundQueue.isEmpty();
    mInboundQueue.enqueueAtTail(entry);
    traceInboundQueueLengthLocked();

    switch (entry->type) {
    case EventEntry::TYPE_KEY: {
        // Optimize app switch latency.
        // If the application takes too long to catch up then we drop all events preceding the app switch key.
        ...
        break;
    }

    case EventEntry::TYPE_MOTION: {
        // Optimize case where the current application is unresponsive and the user
        // decides to touch a window in a different application.
        // If the application takes too long to catch up then we drop all events preceding
        // the touch into the other window.
        MotionEntry* motionEntry = static_cast<MotionEntry*>(entry);
        if (motionEntry->action == AMOTION_EVENT_ACTION_DOWN
                && (motionEntry->source & AINPUT_SOURCE_CLASS_POINTER)
                && mInputTargetWaitCause == INPUT_TARGET_WAIT_CAUSE_APPLICATION_NOT_READY
                && mInputTargetWaitApplicationHandle != NULL) {
            int32_t displayId = motionEntry->displayId;
            int32_t x = int32_t(motionEntry->pointerCoords[0].
                    getAxisValue(AMOTION_EVENT_AXIS_X));
            int32_t y = int32_t(motionEntry->pointerCoords[0].
                    getAxisValue(AMOTION_EVENT_AXIS_Y));
            sp<InputWindowHandle> touchedWindowHandle = findTouchedWindowAtLocked(displayId, x, y);
            if (touchedWindowHandle != NULL
                    && touchedWindowHandle->inputApplicationHandle
                            != mInputTargetWaitApplicationHandle) {
                // User touched a different application than the one we are waiting on.
                // Flag the event, and start pruning the input queue.
                mNextUnblockedEvent = motionEntry;
                needWake = true;
            }
        }
        break;
    }
    }

    return needWake;
}
```

这里直接将EventEntry加入mInboundQueue的队尾。如果是MotionEvent的话，则会由`findTouchedWindowAtLocked`找出当前处于焦点状态的WindowInfo，并且对比之前的mInputTargetWaitApplicationHandle，确定是否需要修剪之前的队列，并将此次窗口变动的事件记录在mNextUnblockedEvent。

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
sp<InputWindowHandle> InputDispatcher::findTouchedWindowAtLocked(int32_t displayId,
        int32_t x, int32_t y) {
    // Traverse windows from front to back to find touched window.
    size_t numWindows = mWindowHandles.size();
    for (size_t i = 0; i < numWindows; i++) {
        sp<InputWindowHandle> windowHandle = mWindowHandles.itemAt(i);
        const InputWindowInfo* windowInfo = windowHandle->getInfo();
        if (windowInfo->displayId == displayId) {
            int32_t flags = windowInfo->layoutParamsFlags;
            if (windowInfo->visible) {
                if (!(flags & InputWindowInfo::FLAG_NOT_TOUCHABLE)) {
                    bool isTouchModal = (flags & (InputWindowInfo::FLAG_NOT_FOCUSABLE
                            | InputWindowInfo::FLAG_NOT_TOUCH_MODAL)) == 0;
                    if (isTouchModal || windowInfo->touchableRegionContainsPoint(x, y)) {
                        // Found window.
                        return windowHandle;
                    }
                }
            }
        }
    }
    return NULL;
}
```

#### - 唤醒looper

通知InputDispatcherThread唤起进行输入事件的下发。

### # InputReader总结

- InputReaderThreader在looper中调用InputReader的`loopOnce`完成一次输入事件的读取。
- InputReader通过EventHub读取`RawEvents`(从/dev/input/event{0..n}读取标准输入，涉及Linux文件系统)
- 读到RawEvents之后交给当前的InputDevice处理。
- InputDevice分配给各个Mapper进行process，生成`NotifyArgs`并添加到QueuedInputListener的队列中。
- 通过QueuedInputListener将`NotifyArgs`队列分别提交到InputDispather的mInboundQueue队列中，并唤醒InputDispatherThread的Looper。如果以KeyEvnet为例，这中间会由IntputManagerServer(或者PhoneWindowManager)，对特定事件进行拦截。

## Native分发输入事件(InputDispatcher)

InputDispatcheThread的Looper被唤醒之后会调用到`dispatchOnce()`。

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
bool InputDispatcherThread::threadLoop() {
    mDispatcher->dispatchOnce();
    return true;
}
```

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::dispatchOnce() {
    nsecs_t nextWakeupTime = LONG_LONG_MAX;
    { // acquire lock
        AutoMutex _l(mLock);
        mDispatcherIsAliveCondition.broadcast();

        // Run a dispatch loop if there are no pending commands.
        // The dispatch loop might enqueue commands to run afterwards.
        if (!haveCommandsLocked()) {
            dispatchOnceInnerLocked(&nextWakeupTime);
        }

        // Run all pending commands if there are any.
        // If any commands were run then force the next poll to wake up immediately.
        if (runCommandsLockedInterruptible()) {
            nextWakeupTime = LONG_LONG_MIN;
        }
    } // release lock

    // Wait for callback or timeout or wake.  (make sure we round up, not down)
    nsecs_t currentTime = now();
    int timeoutMillis = toMillisecondTimeoutDelay(currentTime, nextWakeupTime);
    mLooper->pollOnce(timeoutMillis);
}
```

dispatchOnce()优先处理mCommandQueue里面的消息。

如果没有Command则分发消息。否则执行所有的Command，等待下一次Looper消息。

来看看如何分发消息：

### # 按照消息类型分发

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::dispatchOnceInnerLocked(nsecs_t* nextWakeupTime) {
    nsecs_t currentTime = now();
    ...
    switch (mPendingEvent->type) {
    ...
    case EventEntry::TYPE_KEY: {
        KeyEntry* typedEntry = static_cast<KeyEntry*>(mPendingEvent);
        ...
        done = dispatchKeyLocked(currentTime, typedEntry, &dropReason, nextWakeupTime);
        break;
    }

    case EventEntry::TYPE_MOTION: {
        MotionEntry* typedEntry = static_cast<MotionEntry*>(mPendingEvent);
        ...
        done = dispatchMotionLocked(currentTime, typedEntry,
                &dropReason, nextWakeupTime);
        break;
    }
    ...
    }
    ...
}
```

根据mPendingEvent->type确定消息类型，主要看TYPE_KEY和TYPE_MOTION。

这里以前者为例。

### # dispatchKeyLocked

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
bool InputDispatcher::dispatchKeyLocked(nsecs_t currentTime, KeyEntry* entry,
        DropReason* dropReason, nsecs_t* nextWakeupTime) {
    ...
    // Give the policy a chance to intercept the key.
    if (entry->interceptKeyResult == KeyEntry::INTERCEPT_KEY_RESULT_UNKNOWN) {
        if (entry->policyFlags & POLICY_FLAG_PASS_TO_USER) {
            CommandEntry* commandEntry = postCommandLocked(
                    & InputDispatcher::doInterceptKeyBeforeDispatchingLockedInterruptible);
            if (mFocusedWindowHandle != NULL) {
                commandEntry->inputWindowHandle = mFocusedWindowHandle;
            }
            commandEntry->keyEntry = entry;
            entry->refCount += 1;
            return false; // wait for the command to run
        } else {
            entry->interceptKeyResult = KeyEntry::INTERCEPT_KEY_RESULT_CONTINUE;
        }
    } else if (entry->interceptKeyResult == KeyEntry::INTERCEPT_KEY_RESULT_SKIP) {
        if (*dropReason == DROP_REASON_NOT_DROPPED) {
            *dropReason = DROP_REASON_POLICY;
        }
    }

    // Clean up if dropping the event.
    if (*dropReason != DROP_REASON_NOT_DROPPED) {
        setInjectionResultLocked(entry, *dropReason == DROP_REASON_POLICY
                ? INPUT_EVENT_INJECTION_SUCCEEDED : INPUT_EVENT_INJECTION_FAILED);
        return true;
    }

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
```

这中间有一步是，如果当前的interceptKeyResult为INTERCEPT_KEY_RESULT_UNKNOWN的话，会postCommandLocked到`mCommandQueue`，这里就与`dispatchOnce`处理command衔接起来了。

下面一步步分析:

#### - interceptKeyBeforeDispatching

上面INTERCEPT_KEY_RESULT_UNKNOWN对应的回调函数是interceptKeyBeforeDispatching。

这一步类似于`interceptKeyBeforeEnqueueing`，主要用于处理如下按键：

- HOME
- SEARCH
- KEYCODE_TAB
- KEYCODE_ALL_APPS
- KEYCODE_LANGUAGE_SWITCH
- KEYCODE_SPACE
- KEYCODE_BRIGHTNESS_UP/DOWN

> 具体分析逻辑略过，参考上面。最重实现的函数在`PhoneWindowManager`的`interceptKeyBeforeDispatching`函数。

#### - findFocusedWindowTargetsLocked

这里则是将不可到达的分发事件前置，从而结束分发，增加效率：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
int32_t InputDispatcher::findFocusedWindowTargetsLocked(nsecs_t currentTime,
        const EventEntry* entry, Vector<InputTarget>& inputTargets, nsecs_t* nextWakeupTime) {
    int32_t injectionResult;
    String8 reason;

    // If there is no currently focused window and no focused application
    // then drop the event.
    if (mFocusedWindowHandle == NULL) {
        if (mFocusedApplicationHandle != NULL) {
            injectionResult = handleTargetsNotReadyLocked(currentTime, entry,
                    mFocusedApplicationHandle, NULL, nextWakeupTime,
                    "Waiting because no window has focus but there is a "
                    "focused application that may eventually add a window "
                    "when it finishes starting up.");
            goto Unresponsive;
        }

        ALOGI("Dropping event because there is no focused window or focused application.");
        injectionResult = INPUT_EVENT_INJECTION_FAILED;
        goto Failed;
    }

    // Check permissions.
    if (! checkInjectionPermission(mFocusedWindowHandle, entry->injectionState)) {
        injectionResult = INPUT_EVENT_INJECTION_PERMISSION_DENIED;
        goto Failed;
    }

    // Check whether the window is ready for more input.
    reason = checkWindowReadyForMoreInputLocked(currentTime,
            mFocusedWindowHandle, entry, "focused");
    if (!reason.isEmpty()) {
        injectionResult = handleTargetsNotReadyLocked(currentTime, entry,
                mFocusedApplicationHandle, mFocusedWindowHandle, nextWakeupTime, reason.string());
        goto Unresponsive;
    }

    // Success!  Output targets.
    injectionResult = INPUT_EVENT_INJECTION_SUCCEEDED;
    addWindowTargetLocked(mFocusedWindowHandle,
            InputTarget::FLAG_FOREGROUND | InputTarget::FLAG_DISPATCH_AS_IS, BitSet32(0),
            inputTargets);

    // Done.
Failed:
Unresponsive:
    nsecs_t timeSpentWaitingForApplication = getTimeSpentWaitingForApplicationLocked(currentTime);
    updateDispatchStatisticsLocked(currentTime, entry,
            injectionResult, timeSpentWaitingForApplication);
    return injectionResult;
}
```

- 当前没有处在焦点的窗口，则传递无意义。
- 判断android.Manifest.permission.INJECT_EVENTS权限是否granted
- 获取当前window的状态是否ready，比如inputChannel是否存活等。

最后如果成功逃过一劫，则通过`addWindowTargetLocked`函数将当前窗口的信息。比如`inputChannel`设置到`inputTargets`中去。

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::addWindowTargetLocked(const sp<InputWindowHandle>& windowHandle,
        int32_t targetFlags, BitSet32 pointerIds, Vector<InputTarget>& inputTargets) {
    inputTargets.push();

    const InputWindowInfo* windowInfo = windowHandle->getInfo();
    InputTarget& target = inputTargets.editTop();
    target.inputChannel = windowInfo->inputChannel;
    target.flags = targetFlags;
    target.xOffset = - windowInfo->frameLeft;
    target.yOffset = - windowInfo->frameTop;
    target.scaleFactor = windowInfo->scaleFactor;
    target.pointerIds = pointerIds;
}
```

### # dispatchEventLocked

这一步与MotionEvent共用：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::dispatchEventLocked(nsecs_t currentTime,
        EventEntry* eventEntry, const Vector<InputTarget>& inputTargets) {
    ...
    pokeUserActivityLocked(eventEntry);

    for (size_t i = 0; i < inputTargets.size(); i++) {
        const InputTarget& inputTarget = inputTargets.itemAt(i);
        ssize_t connectionIndex = getConnectionIndexLocked(inputTarget.inputChannel);
        if (connectionIndex >= 0) {
            sp<Connection> connection = mConnectionsByFd.valueAt(connectionIndex);
            prepareDispatchCycleLocked(currentTime, connection, eventEntry, &inputTarget);
        } else {
        ...
        }
    }
}
```

遍历`inputTargets`，拿到每个InputChannel对应的Connection对象(后面会说)。

#### - prepareDispatchCycleLocked

这一步其实就是把`inputTarget->flags`转换成对应的Action，比如ActionDown/UP/Move等：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::prepareDispatchCycleLocked(nsecs_t currentTime,
        const sp<Connection>& connection, EventEntry* eventEntry, const InputTarget* inputTarget) {
    ...
    // Split a motion event if needed.
    // Not splitting.  Enqueue dispatch entries for the event as is.
    enqueueDispatchEntriesLocked(currentTime, connection, eventEntry, inputTarget);
}

void InputDispatcher::enqueueDispatchEntriesLocked(nsecs_t currentTime,
        const sp<Connection>& connection, EventEntry* eventEntry, const InputTarget* inputTarget) {
    bool wasEmpty = connection->outboundQueue.isEmpty();

    // Enqueue dispatch entries for the requested modes.
    enqueueDispatchEntryLocked(connection, eventEntry, inputTarget,
            InputTarget::FLAG_DISPATCH_AS_HOVER_EXIT);
    enqueueDispatchEntryLocked(connection, eventEntry, inputTarget,
            InputTarget::FLAG_DISPATCH_AS_OUTSIDE);
    enqueueDispatchEntryLocked(connection, eventEntry, inputTarget,
            InputTarget::FLAG_DISPATCH_AS_HOVER_ENTER);
    enqueueDispatchEntryLocked(connection, eventEntry, inputTarget,
            InputTarget::FLAG_DISPATCH_AS_IS);
    enqueueDispatchEntryLocked(connection, eventEntry, inputTarget,
            InputTarget::FLAG_DISPATCH_AS_SLIPPERY_EXIT);
    enqueueDispatchEntryLocked(connection, eventEntry, inputTarget,
            InputTarget::FLAG_DISPATCH_AS_SLIPPERY_ENTER);

    // If the outbound queue was previously empty, start the dispatch cycle going.
    if (wasEmpty && !connection->outboundQueue.isEmpty()) {
        startDispatchCycleLocked(currentTime, connection);
    }
}

// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::enqueueDispatchEntryLocked(
        const sp<Connection>& connection, EventEntry* eventEntry, const InputTarget* inputTarget,
        int32_t dispatchMode) {
    int32_t inputTargetFlags = inputTarget->flags;
    if (!(inputTargetFlags & dispatchMode)) {
        return;
    }
    inputTargetFlags = (inputTargetFlags & ~InputTarget::FLAG_DISPATCH_MASK) | dispatchMode;

    // This is a new event.
    // Enqueue a new dispatch entry onto the outbound queue for this connection.
    DispatchEntry* dispatchEntry = new DispatchEntry(eventEntry, // increments ref
            inputTargetFlags, inputTarget->xOffset, inputTarget->yOffset,
            inputTarget->scaleFactor);

    // Apply target flags and update the connection's input state.
    switch (eventEntry->type) {
    case EventEntry::TYPE_KEY: {
        KeyEntry* keyEntry = static_cast<KeyEntry*>(eventEntry);
        dispatchEntry->resolvedAction = keyEntry->action;
        dispatchEntry->resolvedFlags = keyEntry->flags;

        if (!connection->inputState.trackKey(keyEntry,
                dispatchEntry->resolvedAction, dispatchEntry->resolvedFlags)) {
            return; // skip the inconsistent event
        }
        break;
    }

    case EventEntry::TYPE_MOTION: {
        MotionEntry* motionEntry = static_cast<MotionEntry*>(eventEntry);
        if (dispatchMode & InputTarget::FLAG_DISPATCH_AS_OUTSIDE) {
            dispatchEntry->resolvedAction = AMOTION_EVENT_ACTION_OUTSIDE;
        } else if (dispatchMode & InputTarget::FLAG_DISPATCH_AS_HOVER_EXIT) {
            dispatchEntry->resolvedAction = AMOTION_EVENT_ACTION_HOVER_EXIT;
        } else if (dispatchMode & InputTarget::FLAG_DISPATCH_AS_HOVER_ENTER) {
            dispatchEntry->resolvedAction = AMOTION_EVENT_ACTION_HOVER_ENTER;
        } else if (dispatchMode & InputTarget::FLAG_DISPATCH_AS_SLIPPERY_EXIT) {
            dispatchEntry->resolvedAction = AMOTION_EVENT_ACTION_CANCEL;
        } else if (dispatchMode & InputTarget::FLAG_DISPATCH_AS_SLIPPERY_ENTER) {
            dispatchEntry->resolvedAction = AMOTION_EVENT_ACTION_DOWN;
        } else {
            dispatchEntry->resolvedAction = motionEntry->action;
        }
        if (dispatchEntry->resolvedAction == AMOTION_EVENT_ACTION_HOVER_MOVE
                && !connection->inputState.isHovering(
                        motionEntry->deviceId, motionEntry->source, motionEntry->displayId)) {
            dispatchEntry->resolvedAction = AMOTION_EVENT_ACTION_HOVER_ENTER;
        }
        dispatchEntry->resolvedFlags = motionEntry->flags;
        if (dispatchEntry->targetFlags & InputTarget::FLAG_WINDOW_IS_OBSCURED) {
            dispatchEntry->resolvedFlags |= AMOTION_EVENT_FLAG_WINDOW_IS_OBSCURED;
        }
        if (dispatchEntry->targetFlags & InputTarget::FLAG_WINDOW_IS_PARTIALLY_OBSCURED) {
            dispatchEntry->resolvedFlags |= AMOTION_EVENT_FLAG_WINDOW_IS_PARTIALLY_OBSCURED;
        }
        if (!connection->inputState.trackMotion(motionEntry,
                dispatchEntry->resolvedAction, dispatchEntry->resolvedFlags)) {
            return; // skip the inconsistent event
        }
        break;
    }
    }

    // Remember that we are waiting for this dispatch to complete.
    if (dispatchEntry->hasForegroundTarget()) {
        incrementPendingForegroundDispatchesLocked(eventEntry);
    }

    // Enqueue the dispatch entry.
    connection->outboundQueue.enqueueAtTail(dispatchEntry);
    traceOutboundQueueLengthLocked(connection);
}
```

并且把EventEntry转换为DispatchEntry，同时加入到当前这个connection的outboundQueue中队列。这一步处理后就到来Server同Client的通信了。

注意：上面针对`eventEntry->type`分别使用`connection->inputState.trackKey`和`connection->inputState.trackMotion`对当前的Event进行跟踪。

如果当前的action为Cancel或者UP等，那么将不继续跟踪同时不加入到`connection的outboundQueue队列`。以为着这次传递之后，后续这个事件将从头开始，即非持续性事件(inconsistent event)。


#### - startDispatchCycleLocked

这里最终拿到connection的inputPublisher，调用对应的push函数：

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::startDispatchCycleLocked(nsecs_t currentTime,
        const sp<Connection>& connection) {
    ...
    while (connection->status == Connection::STATUS_NORMAL
            && !connection->outboundQueue.isEmpty()) {
        ...
        status_t status;
        EventEntry* eventEntry = dispatchEntry->eventEntry;
        switch (eventEntry->type) {
        case EventEntry::TYPE_KEY: {
            ...
            status = connection->inputPublisher.publishKeyEvent(...);
            break;
        }

        case EventEntry::TYPE_MOTION: {
            ...
            status = connection->inputPublisher.publishMotionEvent(...);
            break;
        }
        ...
        }
        // Check the result.
        ...
        // Re-enqueue the event on the wait queue.
        connection->outboundQueue.dequeue(dispatchEntry);
        traceOutboundQueueLengthLocked(connection);
        connection->waitQueue.enqueueAtTail(dispatchEntry);
        traceWaitQueueLengthLocked(connection);
    }
}
```

如果函数返回失败则，重新加入队尾，继续进入循环。

以KeyEnt来分析puhlish函数:

### # publishKeyEvent(publishMotionEvent)

ViewRootImpl的setView函数中，会初始化一个InputChannel，最终在native创建一个Server InputChannel和Client InputChannel。之后将Server注册到InputDispatcher中，即`registerInputChannel`函数。在这里会创建并记录一个Connection。

而Connection的构造函数中使用Server InputChannel创建一个InputPublisher。

```cpp
// native/libs/input/InputTransport.cpp
status_t InputPublisher::publishKeyEvent(
        uint32_t seq,
        int32_t deviceId,
        int32_t source,
        int32_t action,
        int32_t flags,
        int32_t keyCode,
        int32_t scanCode,
        int32_t metaState,
        int32_t repeatCount,
        nsecs_t downTime,
        nsecs_t eventTime) {
    ...

    if (!seq) {
        ALOGE("Attempted to publish a key event with sequence number 0.");
        return BAD_VALUE;
    }

    InputMessage msg;
    msg.header.type = InputMessage::TYPE_KEY;
    msg.body.key.seq = seq;
    msg.body.key.deviceId = deviceId;
    msg.body.key.source = source;
    msg.body.key.action = action;
    msg.body.key.flags = flags;
    msg.body.key.keyCode = keyCode;
    msg.body.key.scanCode = scanCode;
    msg.body.key.metaState = metaState;
    msg.body.key.repeatCount = repeatCount;
    msg.body.key.downTime = downTime;
    msg.body.key.eventTime = eventTime;
    return mChannel->sendMessage(&msg);
}
```

可以看到，这里通过传入的参数创建一个InputMessage，并交给Server InputChannel.下面看看Server InputChannel是如何发送消息：

```cpp
// native/libs/input/InputTransport.cpp
status_t InputChannel::sendMessage(const InputMessage* msg) {
    size_t msgLength = msg->size();
    ssize_t nWrite;
    do {
        nWrite = ::send(mFd, msg, msgLength, MSG_DONTWAIT | MSG_NOSIGNAL);
    } while (nWrite == -1 && errno == EINTR);

    if (nWrite < 0) {
        int error = errno;
        if (error == EAGAIN || error == EWOULDBLOCK) {
            return WOULD_BLOCK;
        }
        if (error == EPIPE || error == ENOTCONN || error == ECONNREFUSED || error == ECONNRESET) {
            return DEAD_OBJECT;
        }
        return -error;
    }
    if (size_t(nWrite) != msgLength) {
        return DEAD_OBJECT;
    }
    return OK;
}
```

这里的`::send`函数是socket通信，用于发送socket消息到连接的client。到这里，底层的消息分发就结束了。

后面Client就是如何接受消息并传递到DecorView了。

这一步不在这里分析了。

## 其他

pokeUserActivityLocked意为提示用户产生了活动。最终会执行到PowerManagerService的userActivityFromNative函数。

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::pokeUserActivityLocked(const EventEntry* eventEntry) {
    if (mFocusedWindowHandle != NULL) {
        const InputWindowInfo* info = mFocusedWindowHandle->getInfo();
        if (info->inputFeatures & InputWindowInfo::INPUT_FEATURE_DISABLE_USER_ACTIVITY) {
            return;
        }
    }
    int32_t eventType = USER_ACTIVITY_EVENT_OTHER;
    switch (eventEntry->type) {
        case EventEntry::TYPE_MOTION: {
            const MotionEntry* motionEntry = static_cast<const MotionEntry*>(eventEntry);
            if (motionEntry->action == AMOTION_EVENT_ACTION_CANCEL) {
                return;
            }
            if (MotionEvent::isTouchEvent(motionEntry->source, motionEntry->action)) {
                eventType = USER_ACTIVITY_EVENT_TOUCH;
            }
            break;
        }
        case EventEntry::TYPE_KEY: {
            const KeyEntry* keyEntry = static_cast<const KeyEntry*>(eventEntry);
            if (keyEntry->flags & AKEY_EVENT_FLAG_CANCELED) {
                return;
            }
            eventType = USER_ACTIVITY_EVENT_BUTTON;
            break;
        }
    }

    CommandEntry* commandEntry = postCommandLocked(
            & InputDispatcher::doPokeUserActivityLockedInterruptible);
    commandEntry->eventTime = eventEntry->eventTime;
    commandEntry->userActivityEventType = eventType;
}
```

```cpp
// frameworks/native/services/inputflinger/InputDispatcher.cpp
void InputDispatcher::doPokeUserActivityLockedInterruptible(CommandEntry* commandEntry) {
    mLock.unlock();

    mPolicy->pokeUserActivity(commandEntry->eventTime, commandEntry->userActivityEventType);

    mLock.lock();
}

// frameworks/base/services/core/jni/com_android_server_intput_InputManagerService.cpp
void NativeInputManager::pokeUserActivity(nsecs_t eventTime, int32_t eventType) {
    ATRACE_CALL();
    android_server_PowerManagerService_userActivity(eventTime, eventType);
}
```

```cpp
// frameworks/base/services/core/jni/com_android_server_power_PowerManagerService.cpp
void android_server_PowerManagerService_userActivity(nsecs_t eventTime, int32_t eventType) {
    if (gPowerManagerServiceObj) {
        // Throttle calls into user activity by event type.
        // We're a little conservative about argument checking here in case the caller
        // passes in bad data which could corrupt system state.
        if (eventType >= 0 && eventType <= USER_ACTIVITY_EVENT_LAST) {
            nsecs_t now = systemTime(SYSTEM_TIME_MONOTONIC);
            if (eventTime > now) {
                eventTime = now;
            }

            if (gLastEventTime[eventType] + MIN_TIME_BETWEEN_USERACTIVITIES > eventTime) {
                return;
            }
            gLastEventTime[eventType] = eventTime;


            // Tell the power HAL when user activity occurs.
            gPowerHalMutex.lock();
            if (getPowerHal()) {
              Return<void> ret;
              if (gPowerHalV1_1 != nullptr) {
                ret = gPowerHalV1_1->powerHintAsync(PowerHint::INTERACTION, 0);
              } else {
                ret = gPowerHalV1_0->powerHint(PowerHint::INTERACTION, 0);
              }
              processReturn(ret, "powerHint");
            }
            gPowerHalMutex.unlock();

        }

        JNIEnv* env = AndroidRuntime::getJNIEnv();

        env->CallVoidMethod(gPowerManagerServiceObj,
                gPowerManagerServiceClassInfo.userActivityFromNative,
                nanoseconds_to_milliseconds(eventTime), eventType, 0);
        checkAndClearExceptionFromCallback(env, "userActivityFromNative");
    }
}
```

- <https://www.jianshu.com/p/6e250a8ff80c>