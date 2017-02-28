---
layout: post
title: "Canvas的clip函数详解"
category: all-about-tech
tags: 
 - android
 - canvas
 - clip
date: 2016-04-15 02:05:57+00:00
---

最近把canvas的clip函数给过了一遍。整理并记录下来给有需要的朋友.

### 介绍
翻看了下Canvas的源码，关于clip相关的函数，一共有如下几个:

{% highlight java %}
clipPath(@NonNull Path path) 
clipPath(@NonNull Path path, @NonNull Region.Op op)
clipRect(float left, float top, float right, float bottom) clipRect(float left, float top, float right, float bottom,@NonNull Region.Op op)
clipRect(int left, int top, int right, int bottom)
clipRect(@NonNull Rect rect)
clipRect(@NonNull Rect rect, @NonNull Region.Op op) 
clipRect(@NonNull RectF rect)
clipRect(@NonNull RectF rect, @NonNull Region.Op op)
clipRegion(@NonNull Region region)
clipRegion(@NonNull Region region, @NonNull Region.Op op)
{% endhighlight %}

其中最后两个clipRegion相关的已经deprecated。

其实虽然提供了那么多接口，无非就是两个。一种是提供一个形状，一种是提供一个形状的同时提供一个Op.(不知道该怎么翻译Op, 23333)

### 思路
接下来就用ClipRect来实现剪裁效果。

我的思路是按照grid的方式，分别把剪切区域，剪切前的图像，以及各个类型的OP分别画到格子里面。

废话不多说，先来效果图。下图：

![image](/media/imgs/canvas-clip.png)

(请忽略，`I'm HEADER`、`draw by CanvasClipView`、`I'm FOOTER` 这三个区域)
其中剪切区域是左上角和右下角两个有重合区域的矩形（图中的`CLIP-RECT`）。`ORIGINAL`是图形没有做任何剪切的原样。

而每个格子都是通过`Canvas.translate(x,y)`来移动实现Grid效果的。至于这个函数怎么使用请自行Google之。

核心代码其实是：

```java
canvas.clipRect(mClipRect0);
canvas.clipRect(mClipRect1, Region.Op.values()[index - countOffset]);
```

`mClipRect0`是左上角的矩形，`mClipRect1`是右下角的矩形。第二次clipRect通过不同的`Op`作用于前面clipRect的结果从而产生不同的效果。

### 结论

根据最终效果我们可以看到: 

|Op|含义|
|:-:|:-:|
|DIFFERENCE|取原先区域**不相交**的地方。|
|INTERSECT| 取原先区域**只相交**的地方。|
|UNION| 取合并后的区域。|
|XOR| 即`异或`, 取**相交**以外的全部|
|REVERSE_DIFFERENCE|跟`DIFFERENCE`相对，取**后来区域**不相交的集合。|
|REPLACE| 即**替换**，完全只使用**后来作用**的区域。|

### 总结

然而，这个有卵用？

当然有! 比如你想让你的view拥有一个圆角矩形或者实现微信图片消息的形状(当然还可以有其他方案来实现)。等等

### 最后

下面是整段代码:


