---
layout: post
title: "Fragment内部逻辑"
category: all-about-tech
tags: -[Android] -[Fragment]
date: 2017-05-07 23:03:00+00:00
---

## 介绍 

我们知道在Android4.0之后，出了一个叫做Fragment的东西，来减轻Activity的罪孽。Fragment基本上一个轻量化的页面，Activity的行为都可以放在这里来做。

balabala

## 初始化

略过无用的介绍之后，我们来看看Fragment是如何工作的。

### FragmentController
首先，Activity在实例化的时候会生成一个final地全局变量，叫做`FragmentController`，之后Fragment与Activity的交互都是通过这个Controller来牵线搭桥了。也就是说这是一个中间人的角色，称之为Controller再恰到不过了。

下面是这个Controller的初始化过程。

```java
//Activity.java
final FragmentController mFragments = FragmentController.createController(new HostCallbacks());
```

先来谈谈FragmentController，翻开源码发现这玩意的每一个操作都是通过mHost来完成的，而这个Host就是初始化时传入的HostCallbacks。

其次，在FragmentController初始化的时候，这里面有个HostCallbacks，它主要的作用就是Activity提供给FragmentController回调自己的。比如`findViewById`、`onRequestPermissionsFromFragment`、`startActivityForResult`等等都是通过它回调到Activity里面的。同时FragmentManager也会持有之。这玩意才是FragmentManager/Fragment与Activity交互的核心。所以本质上Fragment与Activity连接的核心应该是`HostCallbacks`，而不是`FragmentController`。

### HostCallbacks

好了，我们来看看`HostCallbacks`吧。首先它继承自`FragmentHostCallback`，是一个`FragmentContainer`接口。好吧，个人认为HostCallbacks没啥好讲的。要不我们看看它是如何实现findview的把，毕竟在FragmentManager中会用到。

```java
//Activity$HostCallbacks.java
@Override
public View onFindViewById(int id) {
    return Activity.this.findViewById(id);
}
```

就是调用`Activity.this.findViewById`嘛，哈哈哈。其他的也是同理，略过。

### FragmentHostCallback

这里才是FragmentManager对象实例化的地方，它继承自`FragmentContainer`。像Activity一样，在它init的时候，成员变量中就立马实例了一个`FragmentManagerImpl`对象，然后存储下来。

```java
//FragmentHostCallback.java
final FragmentManagerImpl mFragmentManager = new FragmentManagerImpl();
```

然后，当我们调用Activity.getFragmentManager的时候，Activity调用FragmentController，然后进而调用FragmentHostCallback中的

```java
//FragmentHostCallback.java
FragmentManagerImpl getFragmentManagerImpl() {
    return mFragmentManager;
}
```

基本上就是兜了一圈之后又回来了。然后这里面剩下的逻辑都是LoaderManager的事情了，LoaderManager打算专门讲一下，这里就略过了。

### FragmentManager

当我们把FragmentController、HostCallbacks、FragmentHostCallback的初始化讲完之后，基本上FragmentManager的初始化也讲完了。

需要指出的，Fragment里面mHost和mContainer的初始化时在其`attachController`中完成的。而后者是在FragmentController的`attachHost`中完成的。
```java
//FragmentController.java
public void attachHost(Fragment parent) {
    mHost.mFragmentManager.attachController(
            mHost, mHost /*container*/, parent);
}
```

所以FragmentMamanager的mHost和mContainer都是`HostCallbacks`的实例化对象。

而attachHost是在Activity初始化的时候被调用到的。如下:

```java
//Activity.java

final void attach(Context context, ActivityThread aThread,
        Instrumentation instr, IBinder token, int ident,
        Application application, Intent intent, ActivityInfo info,
        CharSequence title, Activity parent, String id,
        NonConfigurationInstances lastNonConfigurationInstances,
        Configuration config, String referrer, IVoiceInteractor voiceInteractor,
        Window window) {
    attachBaseContext(context);

    mFragments.attachHost(null /*parent*/);
    // ...
}
```

## Fragment

上面我们知道了FragmentManager和Activity的相互关系。下面我们来讲讲Fragment的是如何显示的呢？

### FragmentTransaction

我们知道对于Fragment的操作我们都需要通过FragmentTransaction来操作。获取FragmentTransaction的方式如下：

```java
final FragmentTransaction ft = getFragmentManager().beginTransaction();
```
其实这个时候在FragmentManagerImpl中的实现是创建了一个`BackStackRecord`：

```java
//FragmentManager$FragmentManagerImpl.java
@Override
public FragmentTransaction beginTransaction() {
    return new BackStackRecord(this);
}
```

也就是说FragmentTransaction的实现是在BackStackRecord中。

FragmentTransaction提供了add/replace/remove/hide/show/deatch/attach等多种方式操作Fragment。但是，你要记住了，故名思意它是一个Transaction操作，无论你一次性做了多少个操作，它都是只(只能)提交一次的。所有的这些操作都在一个BackStackRecord中，并且记录下来，也就是说当你按下返回键的时候立马回到此次提交之前的状态。

