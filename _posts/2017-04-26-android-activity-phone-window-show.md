---
layout: post
title: "Activity如何显示view"
category: all-about-tech
tags: -[Android] -[Window] -[PhoneWindow] -[WindowManager]
date: 2017-04-26 13:03:00+00:00
---

作为一个Android开发者，你天天setContentView有意思吗？你知道前前后后Android做了什么吗？

这就是我一直想写但是又没花时间写的东西。

好吧，这就要讲到Activity的启动过程了。

> 本文基于`Android-25`所写，不同版本可能会有出入。

## Activity实例化

我们知道，Activity的启动主要依赖于AMS通过APP的ApplicationThread跨进程调用其`scheduleLaunchActivity`，然后发送一个`LAUNCH_ACTIVITY`的Message，之后ActivityThread会在`handleLaunchActivity`通过`performLaunchActivity`创建并调用起attach和onCreate。这样我们就可以在自己的Activity中的onCreate里面添加我们自己的view并做初始化等等。

> 注意，创建Activity已经onCreate都是通过Instrumentation处理的。其实Instrumentation的主要作用就是处理Activity的生命周期等逻辑的。

```java
//ActivityThread.java
private Activity performLaunchActivity(ActivityClientRecord r, Intent customIntent) {
    // ...
    Activity activity = null;
    try {
        java.lang.ClassLoader cl = r.packageInfo.getClassLoader();
        activity = mInstrumentation.newActivity(
                cl, component.getClassName(), r.intent);
    } 
    // ... 
    try {
        Application app = r.packageInfo.makeApplication(false, mInstrumentation);
		// ...
        if (activity != null) {
            Context appContext = createBaseContextForActivity(r, activity);
            CharSequence title = r.activityInfo.loadLabel(appContext.getPackageManager());
            Configuration config = new Configuration(mCompatConfiguration);
            if (r.overrideConfig != null) {
                config.updateFrom(r.overrideConfig);
            }
            if (DEBUG_CONFIGURATION) Slog.v(TAG, "Launching activity "
                    + r.activityInfo.name + " with config " + config);
            Window window = null;
            if (r.mPendingRemoveWindow != null && r.mPreserveWindow) {
                window = r.mPendingRemoveWindow;
                r.mPendingRemoveWindow = null;
                r.mPendingRemoveWindowManager = null;
            }
            activity.attach(appContext, this, getInstrumentation(), r.token,
                    r.ident, app, r.intent, r.activityInfo, title, r.parent,
                    r.embeddedID, r.lastNonConfigurationInstances, config,
                    r.referrer, r.voiceInteractor, window);

            if (customIntent != null) {
                activity.mIntent = customIntent;
            }
            r.lastNonConfigurationInstances = null;
            activity.mStartedActivity = false;
            int theme = r.activityInfo.getThemeResource();
            if (theme != 0) {
                activity.setTheme(theme);
            }

            activity.mCalled = false;
            if (r.isPersistable()) {
                mInstrumentation.callActivityOnCreate(activity, r.state, r.persistentState);
            } else {
                mInstrumentation.callActivityOnCreate(activity, r.state);
            }
            if (!activity.mCalled) {
                throw new SuperNotCalledException(
                    "Activity " + r.intent.getComponent().toShortString() +
                    " did not call through to super.onCreate()");
            }
    // ...
    return activity;
}
```

所以，这里主要涉及到三件事，分别是:

* **Activity实例化**

	其实Instrumentation只是调用ClassLoader生成了Activity的class，然后实例之。如果你对插件化感兴趣的话，会用到这里。
	
	```java
	(Activity)cl.loadClass(className).newInstance()
	```

