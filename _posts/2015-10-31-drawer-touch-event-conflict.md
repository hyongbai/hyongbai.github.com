---
layout: post
title: "DrawerLayout粗鲁的霸占水平方向的Touch事件"
description: "第一篇博客"
category: 日志
tags: [GitHub]
date: 2015-10-31 02:05:09+00:00
---

#### 实际需求

遇到的需求是这样: 在 `DrawerLayout` 侧滑里面实现 `ListView` 的拖动排序.

#### 遇到问题

但是在实现的过程中发现, 本来上下拖动是正常的, 但是只要一不小心水平滑动之后 `ListView` 就再也接收不到触摸事件了.本来拖到一半的位置就再也没办法继续下去, 也不能拿到 `ACTION_UP` 的事件了.急煞我也.

自己想想, 原因无非就是只要是水平方向的滑动后, `DrawerLayout` 就在 `onInterceptTouchEvent` 截获了点击事件, 那么子 view 永远都收不到触摸事件.

#### 解决思路

只要当前是在拖动状态下, 就在`DrawerLayout`的`Parent`中截获触摸事件, 然后绕过`DrawerLayout`直接传递给`ListView`.

#### 具体代码

    FrameLayout content = new FrameLayout(this) {
        @Override
        public boolean onInterceptTouchEvent(MotionEvent ev) {
            if (listView.isDragging()) {
                return true;
            }
            return super.onInterceptTouchEvent(ev);
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (listView.isDragging()) {
                final float x = event.getX() - getPaddingLeft();
                final float y = event.getY() - getPaddingTop();
                event.setLocation(x, y);
                if (listView.onTouchEvent(event)) {
                    return true;
                }
            }
            return super.onTouchEvent(event);
        }
    };
    
    
不知道细心的你有木有看到上面的那一行:

    final float x = event.getX() - getPaddingLeft();
    final float y = event.getY() - getPaddingTop();
    event.setLocation(x, y);
    
    
是什么鬼呢?

原因在于 `MotionEvent.getX()` 拿到的是距离当前 `view` **左上角** 的位置.传到 `ListView` 的时候, 就多出了 Parent 的做边距和顶边距. 因此需要把这一部分误差去除.

#### 广告时间

具体的实现效果可以参看即将发布的`小天气`里面的效果.