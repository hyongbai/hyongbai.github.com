---
layout: post
title: "WindowManagerService - 窗口焦点"
description: "WindowManagerService - 窗口焦点"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-04-14 21:03:57+00:00
---

> 基于 android-8.1.0_r60
>
> 为求简洁，代码已删除大量细枝末节。

> windowFocusChanged

## 焦点变化时机

主要有如下三个时机触发焦点窗口有变化：

- addWindow

由 ViewRootImpl.setView 时调用 Session.addToDisplay 触发，即WindowManager.addView时。

- relayoutWindow

由 ViewRootImpl.relayoutWindow 时调用 Session.relayout触发，即在ViewRootImpl初次performTraversal时。

- setFocusedApp

当Activity的声明周期走到resume是，在AMS中触发。伪调用如下:

```
-> ActivityStackSupervisor.resumeFocusedStackTopActivityLocked
    -> ActivityStack.resumeTopActivityInnerLocked
        -> ActivityStack.setResumedActivityLocked
            -> AMS.setResumedActivityUncheckLocked
```

触发之后都会调用到`updateFocusedWindowLocked`函数。

### # updateFocusedWindowLocked

```java
// frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java
// TODO: Move to DisplayContent
boolean updateFocusedWindowLocked(int mode, boolean updateInputWindows) {
    // 从RootWindowContainer拿到当前的焦点WindowState，如果同上次获取的`mCurrentFocus`不一致，则认为发生了焦点变动。
    WindowState newFocus = mRoot.computeFocusedWindow();
    if (mCurrentFocus != newFocus) {
        // 发送REPORT_FOCUS_CHANGE消息，告知焦点发生变化。mH对应的Looper同DisplayManagerService的一致。均运行在DisplayThread中。
        mH.removeMessages(H.REPORT_FOCUS_CHANGE);
        mH.sendEmptyMessage(H.REPORT_FOCUS_CHANGE);
        // 这里其实有问题，如果由多个Display，那么此时应当使用newFocus对应的DisplayContent，而不是默认DisplayContent
        final DisplayContent displayContent = getDefaultDisplayContentLocked();
        ...
        final WindowState oldFocus = mCurrentFocus;
        mCurrentFocus = newFocus;
        mLosingFocus.remove(newFocus);
        ...
        int focusChanged = mPolicy.focusChangedLw(oldFocus, newFocus);
        ..
        if ((focusChanged & FINISH_LAYOUT_REDO_LAYOUT) != 0) {
            // The change in focus caused us to need to do a layout.  Okay.
            displayContent.setLayoutNeeded();
            if (mode == UPDATE_FOCUS_PLACING_SURFACES) {
                displayContent.performLayout(true /*initial*/, updateInputWindows);
            }
        }
        ...
        return true;
    }
    return false;
}
```

- 从RootWindowContainer拿到当前的焦点WindowState，如果同上次获取的`mCurrentFocus`不一致，则认为发生了焦点变动。
- 发送REPORT_FOCUS_CHANGE消息，告知焦点发生变化。mH对应的Looper同DisplayManagerService的一致，均运行在DisplayThread中。
- 更新`mCurrentFocus`遍历。并且把newFocus从mLosingFocus中移除。mLosingFocus是一个存储所有被抢夺了焦点的WindowState列表。由一个专门的消息类型，来分发所有的mLosingFocus窗口。

下面来看看RootWindowContainer内部的数据结构。

### # computeFocusedWindow

```java
// frameworks/base/services/core/java/com/android/server/wm/RootWindowContainer.java
WindowState computeFocusedWindow() {
    for (int i = mChildren.size() - 1; i >= 0; i--) {
        final DisplayContent dc = mChildren.get(i);
        final WindowState win = dc.findFocusedWindow();
        if (win != null) {
            return win;
        }
    }
    return null;
}
```

倒序的方式将RootWindowContainer中的DisplayContent遍历出来，直到获取目标WindowState。

具体的逻辑在DisplayContent的findFocusedWindow函数中。

#### - DisplayContent.findFocusedWindow

