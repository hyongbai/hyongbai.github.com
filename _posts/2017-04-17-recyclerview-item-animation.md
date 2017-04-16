---
layout: post
title: "RecyclerView动画内部实现机制"
category: all-about-tech
tags: -[Android] -[Support] -[RecyclerView] -[View] -[Animator]
date: 2017-04-17 14:23:00+00:00
---

> 注: 本文基于25.2.0

在【[RecyclerView绘制流程详解]({% post_url 2017-04-17-recyclerview-rendering %})】提到了RecyclerView的基本绘制流程。但也留了坑，其中很重要的逻辑就是ItemAnimator的部分了。

所以打算来讲讲ItemAnimator。

## 准备工作

我们知道在`dispatchLayoutStep1`如果需要进行的动画也是有条件的。那么`mState.mRunSimpleAnimations`和`mState.mRunPredictiveAnimations`这两个标记是哪里产生的呢？逻辑是什么呢？

在`dispatchLayoutStep1`一开始的时候调用了`processAdapterUpdatesAndSetAnimationFlags`方法。而这里恰恰就有上面两个标识的写入动作。

```java
//RecyclerView.java
/**
 * Consumes adapter updates and calculates which type of animations we want to run.
 * Called in onMeasure and dispatchLayout.
 * <p>
 * This method may process only the pre-layout state of updates or all of them.
 */
private void processAdapterUpdatesAndSetAnimationFlags() {
    if (mDataSetHasChangedAfterLayout) {
        // Processing these items have no value since data set changed unexpectedly.
        // Instead, we just reset it.
        mAdapterHelper.reset();
        mLayout.onItemsChanged(this);
    }
    // simple animations are a subset of advanced animations (which will cause a
    // pre-layout step)
    // If layout supports predictive animations, pre-process to decide if we want to run them
    if (predictiveItemAnimationsEnabled()) {
        mAdapterHelper.preProcess();
    } else {
        mAdapterHelper.consumeUpdatesInOnePass();
    }
    boolean animationTypeSupported = mItemsAddedOrRemoved || mItemsChanged;
    mState.mRunSimpleAnimations = mFirstLayoutComplete
            && mItemAnimator != null
            && (mDataSetHasChangedAfterLayout
                    || animationTypeSupported
                    || mLayout.mRequestedSimpleAnimations)
            && (!mDataSetHasChangedAfterLayout
                    || mAdapter.hasStableIds());
    mState.mRunPredictiveAnimations = mState.mRunSimpleAnimations
            && animationTypeSupported
            && !mDataSetHasChangedAfterLayout
            && predictiveItemAnimationsEnabled();
}
```

可以看到mRunSimpleAnimations和mRunPredictiveAnimations的前提条件是出现Item增删或者变化。并且mItemAnimator的值不为空。也就是说如果没有设定mItemAnimator的话，preLayout的逻辑是不会发生的。这里需要提一嘴的是：mRunPredictiveAnimations的必要条件是在LayoutManager中将`supportsPredictiveItemAnimations`给打开，否则不会执行。

## 预处理

知道了前提条件，那么下面我们来正经看看dispatchLayoutStep1的逻辑吧。

