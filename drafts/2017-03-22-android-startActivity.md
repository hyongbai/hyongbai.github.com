---
layout: post
title: "StartActivity流程"
category: all-about-tech
tags: -[Android] -[ActivityThread]
date: 2017-03-22 01:49:57+00:00
---


Activity.startActivity

ActivityManagerService

```java
final int startActivity(Intent intent, ActivityStackSupervisor.ActivityContainer container) {
    enforceNotIsolatedCaller("ActivityContainer.startActivity");
    final int userId = mUserController.handleIncomingUser(Binder.getCallingPid(),
            Binder.getCallingUid(), mStackSupervisor.mCurrentUser, false,
            ActivityManagerService.ALLOW_FULL_ONLY, "ActivityContainer", null);

    // TODO: Switch to user app stacks here.
    String mimeType = intent.getType();
    final Uri data = intent.getData();
    if (mimeType == null && data != null && "content".equals(data.getScheme())) {
        mimeType = getProviderMimeType(data, userId);
    }
    container.checkEmbeddedAllowedInner(userId, intent, mimeType);

    intent.addFlags(FORCE_NEW_TASK_FLAGS);
    return mActivityStarter.startActivityMayWait(null, -1, null, intent, mimeType, null, null, null,
            null, 0, 0, null, null, null, null, false, userId, container, null);
}
```

ActivityStarter:


```java
final int startActivityMayWait(IApplicationThread caller, int callingUid,
        String callingPackage, Intent intent, String resolvedType,
        IVoiceInteractionSession voiceSession, IVoiceInteractor voiceInteractor,
        IBinder resultTo, String resultWho, int requestCode, int startFlags,
        ProfilerInfo profilerInfo, IActivityManager.WaitResult outResult, Configuration config,
        Bundle bOptions, boolean ignoreTargetSecurity, int userId,
        IActivityContainer iContainer, TaskRecord inTask) {
        ...
        final ActivityRecord[] outRecord = new ActivityRecord[1];
        int res = startActivityLocked(caller, intent, ephemeralIntent, resolvedType,
                aInfo, rInfo, voiceSession, voiceInteractor,
                resultTo, resultWho, requestCode, callingPid,
                callingUid, callingPackage, realCallingPid, realCallingUid, startFlags,
                options, ignoreTargetSecurity, componentSpecified, outRecord, container,
                inTask);
        ...
}
```

```java
final int startActivityLocked(IApplicationThread caller, Intent intent, Intent ephemeralIntent,
        String resolvedType, ActivityInfo aInfo, ResolveInfo rInfo,
        IVoiceInteractionSession voiceSession, IVoiceInteractor voiceInteractor,
        IBinder resultTo, String resultWho, int requestCode, int callingPid, int callingUid,
        String callingPackage, int realCallingPid, int realCallingUid, int startFlags,
        ActivityOptions options, boolean ignoreTargetSecurity, boolean componentSpecified,
        ActivityRecord[] outActivity, ActivityStackSupervisor.ActivityContainer container,
        TaskRecord inTask) {
    
    ...

    doPendingActivityLaunchesLocked(false);

    try {
        mService.mWindowManager.deferSurfaceLayout();
        err = startActivityUnchecked(r, sourceRecord, voiceSession, voiceInteractor, startFlags,
                true, options, inTask);
    } finally {
        mService.mWindowManager.continueSurfaceLayout();
    }
    postStartActivityUncheckedProcessing(r, err, stack.mStackId, mSourceRecord, mTargetStack);
    return err;
}
```

ActivityStack

```java
private int startActivityUnchecked(final ActivityRecord r, ActivityRecord sourceRecord,
        IVoiceInteractionSession voiceSession, IVoiceInteractor voiceInteractor,
        int startFlags, boolean doResume, ActivityOptions options, TaskRecord inTask) {
    ...
    mTargetStack.startActivityLocked(mStartActivity, newTask, mKeepCurTransition, mOptions);
	...
}
```

```
final void startActivityLocked(ActivityRecord r, boolean newTask, boolean keepCurTransition,
        ActivityOptions options) {
   	...
        if (r.mLaunchTaskBehind) {
            // Don't do a starting window for mLaunchTaskBehind. More importantly make sure we
            // tell WindowManager that r is visible even though it is at the back of the stack.
            mWindowManager.setAppVisibility(r.appToken, true);
            ensureActivitiesVisibleLocked(null, 0, !PRESERVE_WINDOWS);
        } else if (SHOW_APP_STARTING_PREVIEW && doShow) {
    ...
}
```