* attach

	这里与Activity最终将view显示出来直接相关。如果没有这一步的话，View也就不能显示出来。这里做了很重要的一件事就是创建了一个`PhoneWindow`。它继承自Window，其实Window本身只是跟View或者跟显示没有啥关系。它只是一个中间人。比如Activity整个窗口布局等都是在里帮你做好了框架。然后就没有了，最终将View交给windowManagerService也跟它没有关系，万事俱备之后坐等ActivityThread用之。
	
	```java
	//Activity.java
	final void attach(Context context, ActivityThread aThread,
	        Instrumentation instr, IBinder token, int ident,
	        Application application, Intent intent, ActivityInfo info,
	        CharSequence title, Activity parent, String id,
	        NonConfigurationInstances lastNonConfigurationInstances,
	        Configuration config, String referrer, IVoiceInteractor voiceInteractor) {
	    attachBaseContext(context);
	
	    mFragments.attachActivity(this, mContainer, null);
	
	    mWindow = PolicyManager.makeNewWindow(this);
	    mWindow.setCallback(this);
	    mWindow.setOnWindowDismissedCallback(this);
	    mWindow.getLayoutInflater().setPrivateFactory(this);
	    if (info.softInputMode != WindowManager.LayoutParams.SOFT_INPUT_STATE_UNSPECIFIED) {
	        mWindow.setSoftInputMode(info.softInputMode);
	    }
	    if (info.uiOptions != 0) {
	        mWindow.setUiOptions(info.uiOptions);
	    }
	    // ... 
	    mWindow.setWindowManager(
	            (WindowManager)context.getSystemService(Context.WINDOW_SERVICE),
	            mToken, mComponent.flattenToString(),
	            (info.flags & ActivityInfo.FLAG_HARDWARE_ACCELERATED) != 0);
	    if (mParent != null) {
	        mWindow.setContainer(mParent.getWindow());
	    }
	    mWindowManager = mWindow.getWindowManager();
	    mCurrentConfig = config;
	}
	```
	
	`mWindow.setCallback(this)`这一句代码，是在Window中设置回调。很重要。
	
	还有一个有意思的地方在于，这里会通过PhoneWindow创建一个`LocalWindowManager`，具体可以看`mWindow.setWindowManager`里面的实现。然后Activity持有的WindowManager就是它了。所以当我们通过`Activity.getSystemService`和`Context.getSystemService`这两种方式拿到的WindowManager等会不一样，比如通过Service/Application等等。
	这就是为什么Service等不能弹出dialog的缘故。不细说，以后专门讲一讲。
	
* onCreate

	这里就是我们熟悉的onCreate了。比如:`setContentView`。
	
## 添加布局

好吧，我们来看看setContentView之后Activity做了什么？

```java
//Activity.java
public void setContentView(int layoutResID) {
    getWindow().setContentView(layoutResID);
    initWindowDecorActionBar();
}
public void setContentView(View view) {
    getWindow().setContentView(view);
    initWindowDecorActionBar();
}
public void setContentView(View view, ViewGroup.LayoutParams params) {
    getWindow().setContentView(view, params);
    initWindowDecorActionBar();
}
```

Activity提供了三种姿势来设置需要显示的View/布局。以上，其实没啥区别。`initWindowDecorActionBar`这里的逻辑先忽略之。

上面提到的三个，其实区别不大，我们就以第一个为例。我们知道Activity里面的Window其实是`PhoneWindow`，所以我们去它里面看看其实如何实现的。

```java
//PhoneWindow.java
@Override
public void setContentView(int layoutResID) {
    // Note: FEATURE_CONTENT_TRANSITIONS may be set in the process of installing the window
    // decor, when theme attributes and the like are crystalized. Do not check the feature
    // before this happens.
    if (mContentParent == null) {
        installDecor();
    } else if (!hasFeature(FEATURE_CONTENT_TRANSITIONS)) {
        mContentParent.removeAllViews();
    }

    if (hasFeature(FEATURE_CONTENT_TRANSITIONS)) {
        final Scene newScene = Scene.getSceneForLayout(mContentParent, layoutResID,
                getContext());
        transitionTo(newScene);
    } else {
        mLayoutInflater.inflate(layoutResID, mContentParent);
    }
    final Callback cb = getCallback();
    if (cb != null && !isDestroyed()) {
        cb.onContentChanged();
    }
}
```

会通过installDecor()初始化DecorView。这个是Activity最最外层的View了（ViewRootImpl严格意义上讲不是一个View）。

