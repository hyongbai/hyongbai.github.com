---
layout: post
title: "Docker-介绍"
description: "Docker-介绍"
category: all-about-tech
tags: [Docker]
date: 2017-08-25 10:05:57+00:00
---

## 简介

Docker是近年来非常火的一项技术了。各个大厂也纷纷给予docker进行了支持。目前Google/微软/Amazon/阿里等都已支持了docker。

有如此多的支持还是与其高性能以及高便捷性分不开的。我们可以使用Docker快速的部署生产环境，而且迁移/部署其他也十分方便。使用Docker之后你想要出现线上环境和开发环境不同的情况都将会很难。

Docker本身是基于Linux的内核的，因此在linux设备上面天然是可以运行的。但是在Windows以及MacOSX上面就需要虚拟化一个linux内核来实现了。

## 历史

Docker初期是DotCloud公司基于lxc实现的容器技术。后来是基于golang实现了的libContainer，之后又发展成为了[RunC](https://github.com/opencontainers/runc)。RunC是目前市面上各种容器类实现方案的核心组件，Docker的贡献也慢慢被弱化了。比如华为等近年来的贡献越来越大了。

由于Docker太火了以至于DotCloud公司改名为Docker了。因而越来越凸现的一个问题就是Docker的商标问题。所以再RunC的基础上也产生了Google的Kubernetes(k8s)，Apache的Mesos以及Cloud Foundry的容器引擎Garden等等。也就是说大家都在兼容Docker容器的基础上慢慢也各种产生了自己的容器方案。从而Docker容器也越来越被弱化了。所以导致的问题是：越来越分裂越来越不相互兼容了。

Whatever，不纠结到底谁是标准谁是标杆，先掌握了使用姿势再说。也许有了更深的理解以及基于业务的考量等等自然而然就明白该选择什么。

## 对比

话说在docker出来之前我们习惯于用VM来做"跨平台"的工作，安装vm之后在其上面再安装对应的操作系统。往往会消耗掉大量的内存和存储。从而大大损耗了硬件资源。而Docker与之不同的地方docker不需要这些东西，docker接近于直接使用硬件资源，且不需要用户安装一个完整的操作系统。从这个层面而言，docker做了大大的简化并且带来了性能的大大增进。

下图是vm和docker之间的架构对比：

![](https://insights.sei.cmu.edu/assets/content/VM-Diagram.png)

*(图自cmu)*

因为VM的实现方式，从而导致了VM启动时需要做大量的初始化工作，因而比较耗时。启动速度必然以分钟为单位记。而Docker的启动速度可达到50ms内。按照docker官方的话来说："虚拟机需要数分钟启动，而Docker容器只需要50毫秒"(docker有没有说过这句话真实性有待验证，Whatever)。

甚至有人画了一张图来比较docker和vm的启动速度。对比起来还是十分强烈的。如下：

![](https://cdn.edureka.co/blog/wp-content/uploads/2016/10/VM-vs-Docker-What-is-Docker-Container-Edureka-1.png)

*(图自https://www.edureka.co/blog/what-is-docker-container)*

总结，docker相对于VM而言，不论是体积还是启动速度还是可维护性都有碾压性的优势。

## 功能

吹地这么邪乎，那么Docker到底能干啥？

举个离职吧，如果你写博客的话，不知道你有没有在自己的电脑上面搭建过Jekyll服务呢？在没使用Docker之前一想到搭建Jekyll就然我觉得好生蛋疼，这里有一份安装Jekyll的范例：<http://jekyllcn.com/docs/installation/>，说了“安装完成 Jekyll 需要几分钟的时间。”等你安装你会发现各种各样的问题，比如Ruby没安装或者gem版本不对或者说使用gem无法下载文件(作为一个听过ruby/gem但是没写过的人来说解决这些问题很蛋疼)。“如果你是Mac用户，你就需要安装 Xcode 和 Command-Line Tools”，简直想吐。有了Docker之后我只要用一(两)条命令就行了.比如：`docker run -p 4000:4000 -v /srv:/srv -d jekyll/jekyll /bin/bash -c "cd /srv && jekyll b && jekyll s"`。

所以，使用Docker我们可以很快的搭建各种环境。可以用来演示可以用来开发。

还有就是，比如我们在一台电脑上面运行自己开发的一个系统，但是放到另外一台电脑之后就蛋疼的发现没法运行了。这种运行环境导致的差异常常出现在我们的日常工作中。而使用Docker就没有这种困扰，我们写好自己的DockerFile即可或者说运行同一个镜像即可。

使用Docker完全就没有了因为不同依赖不同操作系统带来的运行环境的不同了。以及避免迁移过程中产生的必然的痛楚了。

Docker能够给我们带来的便利远远不止于此。

## 最后

前面在历史的部分简单讲了下Docker目前存在的问题。所以总结下来就是Docker目前可能还不适合用在企业级的环境中。

Docker的安装请移步：【[Docker-安装]({% post_url 2017-08-24-docker-installation %})】

> 本文是本人基于前人的分享加上个人浅薄的理解创作而成。
> 下面是部分参考的内容:
>
> <http://dockone.io/article/378>
>
> <http://www.yunweipai.com/archives/10328.html>
>
> <http://www.yunweipai.com/archives/10358.html>
>
> <http://www.10tiao.com/html/240/201701/2649256944/1.html>
>
> <http://dockerpool.com/static/books/docker_practice/index.html>
>
> <http://www.infoq.com/cn/articles/docker-standard-container-execution-engine-runc>