```java
//RecyclerView.java
/**
 * The first step of a layout where we;
 * - process adapter updates
 * - decide which animation should run
 * - save information about current views
 * - If necessary, run predictive layout and save its information
 */
private void dispatchLayoutStep1() {
    // ...
    mViewInfoStore.clear();
    // ...
    processAdapterUpdatesAndSetAnimationFlags();
    // ...
    findMinMaxChildLayoutPositions(mMinMaxLayoutPositions);
    // ...
    if (mState.mRunSimpleAnimations) {
        // Step 0: Find out where all non-removed items are, pre-layout
        int count = mChildHelper.getChildCount();
        for (int i = 0; i < count; ++i) {
            final ViewHolder holder = getChildViewHolderInt(mChildHelper.getChildAt(i));
            if (holder.shouldIgnore() || (holder.isInvalid() && !mAdapter.hasStableIds())) {
                continue;
            }
            final ItemHolderInfo animationInfo = mItemAnimator
                    .recordPreLayoutInformation(mState, holder,
                            ItemAnimator.buildAdapterChangeFlagsForAnimations(holder),
                            holder.getUnmodifiedPayloads());
            mViewInfoStore.addToPreLayout(holder, animationInfo);
            if (mState.mTrackOldChangeHolders && holder.isUpdated() && !holder.isRemoved()
                    && !holder.shouldIgnore() && !holder.isInvalid()) {
                long key = getChangedHolderKey(holder);
                // This is NOT the only place where a ViewHolder is added to old change holders
                // list. There is another case where:
                //    * A VH is currently hidden but not deleted
                //    * The hidden item is changed in the adapter
                //    * Layout manager decides to layout the item in the pre-Layout pass (step1)
                // When this case is detected, RV will un-hide that view and add to the old
                // change holders list.
                mViewInfoStore.addToOldChangeHolders(key, holder);
            }
        }
    }
    if (mState.mRunPredictiveAnimations) {
        // Step 1: run prelayout: This will use the old positions of items. The layout manager
        // is expected to layout everything, even removed items (though not to add removed
        // items back to the container). This gives the pre-layout position of APPEARING views
        // which come into existence as part of the real layout.

        // Save old positions so that LayoutManager can run its mapping logic.
        saveOldPositions();
        final boolean didStructureChange = mState.mStructureChanged;
        mState.mStructureChanged = false;
        // temporarily disable flag because we are asking for previous layout
        mLayout.onLayoutChildren(mRecycler, mState);
        mState.mStructureChanged = didStructureChange;

        for (int i = 0; i < mChildHelper.getChildCount(); ++i) {
            final View child = mChildHelper.getChildAt(i);
            final ViewHolder viewHolder = getChildViewHolderInt(child);
            if (viewHolder.shouldIgnore()) {
                continue;
            }
            if (!mViewInfoStore.isInPreLayout(viewHolder)) {
                int flags = ItemAnimator.buildAdapterChangeFlagsForAnimations(viewHolder);
                boolean wasHidden = viewHolder
                        .hasAnyOfTheFlags(ViewHolder.FLAG_BOUNCED_FROM_HIDDEN_LIST);
                if (!wasHidden) {
                    flags |= ItemAnimator.FLAG_APPEARED_IN_PRE_LAYOUT;
                }
                final ItemHolderInfo animationInfo = mItemAnimator.recordPreLayoutInformation(
                        mState, viewHolder, flags, viewHolder.getUnmodifiedPayloads());
                if (wasHidden) {
                    recordAnimationInfoIfBouncedHiddenView(viewHolder, animationInfo);
                } else {
                    mViewInfoStore.addToAppearedInPreLayoutHolders(viewHolder, animationInfo);
                }
            }
        }
        // we don't process disappearing list because they may re-appear in post layout pass.
        clearOldPositions();
    } else {
        clearOldPositions();
    }
    onExitLayoutOrScroll();
    resumeRequestLayout(false);
    mState.mLayoutStep = State.STEP_LAYOUT;
}
```

其实具体的这段逻辑倒是没有什么多大难点了。

注意，一开始mViewInfoStore中所有的信息都会调用`mViewInfoStore.clear()`方法被清除掉了。在这里重新开始。

首先通过ItemAnimator生成了一个ItemHolderInfo，这个东西主要责任就是记录当前View的layout信息(即:left/top/right/bottom)。这样我们就可以只知道Item在变化之前的位置了，以便后面做动画。具体缓存方法为：`mViewInfoStore.addToPreLayout(holder, animationInfo)`。此时会标记为`FLAG_PRE`。

其次，如果一个Holder被标记为Updated并且有效地话，那么会将其缓存到`OldChangedHolder`中去，即:`mViewInfoStore.addToOldChangeHolders(key, holder)`

## 后处理

