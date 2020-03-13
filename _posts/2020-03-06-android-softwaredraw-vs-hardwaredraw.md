---
layout: post
title: "Android硬件加速绘制时与软件加速的区别"
description: "Android硬件加速绘制时与软件加速的区别"
category: all-about-tech
tags: -[android]
date: 2020-03-06 23:03:57+00:00
---

> 基于android-8.1.0_r60

## 软件绘制

[![Android-ViewRootImpl-doTravelsal-View-onDraw-Software.jpg](https://j.mp/2PMNftt)](https://j.mp/2PU6MYV)

`ViewRootImpl`初始化会创建一个Surface.java文件，用于提供整个绘制过程中的画布。

其内部Canvas对象的初始化过程如下：

```
// Surface.java
mCanvas = new CompatibleCanvas();
---------------------
// Canvas.java
public Canvas() {
 if (!isHardwareAccelerated()) {
  mNativeCanvasWrapper = nInitRaster(null);
 }
}
---------------------
// frameworks/base/core/android_graphics_Canvas.cpp
initRaster(jobject jbit) {
 SkBitmap b;
 GraphicsJNI::getSkBitmap(env, jbit, &b);
 return reinterpret_cast(Canvas::create_canvas(b));
}
---------------------
// frameworks/base/libs/hwui/SkiaCanvas.cpp
Canvas* Canvas::create_canvas(const SkBitmap& b) {
 return new SkiaCanvas(b);
}
```

而在绘制获取Canvas对象前会调用Surface的`lockCanvas`函数，这是一步与开启硬件加速区别的关键一步：

```
// frameworks/base/core/jni/android_view_Surface.cpp
static jlong nativeLockCanvas(JNIEnv* env, jclass clazz,
        jlong nativeObject, jobject canvasObj, jobject dirtyRectObj) {
    // ...
    SkBitmap bitmap;
    ssize_t bpr = outBuffer.stride * bytesPerPixel(outBuffer.format);
    bitmap.setInfo(info, bpr);
    // ...
    Canvas* nativeCanvas = GraphicsJNI::getNativeCanvas(env, canvasObj);
    nativeCanvas->setBitmap(bitmap);
    // ...
    sp<Surface> lockedSurface(surface);
    lockedSurface->incStrong(&sRefBaseOwner);
    return (jlong) lockedSurface.get();
}
```

可以看到每一帧的绘制都对应着新SkBitmap的创建。而其中nativeCanvas就是上面的SkiaCanvas，而`Canvas->setBitmap`用于更新SkiaCanvas内部的SkCanvas实例(mCanvas)。如下：

```cpp
// frameworks/base/libs/hwui/SkiaCanvas.cpp
void SkiaCanvas::setBitmap(const SkBitmap& bitmap) {
    sk_sp<SkColorSpace> cs = bitmap.refColorSpace();
    std::unique_ptr<SkCanvas> newCanvas =
            std::unique_ptr<SkCanvas>(new SkCanvas(bitmap, SkCanvas::ColorBehavior::kLegacy));
    std::unique_ptr<SkCanvas> newCanvasWrapper = SkCreateColorSpaceXformCanvas(newCanvas.get(),
            cs == nullptr ? SkColorSpace::MakeSRGB() : std::move(cs));

    // deletes the previously owned canvas (if any)
    mCanvasOwned = std::move(newCanvas);
    mCanvasWrapper = std::move(newCanvasWrapper);
    mCanvas = mCanvasWrapper.get();

    // clean up the old save stack
    mSaveStack.reset(nullptr);
}
```

这里会根据SkBitmap生成行的mCanvas，用于实现SkiaCanvas对外暴露的Canvas接口。

## 硬件绘制(开启硬件加速)

[![Android-ViewRootImpl-doTravelsal-View-onDraw-HardwareAccelerate-2.jpg](https://j.mp/2U9CtPs)](https://j.mp/3aSl9VB)

其中Canvas是在更新RootDisplayList时创建的，而其最终实例为`DisplayListCanvas`。下面看看`DisplayListCanvas`初始化时与软件绘制时的区别。

```
// DisplayListCanvas.java
private DisplayListCanvas(RenderNode node, int w, int h) {
    super(nCreateDisplayListCanvas(node.mNativeRenderNode, w, h));
}
---------------------
// android_view_DisplayListCanvas.cpp
android_view_DisplayListCanvas_createDisplayListCanvas(jlong n,
        jint w, jint h) {
 RenderNode* rn = reinterpret_cast<RenderNode*>(n);
return reinterpret_cast(Canvas::create_recording_canvas(w, h, rn));
}
---------------------
// base/libs/hwui/hwui/Canvas.cpp
Canvas::create_recording_canvas(int w, int h, RenderNode* n) {
 if (Properties::isSkiaEnabled()) {
  return new skiapipeline::SkiaRecordingCanvas(n, w, h);
 }
 return new RecordingCanvas(w, h);
}
---------------------
// base/libs/hwui/pipeline/skia/SkiaRecordingCanvas.h
SkiaRecordingCanvas(RenderNode* n, int w, int h) {
    initDisplayList(n, w, h);
}
---------------------
// base/libs/hwui/pipeline/skia/SkiaRecordingCanvas.cpp
void initDisplayList(RenderNode* n, int w, int h) {
    mDisplayList->attachRecorder(&mRecorder);
    SkiaCanvas::reset(&mRecorder);
}
---------------------
// frameworks/base/libs/hwui/SkiaCanvas.cpp
void SkiaCanvas::reset(SkCanvas* skiaCanvas) {
    mCanvas = skiaCanvas;
}
```

其中mRecorder是一个SkLiteRecorder实例，主要用于记录View对于Canvas操作的OP。如下：


```cpp
// http://androidxref.com/8.1.0_r33/xref/external/skia/src/core/SkLiteRecorder.h
/**
 * A SkiaCanvas implementation that records drawing operations for deferred rendering backed by a
 * SkLiteRecorder and a SkiaDisplayList.
 */
class SkLiteRecorder final : public SkNoDrawCanvas {
public:
    SkLiteRecorder();
}

---------
// http://androidxref.com/8.1.0_r33/xref/external/skia/src/core/SkLiteRecorder.cpp

SkLiteRecorder::SkLiteRecorder()
    : INHERITED(1, 1)
    , fDL(nullptr) {}

void SkLiteRecorder::reset(SkLiteDL* dl, const SkIRect& bounds) {
    this->resetCanvas(bounds.right(), bounds.bottom());
    fDL = dl;
}

void SkLiteRecorder::onDrawPaint(const SkPaint& paint) {
    fDL->drawPaint(paint);
}

void SkLiteRecorder::onDrawPath(const SkPath& path, const SkPaint& paint) {
    fDL->drawPath(path, paint);
}

---------
// http://androidxref.com/8.1.0_r33/xref/external/skia/src/core/SkLiteDL.cpp
void SkLiteDL::drawPaint(const SkPaint& paint) {
    this->push<DrawPaint>(0, paint);
}
void SkLiteDL::drawPath(const SkPath& path, const SkPaint& paint) {
    this->push<DrawPath>(0, path, paint);
}
```

通过SkLiteRecorder头文件的注释既可知：准备render的操作都会被记录在SkLiteRecorder或者SkiaDisplayList中。最终到OpenGLPipeLine进行绘制的时候才交给GPU进行绘制。

## 区别

- 软件绘制：view绘制时，每一步都直接操作底层的SkCanvas。
- 硬件绘制：view绘制时，每一步都被记录在底层的recorder或者displaylist。直到最后一起交给GPU进行绘制。