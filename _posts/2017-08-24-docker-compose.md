---
layout: post
title: "Docker练手之Docker Compose"
description: "Docker练手之Docker Compose"
category: all-about-tech
tags: [Docker]
date: 2017-09-25 17:52:57+00:00
---

在实际的生产中使用Docker可能还会设计到很多复杂的需求：比如我们使用golang搭建了一个服务器，但是服务器使用sql是很平常的事情，那我们是不是也要搭建一个sql服务，然后现在redis这么火，我们是不是也要介入呢？

以上这些需求我们使用一个Dockerfile是搞不定，同时我们如果在启动一个容器的时候把相关以来的容器也给启动起来呢？

如果你要一个一个手动启动或者自己用脚本实现，也不是不可以。其实，Docker也想到了这一点，Docker提供了一个很好用的工具：Dockerfile。这就是本文所需要讲述的内容。

## 介绍

为了解决上面提到的问题，Docker Compose就产生了。它实际上使用python编写，然后调用Docker命令。也就是说它是基于Docker进行封装出来的Docker。

其实Docker Compose产生以前叫fig，这一个第三方的团队开发出来的工具。后来整个fig团队被Docker收编了，Docker官方在fig的基础上就产生了Docker Compose。

Docker Compose现已开源：<https://github.com/docker/compose>

![](https://github.com/docker/compose/raw/master/logo.png)

## 安装

首先尝试运行一下`docker-compose version`查看是否有安装，如果安装了的话会出现如下信息：

```shell
➜  ~ docker-compose version
docker-compose version 1.16.1, build 6d1ac21
docker-py version: 2.5.1
CPython version: 2.7.13
OpenSSL version: OpenSSL 1.0.1t  3 May 2016
```

如果你没有安装。那么可以尝试如下三种方式(目前已经支持Windows)：

#### Toolbox(Docker for Mac/windows)

因为我们知道Docker的Toolbox中已经集成了Docker Compose，所以如果你安装了ToolBox的话就等于安装了Docker Compose。不过Docker推荐使用`Docker for Mac`和`Docker for Windows`。

请移步：[Docker-安装]({% post_url 2017-08-24-docker-installation %})

#### pip

因为Docker Compose本身是基于python写的，所以它也发布到了PyPI(the Python Package Index)，因而我们可以使用pip来直接安装。

如下：

```shell
sudo pip install -I six && sudo pip install -I docker-compose
```

安装six是为了解决下面的问题：

> docker-compose ImportError: cannot import name _thread

#### 直接安装

可以去<https://github.com/docker/compose/releases>查看当前最新版本的Docker Compose，目前最新的是1.16.1。

在root用户下面执行下面命令：

```
dockerComposeVersion=1.16.1 && 
curl -L https://github.com/docker/compose/releases/download/${dkcdockerComposeVersion}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
```

下载成功即可。

更多关于Compose安装的信息，请访问：<https://docs.docker.com/compose/install/>


## 模板

也许你会很困惑啥是服务，使用Docker不就是镜像和容器嘛。

其实不然，在Compose中有个很重要的概念是服务，所谓服务就是使用容器提供某种功能，没一个容器都对应着一个服务。反过来，一个服务却可以运行多个容器。后面的scale会讲到这一点。

话说，Compose文件很多命令同Dockerfile是一致的，明白Dockerfile就知道Compose文件中指令的含义和用法了。不过，Compose和Dockerfile不是一个概念的东西，Compose更多像是一个组合里面可以随意配备各种Dockfile来完成复杂的配置。

需要注意的是Compose目前已经经历了三个大的版本了，分别是`version "1"`/`version "2"`/`version "3"`。所以你如果在Compose文件的第一句看到类似标记的话，大概就不会纠结这是啥玩意了。

模板文件不打算写了。可以参考这里的： <https://docs.docker.com/compose/compose-file/>

## 使用

docker-compose提供了丰富的命令供使用，下面就来讲讲这些命令是干嘛的。

### 基本命令：

```shell
Usage:
  docker-compose [-f <arg>...] [options] [COMMAND] [ARGS...]
  docker-compose -h|--help
```

### 参数(Options)

> - -f, --file FILE 指定Compose的模板文件，默认为当前文件夹内的`docker-compose.yml`或者`   Specify an alternate compose file (default: docker-compose.yaml`。
-)
- -p, --project-name NAME 指定项目名称，默认为当前文件夹名称。
- --project-directory PATH 指定工作目录，默认为Compose文件所在的目录。
- --verbose 输出调试信息。
- --no-ansi 不输出ANSI字符
- -v, --version 打印Compose的版本信息同时退出 。
- -H, --host HOST 设定需要连接的   Daemon socket(DOCKER HOST)。
- --tls 使用TLS
- --tlscacert CA_PATH         设定ca证书
- --tlscert CLIENT_CERT_PATH  设定TLS证书
- --tlskey TLS_KEY_PATH       设定Path to TLS key
- --tlsverify                 Use TLS and verify the remote
- --skip-hostname-check       Don't check the daemon's hostname against the name specified in the client certificate (for example if your docker host is an IP address)


