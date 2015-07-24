---
layout: post
title: "把Module变成Lib"
category: 日志
tags: 
- AndroidStudio
- Moudle
date: 2015-05-19 10:23:57+08:00
---

使用AndroidStudio时常常需要将一个`Module`变成一个`lib`。在软件里面似乎招不到直接将其变成`lib`的方法。于是看了下其他的的lib的gradle配置，大致改成如下即可。

#### 配置:
> - 注意是`apply plugin: 'com.android.library'` 而不是 `apply plugin: 'com.android.application'`！
> - 将`buildTypes`删去
> - 把`defaultConfig`里面的`applicationId`删去



	apply plugin: 'com.android.library'

	android {
	    compileSdkVersion 21
	    buildToolsVersion "21.1.2"
	    resourcePrefix 'baseui_'

	    defaultConfig {
	        minSdkVersion 14
	        targetSdkVersion 14
	    }
	}
	dependencies {
	    compile fileTree(dir: 'libs', include: ['*.jar'])
	    compile 'com.android.support:appcompat-v7:21.0.3'
	    compile 'com.android.support:recyclerview-v7:21.0.+'
	}

