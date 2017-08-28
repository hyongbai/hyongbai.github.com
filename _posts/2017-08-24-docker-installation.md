---
layout: post
title: "Docker-安装"
description: "Docker-安装"
category: all-about-tech
tags: [Docker]
date: 2017-08-28 00:05:57+00:00
---

上一篇【[Docker-介绍]({% post_url 2017-08-24-docker-introduce %})】简单讲述了Docker是啥。接下来讲讲如何安装。

## 版本

Docker有两个版本。大致是CE和EE。前者是社区版本，后者是企业版本。如果考虑稳定或者官方支持的话使用EE就够了。

每种Docker版本都有两种类型，即Stable和Edge。前者可理解为稳定版，后者可理解为尝鲜版。

## 安装

话说Docker在Linux系统上面安装起来还是很方便的。下面分别讲下在三类系统上面的安装方法。

#### Linux

在Linux上面，Docker为了简化安装过程提供了一个脚本。目前支持`Ubuntu`/`Debian`/`Raspbian`/`CentOS`/`Fedora`等系统。且支持切换Azure以及Aliyun的apt源。

具体安装：

```shell
curl -s https://get.docker.com | sudo sh
```

#### OSX/WINDOWS

在OSX/WINDOWS上面安装Docker大致经历了三个阶段。

1, Boot2Docker

安装boot2locker即可。但是boot2docker安装需要有两个前提条件：
 
- virtualbox
- docker客户端

boot2docker的官网地址：<http://boot2docker.io/>

2, Toolbox

Docker之前是使用boot2docker来进行安装的。不过15年之后Docker出了个DockerToolbox来取代boot2docker，因此只需要将DockerToolbox安装即可。

DockerToolbox包含了：

- **DOCKER ENGINE** Docker的核心
- **COMPOSE** 用来运行docker-compose
- **MACHINE** 用来管理DockerVM的组件
- **KITEMATIC** 用来管理镜像和容器的客户端
- **Oracle VirtualBox** 用来虚拟Linux内核。没错Docker是不能直接运行在Mac/Windows上面的。

<https://docs.docker.com/toolbox/overview/>

3, Docker for mac(windows)

Docker for mac相对于toolbox而言性能跟接近与原生。前者基于HyperKit(一个在osx上面更轻量化的虚拟化解决方案)而后者使用的是VirtualBox(性能不占优势)

mac 上面可以通过

```shell
brew install docker
```

或者直接去官网<https://www.docker.com/docker-mac/>下载安装即可。

Windows同理。

注意，此三种方式安装出来的Docker虚拟机不能直接兼容。

话说这前两种方式我电脑上面都安装了。

#### 免sudo

安装上之后我们可能还需要使用`sudo docker`来使用Docker。因此如果你安装了docker，但又不想每次都使用sudo的话，可以执行如下代码：

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

## 参考

> <https://yq.aliyun.com/articles/57215/>
>
> <https://docs.docker.com/toolbox/toolbox_install_mac/>
>
> <https://docs.docker.com/docker-for-mac/docker-toolbox/>
>
> <https://docs.docker.com/toolbox/toolbox_install_windows/>