```java
// frameworks/base/services/core/java/com/android/server/wm/DisplayContent.java
WindowState findFocusedWindow() {
    mTmpWindow = null;
    // 遍历所有的Child，其中traverseTopToBottom这个参数则表示从后往前倒序遍历。
    forAllWindows(mFindFocusedWindow, true /* traverseTopToBottom */);
    return mTmpWindow;
}

private final ToBooleanFunction<WindowState> mFindFocusedWindow = w -> {
    // 拿到WindowManagerService中的`mFocusedApp`，即处在焦点状态下的AppWindowToken。ActivityThread收到`scheduleResumeActivity`消息之前，会调用WMS的`setFocusedApp`将mFocusedApp设定。
    final AppWindowToken focusedApp = mService.mFocusedApp;
    if (!w.canReceiveKeys())  return false;
    final AppWindowToken wtoken = w.mAppToken;
    // If this window's application has been removed, just skip it.
    if (wtoken != null && (wtoken.removed || wtoken.sendingToBottom)) {
        return false;
    }
    if (focusedApp == null) {
        mTmpWindow = w;
        return true;
    }
    if (!focusedApp.windowsAreFocusable()) {
        mTmpWindow = w;
        return true;
    }
    if (wtoken != null && w.mAttrs.type != TYPE_APPLICATION_STARTING) {
        if (focusedApp.compareTo(wtoken) > 0) {
            mTmpWindow = null;
            return true;
        }
    }
    mTmpWindow = w;
    return true;
};
```

- 调用`forAllWindows`函数遍历所有的Child及其包含的Task

其中traverseTopToBottom这个参数则表示从后往前倒序遍历，即最后加入到TaskStack的Task最先被遍历出。

`forAllWindows`是一个仅仅提供遍历`WindowList`的函数。具体的filter逻辑则依赖ToBooleanFunction(即Callback)实现。

- mFindFocusedWindow

mFindFocusedWindow是`forAllWindows`的具体策略。

按照上面的规则，即第一个接受输入事件(此处KeyEvent而非InputEvent)并且状态不为`removed`和`sendingToBottom`的WindowState对应的AppWindowToken。


#### - DisplayContent.forAllWindows

DisplayContent同RootWindowContainer以及TaskStack/Task/AppWindowToken/WindowState一样，都是`WindowContainer`的子类。其内部有个`mChildren`，他是`WindowList`的实例。

而WindowList虽然继承自ArraryList，但是在使用的时候仍然被当作栈的逻辑来操作。比如下面的`traverseTopToBottom`（即从顶往底遍历），其实就是从ArrayList的后往前遍历。这里需要注意。

```java
// frameworks/base/services/core/java/com/android/server/wm/DisplayContent.java
@Override
boolean forAllWindows(ToBooleanFunction<WindowState> callback, boolean traverseTopToBottom) {
    // Special handling so we can process IME windows with #forAllImeWindows above their IME
    // target, or here in order if there isn't an IME target.
    // 在这里mChildren被当作一个栈来处理。也就是说
    if (traverseTopToBottom) {
        for (int i = mChildren.size() - 1; i >= 0; --i) {
            final DisplayChildWindowContainer child = mChildren.get(i);
            if (child == mImeWindowsContainers && mService.mInputMethodTarget != null) {
                // In this case the Ime windows will be processed above their target so we skip here.
                continue;
            }
            if (child.forAllWindows(callback, traverseTopToBottom)) {
                return true;
            }
        }
    }
    ...
    return false;
}
```



```java
// frameworks/base/services/core/java/com/android/server/wm/DisplayContent.java
DisplayContent(Display display, WindowManagerService service,
        WindowLayersController layersController, WallpaperController wallpaperController) {
    ...
    // These are the only direct children we should ever have and they are permanent.
    super.addChild(mBelowAppWindowsContainers, null);
    super.addChild(mTaskStackContainers, null);
    super.addChild(mAboveAppWindowsContainers, null);
    super.addChild(mImeWindowsContainers, null);
    // Add itself as a child to the root container.
    mService.mRoot.addChild(this, null);
    mDisplayReady = true;
}
```

