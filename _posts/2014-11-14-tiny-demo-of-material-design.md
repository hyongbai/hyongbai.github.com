---
layout: post
title: "Demo of material design"
description: "Android Material Design, Android L"
category: 日志
tags: 
- Android
- Lollipop

date: 2014-11-13 00:32:57+08:00
---


tiny-demo-of-material-design
============================

看到Google play还有快图的新版之后，感觉左上角的那个Drawer图标很是漂亮。于是就自己实现了一下。滑动DrawerLayout的时候，右上角的小图标会跟随滑动来改变自身的形状。效果图如下，感觉还是挺漂亮的。


源码：[`github`](https://github.com/hyongbai/tiny-demo-of-material-design)



![Image](https://raw.githubusercontent.com/hyongbai/tiny-demo-of-material-design/master/ascreenshot-20141114-000506.png)

#### `Dependency` 
`android-support-v7-appcompat` 这个lib的位置在`{sdk}/extras/android/support/v7/appcompat`


##### Blablablabla

Android的V7包里面使用了Toolbar来代替掉之前的ActionBar了，就可以很好地设置了status bar的背景了。用ActionBar的同学应该知道不管怎么使用SystemBarTintManager都不能改变statusBar默认的那个黑色透明背景（它的原理其实只是在DecorView里面add一个背景为你设置的颜色的View而已）。



那么怎么使用V7包来设置Toolbar的背景以及状态栏的背景颜色呢。可以在demo的style里面看到如下两个属性的设置：


	<item name="colorPrimary">@color/accent_material_dark</item>
	<item name="colorPrimaryDark">@color/accent_material_dark</item>


第一个colorPrimary即是Toolbar的背景颜色。第二个colorPrimaryDark即是StatusBar的背景色。将两个色值设置成同一个颜色即可以达到所谓的沉寂式体验了。跟iOS的也就无差别了。

