---
layout: post
title: "[Docker]安装"
description: "[Docker]安装"
category: all-about-tech
tags: [Docker]
date: 2017-08-28 00:05:57+00:00
---

上一篇【[[Docker]介绍]({% post_url 2017-08-24-docker-introduce %})】简单讲述了Docker是啥。接下来讲讲如何安装。

## 安装

话说Docker在Linux系统上面安装起来还是很方便的。下面分别讲下在三类系统上面的安装方法。

#### Linux

在Linux上面，Docker为了简化安装过程提供了一个脚本。目前支持`Ubuntu`/`Debian`/`Raspbian`/`CentOS`/`Fedora`等系统。且支持切换Azure以及Aliyun的apt源。

具体安装：

```shell
curl -s https://get.docker.com | sudo sh
```

#### OSX/WINDOWS

安装boot2locker即可。但是boot2docker安装需要有两个前提条件：

- 1. virtualbox
- 2. docker客户端

boot2docker的官网地址：<http://boot2docker.io/>

#### 免sudo

安装上之后我们可能还需要使用`sudo docker`来使用Docker。因此如果你方式安装了docker，且想摆脱sudo的话，可以执行如下代码：

```shell
sudo groupadd docker && sudo gpasswd -a $USER docker
```

会自动创建一个名为`docker`用户组，好处在于我们使用docker的时候再也不需要使用sudo开头了。

#### 最后

好了，执行成功之后输入：

```shell
➜  ~ docker -v
Docker version 1.8.1, build d12ea79
➜  ~ 
```