```java
//PhoneWindow.java

private void installDecor() {
    if (mDecor == null) {
        mDecor = generateDecor();
        mDecor.setDescendantFocusability(ViewGroup.FOCUS_AFTER_DESCENDANTS);
        mDecor.setIsRootNamespace(true);
        if (!mInvalidatePanelMenuPosted && mInvalidatePanelMenuFeatures != 0) {
            mDecor.postOnAnimation(mInvalidatePanelMenuRunnable);
        }
    }
    if (mContentParent == null) {
        mContentParent = generateLayout(mDecor);

        // Set up decor part of UI to ignore fitsSystemWindows if appropriate.
        mDecor.makeOptionalFitsSystemWindows();

        final DecorContentParent decorContentParent = (DecorContentParent) mDecor.findViewById(
                R.id.decor_content_parent);

        if (decorContentParent != null) {
            mDecorContentParent = decorContentParent;
            mDecorContentParent.setWindowCallback(getCallback());
            if (mDecorContentParent.getTitle() == null) {
                mDecorContentParent.setWindowTitle(mTitle);
            }

            final int localFeatures = getLocalFeatures();
            for (int i = 0; i < FEATURE_MAX; i++) {
                if ((localFeatures & (1 << i)) != 0) {
                    mDecorContentParent.initFeature(i);
                }
            }

            mDecorContentParent.setUiOptions(mUiOptions);

            if ((mResourcesSetFlags & FLAG_RESOURCE_SET_ICON) != 0 ||
                    (mIconRes != 0 && !mDecorContentParent.hasIcon())) {
                mDecorContentParent.setIcon(mIconRes);
            } else if ((mResourcesSetFlags & FLAG_RESOURCE_SET_ICON) == 0 &&
                    mIconRes == 0 && !mDecorContentParent.hasIcon()) {
                mDecorContentParent.setIcon(
                        getContext().getPackageManager().getDefaultActivityIcon());
                mResourcesSetFlags |= FLAG_RESOURCE_SET_ICON_FALLBACK;
            }
            if ((mResourcesSetFlags & FLAG_RESOURCE_SET_LOGO) != 0 ||
                    (mLogoRes != 0 && !mDecorContentParent.hasLogo())) {
                mDecorContentParent.setLogo(mLogoRes);
            }

            // Invalidate if the panel menu hasn't been created before this.
            // Panel menu invalidation is deferred avoiding application onCreateOptionsMenu
            // being called in the middle of onCreate or similar.
            // A pending invalidation will typically be resolved before the posted message
            // would run normally in order to satisfy instance state restoration.
            PanelFeatureState st = getPanelState(FEATURE_OPTIONS_PANEL, false);
            if (!isDestroyed() && (st == null || st.menu == null)) {
                invalidatePanelMenu(FEATURE_ACTION_BAR);
            }
        } else {
            mTitleView = (TextView)findViewById(R.id.title);
            if (mTitleView != null) {
                mTitleView.setLayoutDirection(mDecor.getLayoutDirection());
                if ((getLocalFeatures() & (1 << FEATURE_NO_TITLE)) != 0) {
                    View titleContainer = findViewById(
                            R.id.title_container);
                    if (titleContainer != null) {
                        titleContainer.setVisibility(View.GONE);
                    } else {
                        mTitleView.setVisibility(View.GONE);
                    }
                    if (mContentParent instanceof FrameLayout) {
                        ((FrameLayout)mContentParent).setForeground(null);
                    }
                } else {
                    mTitleView.setText(mTitle);
                }
            }
        }

        if (mDecor.getBackground() == null && mBackgroundFallbackResource != 0) {
            mDecor.setBackgroundFallback(mBackgroundFallbackResource);
        }

        // Only inflate or create a new TransitionManager if the caller hasn't
        // already set a custom one.
        if (hasFeature(FEATURE_ACTIVITY_TRANSITIONS)) {
            if (mTransitionManager == null) {
                final int transitionRes = getWindowStyle().getResourceId(
                        R.styleable.Window_windowContentTransitionManager,
                        0);
                if (transitionRes != 0) {
                    final TransitionInflater inflater = TransitionInflater.from(getContext());
                    mTransitionManager = inflater.inflateTransitionManager(transitionRes,
                            mContentParent);
                } else {
                    mTransitionManager = new TransitionManager();
                }
            }

            mEnterTransition = getTransition(mEnterTransition, null,
                    R.styleable.Window_windowEnterTransition);
            mReturnTransition = getTransition(mReturnTransition, USE_DEFAULT_TRANSITION,
                    R.styleable.Window_windowReturnTransition);
            mExitTransition = getTransition(mExitTransition, null,
                    R.styleable.Window_windowExitTransition);
            mReenterTransition = getTransition(mReenterTransition, USE_DEFAULT_TRANSITION,
                    R.styleable.Window_windowReenterTransition);
            mSharedElementEnterTransition = getTransition(mSharedElementEnterTransition, null,
                    R.styleable.Window_windowSharedElementEnterTransition);
            mSharedElementReturnTransition = getTransition(mSharedElementReturnTransition,
                    USE_DEFAULT_TRANSITION,
                    R.styleable.Window_windowSharedElementReturnTransition);
            mSharedElementExitTransition = getTransition(mSharedElementExitTransition, null,
                    R.styleable.Window_windowSharedElementExitTransition);
            mSharedElementReenterTransition = getTransition(mSharedElementReenterTransition,
                    USE_DEFAULT_TRANSITION,
                    R.styleable.Window_windowSharedElementReenterTransition);
            if (mAllowEnterTransitionOverlap == null) {
                mAllowEnterTransitionOverlap = getWindowStyle().getBoolean(
                        R.styleable.Window_windowAllowEnterTransitionOverlap, true);
            }
            if (mAllowReturnTransitionOverlap == null) {
                mAllowReturnTransitionOverlap = getWindowStyle().getBoolean(
                        R.styleable.Window_windowAllowReturnTransitionOverlap, true);
            }
            if (mBackgroundFadeDurationMillis < 0) {
                mBackgroundFadeDurationMillis = getWindowStyle().getInteger(
                        R.styleable.Window_windowTransitionBackgroundFadeDuration,
                        DEFAULT_BACKGROUND_FADE_DURATION_MS);
            }
            if (mSharedElementsUseOverlay == null) {
                mSharedElementsUseOverlay = getWindowStyle().getBoolean(
                        R.styleable.Window_windowSharedElementsUseOverlay, true);
            }
        }
    }
}
```

