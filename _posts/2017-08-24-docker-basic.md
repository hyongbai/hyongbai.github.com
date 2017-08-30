---
layout: post
title: "Docker练手之基本命令"
description: "Docker练手之基本命令"
category: all-about-tech
tags: [Docker]
date: 2017-08-30 00:05:57+00:00
---

前面介绍了Docker及其安装姿势。现在是该练练手了。

## 镜像

一切关于Docker的使用都要从镜像(Image)开始。所以我们先来看看怎么操作镜像。

#### 命名空间

在下载或者使用镜像的时候，需要告诉docker我们需要谁的、什么样的、啥版本的镜像。比如：ubuntu/ubuntu:14.04，这就代表了Ubuntu公司发行的14.04版的Ubuntu。也就是说镜像的命名空间为`${user}/${name}:${version}`，如果不加版本的话，默认使用的是最新的镜像。这其实只是一种方式。

第二种：还是以Ubuntu为例。Docker公司预留了一系列的著名软件名称当做根命名空间，之后Docker将这些交给第三方维护(一般是软件的发行商)。这种情况下我们就不需要添加`${user}`这个前缀了。比如：ubuntu:14.04或者ubuntu。

第三种：上面两种方式其实“都是”DockerHub。我们也可以指定使用第三方的镜像。比如：localhost:4000/ubuntu:14.04。

Docker镜像大致是这三种命名空间。对了，一般不建议使用latest。因为你昨天用的latest和今天使用的latest可能代表着不同的版本。这样就容易让我们的环境不能保持一致了。

#### 下载镜像

使用pull命令，即docker pull。有了上面关于命名空间的介绍，大概知道怎么指定版本了。例如：

```shell
➜  ~ docker pull ubuntu
Using default tag: latest
latest: Pulling from library/ubuntu
9033d138d2ab: Pulling fs layer 
9033d138d2ab: Pull complete 
3fb6ea6c6e20: Pull complete 
3216af244995: Pull complete 
e0a07d399279: Pull complete 
4ae1232510d5: Pull complete 
56a4fe6a7878: Pull complete 
Digest: sha256:47716ab73252837a8bae20dcedfe86087fa71bb7d3c339160731b3d0aacb5d7b
Status: Downloaded newer image for ubuntu:latest
➜  ~ 
```

因为下载的时候没有标注版本，因此默认下载的是最新版本。

#### 运行镜像

Docker提供了一个很重要的run命令用来运行镜像。比如：

```shell
docker run ubuntu
```

这样就会去运行Ubuntu镜像了。注意：如果此时本地没有对应的镜像的话也会去下载镜像。也就是说你不必要先去下载镜像，然后才能运行。如果，基本上pull在我使用docker的过程中可能很少用到。每执行一次此命令就会创建一个容器(后面会将)，一个镜像可以运行多次从而会产生多个容器。

`run`其实还可以添加多个参数，下面列出了自己整理的部分

```shell
-d deamon 保持后台运行

--name "${CONTAINER_NAME}

-v 设定容器卷，-v "${local_path}:${host_path} 会隐藏容器中的目录，直接使用数据卷。-v "${local_path}" 会将容器中的目录copy到数据卷中，直接使用。 

--volumns-from 设定指定容器拥有的数据卷。

-t --tty 表示tty(终端控制台)。

-i --interactive，表示保持stdin打开。 通常与-t同时出现。

--rm 表示退出时即删除容器。不可与-d同时使用。

-c /bin/bash -c "${command}" 表示运行时会执行的脚本。

-e --env 设定容器的环境变量，容器可以直接读取之。

-h --hosename 设定容器的主机名

-p --publish "${local_port}:${host_port} 给容器指定计算机的端口。

-P --publish-all 将主机的高位端口自动映射给容器，使其可以直接访问。

--expose 设定容器使用的端口以及端口范围，与-P一起方才有效。

--link 只能指定与一个运行中的容器进行内部连接。比如在golang中链接redius容器。

--entry-point 覆盖Dockerfile中的ENTRYPOINT
```

#### 管理镜像

下载了之后你不用关系镜像去哪里了。但是你一定想要知道本地有哪些镜像，甚至删除一个镜像。

```shell
docker images
```

可以列出本地所有的镜像。

```shell
➜  ~ docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
ubuntu              latest              56a4fe6a7878        2 weeks ago         120.1 MB
jekyll/jekyll       3.5                 45aa7893f6ec        5 weeks ago         277 MB
➜  ~ 
```