[![aosp-DisplayContent-forAllWindows-mChildren-till-demo-lldb.png](https://j.mp/3b5ZutL)](https://j.mp/2RvnQFq)


- RootWindowContainer

包含的mChildren数组为DisplayContent[]。即所有的Display对应的DisplayContent都是在`RootWindowContainer`中管理的。

也就是说DisplayContent的创建、缓存、获取都在RootWindowContainer中。

- DisplayContent

包含的mChildren数组为DisplayChildWindowContainer[]。

DisplayContent同Display为绑定关系，一个Display对应一个DisplayContent。前者由DisplayManagerService管理，后者由WindowManagerService管理(在RootWindowContainer中)。

DisplayContent的mChildren数组，固定为4个。见DisplayContent的构造函数。即

```
mBelowAppWindowsContainers
mTaskStackContainers
mAboveAppWindowsContainers
mImeWindowsContainers
```

- TaskStackContainers

继承自`DisplayContent$DisplayChildWindowContainer`。

包含的mChildren数组为TaskStack[]。

基本上所有常规App的Activity都会存储在`TaskStackContainers`里面。

- TaskStack

TaskStack用于存储所有的Task，即它的mChildren数组为Task[]。

在Android8.1中，很多App的默认TaskStackId为[`FULLSCREEN_WORKSPACE_STACK_ID即 “1”`](https://j.mp/2RCGfQM)，详情可见[`ActivityStarter#computeStackFocus函数`](https://j.mp/2K6AbvK)。上面的截图也可以看到`stackId=1`的Stack中包含了当前运行的几乎所有应用。

- Task: AppWindowToken[] mChildren

Task用于存储所有的AppWindowToken，即它的mChildren数组为AppWindowToken[]。

可以“简单”理解为Activity对应的Task，比如修改taskAffinite或者LaunchMode等都会影响Activity对应的Task。比如：

```xml
<activity android:name=".MainActivity"/>
<activity android:name=".Main2Activity" android:launchMode="singleInstance" />
```

MainActivity和Main2Activity的区别就是launchMode不同，获得的结果如下：

[![aosp-DisplayContent-dump-mChildren-tasks-diff-launchmode-demo-lldb.png](https://j.mp/3bar6Oo)](https://j.mp/2xtIor5)


- AppWindowToken

AppWindowToken用于存储所有的WindowState，即它的mChildren数组为WindowState[]。

AppWindowToken在ActivityRecord创建之初创建并持有的，AppWindowToken内部的appToken对象持有ActivityRecord对应的Remote端(相对于Client而言)。简单理解为，IApplicationToken(ActivityRecord$Token) appToken 与AppWindowToken为一一对应关系。可以通过RootWindowContainer的`getAppWindowToken`函数，拿到每个appToken对应的`AppWindowToken`。

AppWindowToken可以简单理解为一个Activity，同时一个Acitivity除了它本身还可以弹出N个Dialog。每个Dialog都有一个WindowState。因此每一个AppWindowToken的WindowState[]都由N+1个数据。

- WindowState

WindowState对应着每一个ViewRootImpl。当执行WindowManager.addView的时候，都会最终在WindowManagerService创建一个WindowState与之对应。

WindowState保留了Client的mWindow、mInputChannel以及displayId等信息，App上的窗口、输入、显示都存储在这里。

#### - DisplayContent.addStackToDisplay

这是一个写入的行为，即往mTaskStackContainers中添加不同的TaskStack。

[![aosp-DisplayContent-addStackToDisplay-callstack-by-startActivity-demo-lldb.png](https://j.mp/2RBRJEc)](https://j.mp/2XzRtcD)

```java
TaskStack addStackToDisplay(int stackId, boolean onTop) {
    TaskStack stack = getStackById(stackId);
    if (stack != null) {
        mTaskStackContainers.positionChildAt(onTop ? POSITION_TOP : POSITION_BOTTOM, stack, false /* includingParents */);
    } else {
        stack = new TaskStack(mService, stackId);
        mTaskStackContainers.addStackToDisplay(stack, onTop);
    }
    if (stackId == DOCKED_STACK_ID) {
        mDividerControllerLocked.notifyDockedStackExistsChanged(true);
    }
    return stack;
}
```

可以看到，只有当某个stackId不存在的时候才会创建新的TaskStack对象，并缓存供下次使用。同时通过上面可知：

- 所有的Activity都是存放在`mTaskStackContainers`当中的某个TaskStack。
- Activity默认对应的TaskStack的stackId为[`FULLSCREEN_WORKSPACE_STACK_ID即 “1”`](https://j.mp/2RCGfQM)。

TaskStack以及其内部的Task对应的创建流程，伪代码如下：

```
ActivityStarter.setTaskFromReuseOrCreateNewTask：
    mTargetStack = computeStackFocus： ActivityStack -> StackWindowController ->  TaskStack
    mTargetStack.createTaskRecord：TaskRecord -> TaskStack -> Task
```

这一过程发生在ActivityStarter的setTaskFromReuseOrCreateNewTask函数中，过程省略。

### # handleMessage: REPORT_FOCUS_CHANGE

上面提到当mFocusWindow变化之后，是通过REPORT_FOCUS_CHANGE消息，在DisplayThread中进行分发的。

下面来看看这个消息是如何运行的：

```java
// frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java
final class H extends android.os.Handler {
    @Override
    public void handleMessage(Message msg) {
        switch (msg.what) {
            case REPORT_FOCUS_CHANGE: {
                WindowState lastFocus;
                WindowState newFocus;
                AccessibilityController accessibilityController = null;
                synchronized(mWindowMap) {
                    if (mAccessibilityController != null && getDefaultDisplayContentLocked().getDisplayId() == DEFAULT_DISPLAY) {
                        accessibilityController = mAccessibilityController;
                    }

                    lastFocus = mLastFocus;
                    newFocus = mCurrentFocus;
                    // 当消息运行时，发生了多次Focus变化。此时如果mCurrentFocus同上次分发后的mLastFocus一致。即Client端的窗口并未发生变化，那么就无需通知Client
                    if (lastFocus == newFocus) {
                        return;
                    }
                    mLastFocus = newFocus;
                    if (newFocus != null && lastFocus != null && !newFocus.isDisplayedLw()) {
                        mLosingFocus.add(lastFocus);
                        lastFocus = null;
                    }
                }

                // First notify the accessibility manager for the change so it has
                // the windows before the newly focused one starts firing eventgs.
                if (accessibilityController != null) {
                    accessibilityController.onWindowFocusChangedNotLocked();
                }

                if (newFocus != null) {
                    // 向mCurrentFocus发送一个获得焦点的消息。即mClient.windowFocusChanged(true)
                    newFocus.reportFocusChangedSerialized(true, mInTouchMode);
                    notifyFocusChanged();
                }

                if (lastFocus != null) {
                    // 向lastFocus发送一个失去焦点的消息。即mClient.windowFocusChanged(false)
                    lastFocus.reportFocusChangedSerialized(false, mInTouchMode);
                }
            } break;

            case REPORT_LOSING_FOCUS: {
                ArrayList<WindowState> losers;
                synchronized(mWindowMap) {
                    losers = mLosingFocus;
                    mLosingFocus = new ArrayList<WindowState>();
                }
                final int N = losers.size();
                for (int i=0; i<N; i++) {
                    losers.get(i).reportFocusChangedSerialized(false, mInTouchMode);
                }
            } break;
            ...
        }
    ...
}
```

- 判断Client是否变化

当消息运行时(位于DisplayThread)，发生了多次Focus变化(其他线程)。

此时如果mCurrentFocus同上次分发后的mLastFocus一致。即Client端的窗口并未发生变化，那么就无需通知Client。

- 向mCurrentFocus和lastFocus分别发生消息

向mCurrentFocus发送一个获得焦点的消息。即mClient.windowFocusChanged(true)。

向lastFocus发送一个失去焦点的消息。即mClient.windowFocusChanged(false)

这里的`mCurrentFocus`以及`mFocusedApp`的值同`adb shell dumpsys window windows`得到的结果一致：

```log
➜  tool-bin git:(master) ✗ adb shell dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp'
  mCurrentFocus=Window{847f51c u0 Application Not Responding: com.android.systemui}
  mFocusedApp=AppWindowToken{6d8161d token=Token{657732e ActivityRecord{3f151a9 u0 me.yourbay.test.lldb/.Main2Activity t1292}}}
 ```

### # reportFocusChangedSerialized

上面的`mCurrentFocus`和`mLastFocus`都是一个WindowState对象。因为焦点本身就是Window为单位进行控制的，因此使用WindowState(而非AppWindowToken等)。

WindowManagerService的addWindow函数等可以直到，WindowState持有了的Client(ViewRootImpl的mWindow)。

```java
// frameworks/base/services/core/java/com/android/server/wm/WindowState.java
void reportFocusChangedSerialized(boolean focused, boolean inTouchMode) {
    try {
        mClient.windowFocusChanged(focused, inTouchMode);
    } catch (RemoteException e) {
    }
    // 回调远程监听焦点的Callback。略。
    ...
}
```

可以看到`windowFocusChanged`会被调用。接下来SystemServer进程的事情就差不多结束了，到了ViewRootImpl了。

## ViewRootImpl

上面WindowState对应的mClient为mWindow，即`ViewRootImpl$W`类。如下：

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
static class W extends IWindow.Stub {
    ...
    @Override
    public void windowFocusChanged(boolean hasFocus, boolean inTouchMode) {
        final ViewRootImpl viewAncestor = mViewAncestor.get();
        if (viewAncestor != null) {
            viewAncestor.windowFocusChanged(hasFocus, inTouchMode);
        }
    }
    ...
}
```

这里直接调用了ViewRootImpl的 `windowFocusChanged` 函数：

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
public void windowFocusChanged(boolean hasFocus, boolean inTouchMode) {
    synchronized (this) {
        mWindowFocusChanged = true;
        mUpcomingWindowFocus = hasFocus;
        mUpcomingInTouchMode = inTouchMode;
    }
    Message msg = Message.obtain();
    msg.what = MSG_WINDOW_FOCUS_CHANGED;
    mHandler.sendMessage(msg);
}
```

向主线程发送了一个MSG_WINDOW_FOCUS_CHANGED的消息。

```java
// frameworks/base/core/java/android/view/ViewRootImpl.java
private void handleWindowFocusChanged() {
    final boolean hasWindowFocus;
    final boolean inTouchMode;
    synchronized (this) {
        if (!mWindowFocusChanged) {
            return;
        }
        mWindowFocusChanged = false;
        hasWindowFocus = mUpcomingWindowFocus;
        inTouchMode = mUpcomingInTouchMode;
    }

    if (mAdded) {
        profileRendering(hasWindowFocus);

        if (hasWindowFocus) {
            ensureTouchModeLocally(inTouchMode);
            if (mAttachInfo.mThreadedRenderer != null && mSurface.isValid()) {
                mFullRedrawNeeded = true;
                try {
                    final WindowManager.LayoutParams lp = mWindowAttributes;
                    final Rect surfaceInsets = lp != null ? lp.surfaceInsets : null;
                    // 更新硬件加速相关的逻辑。
                    mAttachInfo.mThreadedRenderer.initializeIfNeeded(
                            mWidth, mHeight, mAttachInfo, mSurface, surfaceInsets);
                } catch (OutOfResourcesException e) {
                    try {
                        if (!mWindowSession.outOfMemory(mWindow)) {
                            Process.killProcess(Process.myPid());
                        }
                    } catch (RemoteException ex) {
                    }
                    mHandler.sendMessageDelayed(mHandler.obtainMessage(MSG_WINDOW_FOCUS_CHANGED), 500);
                    return;
                }
            }
        }

        mAttachInfo.mHasWindowFocus = hasWindowFocus;

        mLastWasImTarget = WindowManager.LayoutParams.mayUseInputMethod(mWindowAttributes.flags);

        InputMethodManager imm = InputMethodManager.peekInstance();
        if (imm != null && mLastWasImTarget && !isInLocalFocusMode()) {
            imm.onPreWindowFocus(mView, hasWindowFocus);
        }
        if (mView != null) {
            mAttachInfo.mKeyDispatchState.reset();
            // 向DecorView分发dispatchWindowFocusChanged的消息。最后DecorView拿到PhoneWindow的Callback，将消息发送到Activity中。
            mView.dispatchWindowFocusChanged(hasWindowFocus);
            mAttachInfo.mTreeObserver.dispatchOnWindowFocusChange(hasWindowFocus);

            if (mAttachInfo.mTooltipHost != null) {
                mAttachInfo.mTooltipHost.hideTooltip();
            }
        }

        // Note: must be done after the focus change callbacks,
        // so all of the view state is set up correctly.
        if (hasWindowFocus) {
            if (imm != null && mLastWasImTarget && !isInLocalFocusMode()) {
                imm.onPostWindowFocus(mView, mView.findFocus(),
                        mWindowAttributes.softInputMode,
                        !mHasHadWindowFocus, mWindowAttributes.flags);
            }
            // Clear the forward bit.  We can just do this directly, since
            // the window manager doesn't care about it.
            mWindowAttributes.softInputMode &= ~WindowManager.LayoutParams.SOFT_INPUT_IS_FORWARD_NAVIGATION;
            ((WindowManager.LayoutParams) mView.getLayoutParams())
                    .softInputMode &= ~WindowManager.LayoutParams .SOFT_INPUT_IS_FORWARD_NAVIGATION;
            mHasHadWindowFocus = true;

            // Refocusing a window that has a focused view should fire a
            // focus event for the view since the global focused view changed.
            fireAccessibilityFocusEventIfHasFocusedNode();
        } else {
            if (mPointerCapture) {
                handlePointerCaptureChanged(false);
            }
        }
    }
    mFirstInputStage.onWindowFocusChanged(hasWindowFocus);
}
```

最终向DecorView分发 `dispatchWindowFocusChanged` 的消息。最后DecorView拿到PhoneWindow的Callback，将消息发送到Activity中。

## DecorView

`DecorView` 并没有重写 `dispatchWindowFocusChanged` 函数。因此其逻辑在ViewGroup中：

```java
// ViewGroup.java
@Override
public void dispatchWindowFocusChanged(boolean hasFocus) {
    super.dispatchWindowFocusChanged(hasFocus);
    final int count = mChildrenCount;
    final View[] children = mChildren;
    for (int i = 0; i < count; i++) {
        children[i].dispatchWindowFocusChanged(hasFocus);
    }
}

//View.java
public void dispatchWindowFocusChanged(boolean hasFocus) {
    onWindowFocusChanged(hasFocus);
}
```

ViewGroup首先会调用到`onWindowFocusChanged`，之后才会分发给子View。

DecorView 的 `onWindowFocusChanged` 函数如下：

```java
// frameworks/base/core/java/com/android/internal/policy/DecorView.java
@Override
public void onWindowFocusChanged(boolean hasWindowFocus) {
    super.onWindowFocusChanged(hasWindowFocus);

    // If the user is chording a menu shortcut, release the chord since
    // this window lost focus
    if (mWindow.hasFeature(Window.FEATURE_OPTIONS_PANEL) && !hasWindowFocus && mWindow.mPanelChordingKey != 0) {
        mWindow.closePanel(Window.FEATURE_OPTIONS_PANEL);
    }

    // 如果是Activity，那么这个Callback就是Activity本身。否则也有可能是Dialog等。
    final Window.Callback cb = mWindow.getCallback();
    if (cb != null && !mWindow.isDestroyed() && mFeatureId < 0) {
        cb.onWindowFocusChanged(hasWindowFocus);
    }
    if (mPrimaryActionMode != null) {
        mPrimaryActionMode.onWindowFocusChanged(hasWindowFocus);
    }
    if (mFloatingActionMode != null) {
        mFloatingActionMode.onWindowFocusChanged(hasWindowFocus);
    }

    updateElevation();
}
```

此时PhoneWindow的Callback的onWindowFocusChanged会被首先回调。

如果是Activity，那么这个Callback就是Activity本身，否则也有可能是Dialog等。也就是Activity的`onWindowFocusChanged`函数被回调。

## 总结


- windowFocusChanged

updateFocusedWindowLocked发生在Activity的Resume消息之前。但是我们知道WindowState发生在addWindow时才会创建，也就是`handleResumeActivity`发生之后，因此初次运行Activity时其并不会收到`windowFocusChanged`的消息。

不过，在ViewRootImpl调用WindowManagerService的addWindow之后，也会发生一次`updateFocusedWindowLocked`。此时WindowState是持有了mClient的(也就是mWindow对象)。

- resized

performTraversals() 在 `mFirst || windowShouldResize` 时会 relayoutWindow，此时WindowManagerService最终会向mWindow发送一个resized消息。而初次perforTraversals发生在setView之后的下一个TRAVERSAL消息中。

- 原则上

抛开ViewRootImpl的Handler不谈。从也就是说`addWindow`到`relayoutWindow`中间至少隔着一个TRAVERSAL消息。同时WindowManagerService向mClient发送消息，是发生在DisplayThread的Looper中的。也就是说中间，一来一会隔着好几个消息。也就是原则上说resized发生在windowFocusChanged之后好几个消息。

而ViewRootImpl的performTraversal消息至少发送两次(也就是收到resized消息之后)才会进行正在的绘制。

也就是说如果监听windowFocusChanged其实并不能用来当作冷启动的标准。

- 实际上

通过断点DecorView发现。`windowFocusChanged`发生在第一次draw之后，即resized发生在前。也就是说第一次addToDisplay/addWindow并不会发生窗口焦点的变化。