`installDecor`中生成了DecorView/ContentRoot/ContentLayout等。也包括转场动画、输入法弹出方式、ActionBar、Menu等等。具体代码太多了。

## 显示布局

都知道在onResume之前，我们是没办法拿到View的尺寸等信息。这是因为在onResume的时候View压根就没有添加到窗口中。

ActivityManagerService通过ApplicationThread这个binder连接应用的ActivityThread。所以当ActivityManagerService通知我们`scheduleResumeActivity`即表示Activity可以进入onResume这个生命周期了。

我们来看看ActivityThread里面在收到RESUME_ACTIVITY时做了什么。

```java
//ActivityThread.java
final void handleResumeActivity(IBinder token,
        boolean clearHide, boolean isForward, boolean reallyResume, int seq, String reason) {
   // ...
    mSomeActivitiesChanged = true;

    // TODO Push resumeArgs into the activity for consideration
    r = performResumeActivity(token, clearHide, reason);

    if (r != null) {
        final Activity a = r.activity;

        if (localLOGV) Slog.v(
            TAG, "Resume " + r + " started activity: " +
            a.mStartedActivity + ", hideForNow: " + r.hideForNow
            + ", finished: " + a.mFinished);

        final int forwardBit = isForward ?
                WindowManager.LayoutParams.SOFT_INPUT_IS_FORWARD_NAVIGATION : 0;

        // If the window hasn't yet been added to the window manager,
        // and this guy didn't finish itself or start another activity,
        // then go ahead and add the window.
        boolean willBeVisible = !a.mStartedActivity;
        if (!willBeVisible) {
            try {
                willBeVisible = ActivityManagerNative.getDefault().willActivityBeVisible(
                        a.getActivityToken());
            } catch (RemoteException e) {
                throw e.rethrowFromSystemServer();
            }
        }
        if (r.window == null && !a.mFinished && willBeVisible) {
            r.window = r.activity.getWindow();
            View decor = r.window.getDecorView();
            decor.setVisibility(View.INVISIBLE);
            ViewManager wm = a.getWindowManager();
            WindowManager.LayoutParams l = r.window.getAttributes();
            a.mDecor = decor;
            l.type = WindowManager.LayoutParams.TYPE_BASE_APPLICATION;
            l.softInputMode |= forwardBit;
            if (r.mPreserveWindow) {
                a.mWindowAdded = true;
                r.mPreserveWindow = false;
                // Normally the ViewRoot sets up callbacks with the Activity
                // in addView->ViewRootImpl#setView. If we are instead reusing
                // the decor view we have to notify the view root that the
                // callbacks may have changed.
                ViewRootImpl impl = decor.getViewRootImpl();
                if (impl != null) {
                    impl.notifyChildRebuilt();
                }
            }
            if (a.mVisibleFromClient && !a.mWindowAdded) {
                a.mWindowAdded = true;
                wm.addView(decor, l);
            }

        // If the window has already been added, but during resume
        // we started another activity, then don't yet make the
        // window visible.
        } else if (!willBeVisible) {
            if (localLOGV) Slog.v(
                TAG, "Launch " + r + " mStartedActivity set");
            r.hideForNow = true;
        }
        // ...
}
```

