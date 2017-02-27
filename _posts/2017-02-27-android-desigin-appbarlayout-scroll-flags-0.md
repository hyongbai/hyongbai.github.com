---
layout: post
title: "Design之AppBarLayout的滚动样式"
category: all-about-tech
tags:
 - Design
 - Android
date: 2017-02-27 04:11:00+00:00
---

## 前言

为啥会写这么基础的东西呢？因为之前自己写的APP还有公司的APP，为了不影响包体积等。都会自己造轮子，没有系统使用过Android Design包。因此决定自己花点时间把整个Design包全部过一下。

把自己的学习过程记录下来而已。总结出真知。

balabalba不说了。

## 样式分类

AppBarLayout的滚动样式分为5种。

- `SCROLL_FLAG_ENTER_ALWAYS`:手指往上滚动时(即Scroll Down时)，View会消失。反之，View会跟随手指滑动慢慢出现。
- `SCROLL_FLAG_ENTER_ALWAYS_COLLAPSED`:此标志位依赖`SCROLL_FLAG_ENTER_ALWAYS`并且View需要设定
`minHeight`才会生效。比如将`minHeight`设定为`14dp`。手指往上滚动时View仍然会消失。反过来，跟上面不一样的是，View在NestScrolling没有滑动到顶部的时候，View最多只会更随出现`14dp`也就是`minHeight`的高度。当到顶部的时候，方才会慢慢显示剩下的部分。
- `SCROLL_FLAG_EXIT_UNTIL_COLLAPSED`:此标志位需要依赖View设定`minHeight`才会生效。手指往上滚动时，也就是View的Exit状态，View会留下`minHeight`的一段高度露出来，而不会向前面一样完全消失。手指往下滚动时，此标志类似于`SCROLL_FLAG_ENTER_ALWAYS_COLLAPSED`的状态。
- `SCROLL_FLAG_SNAP`:手指停下来的时候，View会根据自身露出来的高度，自动折叠或者伸张。
- `SCROLL_FLAG_SCROLL`:以上所有的标志为都依赖于此标志方能工作。

注意：这5中标志是可以相互组合的哈。其他情况就不展开了。


## Code

下面是我做实验时写的小DEMO中的部分代码:

~~~Java
public class AppLayoutFragment extends BNFragment {
    @BindView(R.id.toolbar)
    Toolbar toolbar;
    @BindView(R.id.title)
    TextView title;

    public AppLayoutFragment() {
        setLayoutId(R.layout.frag_design_applayout);
    }

    @OnClick(R.id.SCROLL_FLAG_ENTER_ALWAYS)
    void onClick0(View v) {
        setScrollFlag(SCROLL_FLAG_ENTER_ALWAYS, v);
    }

    @OnClick(R.id.SCROLL_FLAG_ENTER_ALWAYS_COLLAPSED)
    void onClick1(View v) {
        setScrollFlag(SCROLL_FLAG_ENTER_ALWAYS_COLLAPSED | SCROLL_FLAG_ENTER_ALWAYS, v);
    }

    @OnClick(R.id.SCROLL_FLAG_EXIT_UNTIL_COLLAPSED)
    void onClick2(View v) {
        setScrollFlag(AppBarLayout.LayoutParams.SCROLL_FLAG_EXIT_UNTIL_COLLAPSED, v);
    }

    @OnClick(R.id.SCROLL_FLAG_SNAP)
    void onClick3(View v) {
        setScrollFlag(AppBarLayout.LayoutParams.SCROLL_FLAG_SNAP, v);
    }

    private void setScrollFlag(int flag, View v) {
        if (v instanceof TextView) title.setText(((TextView) v).getText());
        final AppBarLayout.LayoutParams alp = (AppBarLayout.LayoutParams) toolbar.getLayoutParams();
        alp.setScrollFlags(flag | AppBarLayout.LayoutParams.SCROLL_FLAG_SCROLL);
        toolbar.setLayoutParams(alp);
    }
}
~~~

~~~XML
<?xml version="1.0" encoding="utf-8"?>
<android.support.design.widget.CoordinatorLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">

    <android.support.design.widget.AppBarLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content">

        <android.support.v7.widget.Toolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="?android:actionBarSize"
            android:background="@android:color/darker_gray"
            android:minHeight="14dp"
            android:title="IM TITLE"
            app:layout_scrollFlags="scroll|enterAlways"
            />

        <TextView
            android:id="@+id/title"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="@android:color/holo_red_dark"
            android:padding="@dimen/activity_horizontal_margin"
            />
    </android.support.design.widget.AppBarLayout>

    <android.support.v4.widget.NestedScrollView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        app:layout_behavior="@string/appbar_scrolling_view_behavior">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical">

            <Button
                android:id="@+id/SCROLL_FLAG_ENTER_ALWAYS"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="SCROLL_FLAG_ENTER_ALWAYS"
                />

            <Button
                android:id="@+id/SCROLL_FLAG_ENTER_ALWAYS_COLLAPSED"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="SCROLL_FLAG_ENTER_ALWAYS_COLLAPSED"
                />

            <Button
                android:id="@+id/SCROLL_FLAG_EXIT_UNTIL_COLLAPSED"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="SCROLL_FLAG_EXIT_UNTIL_COLLAPSED"
                />

            <Button
                android:id="@+id/SCROLL_FLAG_SNAP"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="SCROLL_FLAG_SNAP"
                />

            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/longText"
                />
        </LinearLayout>
    </android.support.v4.widget.NestedScrollView>
</android.support.design.widget.CoordinatorLayout>
~~~