如果你想查看镜像的详细信息，你可以使用inspect命令。

```shell
docker rmi ${image}
```

可以用来删除镜像。

其中${iamge}既可以是镜像的名称也可以是IMAGE ID。通过`docker images` 看到的IMAGE ID只是ID的前12位。比如ubuntu是`56a4fe6a7878`，其实完整的是`56a4fe6a7878a43f591155ed8f426ad857b452b1e42b83c0a702aab260b0efd3`。不过，放心这两个ID可以通用。类似于git里面的COMMIT ID。比如我们删除上面的jekyll。

```shell
➜  ~ docker rmi 45aa7893f6ec
Error response from daemon: conflict: unable to delete 45aa7893f6ec (cannot be forced) - image is being used by running container ed8f7bb79a6f
Error: failed to remove images: [45aa7893f6ec]
```

得到的结果却是失败。这里也需要注意的是正在运行中的镜像是无法被删除的。

#### 搜索镜像

如果你使用Ubuntu的话，你一定对从源里面搜索软件不陌生。那Docker是不是也可以呢？是的，可以。命令是简单的search，即:

> docker search ${key}

比如：

```shell
➜  ~ docker search cowsay
NAME                      DESCRIPTION                                     STARS     OFFICIAL   AUTOMATED
svpooni70/cowsay          cowsay                                          1                    
grycap/cowsay             Alpine-less Cowsay (with Fortune)               1                    [OK]
larv/fortunes-cowsay      ubuntu, fortune, cowsay                         1                    [OK]
```

(结果太多，只列出了部分)

## 容器

容器跟镜像的关系。与很多人而言可能不太清楚镜像和容器的关系。其实很简单，每一个镜像运行起来之后就是一个容器。前者相当于Apk文件，后者相当于安装在手机上面的APP(或者说使用双开/多开助手开出来的APP)。删除容器(APP)不会删除镜像(Apk)，因为完全是两回事。

浓缩成一句：镜像运行后就是容器。

> if an image is a class, then a container is an instance of a class

这样说也不是不可以。

#### 管理

这里讲讲如何管理设备上面的容器。

- **创建**

```shell
docker create
```

除了上面说的docker run。还可以通过create来创建。docker create与前者的区别在于后者只创建不运行。

- **查看**

```shell
docker ps
```

可以查看所有正在运行中的容器。

```shell
docker ps -a
```

可以用来查看所有的容器，包括没运行的。

- **删除**

```shell
docker rm ${container}
```

可以通过"CONTAINER ID"或者"NAME"来删除不在运行状态的容器。同样的，正在运行中的容器你是没法删除的。还可以使用:

```shell
docker rm `docker ps -aq`
```

来删除所有停止运行的容器。

- **起/停**

```shell
docker start/stop ${container}
```

用来停止或者启动容器。

- **暂停**

```shell
docker pause/unpause ${container}
```

可以用来暂停和继续容器，注意此时容器不会退出。

- **杀死**

```shell
docker kill ${container}
```

可以用于杀死容器。容器可能来不及做出响应即退出了。这是与stop的区别。

- **测试**

```shell
➜  ~ docker ps  --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}"
CONTAINER ID        IMAGE               STATUS              NAMES
ed8f7bb79a6f        45aa7893f6ec        Up 18 seconds       gigantic_panini
➜  ~ docker ps  -a --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}"
CONTAINER ID        IMAGE               STATUS                      NAMES
6fcfe45a97d1        alpine              Exited (0) 25 minutes ago   i-am-alpine
8d24db3dc4fb        alpine              Exited (0) 27 minutes ago   hungry_mcnulty
ed8f7bb79a6f        45aa7893f6ec        Up 30 seconds               gigantic_panini
➜  ~ docker rm 8d24db3dc4fb && docker ps  -a --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}"
8d24db3dc4fb
CONTAINER ID        IMAGE               STATUS                      NAMES
6fcfe45a97d1        alpine              Exited (0) 25 minutes ago   i-am-alpine
ed8f7bb79a6f        45aa7893f6ec        Up About a minute           gigantic_panini
➜  ~ docker stop ed8f7bb79a6f && docker ps 
ed8f7bb79a6f
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
➜  ~ docker start ed8f7bb79a6f && docker ps  --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}" 
ed8f7bb79a6f
CONTAINER ID        IMAGE               STATUS                  NAMES
ed8f7bb79a6f        45aa7893f6ec        Up Less than a second   gigantic_panini
```