其中`performResumeActivity`即使调用到activity里面的`performResume`，我们的onResume就在这里完成了。

接着才会拿到Activity里面的Window，然后将其中的DecorView通过WindowManager的addView添加到窗口当中。此时才会显示。也就是说onResume是在addView之前就发生了。

## 事件分发

Activity在attach中PhoneWindow初始化时注册了一个Callback，主要目的是用来处理各种Event、Menu等，比如KeyEvent、TouchEvent等等。

具体包含的接口如下：

```java
//Window$Callback.java
public interface Callback {
    public boolean dispatchKeyEvent(KeyEvent event);
    public boolean dispatchKeyShortcutEvent(KeyEvent event);
    public boolean dispatchTouchEvent(MotionEvent event);
    public boolean dispatchTrackballEvent(MotionEvent event);
    public boolean dispatchGenericMotionEvent(MotionEvent event);
    public boolean dispatchPopulateAccessibilityEvent(AccessibilityEvent event);
    public View onCreatePanelView(int featureId);
    public boolean onCreatePanelMenu(int featureId, Menu menu);
    public boolean onPreparePanel(int featureId, View view, Menu menu);
    public boolean onMenuOpened(int featureId, Menu menu);
    public boolean onMenuItemSelected(int featureId, MenuItem item);
    public void onWindowAttributesChanged(WindowManager.LayoutParams attrs);
    public void onContentChanged();
    public void onWindowFocusChanged(boolean hasFocus);
    public void onAttachedToWindow();
    public void onDetachedFromWindow();
    public void onPanelClosed(int featureId, Menu menu);
    public boolean onSearchRequested();
    public boolean onSearchRequested(SearchEvent searchEvent);
    public ActionMode onWindowStartingActionMode(ActionMode.Callback callback);
    public ActionMode onWindowStartingActionMode(ActionMode.Callback callback, int type);
    public void onActionModeStarted(ActionMode mode);
    public void onActionModeFinished(ActionMode mode);
    default public void onProvideKeyboardShortcuts(
            List<KeyboardShortcutGroup> data, @Nullable Menu menu, int deviceId) { };
}
```

不论是KeyEvent还是MotionEvent，都是通过ViewRootImpl传递到DecorView，然后在DecorView中通过回调传递到Activity中，保证整个事件都是可以在Activity中优先收取优先截获。Activity默认会再将是将事件传递给PhoneWindow，然后PhoneWindow再将其专递给DecorView的super.xxx分发到ViewTree中去。

比如，我们以MotionEvent为例。

大致是：

### ViewRootImpl收到

所有的Event都是来自于ViewRootImpl这个最外层的Parent。

它是通过实现InputStage的onProcess实现采集各种原始的Event，然后根据其类型分发下来。

```java
//ViewRootImpl$ViewPostImeInputStage.java
@Override
protected int onProcess(QueuedInputEvent q) {
    if (q.mEvent instanceof KeyEvent) {
        return processKeyEvent(q);
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
```

实现了`onProcess`，这里就分别处理了KeyEvent等。

下面是处理Touch事件的`processPointerEvent`的实现：

