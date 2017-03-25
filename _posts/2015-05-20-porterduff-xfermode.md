---
layout: post
title: "Xfermode 和 PorterDuff"
category: all-about-tech
tags: 
- Xfermode
- PorterDuff

date: 2015-05-20 02:23:57+08:00
--- 
#### **1.Xfermode**:
 
Xfermode有三个子类 :

 - AvoidXfermode  指定了一个颜色和容差，强制Paint避免在它上面绘图(或者只在它上面绘图)。

 - PixelXorXfermode  当覆盖已有的颜色时，应用一个简单的像素异或操作。
 
 - PorterDuffXfermode  这是一个非常强大的转换模式，使用它，可以使用图像合成的16条Porter-Duff规则的任意一条来控制Paint如何与已有的Canvas图像进行交互。

要应用转换模式，可以使用setXferMode方法，如下所示：


	AvoidXfermode avoid = new AvoidXfermode(Color.BLUE, 10, AvoidXfermode.Mode. AVOID);    borderPen.setXfermode(avoid); 


#### **2.PorterDuff**:



PorterDuff.Mode为枚举类,一共有16个枚举值:

> - 1.PorterDuff.Mode.CLEAR:所绘制不会提交到画布上。
> - 2.PorterDuff.Mode.SRC 显示上层绘制图片
> - 3.PorterDuff.Mode.DST 显示下层绘制图片
> - 4.PorterDuff.Mode.SRC_OVER 正常绘制显示，上下层绘制叠盖。
> - 5.PorterDuff.Mode.DST_OVER 上下层都显示。下层居上显示。
> - 6.PorterDuff.Mode.SRC_IN 取两层绘制交集。显示上层。
> - 7.PorterDuff.Mode.DST_IN 取两层绘制交集。显示下层。
> - 8.PorterDuff.Mode.SRC_OUT 取上层绘制非交集部分。
> - 9.PorterDuff.Mode.DST_OUT 取下层绘制非交集部分。
> - 10.PorterDuff.Mode.SRC_ATOP 取下层非交集部分与上层交集部分
> - 11.PorterDuff.Mode.DST_ATOP 取上层非交集部分与下层交集部分
> - 12.PorterDuff.Mode.XOR 异或：去除两图层交集部分
> - 13.PorterDuff.Mode.DARKEN 取两图层全部区域，交集部分颜色加深
> - 14.PorterDuff.Mode.LIGHTEN 取两图层全部，点亮交集部分颜色
> - 15.PorterDuff.Mode.MULTIPLY 取两图层交集部分叠加后颜色
> - 16.PorterDuff.Mode.SCREEN 取两图层全部区域，交集部分变为透明色

