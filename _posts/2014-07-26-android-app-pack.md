---
layout: post
title: "Android自动打包 友盟多渠道"
description: "Android 打包 友盟多渠道"
category: 日志
tags: [Android]
date: 2014-07-26 12:57:57+00:00
---


android-app-pack
================

auto pack android app through ant

[项目地址]  (https://github.com/hyongbai/android-app-pack)

1.用法：

    a.  把custom_build.xml复制到工程的跟目录。
 
    b.  把本目录的路径放到PATH中。(Linux和Mac用户你懂的)，如果是windows用户，俺也不管了。

    c.  在工程根目录或者指定工程目录执行android-app-pack。
            
        例如: ~/xxx: android-app-pack 或者 android-app-pack ~/xxx

2.相关说明

    a.友盟多渠道打包：
    
        在根目录里面，创建一个"pack.config"文件。有几个channel就创建几条channel=xxx（xxx表示channel name）

        例如:
      
            channel=91
            channel=Tencent
            channel=WanDouJia
            channel=360
            channel=XiaoMi
            channel=163
            channel=daXiangCe      

    b.如果在使用的过程中出现了。invalid resource blablabla之类的。然后以bin/res/crunch结尾的，请删除之。

    c.签名

        在根目录添加 ant.properties，内容是key的路径以及密码神马的

        例如:

            key.store=abc.keystore
            key.alias=abc
            key.store.password=123
            key.alias.password=123   

3.环境变量神马

    在使用之前注意自己的环境变量是不是设置正确了。有没有把sdk/tools放到PATH里面。如果你不知道神马叫做PATH，请Google之。

    如果打包出现错误，请确认自己的工程内部是不是有错误。

    打包的时候请记得关闭自己的log，不要做没有节操的工程师。如果你用刷了MIUI的手机调试bug，你就知道什么叫做刷屏了。

    作为一个Android开发者，你最好配一个Nexus手机，然后，刷CM的rom。如果你不知道怎么刷机，，，，俺也没办法了。Google之。

注：
    custom_build.xml参考了 [AntDemo](https://github.com/sinkcup/AntDemo) 在此表示感谢
 