> If you want to secure your Docker client connections b is an IP address)
  --project-directory PATH    Specify an alternate working directory (default, you can move the files to the .docker directory in your home directory – and set the `DOCKER_HOST` and `DOCKER_TLS_VERIFY` variables as well (instead of passing -H=tcp://$HOST:2376 and --tlsverify on every call).

>  \$ mkdir -pv ~/.docker
>  \$ cp -v {ca,cert,key}.pem ~/.docker
>  \$ export DOCKER_HOST=tcp://$HOST:2376 DOCKER_TLS_VERIFY=1

也就是说如果将证书们放到`～/.docker/`目录下，则无需制定证书。如果设定了`DOCKER_HOST`和`DOCKER_TLS_VERIFY`这两个环境变量的话，则所有docker操作都是安全连接的。

关于证书相关的内容可以访问：<https://docs.docker.com/engine/security/https/>


### 命令(COMMAND)

运行Compose的时候，同一个service可以使用scale运行多个容器。可以通过`docker ps`来查看。所有带有`--index`选项的命令都可以使用`--index=INDEX`来指定所服务所启动的第INDEX个容器。

- **build**

用来编译Compose工程。默认build所有service，可以指定service。

使用方式：

```shell
Usage: build [options] [--build-arg key=val...] [SERVICE...]
```

它有如下参数：

> - --force-rm              删除中间产生的镜像。
> - --no-cache              编译时不使用cache(也就是说如果之前编译过，不管配置是不是有变化，都会重新编译，镜像的创建时间永远都会是最新的)。
> - --pull                  永远都尝试使用更新版本的镜像。
> - --build-arg key=val     给一个服务(镜像)设置编译时的变量。

- **bundle**

可以讲Compose文件转化成dab格式的文件，以利于集群部署。

```shell
Usage: bundle [options]
```

参数：

> - --push-images Automatically push images for any services which have a `build` option specified.
- -o, --output PATH Path to write the bundle file to. Defaults to "<project name>.dab".

镜像必须要包含有digests，否则无法成功。使用build(Dockerfile)方式则不能成功(why? TBC)。

- **config**

用来查看Compose文件的配置信息。

```shell
Usage: config [options]
```

> - --resolve-image-digests 将image替换成对应的digests比如：python:3.4-alpine ➜ python@sha256:f16b79650e7ae62a34ce363aed0d875a35bf5c21efe0efa25c001683b0db9148
- -q, --quiet 安静模式，什么也不输出
- --services 打印所有的服务
- --volumes 打印所有的数据卷

- **create**

用以为service创建(镜像)容器。

```shell
Usage: create [options]
```

参数包括：

> - --force-recreate
> - --no-recreate
> - --no-build            
> - --build

含义同up中一致。

- **down**

用以删除up创建出来的容器、数据卷、镜像等。

 > - --rmi type 只能是`all`和`local`之一，前者表示删除服务所用到的所有镜像; 后者表示只删除使用`image`字段时未设定custom tag的镜像。(正在被容器使用的镜像则无法被删除)
> - -v, --volumes 删除通过`volumes`设定的数据卷或者使用到的匿名数据卷。(匿名?what?)
> - --remove-orphans 删除所有在Compose文件中未设定的容器。

默认情况下删除Compose中定义的容器/`networks`字段定义的网络/默认的网络。另：标记为`external`的volumn以及network将无法被删除。关于network请参见：<https://docs.docker.com/compose/networking/> 和 <https://docs.docker.com/compose/compose-file/#network_mode>

- **events**

用来输出Compose里面service对应的container的events。所谓events就是容器各种状态切换产生的事件，比如start/attach/kill/die/stop等等，同`docker events`。

```shell
Usage: events [options] [SERVICE...]

Options:
    --json      表示将结果以json形式输出
```

如果不添加SERVICE的话，显示的是Compose中所有的service。

输出结果如下:

```
2017-09-07 10:27:28.987936 container attach be4c432e4dbca24a0ef12f0a19430e2748012934b0eb6d072fc2f248866fd41a (image=redis, name=compheello_redis_1)
2017-09-07 10:27:29.193309 container start be4c432e4dbca24a0ef12f0a19430e2748012934b0eb6d072fc2f248866fd41a (image=redis, name=compheello_redis_1)
2017-09-07 10:27:29.389165 container attach ebd8f341cce0475f94a0823d537c6f737e3cee0ff56ad033ea34bb7ef25d6905 (image=compheello_webs, name=compheello_webs_1)
2017-09-07 10:27:29.535163 container start ebd8f341cce0475f94a0823d537c6f737e3cee0ff56ad033ea34bb7ef25d6905 (image=compheello_webs, name=compheello_webs_1)
2017-09-07 10:29:59.441448 container kill ebd8f341cce0475f94a0823d537c6f737e3cee0ff56ad033ea34bb7ef25d6905 (image=compheello_webs, name=compheello_webs_1)
2017-09-07 10:29:59.520446 container die ebd8f341cce0475f94a0823d537c6f737e3cee0ff56ad033ea34bb7ef25d6905 (image=compheello_webs, name=compheello_webs_1)
2017-09-07 10:29:59.924449 container stop ebd8f341cce0475f94a0823d537c6f737e3cee0ff56ad033ea34bb7ef25d6905 (image=compheello_webs, name=compheello_webs_1)
2017-09-07 10:29:59.942493 container kill be4c432e4dbca24a0ef12f0a19430e2748012934b0eb6d072fc2f248866fd41a (image=redis, name=compheello_redis_1)
2017-09-07 10:30:00.084357 container die be4c432e4dbca24a0ef12f0a19430e2748012934b0eb6d072fc2f248866fd41a (image=redis, name=compheello_redis_1)
2017-09-07 10:30:00.524794 container stop be4c432e4dbca24a0ef12f0a19430e2748012934b0eb6d072fc2f248866fd41a (image=redis, name=compheello_redis_1)
```

- **exec**

等同于`docker exec`，即连接到container内部，方便执行命令。

- **kill**

强制停止当前正在运行的container。

```shell
Usage: kill [options] [SERVICE...]
Options:
-s SIGNAL 可以添加signal
```

比如：

```shell
docker-compose kill -s SIGINT
```

- **logs**

查看service中的log。类似`docker logs`。

- **pause/unpause**

暂停容器的service。如果pause了web依赖的redius的话，web仍然正常运行，但是调用redis的地方会block住直到redis被`unpause`。

- **port**

类似于`docker port`用于查看service内部某个port被使用的情况。

用法：

```shell
Usage: port [options] SERVICE PRIVATE_PORT

Options:
--protocol=proto  tcp or udp [default: tcp]
--index=index 
```

使用，比如：

```shell
➜  comp_heello  docker-compose port webs 5000
0.0.0.0:5000
```

- **ps**

同`docker ps`

用法：

```shell
Usage: ps [options] [SERVICE...]

Options:
-q    只显示id
```

比如：

```shell
➜  comp_heello dkcom ps  
       Name                     Command               State           Ports         
------------------------------------------------------------------------------------
compheello_redis_1   docker-entrypoint.sh redis ...   Up      6379/tcp              
compheello_webs_1    python app.py                    Up      0.0.0.0:5000->5000/tcp
```

- **pull/push**

类似与`docker pull/push`

用法：

```shell
Usage: pull [options] [SERVICE...]

Options:
    --ignore-pull-failures  Pull what it can and ignores images with pull failures.
    --parallel              Pull multiple images in parallel.
    --quiet                 Pull without printing progress information
```

```shell
Usage: push [options] [SERVICE...]

Options:
    --ignore-push-failures  Push what it can and ignores images with push failures.
```

注意：处于pause状态下的服务(容器)只能通过unpause才能进行其他操作，比如你不能stop/kill一个pause状态下的服务(容器)。

- **restart/start/stop**

仅仅用以重启Compose里停止的或者正在运行中的service，并不会执行build等行为。也就是说使用这个命令来重启你的service，即使你的Compose文件或者Dockerfile有变化的话，重启的过程中也[不会]涉及到重新build image以及run image/container等。

```shell
Usage: restart [options] [SERVICE...]

Options:
-t, --timeout TIMEOUT      设定关闭容器所需要的以秒为单位的超时时间，默认是10秒。
```

上面提到了可以用来重启停止的或者正在运行中的，那么其他状态的比如pause状态的服务(容器)是否可以重启呢？答案当然是否定的。

同理`docker-compose start`和`docker-composer stop`也是一样的。不过，start并无timeout选项。

- **rm**

用以删除所有「停止」状态的服务(容器)。同`docker rm`一样，删除容器的时候，会将容器内部产生的所有数据给删除。但是，莫热情况下容器挂载的数据卷(VOLUMN)并不会一同被删掉。

如果当前的服务不是停止状态的话，要怎么操作呢？下面看看Options。

```shell
Usage: rm [options] [SERVICE...]

Options:
    -f, --force   删除的时候不寻求确认。默认需要输入`y`(Are you sure? [yN] )
    -s, --stop    删除之前停止当前的服务(非pause状态)
    -v            删除容器挂载的「匿名」VOLUMN，非匿名的不受影响。
```

如果不指定service(无法添加index)，那么所有的service都会被删除。

- **run**

顾名思义，用来运行Compose里面一个服务。类似与`docker run`，如果没有build过，那么他会自动build，然后再运行。


用法：

```shell
Usage: run [options] [-v VOLUME...] [-p PORT...] [-e KEY=VAL...] SERVICE [COMMAND] [ARGS...]

Options:
    -d                    后台运行
    --name NAME           给运行起来的容器命名
    --entrypoint CMD      即ENTRYPOINT
    -e KEY=VAL            设定环境变量
    -u, --user=""         指定运行的用户
    --no-deps             不启动连接的服务(运行后基本执行到需要的服务的地方肯定会报错)
    --rm                  容器停止之后会被自动删除
    -p, --publish=[]      发布/绑定端口
    --service-ports       映射Compose中设定的ports端口
    -v, --volume=[]       绑定数据卷
    -T                    停用pty(pseudo-tty, 伪终端)
    -w, --workdir=""      设定容器运行时的WORKDIR
```

> 注意：
- Compose指定的ports将不会被publish，需要你通过`-p`/`--publish`/`--service-ports`选项来publish。。
- run时如果已经build过或者说已存在镜像，则不管Compose文件等有没有变化都不会再次build。
- 如果未指定名字则每次都会创建新容器。命名规则为: `{project}_{service}_run_{INDEX}`。比如：`heello_webs_1`/`heello_webs_2`等
- stop时，links了的服务不会被停掉。

- **scale**

目前已废弃。使用up里面的`--scale`选项即可。

- **top**

在linux/mac上面运行过top的应该知道。没什么好说的。

- **up**

```shell
docker-compose up [options]
```

这个是`docker-compose`中最重要的一个命令，它包含了下载、构建、创建、运行等等系列行为。一般情况下是只要你写好了yml文件，直接使用up就可以坐等container运行起来了。

当然了up本身也包含了一系列的操作，下面是其带有的参数列表。

参数：

> 
- -d daemon 后台运行
- --no-color log中不用颜色区分container
- --no-deps  不启动关联容器
- --force-recreate  强制重新创建容器(即使容器配置以及镜像均未发生任何变化)
- --no-recreate 如果容器已经存在，那么不重新创建。与`--force-recreate`互斥。
- --no-build 即使镜像不存在，也不build。
- --build 默认，如果镜像不存在则编译镜像。
- --abort-on-container-exit 任何一个容器退出则停止其他所有的容器，与`-d`互斥。
- -t, --timeout TIMEOUT 单位：秒，默认10;用来关闭器已经attached或者正在运行的容器的超时值。
- -remove-orphans 删除构建时产生的且不被使用到的镜像。
- --exit-code-from SERVICE 返回选中容器的返回值。
- --scale SERVICE=NUM 用来指定启动的service的对应的容器的数量，比如--scale web=2，表示启动2个web容器。集群可能会更有用。

比如：

```shell
docker-compose -f ~/docker/test/comp.yml -p heeelo/ up -d
```

不出错你就可以使用`docker ps`或者`docker-compose ps`查看到当前正在运行的容器了。

## 实例

默认情况下新建一个文件夹，然后这个文件夹就是project名字，Compose名字要写成`docker-compose.yml`或者`docker-compose.yaml`。其实也是可以通过-p来指定project名，通过-f来指定Compose文件。

也许你还不太清楚project名字是啥意思，运行之后你可以通过`docker images`来查看当前所有的镜像，你会发现你写的镜像名前面都加上的前缀为project名。最后加上service的index(从1开始)

下面是不同的project名生成的镜像。

```shell
REPOSITORY      TAG    IMAGE ID      CREATED         VIRTUAL SIZE
compheello_webs latest 3e6dc8506089  10 minutes ago  684.7 MB
hellllo_webs    latest 3e6dc8506089  10 minutes ago  684.7 MB
compose_webs    latest 3e6dc8506089  10 minutes ago  684.7 MB
```

下面是镜像运行出来的容器：

```shell
CONTAINER ID  IMAGE            NAMES
0c45b74e3974  hellllo_webs     hellllo_webs_1
43e646ddb134  compheello_webs  compheello_webs_1
4fad97773f08  compose_webs     compose_webs_1
```
 
容器名就是在镜像名的基础上添加了数字。

## 实例

随便创建一个文件夹，比如叫做`compose/`，然后在里面创建如下文件。

(实例来自docker官方)

- **Dockerfile**

```shell
FROM python:3.4-alpine
ADD app.py /
RUN pip install flask redis
CMD ["python", "app.py"]
```

- **compose.yml**

```shell
version: '3'
services:
  web:
    build: .
    ports:
     - "5000:5000"
  redis:
    image: "redis:4.0.1-alpine"
```

其中`web`和`redis`都是这个Compose文件中的service。

- **app.py**

```python
// app.py
from flask import Flask
from redis import Redis

app = Flask(__name__)
redis = Redis(host='redis', port=6379)

@app.route('/')
def hello():
    count = redis.incr('hits')
    return 'Hello World! I have been seen {} times.\n'.format(count)

if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)
```

- 运行

![](http://7xkm4a.com1.z0.glb.clouddn.com/Screenshot%20from%202017-09-25%2018-52-24.png)

去浏览器访问: <http://0.0.0.0:5000> 可以看到：

> Hello World! I have been seen 1 times. 

## 参考

> <http://dockone.io/article/834>
>
> <https://docs.docker.com/compose/>
>
> <https://docs.docker.com/compose/compose-file>
>
> <http://www.cnblogs.com/nufangrensheng/p/3512548.html>
>
> <https://docs.docker.com/engine/security/httpscompose/>
>
> <https://yeasy.gitbooks.io/docker_practice/content/compose/>
>
> <https://htmlpreview.github.io/?https://github.com/redhat-developer/docker-java/blob/javaone2015/readme.html#Docker_Compose>
>
> <>