```java
//RecyclerView.java
private void dispatchLayoutStep3() {
    mState.assertLayoutStep(State.STEP_ANIMATIONS);
    eatRequestLayout();
    onEnterLayoutOrScroll();
    mState.mLayoutStep = State.STEP_START;
    if (mState.mRunSimpleAnimations) {
        // Step 3: Find out where things are now, and process change animations.
        // traverse list in reverse because we may call animateChange in the loop which may
        // remove the target view holder.
        for (int i = mChildHelper.getChildCount() - 1; i >= 0; i--) {
            ViewHolder holder = getChildViewHolderInt(mChildHelper.getChildAt(i));
            if (holder.shouldIgnore()) {
                continue;
            }
            long key = getChangedHolderKey(holder);
            final ItemHolderInfo animationInfo = mItemAnimator
                    .recordPostLayoutInformation(mState, holder);
            ViewHolder oldChangeViewHolder = mViewInfoStore.getFromOldChangeHolders(key);
            if (oldChangeViewHolder != null && !oldChangeViewHolder.shouldIgnore()) {
                // run a change animation

                // If an Item is CHANGED but the updated version is disappearing, it creates
                // a conflicting case.
                // Since a view that is marked as disappearing is likely to be going out of
                // bounds, we run a change animation. Both views will be cleaned automatically
                // once their animations finish.
                // On the other hand, if it is the same view holder instance, we run a
                // disappearing animation instead because we are not going to rebind the updated
                // VH unless it is enforced by the layout manager.
                final boolean oldDisappearing = mViewInfoStore.isDisappearing(
                        oldChangeViewHolder);
                final boolean newDisappearing = mViewInfoStore.isDisappearing(holder);
                if (oldDisappearing && oldChangeViewHolder == holder) {
                    // run disappear animation instead of change
                    mViewInfoStore.addToPostLayout(holder, animationInfo);
                } else {
                    final ItemHolderInfo preInfo = mViewInfoStore.popFromPreLayout(
                            oldChangeViewHolder);
                    // we add and remove so that any post info is merged.
                    mViewInfoStore.addToPostLayout(holder, animationInfo);
                    ItemHolderInfo postInfo = mViewInfoStore.popFromPostLayout(holder);
                    if (preInfo == null) {
                        handleMissingPreInfoForChangeError(key, holder, oldChangeViewHolder);
                    } else {
                        animateChange(oldChangeViewHolder, holder, preInfo, postInfo,
                                oldDisappearing, newDisappearing);
                    }
                }
            } else {
                mViewInfoStore.addToPostLayout(holder, animationInfo);
            }
        }

        // Step 4: Process view info lists and trigger animations
        mViewInfoStore.process(mViewInfoProcessCallback);
    }
    // ...
}
```

这里会有个逻辑判断，即oldChangeViewHolder是否存在且有效。如果有效地话，表示在预处理的时候这个位置的Holder被标记为updated了。

如果旧的holder跟新的holder为同一个并且oldDisappearing的话，则执行Disappearing。

否则直接调用animateChange往ItemAnimator中添加ChangeInfo，此时也会触发动画。

其他情况则直接标记为`FLAG_POST`(mViewInfoStore.addToPostLayout(holder, animationInfo))。

当所有的Holder被处理完之后调用`mViewInfoStore.process(mViewInfoProcessCallback)`。用来处理所有被加入进去的HOLDER们，也包括前面FLAG_PRE的部分。此时也会触发动画。

### Process

好吧，那我们来看看process是如何跟ItemAnimator联系起来的。这里的ProcessCallBack是RecyclerView里面的