```java
//ViewRootImpl.java
private int processPointerEvent(QueuedInputEvent q) {
    final MotionEvent event = (MotionEvent)q.mEvent;

    mAttachInfo.mUnbufferedDispatchRequested = false;
    final View eventTarget =
            (event.isFromSource(InputDevice.SOURCE_MOUSE) && mCapturingView != null) ?
                    mCapturingView : mView;
    mAttachInfo.mHandlingPointerEvent = true;
    boolean handled = eventTarget.dispatchPointerEvent(event);
    maybeUpdatePointerIcon(event);
    mAttachInfo.mHandlingPointerEvent = false;
    if (mAttachInfo.mUnbufferedDispatchRequested && !mUnbufferedInputDispatch) {
        mUnbufferedInputDispatch = true;
        if (mConsumeBatchedInputScheduled) {
            scheduleConsumeBatchedInputImmediately();
        }
    }
    return handled ? FINISH_HANDLED : FORWARD;
}
```

其中`eventTarget.dispatchPointerEvent`，就是传递给DecorView。之后DecorView的dispatchTouchEvent会响应。

### DecorView响应

```java
//DecorView.java
@Override
public boolean dispatchTouchEvent(MotionEvent ev) {
    final Window.Callback cb = mWindow.getCallback();
    return cb != null && !mWindow.isDestroyed() && mFeatureId < 0
            ? cb.dispatchTouchEvent(ev) : super.dispatchTouchEvent(ev);
}
```

注意，这里的`mWindow.getCallback()`就是我们的Activity。此时会回调给Activity的`dispatchTouchEvent`中去。

### Activity响应

```java
//Activity.java
public boolean dispatchTouchEvent(MotionEvent ev) {
    if (ev.getAction() == MotionEvent.ACTION_DOWN) {
        onUserInteraction();
    }
    if (getWindow().superDispatchTouchEvent(ev)) {
        return true;
    }
    return onTouchEvent(ev);
}
```

其实Activity收到之后立马就调用到DecorView的ViewTree中了。不过，好像没看到啊。对，其实那个getWindow().superDispatchTouchEvent(ev)即是。

getWindow就是PhoneWindow，superDispatchTouchEvent最终调用的是DecorView.superDispatchTouchEvent中，直接进入到我们熟悉的ViewGroup的Touch事件分发。

这里是`getWindow().superDispatchTouchEvent(ev)`的具体实现：

```java
// PhoneWindow.java
@Override
public boolean superDispatchTouchEvent(MotionEvent event) {
    return mDecor.superDispatchTouchEvent(event);
}

// DecorView.java
public boolean superDispatchTouchEvent(MotionEvent event) {
    return super.dispatchTouchEvent(event);
}
```

对不。

Activity中为什么要非这劲绕以圈呢？其实就是为了让Activity可以优先控制这些个事件，而已。

## ActionBar

ActionBar是在setContentView的时候一并处理的。下面是setContentView中调用的`initWindowDecorActionBar`。

```java
//Activity.java
private void initWindowDecorActionBar() {
    Window window = getWindow();

    // Initializing the window decor can change window feature flags.
    // Make sure that we have the correct set before performing the test below.
    window.getDecorView();

    if (isChild() || !window.hasFeature(Window.FEATURE_ACTION_BAR) || mActionBar != null) {
        return;
    }

    mActionBar = new WindowDecorActionBar(this);
    mActionBar.setDefaultDisplayHomeAsUpEnabled(mEnableDefaultActionBarUp);

    mWindow.setDefaultIcon(mActivityInfo.getIconResource());
    mWindow.setDefaultLogo(mActivityInfo.getLogoResource());
}
```

其实主要就是生成一个`WindowDecorActionBar`。而ActionBar的布局等等都是在init函数中实现的。来看看：