> 其中`-format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}"`表示格式化输出并只显示ID、镜像、状态和名称。以后会写个专题来讲ps。

#### 进入容器

不论是开发还是运维都会有需要进入容器内部的需求。Docker提供了多种方式，这里主要列出两种：

- **attach**

```shell
docker attach ${container}
```

此种方式可以进入一个正在后台运行的容器。然后在里面执行任务、指令等。但是一旦你exit之后，这个容器也将会自动停止。

- **exec**

```shell
docker exec ${container} ${command}
```

在容器中执行命令，获取结果，但不会停留在容器中。加上-it之后会停留在容器内部的console中，并且可以继续执行其他操作。

```shell
➜  ~ docker exec 8e1e99e5e199 date
Tue Aug 29 18:44:03 UTC 2017
➜  ~ docker exec -it 8e1e99e5e199 /bin/sh
# date
Tue Aug 29 18:44:17 UTC 2017
# exit
➜  ~ 
```

- **其他**

除此之外可以在容器内部安装ssh，然后通过ssh方式登录进去。登录后退出，也不会导致容器连带退出。

#### 命名

命名规则。默认情况下Docker会随机给容器命名，规则为一个形容词加上一个科学家/黑客/工程师的名字中间以下划线"_"隔开。不过你要是不喜欢这种形容词加上人名的方式命名你的容器的话，你可以在run的时候天剑 --name 参数即可。

```shell
➜  ~ sudo docker run alpine
➜  ~ sudo docker run --name i-am-alpine alpine     
➜  ~ sudo docker ps -a --format "table {{.ID}}\t{{.Image}}\t{{.Names}}"
CONTAINER ID        IMAGE               NAMES
6fcfe45a97d1        alpine              i-am-alpine
8d24db3dc4fb        alpine              hungry_mcnulty
ed8f7bb79a6f        45aa7893f6ec        gigantic_panini
```

上面创建了两个容器。可以清楚地看到使用--name之后的容器最终的名字为`i-am-alpine`，这与预期一毛一样。

**重命名**

那如果容器已经运行/创建了，但是手滑我不喜欢这个名字，如何给修改容器的名称呢？Docker提供了rename的命令。具体如下：

```shell
docker rename ${container} ${name}
```
来来来，我们把i-am-alpine改成i-am-alpine2试试：

```shell
➜  ~ sudo docker rename i-am-alpine i-am-alpine2
➜  ~ sudo docker ps -a  --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}"
CONTAINER ID        IMAGE               STATUS                         NAMES
6fcfe45a97d1        alpine              Exited (0) About an hour ago   i-am-alpine2
```

#### 端口

容器的使用还有个很重要的一点就是端口映射。如果不设置映射的话，容器就无法被外部所访问到。

比如我如果运行jekyll容器的话，就需要映射一个外部端口才能在浏览器中访问容器内部。

- **查看端口**

```shell
docker port ${container}
```

例如：

```shell
➜  ~ sudo docker port ed8f7bb79a6f          
4000/tcp -> 0.0.0.0:4000
➜  ~ 
```

列出了容器所有的端口列表。

```shell
➜  ~ sudo docker port ed8f7bb79a6f 4000/tcp
0.0.0.0:4000
➜  ~ 
```

详细列出某个端口的映射情况。


> 设置端口有多种方式。

- **运行镜像时添加参数:**

-p --publish {local_port}:{host_port} 给容器指定计算机的端口。

-P --publish-all 将主机的高位端口自动映射给容器，使其可以直接访问。

--expose 设定容器使用的端口以及端口范围，与-P一起方才有效。

- **DockerFile的EXPOSE**

详见下方的DockerFile。

- **直接修改容器端口**

#### 查看log

```shell
docker logs ${container}
```

Docker支持查看容器运行的log情况。

#### 等待执行

```shell
docker wait ${container}
```

它会阻塞知道容器运行结束。


## 导出/导入

docker支持讲我们的镜像导出成文件，也可以从文件中导入镜像。

下面来看看如何操作：

#### save

将镜像导出并保存为一个文件。此命令只对镜像有用。因为它是对镜像镜像操作，所以镜像本身所有的操作/层级/数据等全部都会被保留下来。

```shell
docker save ${image} > ${file_name}
# 或者
docker save -o ${file_name} ${file_name} 均可
```

实战：