```java
//ViewInfoStore.java
void process(ProcessCallback callback) {
    for (int index = mLayoutHolderMap.size() - 1; index >= 0; index --) {
        final ViewHolder viewHolder = mLayoutHolderMap.keyAt(index);
        final InfoRecord record = mLayoutHolderMap.removeAt(index);
        if ((record.flags & FLAG_APPEAR_AND_DISAPPEAR) == FLAG_APPEAR_AND_DISAPPEAR) {
            // Appeared then disappeared. Not useful for animations.
            callback.unused(viewHolder);
        } else if ((record.flags & FLAG_DISAPPEARED) != 0) {
            // Set as "disappeared" by the LayoutManager (addDisappearingView)
            if (record.preInfo == null) {
                // similar to appear disappear but happened between different layout passes.
                // this can happen when the layout manager is using auto-measure
                callback.unused(viewHolder);
            } else {
                callback.processDisappeared(viewHolder, record.preInfo, record.postInfo);
            }
        } else if ((record.flags & FLAG_APPEAR_PRE_AND_POST) == FLAG_APPEAR_PRE_AND_POST) {
            // Appeared in the layout but not in the adapter (e.g. entered the viewport)
            callback.processAppeared(viewHolder, record.preInfo, record.postInfo);
        } else if ((record.flags & FLAG_PRE_AND_POST) == FLAG_PRE_AND_POST) {
            // Persistent in both passes. Animate persistence
            callback.processPersistent(viewHolder, record.preInfo, record.postInfo);
        } else if ((record.flags & FLAG_PRE) != 0) {
            // Was in pre-layout, never been added to post layout
            callback.processDisappeared(viewHolder, record.preInfo, null);
        } else if ((record.flags & FLAG_POST) != 0) {
            // Was not in pre-layout, been added to post layout
            callback.processAppeared(viewHolder, record.preInfo, record.postInfo);
        } else if ((record.flags & FLAG_APPEAR) != 0) {
            // Scrap view. RecyclerView will handle removing/recycling this.
        } else if (DEBUG) {
            throw new IllegalStateException("record without any reasonable flag combination:/");
        }
        InfoRecord.recycle(record);
    }
}
```

其实它会将mLayoutHolderMap中所有的InfoRecord给遍历出来，而其中所有的逻辑都是在ProcessCallBack中实现的，这里只是扮演一个分发的角色。

下面是ProcessCallback的具体实现：

```java
//RecyclerView.java
/**
 * The callback to convert view info diffs into animations.
 */
private final ViewInfoStore.ProcessCallback mViewInfoProcessCallback =
        new ViewInfoStore.ProcessCallback() {
    @Override
    public void processDisappeared(ViewHolder viewHolder, @NonNull ItemHolderInfo info,
            @Nullable ItemHolderInfo postInfo) {
        mRecycler.unscrapView(viewHolder);
        animateDisappearance(viewHolder, info, postInfo);
    }
    @Override
    public void processAppeared(ViewHolder viewHolder,
            ItemHolderInfo preInfo, ItemHolderInfo info) {
        animateAppearance(viewHolder, preInfo, info);
    }

    @Override
    public void processPersistent(ViewHolder viewHolder,
            @NonNull ItemHolderInfo preInfo, @NonNull ItemHolderInfo postInfo) {
        viewHolder.setIsRecyclable(false);
        if (mDataSetHasChangedAfterLayout) {
            // since it was rebound, use change instead as we'll be mapping them from
            // stable ids. If stable ids were false, we would not be running any
            // animations
            if (mItemAnimator.animateChange(viewHolder, viewHolder, preInfo, postInfo)) {
                postAnimationRunner();
            }
        } else if (mItemAnimator.animatePersistence(viewHolder, preInfo, postInfo)) {
            postAnimationRunner();
        }
    }
    @Override
    public void unused(ViewHolder viewHolder) {
        mLayout.removeAndRecycleView(viewHolder.itemView, mRecycler);
    }
};
```

我们主要看看其中的processDisappear的实现逻辑。

```java
// RecyclerView.java
void animateDisappearance(@NonNull ViewHolder holder,
        @NonNull ItemHolderInfo preLayoutInfo, @Nullable ItemHolderInfo postLayoutInfo) {
    addAnimatingView(holder);
    holder.setIsRecyclable(false);
    if (mItemAnimator.animateDisappearance(holder, preLayoutInfo, postLayoutInfo)) {
        postAnimationRunner();
    }
}
```

这里关键的是两处逻辑：一个是`addAnimatingView(holder)`,一处是`mItemAnimator.animateDisappearance(holder, preLayoutInfo, postLayoutInfo)`。

前者不同的地方在于，如果一个Holder里面的itemView已经被Remove掉或者detach掉的话会被重新添加到RecyclerView中去。

