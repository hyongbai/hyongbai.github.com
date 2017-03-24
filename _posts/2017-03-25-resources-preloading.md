---
layout: post
title: "系统资源预加载的来龙去脉"
category: all-about-tech
tags: -[Android] -[Resource] -[AssetManager]
date: 2017-03-25 00:02:57+00:00
---

在[Resource通过resId获取Drawable的流程]({% post_url 2017-03-24-assetmanaget-getdrawable %})一文中我们提到了sPreloadedDrawables，它们是用来缓存预加载的一些图片资源等，在ResourcesImpl的源码当中我们看到sPreloadedDrawables的初始化过程。

```java
static {
    sPreloadedDrawables = new LongSparseArray[2];
    sPreloadedDrawables[0] = new LongSparseArray<>();
    sPreloadedDrawables[1] = new LongSparseArray<>();
}
```

为什么是一个二维数组呢？？？

请往下看 :)

前面我们讲到图片加载完了的时候会缓存起来。实现是这样的：

```java
private void cacheDrawable(TypedValue value, boolean isColorDrawable, DrawableCache caches,
        Resources.Theme theme, boolean usesTheme, long key, Drawable dr) {
    final Drawable.ConstantState cs = dr.getConstantState();
    if (cs == null) {
        return;
    }

    if (mPreloading) {
        final int changingConfigs = cs.getChangingConfigurations();
        if (isColorDrawable) {
            if (verifyPreloadConfig(changingConfigs, 0, value.resourceId, "drawable")) {
                sPreloadedColorDrawables.put(key, cs);
            }
        } else {
            if (verifyPreloadConfig(
                    changingConfigs, LAYOUT_DIR_CONFIG, value.resourceId, "drawable")) {
                if ((changingConfigs & LAYOUT_DIR_CONFIG) == 0) {
                    // If this resource does not vary based on layout direction,
                    // we can put it in all of the preload maps.
                    sPreloadedDrawables[0].put(key, cs);
                    sPreloadedDrawables[1].put(key, cs);
                } else {
                    // Otherwise, only in the layout dir we loaded it for.
                    sPreloadedDrawables[mConfiguration.getLayoutDirection()].put(key, cs);
                }
            }
        }
    } else {
        synchronized (mAccessLock) {
            caches.put(key, theme, cs, usesTheme);
        }
    }
}
```
这里很奇怪的一个地方是，如果mPreloading为true的话，就不会往前面提到的那两个cache里面写入了。它就会忘`sPreloadedColorDrawables`和`sPreloadedDrawables`写入了。至于为什么这样呢？我猜测大概是因为preload出来的资源是不会为释放掉的，而其他的资源(DrawableCache中存储资源使用的是锁应用)是会被自动释放掉的。

对了，看上面`(changingConfigs & LAYOUT_DIR_CONFIG) == 0`的时候sPreloadedDrawables的对象全部写入，否则只往LayoutDirection对应的位置写入。其实这里看到LayoutDirection就可以知道为什么是二维数组了。因为姚明是LTR要么是RTL(其实一般只有古中文以及中东才会用到RTL)。

而且，那两个preload缓存也只在这里才会被写入。那么，当什么时候mPreloading才会true，什么时候才不为true呢？

继续看代码，可以发现只有在ResourcesImpl的startPreloading方法里面才会将mPreloading设置为TRUE。在stopPreloading里面重新设置为FALSE。

而这两个方法是在Zygote启动的时候才会被调用。那么我们去到Zygote中调用的地方看看。

```java
//ZygoteInit中
/**
 * Load in commonly used resources, so they can be shared across
 * processes.
 *
 * These tend to be a few Kbytes, but are frequently in the 20-40K
 * range, and occasionally even larger.
 */
private static void preloadResources() {
    final VMRuntime runtime = VMRuntime.getRuntime();

    try {
        mResources = Resources.getSystem();
        mResources.startPreloading();
        if (PRELOAD_RESOURCES) {
            Log.i(TAG, "Preloading resources...");

            long startTime = SystemClock.uptimeMillis();
            TypedArray ar = mResources.obtainTypedArray(
                    com.android.internal.R.array.preloaded_drawables);
            int N = preloadDrawables(ar);
            ar.recycle();
            Log.i(TAG, "...preloaded " + N + " resources in "
                    + (SystemClock.uptimeMillis()-startTime) + "ms.");

            startTime = SystemClock.uptimeMillis();
            ar = mResources.obtainTypedArray(
                    com.android.internal.R.array.preloaded_color_state_lists);
            N = preloadColorStateLists(ar);
            ar.recycle();
            Log.i(TAG, "...preloaded " + N + " resources in "
                    + (SystemClock.uptimeMillis()-startTime) + "ms.");

            if (mResources.getBoolean(
                    com.android.internal.R.bool.config_freeformWindowManagement)) {
                startTime = SystemClock.uptimeMillis();
                ar = mResources.obtainTypedArray(
                        com.android.internal.R.array.preloaded_freeform_multi_window_drawables);
                N = preloadDrawables(ar);
                ar.recycle();
                Log.i(TAG, "...preloaded " + N + " resource in "
                        + (SystemClock.uptimeMillis() - startTime) + "ms.");
            }
        }
        mResources.finishPreloading();
    } catch (RuntimeException e) {
        Log.w(TAG, "Failure preloading resources", e);
    }
}
```

