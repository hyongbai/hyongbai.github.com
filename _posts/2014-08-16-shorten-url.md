---
layout: post
title: "Hello World @ GitHub"
description: "第一篇博客"
category: 日志
tags: [GitHub]
date: 2014-07-22 23:05:57+00:00
---

[项目地址](http://t.cn/RPTSmA6)

This is a public repo for user to shorten a long url.

update note:

01/22/14  Just sina shorten url is supported up to now.
03/05/14  add support of baidu and google 
Before using:

chmod +x shoturl


#pwd is the abs path of shoturl
echo PATH=$PATH:(pwd) >> ~/.bashrc
Usage:

shoturl http://www.google.com (or shoturl www.google.com)

>>>>result:http://t.cn/h51yw