```java
//RecyclerView.java
/**
 * Adds a view to the animatingViews list.
 * mAnimatingViews holds the child views that are currently being kept around
 * purely for the purpose of being animated out of view. They are drawn as a regular
 * part of the child list of the RecyclerView, but they are invisible to the LayoutManager
 * as they are managed separately from the regular child views.
 * @param viewHolder The ViewHolder to be removed
 */
private void addAnimatingView(ViewHolder viewHolder) {
    final View view = viewHolder.itemView;
    final boolean alreadyParented = view.getParent() == this;
    mRecycler.unscrapView(getChildViewHolder(view));
    if (viewHolder.isTmpDetached()) {
        // re-attach
        mChildHelper.attachViewToParent(view, -1, view.getLayoutParams(), true);
    } else if(!alreadyParented) {
        mChildHelper.addView(view, true);
    } else {
        mChildHelper.hide(view);
    }
}
```

这里主要的作用就是将被删除的View重新添加到RecyclerView中去。这样被删除掉的view就能够显示出来了。那么问题来了？什么时候重新加回来呢？

别急，其实在ItemAnimator中会有一个`dispatchRemoveFinished`方法，当ViewHolder执行完Remove动画之后会回调之。当我们设定自定义的ItemAnimator也好，或者使用RecyclerView自己设定的ItemAnimator也好。都会在这个ItemAnimator中注册一个继承自`ItemAnimatorListener`接口的内部类ItemAnimatorRestoreListener的实例化对象。

实现如下：

```java
//RecyclerView.java
    private class ItemAnimatorRestoreListener implements ItemAnimator.ItemAnimatorListener {

        ItemAnimatorRestoreListener() {
        }

        @Override
        public void onAnimationFinished(ViewHolder item) {
            item.setIsRecyclable(true);
            if (item.mShadowedHolder != null && item.mShadowingHolder == null) { // old vh
                item.mShadowedHolder = null;
            }
            // always null this because an OldViewHolder can never become NewViewHolder w/o being
            // recycled.
            item.mShadowingHolder = null;
            if (!item.shouldBeKeptAsChild()) {
                if (!removeAnimatingView(item.itemView) && item.isTmpDetached()) {
                    removeDetachedView(item.itemView, false);
                }
            }
        }
    }
```

当某个ViewHolder的动画执行结束之后会被回调过来，发现这个ViewHolder不存在的时候会调用`removeDetachedView`将其从RecyclerView中移除。这就是RecyclerView实现一个删除了的View的动画逻辑。

### animateChange

```java
// RecyclerView.java
private void animateChange(@NonNull ViewHolder oldHolder, @NonNull ViewHolder newHolder,
        @NonNull ItemHolderInfo preInfo, @NonNull ItemHolderInfo postInfo,
        boolean oldHolderDisappearing, boolean newHolderDisappearing) {
    oldHolder.setIsRecyclable(false);
    if (oldHolderDisappearing) {
        addAnimatingView(oldHolder);
    }
    if (oldHolder != newHolder) {
        if (newHolderDisappearing) {
            addAnimatingView(newHolder);
        }
        oldHolder.mShadowedHolder = newHolder;
        // old holder should disappear after animation ends
        addAnimatingView(oldHolder);
        mRecycler.unscrapView(oldHolder);
        newHolder.setIsRecyclable(false);
        newHolder.mShadowingHolder = oldHolder;
    }
    if (mItemAnimator.animateChange(oldHolder, newHolder, preInfo, postInfo)) {
        postAnimationRunner();
    }
}
```

这里面其实与上面的`animateDisappearance`类似，会调用一系列的`addAnimatingView`来确保需要做动画的View能够显示在RecyclerView中。之后交给`mItemAnimator`处理具体的动画。

## 执行动画

上面说的触发动画其实全部都是执行`postAnimationRunner`，post一个mItemAnimatorRunner来执行`mItemAnimator.runPendingAnimations`。注意这里是一个post任务，并且只会执行一次，所以在step3中及时调用多次也只会触发一次，而已。

```java
//RecyclerView.java
private Runnable mItemAnimatorRunner = new Runnable() {
    @Override
    public void run() {
        if (mItemAnimator != null) {
            mItemAnimator.runPendingAnimations();
        }
        mPostedAnimatorRunner = false;
    }
};

/**
 * Post a runnable to the next frame to run pending item animations. Only the first such
 * request will be posted, governed by the mPostedAnimatorRunner flag.
 */
void postAnimationRunner() {
    if (!mPostedAnimatorRunner && mIsAttached) {
        ViewCompat.postOnAnimation(this, mItemAnimatorRunner);
        mPostedAnimatorRunner = true;
    }
}
```