```java
//com.android.internal.app.WindowDecorActionBar.java
public WindowDecorActionBar(Activity activity) {
    mActivity = activity;
    Window window = activity.getWindow();
    View decor = window.getDecorView();
    boolean overlayMode = mActivity.getWindow().hasFeature(Window.FEATURE_ACTION_BAR_OVERLAY);
    init(decor);
    if (!overlayMode) {
        mContentView = decor.findViewById(android.R.id.content);
    }
}

private void init(View decor) {
    mOverlayLayout = (ActionBarOverlayLayout) decor.findViewById(
            com.android.internal.R.id.decor_content_parent);
    if (mOverlayLayout != null) {
        mOverlayLayout.setActionBarVisibilityCallback(this);
    }
    mDecorToolbar = getDecorToolbar(decor.findViewById(com.android.internal.R.id.action_bar));
    mContextView = (ActionBarContextView) decor.findViewById(
            com.android.internal.R.id.action_context_bar);
    mContainerView = (ActionBarContainer) decor.findViewById(
            com.android.internal.R.id.action_bar_container);
    mSplitView = (ActionBarContainer) decor.findViewById(
            com.android.internal.R.id.split_action_bar);

    if (mDecorToolbar == null || mContextView == null || mContainerView == null) {
        throw new IllegalStateException(getClass().getSimpleName() + " can only be used " +
                "with a compatible window decor layout");
    }

    mContext = mDecorToolbar.getContext();
    mContextDisplayMode = mDecorToolbar.isSplit() ?
            CONTEXT_DISPLAY_SPLIT : CONTEXT_DISPLAY_NORMAL;

    // This was initially read from the action bar style
    final int current = mDecorToolbar.getDisplayOptions();
    final boolean homeAsUp = (current & DISPLAY_HOME_AS_UP) != 0;
    if (homeAsUp) {
        mDisplayHomeAsUpSet = true;
    }

    ActionBarPolicy abp = ActionBarPolicy.get(mContext);
    setHomeButtonEnabled(abp.enableHomeButtonByDefault() || homeAsUp);
    setHasEmbeddedTabs(abp.hasEmbeddedTabs());

    final TypedArray a = mContext.obtainStyledAttributes(null,
            com.android.internal.R.styleable.ActionBar,
            com.android.internal.R.attr.actionBarStyle, 0);
    if (a.getBoolean(R.styleable.ActionBar_hideOnContentScroll, false)) {
        setHideOnContentScrollEnabled(true);
    }
    final int elevation = a.getDimensionPixelSize(R.styleable.ActionBar_elevation, 0);
    if (elevation != 0) {
        setElevation(elevation);
    }
    a.recycle();
}
```

在PhoneWindow的`generateLayout`中，初始化mContentRoot的LayoutResourceId时，可以发现，如果不是`FEATURE_NO_TITLE`的话，最终会使用`R.layout.screen_action_bar`这个Layout。源代码如下：

```java
//PhoneWindow.java
if ((features & (1 << FEATURE_NO_TITLE)) == 0) {
    // If no other features and not embedded, only need a title.
    // If the window is floating, we need a dialog layout
    if (mIsFloating) {
        TypedValue res = new TypedValue();
        getContext().getTheme().resolveAttribute(
                R.attr.dialogTitleDecorLayout, res, true);
        layoutResource = res.resourceId;
    } else if ((features & (1 << FEATURE_ACTION_BAR)) != 0) {
        layoutResource = a.getResourceId(
                R.styleable.Window_windowActionBarFullscreenDecorLayout,
                R.layout.screen_action_bar);
    } else {
        layoutResource = R.layout.screen_title;
    }
    // System.out.println("Title!");
}
```

这个`screen_action_bar`就是WindowDecorActionBar中ActionBar的布局了。

好吧，那咱们来看看WindowDecorActionBar的布局如何：

```xml
//screen_action_bar.xml
<com.android.internal.widget.ActionBarOverlayLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/decor_content_parent"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:splitMotionEvents="false"
    android:theme="?attr/actionBarTheme">
    <FrameLayout android:id="@android:id/content"
                 android:layout_width="match_parent"
                 android:layout_height="match_parent" />
    <com.android.internal.widget.ActionBarContainer
        android:id="@+id/action_bar_container"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_alignParentTop="true"
        style="?attr/actionBarStyle"
        android:transitionName="android:action_bar"
        android:touchscreenBlocksFocus="true"
        android:gravity="top">
        <com.android.internal.widget.ActionBarView
            android:id="@+id/action_bar"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            style="?attr/actionBarStyle" />
        <com.android.internal.widget.ActionBarContextView
            android:id="@+id/action_context_bar"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:visibility="gone"
            style="?attr/actionModeStyle" />
    </com.android.internal.widget.ActionBarContainer>
    <com.android.internal.widget.ActionBarContainer android:id="@+id/split_action_bar"
                  android:layout_width="match_parent"
                  android:layout_height="wrap_content"
                  style="?attr/actionBarSplitStyle"
                  android:visibility="gone"
                  android:touchscreenBlocksFocus="true"
                  android:gravity="center"/>
</com.android.internal.widget.ActionBarOverlayLayout>
```