---
layout: post
title: "View的post函数详析"
description: "View的post函数详析"
category: all-about-tech
tags: -[android]
date: 2019-08-26 23:03:57+00:00
---

> 基于Android 28

View本身也提供了post接口来在主线程中处理异步任务。但是不同的是，view中做了保障机制：即所有的任务都是在绘制第一帧的时候才能进入MainLooper。

下面看具体分析：

## HandlerActionQueue

那么就先从入口往里面一层层看，下面是post函数的具体实现。

#### View.post()函数

```java
// frameworks/base/core/java/android/view/View.java
public boolean post(Runnable action) {
    final AttachInfo attachInfo = mAttachInfo;
    if (attachInfo != null) {
        return attachInfo.mHandler.post(action);
    }
    // Postpone the runnable until we know on which thread it needs to run.
    // Assume that the runnable will be successfully placed after attach.
    getRunQueue().post(action);
    return true;
}
```

这里有两个有用的信息：

- 如果当前存在AttachInfo那么直接使用它里面的Handler发送消息。这同正常的Handler机制是一致的。
- 如果不存在，那么获取一个RunQueue并post给它。

至于AttachInfo什么情况下不为空，一会会跟下面的RunQueue会合起来看。这里主要看一下RunQueue。

#### getRunQueue()

```java
// frameworks/base/core/java/android/view/View.java
private HandlerActionQueue getRunQueue() {
    if (mRunQueue == null) {
        mRunQueue = new HandlerActionQueue();
    }
    return mRunQueue;
}
```

getRunQueue返回的是本地缓存的一个HandlerActionQueue类的实例mRunQueue，并且mRunQueue本身是lazyInit的。

下面再看来看mRunQueue如何处理postDelayed()：

#### postDelayed

```java
// frameworks/base/core/java/android/view/HandlerActionQueue.java
public void postDelayed(Runnable action, long delayMillis) {
    final HandlerAction handlerAction = new HandlerAction(action, delayMillis);

    synchronized (this) {
        if (mActions == null) {
            mActions = new HandlerAction[4];
        }
        mActions = GrowingArrayUtils.append(mActions, mCount, handlerAction);
        mCount++;
    }
}
```

这里其实也非常明显，首先HandlerActionQueue会将进来的Runnable对象封装成HandlerAction。最后将HandlerAction对象加入到本地的mActions(即HandlerAction数组中)缓存起来。

到这里其实调用就结束了，那么什么时候才会执行到呢？

## dispatchAttachedToWindow

其实稍微注意一下源码就可以发现，在View的dispatchAttachedToWindow方法中会设置AttachInfo并且处理mRunQueue中的队列：


```java
// frameworks/base/core/java/android/view/View.java
void dispatchAttachedToWindow(AttachInfo info, int visibility) {
    mAttachInfo = info;
    // ...
    // Transfer all pending runnables.
    if (mRunQueue != null) {
        mRunQueue.executeActions(info.mHandler);
        mRunQueue = null;
    }
    performCollectViewAttributes(mAttachInfo, visibility);
    onAttachedToWindow();
    // ...
}
```

上面提到的mAttachInfo就在这里赋值的，经过这一步之后再执行View的post方法就会直接使用Handler发送消息了。

之后会读取mRunQueue（默认情况下没人调用post等相关方法这个变量会是null），并将mAttachInfo中的mHandler对象传递到其内部的executeActions中，同时在View里将mRunQueue置null。

下面来看HandlerActionQueue的executeActions函数

#### executeActions

```java
// frameworks/base/core/java/android/view/HandlerActionQueue.java
public void executeActions(Handler handler) {
    synchronized (this) {
        final HandlerAction[] actions = mActions;
        for (int i = 0, count = mCount; i < count; i++) {
            final HandlerAction handlerAction = actions[i];
            handler.postDelayed(handlerAction.action, handlerAction.delay);
        }

        mActions = null;
        mCount = 0;
    }
}
```

这里其实就是读取HandlerAction数组并通过View中传递过来的mHandler执行postDelay的行为。

其实不论是在什么时机调用post最终都会用到mAttachInfo的mHandler对象来发送消息到MainLooper中。

虽然知道view.post的任务最终的一定会通过AttachInfo的mHandler对象post出去，但是他是哪里来的呢？

## doTraversal() 

我们都知道Android上面View的绘制都是在doTraversal的完成的。

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
void doTraversal() {
    if (mTraversalScheduled) {
        mTraversalScheduled = false;
        mHandler.getLooper().getQueue().removeSyncBarrier(mTraversalBarrier);

        if (mProfile) {
            Debug.startMethodTracing("ViewAncestor");
        }

        performTraversals();

        if (mProfile) {
            Debug.stopMethodTracing();
            mProfile = false;
        }
    }
}
```

而doTraversal()函数本身会调用 performTraversals()来完成具体的绘制调用，因为绘制涉及到非常多的流程，所以这一步其实非常庞大，但是还是可以找到上面提到的dispatchAttachedToWindow相关的行为:

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
private void performTraversals() {
// ...
    Rect frame = mWinFrame;
    if (mFirst) {
        // ...
        host.dispatchAttachedToWindow(mAttachInfo, 0);
        mAttachInfo.mTreeObserver.dispatchOnWindowAttachedChange(true);
        dispatchApplyInsets(host);
    // ...
    }
    // ...
    mFirst = false;
    // ...
    boolean cancelDraw = mAttachInfo.mTreeObserver.dispatchOnPreDraw() || !isViewVisible;
    if (!cancelDraw && !newSurface) {
        if (mPendingTransitions != null && mPendingTransitions.size() > 0) {
            for (int i = 0; i < mPendingTransitions.size(); ++i) {
                mPendingTransitions.get(i).startChangingAnimations();
            }
            mPendingTransitions.clear();
        }

        performDraw();
    } else {
        // ..
    }
    mIsInTraversal = false;
}
```

可以看到mFirst为true时，即准备开始第一次绘制时会调用mHost的dispatchAttachedToWindow函数，经过ViewGroup对各个子View进行dispatchAttachedToWindow事件的层层风发，最终执行到调用post方法的那个view。

其中mHost其实就是在Activity执行setContentView之后经过PhoneWindow最后创建ViewRootImpl并设置进来的DecorView。

具体doTraversal是如何运行的，那就是View本身绘制流程了。要想讲清楚需要挺大篇幅，这里不再展开了。

## 延伸

#### 与直接创建Handler的不同

> 仅考虑是在主线程内部创建Handler的情况。

其实通过上面的分析已经可以得出非常明显的结论：那就是，view.post如果在没有绘制第一帧的情况下，所有的任务都不会被执行，并且会缓存在HandlerActionQueue中等待dispatchAttachToWindow时机。而在HandlerActionQueue被执行时，还会再次讲先前的任务post一遍。

而Handler最直接，在你发送任务的时候就会立马进入MainLooper等待下次被调起。这个过程其实同View的绘制流程其实是脱节的。

#### 与ViewTreeObserver的不同

ViewTreeObserver行为发生在View的绘制过程中，并且可以对当前view绘制事件进行拦截。简单来说，当我知道你的view尺寸之后我可以作出改变并且要求你停止此次绘制(见上面performTraversals函数最终的cancelDraw)。

如果想要第一事件获取View的宽高并且及时对自身的UI作出改变，则非常建议使用ViewTreeObserver。使用view.post很有可能是发生在MainLooper执行完绘制第一帧之后，从而导致节目的抖动或者闪烁。

其实究其原因还是ViewTreeObserver同Handler本身完全不是一回事。放在这里提是提醒一下，想在View的绘制周期中干活其实是有更好的选择。