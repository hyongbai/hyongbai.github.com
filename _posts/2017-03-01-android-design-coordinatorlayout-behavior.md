---
layout: post
title: "Design之CoordinatorLayout Behavior的前世今生"
category: all-about-tech
tags:
 - Design
 - Android
 - CoordinatorLayout
 - Behavior
date: 2017-03-01 01:30:00+00:00
---

## 简单介绍

Behavior是`CoordinatorLayout`里面的一个很重要的部件。使用它可以实现View之间的相互依赖，比如`SnackBar`弹出来的时候`FloatingActionButton`会自动被顶上去。还有就是可以实现类似`Lollipop`之后出现的`NestScrolling`。同时你也可以用它来监听/拦截`TouchEvent`以及`MeasureChild`而不用自定义一个View。是不是很方便。

但是，使用它的前提必须被CoordinatorLayout嵌套在外面。这句话似乎是废话，因为本身Behavior就是`CoordinatorLayout`内部类。

这里是Android官方关于Behavior的介绍：

>
interaction behavior plugin for child views of CoordinatorLayout.<br/>
A Behavior implements one or more interactions that a user can take on a child view. These interactions may include drags, swipes, flings, or any other gestures.

[官方API文档地址](https://developer.android.com/reference/android/support/design/widget/CoordinatorLayout.Behavior.html)


## Behavior实例化

### Progamatically

直接创建一个Behavior。拿到View的LayoutParams(CoordinatorLayout.LayoutParams)之后设定即可。比如:

```java
final CoordinatorLayout.Behavior behavior = new FloatingActionButton.Behavior();
final CoordinatorLayout.LayoutParams clp = (CoordinatorLayout.LayoutParams) view.getLayoutParams();
if (clp != null) clp.setBehavior(behavior);
```

### xml

如果有在xml文件中设置`layout_behavior`了的话，会在inflate的时候初始化LayoutParams中解析出对应的Behavior。相关代码如下。

如下是LayoutParams构造函数中的代码：

```java
LayoutParams(Context context, AttributeSet attrs) {
            super(context, attrs);
            ...
             mBehaviorResolved = a.hasValue(
                    R.styleable.CoordinatorLayout_Layout_layout_behavior);
            if (mBehaviorResolved) {
                mBehavior = parseBehavior(context, attrs, a.getString(
                        R.styleable.CoordinatorLayout_Layout_layout_behavior));
            }
            ...
}
```
基本上就是独处string。
下面是`parseBehavior`的部分：

```java
static Behavior parseBehavior(Context context, AttributeSet attrs, String name) {
    if (TextUtils.isEmpty(name)) {
        return null;
    }

    final String fullName;
    if (name.startsWith(".")) {
        // Relative to the app package. Prepend the app package name.
        fullName = context.getPackageName() + name;
    } else if (name.indexOf('.') >= 0) {
        // Fully qualified package name.
        fullName = name;
    } else {
        // Assume stock behavior in this package (if we have one)
        fullName = !TextUtils.isEmpty(WIDGET_PACKAGE_NAME)
                ? (WIDGET_PACKAGE_NAME + '.' + name)
                : name;
    }

    try {
        Map<String, Constructor<Behavior>> constructors = sConstructors.get();
        if (constructors == null) {
            constructors = new HashMap<>();
            sConstructors.set(constructors);
        }
        Constructor<Behavior> c = constructors.get(fullName);
        if (c == null) {
            final Class<Behavior> clazz = (Class<Behavior>) Class.forName(fullName, true,
                    context.getClassLoader());
            c = clazz.getConstructor(CONSTRUCTOR_PARAMS);
            c.setAccessible(true);
            constructors.put(fullName, c);
        }
        return c.newInstance(context, attrs);
    } catch (Exception e) {
        throw new RuntimeException("Could not inflate Behavior subclass " + fullName, e);
    }
}
```

代码挺多的，<del>其实很多都是废话</del>。核心部分是通过fullName创建对应的Class，然后通过构造函数`Behavior(Context context, AttributeSet attrs)`实例化一个behavior对象。注意，这里需要注意的是，如果你想自定义一个behavior，并且要在xml中指定它的话，请一定要实现`Behavior(Context context, AttributeSet attrs)`这个构造函数，否则将无法使用。

### Annotation

如果没有在xml指定behavior的话，CoordinatorLayout会在`getResolvedLayoutParams`的时候通过View对应Class的注解实例化一个默认的Behavior。实例化的部分如下：

```java
LayoutParams getResolvedLayoutParams(View child) {
    final LayoutParams result = (LayoutParams) child.getLayoutParams();
    if (!result.mBehaviorResolved) {
        Class<?> childClass = child.getClass();
        DefaultBehavior defaultBehavior = null;
        while (childClass != null &&
                (defaultBehavior = childClass.getAnnotation(DefaultBehavior.class)) == null) {
            childClass = childClass.getSuperclass();
        }
        if (defaultBehavior != null) {
            try {
                result.setBehavior(defaultBehavior.value().newInstance());
            } catch (Exception e) {
                Log.e(TAG, "Default behavior class " + defaultBehavior.value().getName() +
                        " could not be instantiated. Did you forget a default constructor?", e);
            }
        }
        result.mBehaviorResolved = true;
    }
    return result;
}
```
有很多View比如`FloatingActionButton`以及`AppBarLayout`都在class中添加了注解。如下：

```java
@CoordinatorLayout.DefaultBehavior(AppBarLayout.Behavior.class)
public class AppBarLayout extends LinearLayout {
```

```java
@CoordinatorLayout.DefaultBehavior(FloatingActionButton.Behavior.class)
public class FloatingActionButton extends VisibilityAwareImageButton {
```

这就是为什么你没在xml中指定behavior，但这些View的LayoutParams中仍然会有behavior的缘故。

## Behavior是怎么做到的：

### 1. View之间的相互依赖

#### 1.1 滤出依赖关系

CoordinatorLayout会在`onMeasure`的时候调用`prepareChildren()`

```java
private void prepareChildren() {
    mDependencySortedChildren.clear();
    mChildDag.clear();

    for (int i = 0, count = getChildCount(); i < count; i++) {
        final View view = getChildAt(i);

        final LayoutParams lp = getResolvedLayoutParams(view);
        lp.findAnchorView(this, view);

        mChildDag.addNode(view);

        // Now iterate again over the other children, adding any dependencies to the graph
        for (int j = 0; j < count; j++) {
            if (j == i) {
                continue;
            }
            final View other = getChildAt(j);
            final LayoutParams otherLp = getResolvedLayoutParams(other);
            if (otherLp.dependsOn(this, other, view)) {
                if (!mChildDag.contains(other)) {
                    // Make sure that the other node is added
                    mChildDag.addNode(other);
                }
                // Now add the dependency to the graph
                mChildDag.addEdge(view, other);
            }
        }
    }
    
    // Finally add the sorted graph list to our list
	mDependencySortedChildren.addAll(mChildDag.getSortedList());
	// We also need to reverse the result since we want the start of the list to contain
	// Views which have no dependencies, then dependent views after that
	Collections.reverse(mDependencySortedChildren);
}
```

这段代码的核心就是将所有的子view一一通过`otherLp.dependsOn(this, other, view)`检查两者之间是否存在依赖关系。如果有的话就会加入到mChildDag里面。

这里会列出有相互依赖关系的view。最后生成一个list。这个里面的排序可以看看`mChildDag.getSortedList()`里面的算法部分。根据其注释的话大意是实现了一个简单DirectedAcyclicGraph。核心代码是里面的`dfs`算法实现的，不做赘述。记住`mDependencySortedChildren`中的数据在(只在)这里填充的就行了。之后所有的实现都是在这个List上面操作的。

所以，如果你想依赖某个View的话只需要在Behavior的`layoutDependsOn`中加入你自己的判断即可。如果存在依赖关系的话，从属的View(也就是那个dependency)发生变化的时候，Behavior的`onDependentViewChanged`会被调用到。因此，只要在这里面加上自己想要实现的逻辑即可。那么接下来的问题就是`onDependentViewChanged`是如何被调用到的呢问？

#### 1.2 Dependency变化时通知对应的View

由上面我们可以知道当`Denpendency`有变化的时候`onDependentViewChanged`会被调用。通过查看`onDependentViewChanged`的调用路径可以发现:

![](/media/imgs/Behavior-onDependentViewChanged-invoked-by.jpg)

会有三个地方调用到此方法。即：

- `dispatchDependentViewsChanged(View)`
- `offsetChildToAnchor(View, int)`
- `onChildViewsChanged(int)`

#### 1.2.1 dispatchDependentViewsChanged
其中`dispatchDependentViewsChanged(View)`是public方法，因此是给外部使用的。比如`AppBarLayout`在被滑动的时候会调用此处。下面看下这个方法的具体实现：

```java
public void dispatchDependentViewsChanged(View view) {
    final List<View> dependents = mChildDag.getIncomingEdges(view);
    if (dependents != null && !dependents.isEmpty()) {
        for (int i = 0; i < dependents.size(); i++) {
            final View child = dependents.get(i);
            CoordinatorLayout.LayoutParams lp = (CoordinatorLayout.LayoutParams)
                    child.getLayoutParams();
            CoordinatorLayout.Behavior b = lp.getBehavior();
            if (b != null) {
                b.onDependentViewChanged(this, child, view);
            }
        }
    }
}
```
可以清楚的看到，这里会列出所以依赖AppBarLayout的View(即`mChildDag.getIncomingEdges(view)`)。然后逐一通知。

(注意，本文是基于Design包分析的，跟API24里面的实现会有不同。具体哪里不同不同在哪不属于本文范畴)


#### 1.2.2 onChildViewsChanged

跟上面只处理单个View的依赖所不同的是，这个函数主要的目的是处理所有的View的所有的依赖。

```java
final void onChildViewsChanged(@DispatchChangeEvent final int type) {
    final int layoutDirection = ViewCompat.getLayoutDirection(this);
    final int childCount = mDependencySortedChildren.size();
    ...
    for (int i = 0; i < childCount; i++) {
        final View child = mDependencySortedChildren.get(i);
        final LayoutParams lp = (LayoutParams) child.getLayoutParams();
        if (type == EVENT_PRE_DRAW && child.getVisibility() == View.GONE) {
            // Do not try to update GONE child views in pre draw updates.
            continue;
        }

        // Check child views before for anchor
        for (int j = 0; j < i; j++) {
            final View checkChild = mDependencySortedChildren.get(j);

            if (lp.mAnchorDirectChild == checkChild) {
                offsetChildToAnchor(child, layoutDirection);
            }
        }
        ...//省略部分代码
        // Update any behavior-dependent views for the change
        for (int j = i + 1; j < childCount; j++) {
            final View checkChild = mDependencySortedChildren.get(j);
            final LayoutParams checkLp = (LayoutParams) checkChild.getLayoutParams();
            final Behavior b = checkLp.getBehavior();

            if (b != null && b.layoutDependsOn(this, checkChild, child)) {
                if (type == EVENT_PRE_DRAW && checkLp.getChangedAfterNestedScroll()) {
                    // If this is from a pre-draw and we have already been changed
                    // from a nested scroll, skip the dispatch and reset the flag
                    checkLp.resetChangedAfterNestedScroll();
                    continue;
                }

                final boolean handled;
                switch (type) {
                    case EVENT_VIEW_REMOVED:
                        // EVENT_VIEW_REMOVED means that we need to dispatch
                        // onDependentViewRemoved() instead
                        b.onDependentViewRemoved(this, checkChild, child);
                        handled = true;
                        break;
                    default:
                        // Otherwise we dispatch onDependentViewChanged()
                        handled = b.onDependentViewChanged(this, checkChild, child);
                        break;
                }

                if (type == EVENT_NESTED_SCROLL) {
                    // If this is from a nested scroll, set the flag so that we may skip
                    // any resulting onPreDraw dispatch (if needed)
                    checkLp.setChangedAfterNestedScroll(handled);
                }
            }
        }
    }
    ...
}
```

可以看到当`EVENT_NESTED_SCROLL`的时候会调用`b.onDependentViewChanged`,当`EVENT_VIEW_REMOVED`的时候调用了`b.onDependentViewRemoved`,`EVENT_PRE_DRAW`并且`LayoutParams.getChangedAfterNestedScroll`的时候会调用`LayoutParams.resetChangedAfterNestedScroll`.

**EVENT_VIEW_REMOVED**

CoordinatorLayout在构造函数里面注册了一个`HierarchyChangeListener`。当View被删除的时候会被回调`onChildViewRemoved`中调用`onChildViewsChanged(EVENT_VIEW_REMOVED)`进而回调到Behavior中去。

**EVENT_PRE_DRAW**

在onMeasure的时候调用`ensurePreDrawListener`，这里面会根据是否有View存在有以来关系，如果有的话就是注册一个`OnPreDrawListener`，源码如下:

```java
void ensurePreDrawListener() {
    boolean hasDependencies = false;
    final int childCount = getChildCount();
    for (int i = 0; i < childCount; i++) {
        final View child = getChildAt(i);
        if (hasDependencies(child)) {
            hasDependencies = true;
            break;
        }
    }

    if (hasDependencies != mNeedsPreDrawListener) {
        if (hasDependencies) {
            addPreDrawListener();
        } else {
            removePreDrawListener();
        }
    }
}
```

可以看到，如果没有以来关系的话，那么就把这个`OnPreDrawListener`给移除掉。在PreDraw的时候会调用`onChildViewsChanged(EVENT_PRE_DRAW)`。

**EVENT_NESTED_SCROLL**

在`onNestedScroll(View, int, int, int, int)`/`onNestedPreScroll(View, int, int, int[])`/`onNestedFling(View, float, float, boolean)`这三个函数中只要有Behavior有截获的话都会调用`EVENT_NESTED_SCROLL`。关于NestScrolling会写一个文章详解其工作原理。


#### 1.2.3 offsetChildToAnchor

这里要说到一个属性就是Anchor。当你为View设定一个Anchor之后。View会按照AnchorGravity对齐。可以简单地理解RelativeLayout。其实具体的实现就是根据Anchor的位置以及相对位置计算出自身的边距。具体代码可以参看`getDesiredAnchoredChildRectWithoutConstraints`


### 2. 拦截/处理滑动事件(TouchEvent)
```java
private boolean performIntercept(MotionEvent ev, final int type) {
    boolean intercepted = false;
    boolean newBlock = false;

    MotionEvent cancelEvent = null;

    final int action = MotionEventCompat.getActionMasked(ev);

    final List<View> topmostChildList = mTempList1;
    getTopSortedChildren(topmostChildList);

    // Let topmost child views inspect first
    final int childCount = topmostChildList.size();
    for (int i = 0; i < childCount; i++) {
        final View child = topmostChildList.get(i);
        final LayoutParams lp = (LayoutParams) child.getLayoutParams();
        final Behavior b = lp.getBehavior();

        if ((intercepted || newBlock) && action != MotionEvent.ACTION_DOWN) {
            // Cancel all behaviors beneath the one that intercepted.
            // If the event is "down" then we don't have anything to cancel yet.
            if (b != null) {
                if (cancelEvent == null) {
                    final long now = SystemClock.uptimeMillis();
                    cancelEvent = MotionEvent.obtain(now, now,
                            MotionEvent.ACTION_CANCEL, 0.0f, 0.0f, 0);
                }
                switch (type) {
                    case TYPE_ON_INTERCEPT:
                        b.onInterceptTouchEvent(this, child, cancelEvent);
                        break;
                    case TYPE_ON_TOUCH:
                        b.onTouchEvent(this, child, cancelEvent);
                        break;
                }
            }
            continue;
        }

        if (!intercepted && b != null) {
            switch (type) {
                case TYPE_ON_INTERCEPT:
                    intercepted = b.onInterceptTouchEvent(this, child, ev);
                    break;
                case TYPE_ON_TOUCH:
                    intercepted = b.onTouchEvent(this, child, ev);
                    break;
            }
            if (intercepted) {
                mBehaviorTouchView = child;
            }
        }

        // Don't keep going if we're not allowing interaction below this.
        // Setting newBlock will make sure we cancel the rest of the behaviors.
        final boolean wasBlocking = lp.didBlockInteraction();
        final boolean isBlocking = lp.isBlockingInteractionBelow(this, child);
        newBlock = isBlocking && !wasBlocking;
        if (isBlocking && !newBlock) {
            // Stop here since we don't have anything more to cancel - we already did
            // when the behavior first started blocking things below this point.
            break;
        }
    }

    topmostChildList.clear();

    return intercepted;
}
```
这段代码其实很好理解，其中的`type`表示TouchEvent的类型。即为了区分到底是IntercepTouchEvent还是TouchEvent。
可以看到它首先获得了当前View的所以的Children.这个Children列表是按照`TOP_SORTED_CHILDREN_COMPARATOR`排序的。但，这个COMPARATOR仅仅在`Lollipop`后不为空。其实它主要是的作用是在L之后View多了一个Z的属性。Z越大View越在上面。比如A的z为1，而B为0.理论上来说B是在A后面的话，是可以盖住A的。实际情况是A会盖住B。

接着看代码，如果遇到有Behavior拦截了TouchEvent后，后面的View都会受到Cancel事件。(问题来了：为什么前面的View不会收到Cancel事件呢？)。然后TouchEvent就不会再CoordinatorLayout中往下传递了。

如果你想在子View中拦截TouchEvent的话，那么就可以实现这两个方法。有没有很方便呢？不同的地方在于，这里相当于在CoordinatorLayout中拦截TouchEvent。而不是在CoordinatorLayout的子View中。

### 3. 控制控件尺寸的测算(MeasureChild)

这个其实最好理解了。下面贴上`onMeasure`中的核心代码：

```java
final Behavior b = lp.getBehavior();
if (b == null || !b.onMeasureChild(this, child, childWidthMeasureSpec, keylineWidthUsed,
        childHeightMeasureSpec, 0)) {
    onMeasureChild(child, childWidthMeasureSpec, keylineWidthUsed,
            childHeightMeasureSpec, 0);
}
```

可以在onMeasureChild测算完之后返回true，那么CoordinatorLayout中便不再会去测算。完全不用重新view。很方便吧。

### 4. NestScrolling

知道Behavior可以这么做即可。会专门讲讲NestScrolling。