---
layout: post
title: "Spiral matrix"
category: all-about-tech
tags: 
 - algo
 - spial matrix
date: 2016-05-12 12:05:57+00:00
---

### 先贴代码:)

```Java
public class Solution {
    private final static int TO_NONE = -1;
    private final static int TO_UP = 3;
    private final static int TO_LEFT = 2;
    private final static int TO_DOWN = 1;
    private final static int TO_RIGHT = 0;
    //
    private int mDirCursor = 0;
    private int mDirection = TO_NONE;
    private int[] mDirectArr = new int[]{TO_RIGHT, TO_DOWN, TO_LEFT, TO_UP};
    //
    private int x, y;
    private int[][] mMatrix;
    private int horizontal, vertical;
    private int left = 0, top = 0, right = 0, bottom = 0;

    public List<Integer> spiralOrder(int[][] matrix) {
        this.mMatrix = matrix;
        if (matrix == null || matrix.length == 0 || isEmpty(matrix[0])) {
            return new ArrayList<>(0);
        }
        vertical = matrix.length;
        horizontal = matrix[0].length;
        //
        final int total = horizontal * vertical;
        final Integer[] result = new Integer[total];
        //
        for (int i = 0; i < total; i++) {
            result[i] = getValue(mDirection);
        }
        return Arrays.asList(result);
    }

    private int getValue(int from) {
        mDirection = getNext(mDirCursor, mDirectArr);
        final boolean dirChange = mDirection != from;
        //
        if (mDirection == TO_RIGHT) {
            if (dirChange) {
                x = top;
                y = left;
            } else {
                y++;
            }
            if (y > horizontal - right - 1) {
                top++;
                mDirCursor++;
                return getValue(mDirection);
            }
        } else if (mDirection == TO_DOWN) {
            if (dirChange) {
                x = top;
                y = horizontal - right - 1;
            } else {
                x++;
            }
            if (x > vertical - bottom - 1) {
                right++;
                mDirCursor++;
                return getValue(mDirection);
            }
        } else if (mDirection == TO_LEFT) {
            if (dirChange) {
                x = vertical - bottom - 1;
                y = horizontal - right - 1;
            } else {
                y--;
            }
            if (y < left) {
                bottom++;
                mDirCursor++;
                return getValue(mDirection);
            }
        } else if (mDirection == TO_UP) {
            if (dirChange) {
                x = vertical - bottom - 1;
                y = left;
            } else {
                x--;
            }
            if (x < top) {
                left++;
                mDirCursor++;
                return getValue(mDirection);
            }
        }
        return mMatrix[x][y];
    }


    private int getNext(int current, int[] directArr) {
        return directArr[current % directArr.length];
    }

    private boolean isEmpty(int[] arr) {
        return arr == null || arr.length == 0;
    }
}
```