```java
final void ensureActivitiesVisibleLocked(ActivityRecord starting, int configChanges,
        boolean preserveWindows) {
   	...
                if (r.app == null || r.app.thread == null) {
                    if (makeVisibleAndRestartIfNeeded(starting, configChanges, isTop,
                            resumeNextActivity, r)) {
                        if (activityNdx >= activities.size()) {
                            // Record may be removed if its process needs to restart.
                            activityNdx = activities.size() - 1;
                        } else {
                            resumeNextActivity = false;
                        }
                    }
    ...
}
```
```java
private boolean makeVisibleAndRestartIfNeeded(ActivityRecord starting, int configChanges,
        boolean isTop, boolean andResume, ActivityRecord r) {
    // We need to make sure the app is running if it's the top, or it is just made visible from
    // invisible. If the app is already visible, it must have died while it was visible. In this
    // case, we'll show the dead window but will not restart the app. Otherwise we could end up
    // thrashing.
    if (isTop || !r.visible) {
        // This activity needs to be visible, but isn't even running...
        // get it started and resume if no other stack in this stack is resumed.
        if (DEBUG_VISIBILITY) Slog.v(TAG_VISIBILITY, "Start and freeze screen for " + r);
        if (r != starting) {
            r.startFreezingScreenLocked(r.app, configChanges);
        }
        if (!r.visible || r.mLaunchTaskBehind) {
            if (DEBUG_VISIBILITY) Slog.v(TAG_VISIBILITY, "Starting and making visible: " + r);
            setVisible(r, true);
        }
        if (r != starting) {
            mStackSupervisor.startSpecificActivityLocked(r, andResume, false);
            return true;
        }
    }
    return false;
}
```
```java
void startSpecificActivityLocked(ActivityRecord r,
        boolean andResume, boolean checkConfig) {
    // Is this activity's application already running?
    ProcessRecord app = mService.getProcessRecordLocked(r.processName,
            r.info.applicationInfo.uid, true);

    r.task.stack.setLaunchTime(r);

    if (app != null && app.thread != null) {
        try {
            if ((r.info.flags&ActivityInfo.FLAG_MULTIPROCESS) == 0
                    || !"android".equals(r.info.packageName)) {
                // Don't add this if it is a platform component that is marked
                // to run in multiple processes, because this is actually
                // part of the framework so doesn't make sense to track as a
                // separate apk in the process.
                app.addPackage(r.info.packageName, r.info.applicationInfo.versionCode,
                        mService.mProcessStats);
            }
            realStartActivityLocked(r, app, andResume, checkConfig);
            return;
        } catch (RemoteException e) {
            Slog.w(TAG, "Exception when starting activity "
                    + r.intent.getComponent().flattenToShortString(), e);
        }

        // If a dead object exception was thrown -- fall through to
        // restart the application.
    }

    mService.startProcessLocked(r.processName, r.info.applicationInfo, true, 0,
            "activity", r.intent.getComponent(), false, false, true);
}
```
```java
final boolean realStartActivityLocked(ActivityRecord r, ProcessRecord app,
        boolean andResume, boolean checkConfig) throws RemoteException {
    ...
        if (andResume) {
            app.hasShownUi = true;
            app.pendingUiClean = true;
        }
        app.forceProcessStateUpTo(mService.mTopProcessState);
        app.thread.scheduleLaunchActivity(new Intent(r.intent), r.appToken,
                System.identityHashCode(r), r.info, new Configuration(mService.mConfiguration),
                new Configuration(task.mOverrideConfig), r.compat, r.launchedFromPackage,
                task.voiceInteractor, app.repProcState, r.icicle, r.persistentState, results,
                newIntents, !andResume, mService.isNextTransitionForward(), profilerInfo);
    ...
}
```

ActivityThread.ApplicationThread
```java
@Override
public final void scheduleLaunchActivity(Intent intent, IBinder token, int ident,
        ActivityInfo info, Configuration curConfig, Configuration overrideConfig,
        CompatibilityInfo compatInfo, String referrer, IVoiceInteractor voiceInteractor,
        int procState, Bundle state, PersistableBundle persistentState,
        List<ResultInfo> pendingResults, List<ReferrerIntent> pendingNewIntents,
        boolean notResumed, boolean isForward, ProfilerInfo profilerInfo) {

    updateProcessState(procState, false);

    ActivityClientRecord r = new ActivityClientRecord();

    r.token = token;
    r.ident = ident;
    r.intent = intent;
    r.referrer = referrer;
    r.voiceInteractor = voiceInteractor;
    r.activityInfo = info;
    r.compatInfo = compatInfo;
    r.state = state;
    r.persistentState = persistentState;

    r.pendingResults = pendingResults;
    r.pendingIntents = pendingNewIntents;

    r.startsNotResumed = notResumed;
    r.isForward = isForward;

    r.profilerInfo = profilerInfo;

    r.overrideConfig = overrideConfig;
    updatePendingConfiguration(curConfig);

    sendMessage(H.LAUNCH_ACTIVITY, r);
}
```

