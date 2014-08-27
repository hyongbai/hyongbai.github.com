---
layout: post
title: "OSX 安装JAVA"
description: "osx java "
category: 日志
tags:
- Java
- Osx
date: 2014-08-27 22:28:57+00:00
---

---
前言
---

一直以来都是使用Linux，linux上面安装JDK自认为是驾轻就熟了。由于Mac使用不久，一直以来使用也是Mac自带的1.6，最近因为工作上面的事需要升级到1.7。但是去官网下面下载下来的是一个dmg文件，点击安装之后尼玛谁知道它安装到什么地方了。遂Google之，发现原来这个dmg文件被安装到“ /Library/Java/JavaVirtualMachines/jdk1.7.0_67.jdk ”中了，只要知道其bin文件的位置就好办了。所要做的事情就是将其加入到bin里面就OK了。方法如下。

---
编辑配置文件
---

vim ~/.bash_profile

输入:

	export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk1.7.0_67.jdk/Contents/Home #jdk安装路径   
	export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar
	export PATH=$PATH:$JAVA_HOME/bin

保存

（如果你不会使用vim或者vi的话，Google之。或者使用其他代替）

---
更新配置文件
---

source ~/.bash_profile


---
祝君好运
---