### Op

比如当我们使用替换的方式显示一个新的Fragment的时候。

实例代码:

```java
getFragmentManager().beginTransaction().replace(id, fragment, tag).addToBackStack(null).commit();
```

不管是replace还是其他方法，最终都是创建一个Op，然后将这个Op加入到链表中去。如下：

```java
//BackStackState.java
private void doAddOp(int containerViewId, Fragment fragment, String tag, int opcmd) {
    fragment.mFragmentManager = mManager;
    // ...
    Op op = new Op();
    op.cmd = opcmd;
    op.fragment = fragment;
    addOp(op);
}

void addOp(Op op) {
    if (mHead == null) {
        mHead = mTail = op;
    } else {
        op.prev = mTail;
        mTail.next = op;
        mTail = op;
    }
    op.enterAnim = mEnterAnim;
    op.exitAnim = mExitAnim;
    op.popEnterAnim = mPopEnterAnim;
    op.popExitAnim = mPopExitAnim;
    mNumOp++;
}
```

也就是说在同一个Transaction中可以同时执行多个操作，这也是为啥要叫beginTransaction().

### commit

之后需要调用commit等来提交操作，且只能调用一次commit。

```java
//BackStackState.java
public int commit() {
    return commitInternal(false);
}
int commitInternal(boolean allowStateLoss) {
    if (mCommitted) {
        throw new IllegalStateException("commit already called");
    }
    if (FragmentManagerImpl.DEBUG) {
        Log.v(TAG, "Commit: " + this);
        LogWriter logw = new LogWriter(Log.VERBOSE, TAG);
        PrintWriter pw = new FastPrintWriter(logw, false, 1024);
        dump("  ", null, pw, null);
        pw.flush();
    }
    mCommitted = true;
    if (mAddToBackStack) {
        mIndex = mManager.allocBackStackIndex(this);
    } else {
        mIndex = -1;
    }
    mManager.enqueueAction(this, allowStateLoss);
    return mIndex;
}
```

commit之后主要是在FragmentManager的mPendingActions中添加一个post任务。不信你看：

```java
//FragmentManager$FragmentManagerImpl.java
public void enqueueAction(Runnable action, boolean allowStateLoss) {
    if (!allowStateLoss) {
        checkStateLoss();
    }
    synchronized (this) {
        if (mDestroyed || mHost == null) {
            throw new IllegalStateException("Activity has been destroyed");
        }
        if (mPendingActions == null) {
            mPendingActions = new ArrayList<Runnable>();
        }
        mPendingActions.add(action);
        if (mPendingActions.size() == 1) {
            mHost.getHandler().removeCallbacks(mExecCommit);
            mHost.getHandler().post(mExecCommit);
        }
    }
}
```

添加第一个Action的时候，会post一个`mExecCommit`任务，而这个任务的主要作用就是在主线程中调用execPendingActions()将mPendingActions里面的action(即BackStackState)一一执行run()，略之。

### Execute commit(Action)

上面讲到在mExecCommit，最终会处理每一个BackStackState。看看BackStackState是如何实现`run()`的。

```java
//BackStackState.java
public void run() {
    if (FragmentManagerImpl.DEBUG) {
        Log.v(TAG, "Run: " + this);
    }

    if (mAddToBackStack) {
        if (mIndex < 0) {
            throw new IllegalStateException("addToBackStack() called after commit()");
        }
    }

    bumpBackStackNesting(1);

    if (mManager.mCurState >= Fragment.CREATED) {
        SparseArray<Fragment> firstOutFragments = new SparseArray<Fragment>();
        SparseArray<Fragment> lastInFragments = new SparseArray<Fragment>();
        calculateFragments(firstOutFragments, lastInFragments);
        beginTransition(firstOutFragments, lastInFragments, false);
    }

    Op op = mHead;
    while (op != null) {
        switch (op.cmd) {
            case OP_ADD: {
                Fragment f = op.fragment;
                f.mNextAnim = op.enterAnim;
                mManager.addFragment(f, false);
            }
            break;
            case OP_REPLACE: {
                Fragment f = op.fragment;
                int containerId = f.mContainerId;
                if (mManager.mAdded != null) {
                    for (int i = mManager.mAdded.size() - 1; i >= 0; i--) {
                        Fragment old = mManager.mAdded.get(i);
                        if (FragmentManagerImpl.DEBUG) {
                            Log.v(TAG,
                                    "OP_REPLACE: adding=" + f + " old=" + old);
                        }
                        if (old.mContainerId == containerId) {
                            if (old == f) {
                                op.fragment = f = null;
                            } else {
                                if (op.removed == null) {
                                    op.removed = new ArrayList<Fragment>();
                                }
                                op.removed.add(old);
                                old.mNextAnim = op.exitAnim;
                                if (mAddToBackStack) {
                                    old.mBackStackNesting += 1;
                                    if (FragmentManagerImpl.DEBUG) {
                                        Log.v(TAG, "Bump nesting of "
                                                + old + " to " + old.mBackStackNesting);
                                    }
                                }
                                mManager.removeFragment(old, mTransition, mTransitionStyle);
                            }
                        }
                    }
                }
                if (f != null) {
                    f.mNextAnim = op.enterAnim;
                    mManager.addFragment(f, false);
                }
            }
            break;
            case OP_REMOVE: {
                Fragment f = op.fragment;
                f.mNextAnim = op.exitAnim;
                mManager.removeFragment(f, mTransition, mTransitionStyle);
            }
            break;
            case OP_HIDE: {
                Fragment f = op.fragment;
                f.mNextAnim = op.exitAnim;
                mManager.hideFragment(f, mTransition, mTransitionStyle);
            }
            break;
            case OP_SHOW: {
                Fragment f = op.fragment;
                f.mNextAnim = op.enterAnim;
                mManager.showFragment(f, mTransition, mTransitionStyle);
            }
            break;
            case OP_DETACH: {
                Fragment f = op.fragment;
                f.mNextAnim = op.exitAnim;
                mManager.detachFragment(f, mTransition, mTransitionStyle);
            }
            break;
            case OP_ATTACH: {
                Fragment f = op.fragment;
                f.mNextAnim = op.enterAnim;
                mManager.attachFragment(f, mTransition, mTransitionStyle);
            }
            break;
            default: {
                throw new IllegalArgumentException("Unknown cmd: " + op.cmd);
            }
        }

        op = op.next;
    }

    mManager.moveToState(mManager.mCurState, mTransition,
            mTransitionStyle, true);

    if (mAddToBackStack) {
        mManager.addBackStackState(this);
    }
}
```