```shell
➜  docker save  -o alpine-0 alpine
➜  docker save alpine > alpine-0-1
➜  ll
total 8280
drwxr-xr-x 2 ram  ram     4096 8月  30 15:29 .
drwxr-xr-x 4 ram  ram     4096 8月  30 15:28 ..
-rw-r--r-- 1 root root 4231680 8月  30 15:28 alpine-0
-rw-r--r-- 1 ram  ram  4231680 8月  30 15:29 alpine-0-1
```

导出的是tar文件。

通过md5比较，你会发现这两个文件一毛一样。

注意，docker save 支持一次性保存多个镜像到一个文件。比如：

```shell
docker save -o multi-images.tar ${container0} ${container1}
```

导入的话，可以通过`load` 即可。如果本地已经存在对应的镜像则会被覆盖。文件中如果有多个镜像的话，会一次性全部导入。

比如：

```shell
sudo docker load -i multi-al-ub-0
```

#### export

与save不同的是，docker只能用来将容器导出为镜像，注意，不是容器。任何的元数据，包括端口映射、CMD、ENTRYPOINT等全部都丢失。据说这个过程中也会丢失原镜像中的commit记录，从而导致文件会比save的方式要小一些。

```shell
docker export ${container} > ${file_name}
# 或者
docker export -o ${container} ${file_name} 均可
```

导出就不做演示了。

来看看导入。它只能将导出的容器导入成镜像。但是我们可以给导入的文件设定镜像名称和版本。在我的电脑上面发现，两次导入使用相同的名称的话，第一次导入的镜像不会被覆盖，但是名字和TAG都变成了`<none>`。

```shell
docker import ${file_name} ${repository}:${tag}
```

#### commit

commit能把容器中所有内容保存为镜像。容器中的变动会生成一个新的层，同时基于原先镜像的层生成镜像。在创建过程中容器会进入pause状态，但不会停止，commit结束之后会继续运行，可以使用--pause==false来禁止这种行为。

```shell
docker commit ${container} ${user}/${name}:${tag}
```

镜像命名空间见上面所述。

比如：

```shell
➜  ~ docker commit 6fcda2c4e3b0 hyongbai/u-ssh      
72520465cb90cb4f3d7fad969e9c4040d2703a57516d9e13514b6fff1916c979
➜  ~ docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
hyongbai/u-ssh      latest              72520465cb90        7 seconds ago       213.8 MB
```

可以看到创建了一个`hyongbai/u-ssh:latest`镜像。

这个镜像运行的话，之前容器里面的东西也都会存在。

####　上传镜像

也可以向git一样，将生成的镜像上传到远端仓库中去。

使用如下命令即可：

```shell
docker push ${user}/${name}:${tag}
```

但是前提是你需要登录／注册到DockerHub。如下:

```shell
➜  ~ docker login
Username: <input>
Password: <input>
Email: <input>
WARNING: login credentials saved in /home/ram/.docker/config.json
Login Succeeded
➜  ~ 
```

#### 总结

最终我测试了一下save方式保存的镜像也可以通过import来导入，但是不能运行。反之export出来的镜像不能load成功。所以，导入的时候记得一一对应。save -> load , export -> import.

## 加速

在国内访问DockerHub速度上面难免会跟不上。好在的是国内有服务商提供了加速功能。

- 阿里云：

你需要去阿里云创建一个账号。然进入教程：

<https://yq.aliyun.com/articles/29941>

- DaoCloud

同样的，你需要去DaoCloud创建一个账号。

然后打开<https://www.daocloud.io/mirror#accelerator-doc>，里面会自动显示出你专有的加速连接。执行它的脚本即可，比阿里云方便多了。

最后，上一张docker lifecycle的图片:

![](https://media.licdn.com/mpr/mpr/shrinknp_800_800/AAEAAQAAAAAAAAS6AAAAJGE2NDg5M2RjLTcxYTQtNDlmYS04OGY5LWI3YmU0Y2UwNjAyZQ.png)

(图自：https://www.linkedin.com/pulse/why-docker-becoming-so-appealing-computer-technology-nizam-muhammad)

## 参考

> <http://dockone.io/article/455>
>
> http://www.linuxeye.com/Linux/2117.html
> 
> <http://paislee.io/how-to-automate-docker-deployments/>
>
> <https://docs.docker.com/engine/reference/commandline/docker/>
>
> <https://tuhrig.de/difference-between-save-and-export-in-docker/>
>
> <https://docs.docker.com/engine/userguide/storagedriver/imagesandcontainers/>
> 