所以ItemAnimator最终执行动画的地方在于`runPendingAnimations`。在之前所有对动画操作的时候都会被放入删除/添加/移动/变化的列表中去，然后在这个方法里面执行对应的操作动画。

我们以RecyclerView自带的DefaultItemAnimator为例。

```java
//DefaultItemAnimator.java
@Override
public void runPendingAnimations() {
    boolean removalsPending = !mPendingRemovals.isEmpty();
    boolean movesPending = !mPendingMoves.isEmpty();
    boolean changesPending = !mPendingChanges.isEmpty();
    boolean additionsPending = !mPendingAdditions.isEmpty();
    if (!removalsPending && !movesPending && !additionsPending && !changesPending) {
        // nothing to animate
        return;
    }
    // First, remove stuff
    for (ViewHolder holder : mPendingRemovals) {
        animateRemoveImpl(holder);
    }
    mPendingRemovals.clear();
    // Next, move stuff
    if (movesPending) {
        final ArrayList<MoveInfo> moves = new ArrayList<>();
        moves.addAll(mPendingMoves);
        mMovesList.add(moves);
        mPendingMoves.clear();
        Runnable mover = new Runnable() {
            @Override
            public void run() {
                for (MoveInfo moveInfo : moves) {
                    animateMoveImpl(moveInfo.holder, moveInfo.fromX, moveInfo.fromY,
                            moveInfo.toX, moveInfo.toY);
                }
                moves.clear();
                mMovesList.remove(moves);
            }
        };
        if (removalsPending) {
            View view = moves.get(0).holder.itemView;
            ViewCompat.postOnAnimationDelayed(view, mover, getRemoveDuration());
        } else {
            mover.run();
        }
    }
    // Next, change stuff, to run in parallel with move animations
    if (changesPending) {
        final ArrayList<ChangeInfo> changes = new ArrayList<>();
        changes.addAll(mPendingChanges);
        mChangesList.add(changes);
        mPendingChanges.clear();
        Runnable changer = new Runnable() {
            @Override
            public void run() {
                for (ChangeInfo change : changes) {
                    animateChangeImpl(change);
                }
                changes.clear();
                mChangesList.remove(changes);
            }
        };
        if (removalsPending) {
            ViewHolder holder = changes.get(0).oldHolder;
            ViewCompat.postOnAnimationDelayed(holder.itemView, changer, getRemoveDuration());
        } else {
            changer.run();
        }
    }
    // Next, add stuff
    if (additionsPending) {
        final ArrayList<ViewHolder> additions = new ArrayList<>();
        additions.addAll(mPendingAdditions);
        mAdditionsList.add(additions);
        mPendingAdditions.clear();
        Runnable adder = new Runnable() {
            @Override
            public void run() {
                for (ViewHolder holder : additions) {
                    animateAddImpl(holder);
                }
                additions.clear();
                mAdditionsList.remove(additions);
            }
        };
        if (removalsPending || movesPending || changesPending) {
            long removeDuration = removalsPending ? getRemoveDuration() : 0;
            long moveDuration = movesPending ? getMoveDuration() : 0;
            long changeDuration = changesPending ? getChangeDuration() : 0;
            long totalDelay = removeDuration + Math.max(moveDuration, changeDuration);
            View view = additions.get(0).itemView;
            ViewCompat.postOnAnimationDelayed(view, adder, totalDelay);
        } else {
            adder.run();
        }
    }
}
```

可以看到它其实是按照删除/移动/变化/添加的次序依次来做动画的。动画的具体实现见`animateRemoveImpl`/`animateMoveImpl`/`animateChangeImpl`/`animateAddImpl`即可。逻辑比较直接，不做介绍了。需要注意的是不论何种类型的动画，结束后都会调用`dispatchAnimationFinished(ViewHolder viewHolder)`回调到RecyclerView的ItemAnimatorRestoreListener中。


## 最后

这里只是粗略的讲述了一下RecyclerView关于动画的内部实现。如果你仅仅想修改动画本身的话，对照着DefaultItemAnimator的四种动画样式做修改即可。