上面的代码中我们看到了调用了Resources的startPreloading方法。这里加载的所有的资源全部都会放在内存中，直到进程被杀死。

所以，如果可以，我们尽量使用系统自带的资源

## 附录

下面列出系统会预加载的一些资源文件。(资源里面应用的资源也会被当做预加载。)

```xml
    <array name="preloaded_drawables">
        <item>@drawable/ab_share_pack_material</item>
        <item>@drawable/ab_solid_shadow_material</item>
        <item>@drawable/action_bar_item_background_material</item>
        <item>@drawable/activated_background_material</item>
        <item>@drawable/btn_borderless_material</item>
        <item>@drawable/btn_check_material_anim</item>
        <item>@drawable/btn_colored_material</item>
        <item>@drawable/btn_default_material</item>
        <item>@drawable/btn_group_holo_dark</item>
        <item>@drawable/btn_group_holo_light</item>
        <item>@drawable/btn_radio_material_anim</item>
        <item>@drawable/btn_star_material</item>
        <item>@drawable/btn_toggle_material</item>
        <item>@drawable/button_inset</item>
        <item>@drawable/cab_background_bottom_material</item>
        <item>@drawable/cab_background_top_material</item>
        <item>@drawable/control_background_32dp_material</item>
        <item>@drawable/control_background_40dp_material</item>
        <item>@drawable/dialog_background_material</item>
        <item>@drawable/editbox_dropdown_background_dark</item>
        <item>@drawable/edit_text_material</item>
        <item>@drawable/expander_group_material</item>
        <item>@drawable/fastscroll_label_left_material</item>
        <item>@drawable/fastscroll_label_right_material</item>
        <item>@drawable/fastscroll_thumb_material</item>
        <item>@drawable/fastscroll_track_material</item>
        <item>@drawable/floating_popup_background_dark</item>
        <item>@drawable/floating_popup_background_light</item>
        <item>@drawable/gallery_item_background</item>
        <item>@drawable/ic_ab_back_material</item>
        <item>@drawable/ic_ab_back_material_dark</item>
        <item>@drawable/ic_ab_back_material_light</item>
        <item>@drawable/ic_account_circle</item>
        <item>@drawable/ic_arrow_drop_right_black_24dp</item>
        <item>@drawable/ic_clear</item>
        <item>@drawable/ic_clear_disabled</item>
        <item>@drawable/ic_clear_material</item>
        <item>@drawable/ic_clear_normal</item>
        <item>@drawable/ic_commit_search_api_material</item>
        <item>@drawable/ic_dialog_alert_material</item>
        <item>@drawable/ic_find_next_material</item>
        <item>@drawable/ic_find_previous_material</item>
        <item>@drawable/ic_go</item>
        <item>@drawable/ic_go_search_api_material</item>
        <item>@drawable/ic_media_route_connecting_material</item>
        <item>@drawable/ic_media_route_material</item>
        <item>@drawable/ic_menu_close_clear_cancel</item>
        <item>@drawable/ic_menu_copy_material</item>
        <item>@drawable/ic_menu_cut_material</item>
        <item>@drawable/ic_menu_find_material</item>
        <item>@drawable/ic_menu_more</item>
        <item>@drawable/ic_menu_moreoverflow_material</item>
        <item>@drawable/ic_menu_paste_material</item>
        <item>@drawable/ic_menu_search_material</item>
        <item>@drawable/ic_menu_selectall_material</item>
        <item>@drawable/ic_menu_share_material</item>
        <item>@drawable/ic_search_api_material</item>
        <item>@drawable/ic_voice_search_api_material</item>
        <item>@drawable/indicator_check_mark_dark</item>
        <item>@drawable/indicator_check_mark_light</item>
        <item>@drawable/item_background_borderless_material</item>
        <item>@drawable/item_background_borderless_material_dark</item>
        <item>@drawable/item_background_borderless_material_light</item>
        <item>@drawable/item_background_material</item>
        <item>@drawable/item_background_material_dark</item>
        <item>@drawable/item_background_material_light</item>
        <item>@drawable/list_choice_background_material</item>
        <item>@drawable/list_divider_material</item>
        <item>@drawable/list_section_divider_material</item>
        <item>@drawable/menu_background_fill_parent_width</item>
        <item>@drawable/notification_material_action_background</item>
        <item>@drawable/notification_material_media_action_background</item>
        <item>@drawable/number_picker_divider_material</item>
        <item>@drawable/popup_background_material</item>
        <item>@drawable/popup_inline_error_above_holo_dark</item>
        <item>@drawable/popup_inline_error_above_holo_light</item>
        <item>@drawable/popup_inline_error_holo_dark</item>
        <item>@drawable/popup_inline_error_holo_light</item>
        <item>@drawable/progress_horizontal_material</item>
        <item>@drawable/progress_indeterminate_horizontal_material</item>
        <item>@drawable/progress_large_material</item>
        <item>@drawable/progress_medium_material</item>
        <item>@drawable/progress_small_material</item>
        <item>@drawable/quickcontact_badge_overlay_dark</item>
        <item>@drawable/quickcontact_badge_overlay_light</item>
        <item>@drawable/quickcontact_badge_overlay_normal_dark</item>
        <item>@drawable/quickcontact_badge_overlay_normal_light</item>
        <item>@drawable/quickcontact_badge_overlay_pressed_dark</item>
        <item>@drawable/quickcontact_badge_overlay_pressed_light</item>
        <item>@drawable/ratingbar_indicator_material</item>
        <item>@drawable/ratingbar_material</item>
        <item>@drawable/ratingbar_small_material</item>
        <item>@drawable/screen_background_dark</item>
        <item>@drawable/screen_background_dark_transparent</item>
        <item>@drawable/screen_background_light</item>
        <item>@drawable/screen_background_light_transparent</item>
        <item>@drawable/screen_background_selector_dark</item>
        <item>@drawable/screen_background_selector_light</item>
        <item>@drawable/scrollbar_handle_material</item>
        <item>@drawable/seekbar_thumb_material_anim</item>
        <item>@drawable/seekbar_tick_mark_material</item>
        <item>@drawable/seekbar_track_material</item>
        <item>@drawable/spinner_background_material</item>
        <item>@drawable/spinner_textfield_background_material</item>
        <item>@drawable/switch_thumb_material_anim</item>
        <item>@drawable/switch_track_material</item>
        <item>@drawable/tab_indicator_material</item>
        <item>@drawable/text_cursor_material</item>
        <item>@drawable/text_edit_paste_window</item>
        <item>@drawable/textfield_search_material</item>
        <item>@drawable/text_select_handle_left_material</item>
        <item>@drawable/text_select_handle_middle_material</item>
        <item>@drawable/text_select_handle_right_material</item>
        <item>@drawable/toast_frame</item>
    </array>
```
```xml
    <array name="preloaded_color_state_lists">
        <item>@color/primary_text_dark</item>
        <item>@color/primary_text_dark_disable_only</item>
        <item>@color/primary_text_dark_nodisable</item>
        <item>@color/primary_text_disable_only_holo_dark</item>
        <item>@color/primary_text_disable_only_holo_light</item>
        <item>@color/primary_text_holo_dark</item>
        <item>@color/primary_text_holo_light</item>
        <item>@color/primary_text_light</item>
        <item>@color/primary_text_light_disable_only</item>
        <item>@color/primary_text_light_nodisable</item>
        <item>@color/primary_text_nodisable_holo_dark</item>
        <item>@color/primary_text_nodisable_holo_light</item>
        <item>@color/secondary_text_dark</item>
        <item>@color/secondary_text_dark_nodisable</item>
        <item>@color/secondary_text_holo_dark</item>
        <item>@color/secondary_text_holo_light</item>
        <item>@color/secondary_text_light</item>
        <item>@color/secondary_text_light_nodisable</item>
        <item>@color/secondary_text_nodisable_holo_dark</item>
        <item>@color/secondary_text_nodisable_holo_light</item>
        <item>@color/secondary_text_nofocus</item>
        <item>@color/hint_foreground_dark</item>
        <item>@color/hint_foreground_holo_dark</item>
        <item>@color/hint_foreground_holo_light</item>
        <item>@color/hint_foreground_light</item>
        <item>@color/bright_foreground_light</item>
        <item>@color/bright_foreground_dark</item>
        <item>@color/tab_indicator_text</item>
        <item>#ff000000</item>
        <item>#00000000</item>
        <item>#ffffffff</item>

        <!-- Material color state lists -->
       <item>@color/background_cache_hint_selector_material_dark</item>
       <item>@color/background_cache_hint_selector_material_light</item>
       <item>@color/btn_default_material_dark</item>
       <item>@color/btn_default_material_light</item>
       <item>@color/primary_text_disable_only_material_dark</item>
       <item>@color/primary_text_disable_only_material_light</item>
       <item>@color/primary_text_material_dark</item>
       <item>@color/primary_text_material_light</item>
       <item>@color/search_url_text_material_dark</item>
       <item>@color/search_url_text_material_light</item>
    </array>
```