```java
public class CanvasClipView extends View {
    private int mColumns = 3;
    private int mVerCount;
    private int mItemSize;
    private int countOffset = 2;
    private int mDividerSize = ViewUtil.getDP(10);
    private int mItemCount = Region.Op.values().length + countOffset;
    //
    private RectF mTempRect = new RectF();
    private Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    //
    private RectF mClipRect0 = new RectF();
    private RectF mClipRect1 = new RectF();

    public CanvasClipView(Context context) {
        super(context);
    }

    public CanvasClipView(Context context, AttributeSet attrs) {
        super(context, attrs);
    }

    public CanvasClipView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        mPaint.setFakeBoldText(true);
        mPaint.setTextSize(ViewUtil.getSP(10));
        mPaint.setTextAlign(Paint.Align.CENTER);
        mPaint.setShadowLayer(1, 1, 1, 0xff000000);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(MeasureSpec.makeMeasureSpec(MeasureSpec.getSize(widthMeasureSpec), MeasureSpec.EXACTLY), heightMeasureSpec);
        mItemSize = (getMeasuredWidth() - mDividerSize * (mColumns + 1)) / mColumns;
        mVerCount = (mItemCount / mColumns) + (mItemCount % mColumns == 0 ? 0 : 1);
        setMeasuredDimension(getMeasuredWidth(), mItemSize * mVerCount + mDividerSize * (mVerCount + 1));
        //
        mClipRect0.set(0, 0, mItemSize / 2, mItemSize / 2);
        mClipRect1.set(mItemSize / 4, mItemSize / 4, mItemSize, mItemSize);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        // draw divider line
        mPaint.setColor(0xFF000000);
        mPaint.setStrokeWidth(ViewUtil.getDP(1));
        final int offset = mDividerSize / 2;
        for (int i = 0; i <= mColumns; i++) {
            final int x = i * (mDividerSize + mItemSize) + offset;
            canvas.drawLine(x, offset, x, getMeasuredHeight() - offset, mPaint);
        }
        for (int i = 0; i <= mVerCount; i++) {
            final int y = i * (mDividerSize + mItemSize) + offset;
            canvas.drawLine(offset, y, getMeasuredWidth() - offset, y, mPaint);
        }
        //
        for (int i = 0; i < mItemCount; i++) {
            final int tranX = (i % mColumns) * (mDividerSize + mItemSize) + mDividerSize;
            final int tranY = (i / mColumns) * (mDividerSize + mItemSize) + mDividerSize;

            // save matrix
            final int matrixCount = canvas.save(Canvas.MATRIX_SAVE_FLAG);
            canvas.translate(tranX, tranY);

            // draw clip
            final int clipCount = canvas.save(Canvas.CLIP_SAVE_FLAG);
            final String name = drawTheRects(canvas, i);
            canvas.restoreToCount(clipCount);

            // draw name
            mPaint.setColor(0xFFFFFFFF);
            canvas.drawText(name, mItemSize / 2, mItemSize, mPaint);

            // restore matrix
            canvas.restoreToCount(matrixCount);
        }
    }

    private String drawTheRects(Canvas canvas, int index) {
        final String name;
        if (index == 0) {
            name = "CLIP-RECT";
            mPaint.setColor(0xFFFF0000);
            mPaint.setStyle(Paint.Style.STROKE);
            canvas.drawRect(mClipRect0, mPaint);
            canvas.drawRect(mClipRect1, mPaint);
        } else {
            if (index < countOffset) {
                name = "ORIGINAL";
            } else {
                canvas.clipRect(mClipRect0);
                canvas.clipRect(mClipRect1, Region.Op.values()[index - countOffset]);
                name = Region.Op.values()[index - countOffset].toString();
            }
            drawBasic(canvas);
        }
        return name;
    }

    private void drawBasic(Canvas canvas) {
        mPaint.setStyle(Paint.Style.FILL);
        canvas.clipRect(0, 0, mItemSize, mItemSize);
        //
        repeatlyDraw(canvas, 0, mItemSize / 4);
        //
//        mPaint.setColor(0xFF000000);
//        mPaint.setStrokeWidth(ViewUtil.getDP(8));
//        canvas.drawLine(0, 0, mItemSize, mItemSize, mPaint);
    }

    private void repeatlyDraw(Canvas canvas, int... offsets) {
        for (int off : offsets) {
            mTempRect.set(off, off, mItemSize - off, mItemSize - off);
            drawRectWithCircle(canvas, mTempRect);
        }
    }

    private void drawRectWithCircle(Canvas canvas, RectF rectF) {
        mPaint.setColor(0xFF00FF00);
        canvas.drawRect(rectF, mPaint);
        mPaint.setColor(0xFF0000FF);
        canvas.drawRoundRect(rectF, rectF.width() / 2, rectF.height() / 2, mPaint);
    }
}
```