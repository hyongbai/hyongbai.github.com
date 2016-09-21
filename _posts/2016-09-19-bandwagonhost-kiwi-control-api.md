---
layout: post
title: "命令行代替搬瓦工kiwi"
description: "命令行代替搬瓦工kiwi"
category: all-about-tech
tags: [GitHub]
date: 2016-09-19 23:05:57+00:00
---
 
## 前言

随着各种翻墙服务的倒闭，越来越多的人选择了自己搭建vps来翻墙。于是乎我也不能落下潮流，故而自己用搬瓦工[bandwagonhost.com](https://bandwagonhost.com)搭建了一个shadowsocks服务(基本上一键安装，还有OpenVPN可选)。

由于本人之前使用的是搬瓦工先前的一个最基础的套餐`RAM:72MB,DISK:1.8GB,BANDWIDTH:100GB`, 经常用久了就感觉变慢了(也许是心里作用)。所以就准备重启一下。

但是，每次都需要进入官网，登录完之后一系列操作后打开wiki，漫长等待后终于看到了restart按钮。而且有时候搬瓦工官网还会被墙，麻痹谁能受得了这么漫长的等待。

## 发展

今天，又遇到了重启的问题。费了九牛二虎之力后打开wiki，重启完没有立马关闭，在里面逛了一圈。发现，wiki控制台`KiwiVM Extras`栏有一个“API”的链接。点进去后发现顶部赫然写着**REST API**几个大字，下面有`Your VEID`和`Your API KEY`.往下翻，看到了**// Sample 5. Restart VPS using wget**.

	wget -qO- "https://api.64clouds.com/v1/restart?veid={YOUR_OWN_VEID}&api_key={YOUR_API_KEY_HERE}"


于是试了试，居然成功了。

## 后来

想着以后直接一个reboot就好了，谁想记id和key谁记，我不。于是写了如下的shell脚本，放到`.bash_profile`中，在终端执行`bwg_reboot`即可。

~~~ shell
	__request_bwg()
	{
	    __option="${1}"
	    __api_key="${2}"
	    __bwg_host="https://api.64clouds.com/v1/${__option}?veid={YOUR_OWN_VEID}&api_key=${__api_key}"
	    wget -qO- "${__bwg_host}"
	}

	config_bandwagonhost()
	{
	    API_KEY=''
	    alias bwg_stop='__request_bwg "stop" "${API_KEY}"'
	    alias bwg_start='__request_bwg "start" "${API_KEY}"'
	    alias bwg_reboot='__request_bwg "restart" "${API_KEY}"'
	}
~~~

妈妈再也不用担心我要重启搬瓦工了。

如果有什么事情是一行命令搞不定的，那就两行:)

从此过上了幸福生活。


## 下面是部分接口

|:-:|:-:|:-:|
|Call|Parameters|Description and return values|
|start|none|Starts the VPS|
|stop|none|Stops the VPS|
|restart|none|Reboots the VPS|
|kill|none|Allows to forcibly stop a VPS that is stuck and cannot be stopped by normal means. Please use this feature with great care as any unsaved data will be lost.|
|getServiceInfo|
|getLiveServiceInfo|
|resetRootPassword|
|getUsageGraphs|

更多的可以去kiwi上面看。