这里说白了就是将一个个Op的类型拎出来在然后分发到FragmentManager里面去一一处理。FragmentManager中具体如何处理，就不表述了。

注意，在处理REPLACE的时候，在找到相同containerId的情况下：如果要某个需要被Replace的Fragment与当前的Fragment为同一个对象的时候，会将Op中的Fragment置空。之后所有的Fragment，不管是否与用来替代的Fragment是否为同一个对象都会从mAdd中被移除掉，同时加入到Op.removed列表中。最后将Op的Fragment调用Add显示出来。

下面划重点：

```java
case OP_REPLACE: {
    Fragment f = op.fragment;
    int containerId = f.mContainerId;
    if (mManager.mAdded != null) {
        for (int i = mManager.mAdded.size() - 1; i >= 0; i--) {
            Fragment old = mManager.mAdded.get(i);
            if (FragmentManagerImpl.DEBUG) {
                Log.v(TAG,
                        "OP_REPLACE: adding=" + f + " old=" + old);
            }
            if (old.mContainerId == containerId) {
                if (old == f) {
                    op.fragment = f = null;
                } else {
                    if (op.removed == null) {
                        op.removed = new ArrayList<Fragment>();
                    }
                    op.removed.add(old);
                    old.mNextAnim = op.exitAnim;
                    if (mAddToBackStack) {
                        old.mBackStackNesting += 1;
                        if (FragmentManagerImpl.DEBUG) {
                            Log.v(TAG, "Bump nesting of "
                                    + old + " to " + old.mBackStackNesting);
                        }
                    }
                    mManager.removeFragment(old, mTransition, mTransitionStyle);
                }
            }
        }
    }
    if (f != null) {
        f.mNextAnim = op.enterAnim;
        mManager.addFragment(f, false);
    }
}
```

以上就是REPLACE的逻辑。

注意，在`run()`的结尾处，调用了两段代码，如下：

```java
//BackStackState.java
mManager.moveToState(mManager.mCurState, mTransition,
        mTransitionStyle, true);

if (mAddToBackStack) {
    mManager.addBackStackState(this);
}
```

第一个调用会刷新Menu，第二个是会加入到BackStack中去，处理返回的时候能回到此状态。

## Fragment嵌套

在Android4.2(SDK17)中Android支持在Fragment里面嵌套Fragment。使用起来跟在Activity中使用Fragment类似，除了拿到的FragmentManager是Fragment中的`getChildFragmentManager()`之外无异。

来看看，其中最核心的一段代码：

```java
//Fragment.java
void instantiateChildFragmentManager() {
    mChildFragmentManager = new FragmentManagerImpl();
    mChildFragmentManager.attachController(mHost, new FragmentContainer() {
        @Override
        @Nullable
        public View onFindViewById(int id) {
            if (mView == null) {
                throw new IllegalStateException("Fragment does not have a view");
            }
            return mView.findViewById(id);
        }

        @Override
        public boolean onHasView() {
            return (mView != null);
        }
    }, this);
}
```

注意这里使用的`mHost`就是Activity里面的`HostCallbacks`了。当Fragment的周期有变化的时候，都会调用mChildFragmentManager做相应的分发。

## TODO
>- Fragment动画
- Activity交互:ActionBar、Menu、返回键
