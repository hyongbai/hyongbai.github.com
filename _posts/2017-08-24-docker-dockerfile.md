---
layout: post
title: "Docker练手之Dockerfile"
description: "Docker练手之Dockerfile"
category: all-about-tech
tags: [Docker]
date: 2017-09-02 12:52:57+00:00
---

Docker可以通过从文件中读取指令集来生成镜像，而这个文件有个专有的名称叫做Dockerfile。

使用Dockerfile的好处在于，我们可以设定更多更加复杂的构建脚本，从而让Docker实现更加高级的功能。

好吧，今天来看看如何使用Dockerfile。

## DockerFile

它的指令格式，很简单。如下：

```shell
# Comment
INSTRUCTION arguments
```

Dockerfile中的指令(INSTRUCTION)理论上来说是支持大小写混用的，但是通常情况下都是用大写格式的。为什么呢？方便跟参数区分出来呗。

Dockerfile的使用方式很简单。进入Dockerfile所在的目录，然后运行：

```shell
docker build .
```

下面一个个来讲每个指令的用法。

#### FROM

Dockerfile必须以FROM开头，因为得有一个镜像。所以FROM的参数是各种镜像。镜像名称同run时通用的。也就是说如果你不给镜像添加tag的话，默认使用的是latest。但，不建议使用latest。

Dockerfile其实不一定必须以FROM开头，按照Docker[官方解释](https://docs.docker.com/engine/reference/builder/#understand-how-arg-and-from-interact)FROM可以放到ARG后，然后在FROM中使用ARG指定的值。ARG后面会讲。

实例：

```shell
➜  cat Dockerfile
FROM node:7
ADD . /app
RUN cd /app && npm install
LABEL name=ram id=hyongbai
CMD npm start
➜  docker build -t hyongbai/node:sample .
Sending build context to Docker daemon 2.048 kB
Step 1 : FROM node:7
7: Pulling from library/node
7564fb0f3938: Pulling fs layer 
7564fb0f3938: Pull complete 
43f326cb77bd: Pull complete 
67c1a72d1602: Pull complete 
51b7de53e972: Pull complete 
90d5a308bbca: Pull complete 
65895c3fa824: Pull complete 
86ae4e8c9d97: Pull complete 
80dff7583398: Pull complete 
31cb13952787: Pull complete 
715d3161cc24: Pull complete 
12a756bb98e4: Pull complete 
503c0dbb7493: Pull complete 
0024fae396a7: Pull complete 
cc56e1a043b2: Pull complete 
Digest: sha256:26cc5a2828d1fcc7b5171484795e12422ffefa8472e62cbd1d8afc7912a7cfdc
Status: Downloaded newer image for node:7
 ---> cc56e1a043b2
Step 2 : ADD . /app
 ---> e9b62845a58a
Removing intermediate container f781546cd7ba
Step 3 : RUN cd /app && npm install
 ---> Running in dae600ba37cd
 ...
 ---> 5959f92b67ad
Removing intermediate container dae600ba37cd
Step 4 : CMD npm start
 ---> Running in afa614bc1e1c
 ---> e0d299aa607f
Removing intermediate container afa614bc1e1c
Successfully built e0d299aa607f
➜  docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
hyongbai/node       sample        aa39ebe8c4f9        3 minutes ago       660.4 MB
```

上面表示基于node:7来构建镜像，最终生成了一个`hyongbai/node:sample`镜像。

```shell
FROM scratch
```

scratch是Docker里面一个很特殊的镜像，特殊在它是一个空。

#### MAINTAINER

即维护者，相当于给这个镜像署名，用以指定作者的名字(信息)。

比如：

```shell
MAINTAINER ram "hyongbai@gmail.com"
```

当然还有一种方式来指定maintainer信息。往下看。

#### LABEL

在构建的时候我们可以使用LABEL指令给镜像中添加元数据。元数据是键值对的形式，添加多个时键值对之间需要以空格隔开。最后在生产的镜像中我们可以通过inspect来看到镜像中带有的元数据。比如上面的Dockerfile中加上了`LABEL name=ram id=hyongbai`。

```shell
"Labels": {
    "id": "hyongbai",
    "name": "ram"
}
```

上面提到了MAINTAINER，其实也可以通过LABEL来生成。如下：

```
LABEL maintainer="ram \"hyongbai@gmail.com\""
```

#### ENV

ENV是环境变量的意思。也就是说我们可以通过ENV指令来给镜像设定环境变量，且后面的指令也可以直接使用。

比如：

```shell
ENV user=ram
ENV user ram
```

这两种方式都是可以的。

对了，不仅仅是Dockerfile中可以用，当我们运行构建出的镜像的容器的时候也可以直接读取到的。

#### ARG

ARG是一个神奇的东西，它可以创建构建镜像时使用的变量。神奇的是构建是它可以使用--build-arg {varname}={value}来更改它。可以设定多个。

基本用法：

```shell
ARG site=github
RUN echo "${site}
```

要想修改的话：

```shell
docker build --build-arg site=google .
```

#### WORKDIR

用来设定构建环境的工作目录。

```shell
# Dockerfile

FROM alpine:3.6
ARG host
WORKDIR ${host}
RUN pwd && touch abc && ls -l && cd /
RUN pwd && ls -l

# buil

Sending build context to Docker daemon 3.584 kB
Step 1 : FROM alpine:3.6
 ---> a084521541f8
Step 2 : ARG host
 ---> Running in 5358702e0652
 ---> 8b7574b1a413
Removing intermediate container 5358702e0652
Step 3 : WORKDIR ${host}
 ---> Running in 0585b8142618
 ---> 53d7e4fb4f64
Removing intermediate container 0585b8142618
Step 4 : RUN pwd && touch abc && ls -l && cd /
 ---> Running in fc5ff7b8aa1e
/hello
total 0
-rw-r--r--    1 root     root             0 Sep  1 10:10 abc
 ---> ab8c7c2e75ef
Removing intermediate container fc5ff7b8aa1e
Step 5 : RUN pwd && ls -l
 ---> Running in 315a66f3b6d3
/hello
total 0
-rw-r--r--    1 root     root             0 Sep  1 10:10 abc
 ---> 161b11ede2b1
Removing intermediate container 315a66f3b6d3
Successfully built 161b11ede2b1
```

上面的示例中的两个RUN指令都是在WORKDIR里面进行的。而且虽然上一个指令最后进入了根目录“/”，但是下一个指令仍然实在WORKDIR。这也验证了Docker指令与指令之间是相互独立的这个事实。

#### EXPOSE

用来暴露镜像中的接口的。暴露的接口不一定就是发布的，也就是说还需要跟主机的接口映射上。当我们的创建容器的时候添加"-P"时，Docker会自动将主机的高位端口(40000+)映射到我们EXPOSE出来的端口。

基本用法：

```shell
EXPOSE {port1} {port2} ...
```

#### RUN

用来实现命令，后面的参数可以是镜像支持的脚本命令，比如shell命令等。需要注意的是，Dockerfile里面每一个指令都代表着一层，产生的信息都会被记录下来。而且层与层之间是相互独立的，不同于我们在terminal里面的执行环境。其实Docker的镜像也是基于层的概念来建立的，下一个指令是基于当前的镜像镜像commit，也就是说是产生的是一个新的镜像，所以上一层产生中间环境都无法在下一层中继续使用。

基本用法：

```shell
RUN <command> 
RUN ["executable", "param1", "param2"] (exec form)
```

实战：

```shell
➜  cat run/Dockerfile 
FROM alpine:3.6
ADD . app/
RUN cd app/ && ls
RUN ls
➜  sudo docker build -f run/Dockerfile run
Sending build context to Docker daemon 2.048 kB
Step 1 : FROM alpine:3.6
 ---> a084521541f8
Step 2 : ADD . app/
 ---> be7f81e1442b
Removing intermediate container 761b53e9558b
Step 3 : RUN cd app/ && ls
 ---> Running in 60ef40115508
Dockerfile
 ---> 92e7ea9e2d1e
Removing intermediate container 60ef40115508
Step 4 : RUN ls
 ---> Running in 66ee5351cc81
app
bin
dev
etc
home
lib
media
mnt
proc
root
run
sbin
srv
sys
tmp
usr
var
 ---> f11e72ed2dfa
Removing intermediate container 66ee5351cc81
Successfully built f11e72ed2dfa
```

上面可以看到第一句`RUN cd app/ && ls`和第二句`RUN ls`产生的结果是不一样的，也就证明了第二次RUN不在第一次RUN执行的结果中。

- **shell**

> RUN的shell格式指令，默认在linux上面运行在`/bin/sh -c`，在Windows上面运行在`cmd /S /C`环境中。

RUN也支持一次执行多个命令(其实上面例子中的`RUN cd app/ && ls`就是两个命令)，其实是同shell的写法一致。比如：

```shell
# 下面前两个正常情况下结果是一致的。关于他们的不同，自行Google吧。
RUN cd app/; ls
RUN cd app/ && ls
RUN cd app/ || ls

# 也支持使用"\"换行:
RUN cd app/;\
ls

# 但是不支持下面这种在shell中支持的换行方式：
RUN cd app/ &&
ls
```

- **exec**

上面提到了RUN支持shell格式和exec格式，这两种方式。

使用exec方式时，所有的参数都必须包在一对双引号中间，如果你想输出双引号的话，你得转义。

第一个参数表示指令，后面都是参数，此时参数中的变量将会被当做字符串处理。但是，通常情况下我们需要将变量打印出来，此种情况下你需要在前面插入`"/bin/sh", "-c"`两个参数。

如下：

```shell
# Dockerfile
FROM alpine:3.6
RUN echo "HOME = $HOME"
RUN ["echo","HOME = $HOME"]
RUN ["/bin/sh", "-c" , "echo HOME = $HOME"]

# 运行结果
➜  sudo docker build -f run/Dockerfile run
Sending build context to Docker daemon 2.048 kB
Step 1 : FROM alpine:3.6
 ---> a084521541f8
Step 2 : RUN echo "HOME = $HOME"
 ---> Running in 50c68c66623e
HOME = /root
 ---> eaeff82961f7
Removing intermediate container 50c68c66623e
Step 3 : RUN echo HOME = $HOME
 ---> Running in e5ec2587403c
HOME = $HOME
 ---> 10bbbe88ad63
Removing intermediate container e5ec2587403c
Step 4 : RUN /bin/sh -c echo HOME = $HOME
 ---> Running in 8e15bd8eb2ae
HOME = /root
 ---> 20a09104500a
Removing intermediate container 8e15bd8eb2ae
Successfully built 20a09104500a
```

可以看到使用shell的方式可以读取变量中的值，而使用exec则不行，但是在exec前添加`/bin/sh -c`又可以读取了。为什么呢？

首先，shell可以读出来，是因为shell默认使用的是`/bin/sh -c`来解释的。也就是说它直接就是第三种。

其次，exec不能读，是因为它直接执行的是其命令本身，而不经过shell解释器。

更多详细介绍可以参考：[Docker官方关于RUN的介绍](https://docs.docker.com/engine/reference/builder/#run)。

#### CMD

用法以及规则同RUN，也是写在Dockerfile中用来执行命令的。与RUN不同的是，不论你写多少条CMD，只有最后一条才会生效。

不是说每一条指令都是一层并且创建一个commit，那么为什么之后之后一条生效呢？因为CMD不是在构镜像时使用的，它只会在【容器】运行的时候运行。因此Docker可以实现最后一条生效。

除了RUN的两种写法，CMD还有另外一种写法。

```shell
CMD ["param1", "param2"]
```

这种exec方式移除了`executable`，那，没有了指令还玩啥啊？没关系，不是没有指令吗，Docker把两个参数当做另一个指令的参数来用，而这个指令就是`ENTRYPOINT`。

既然前有RUN后有ENTRYPOINT，那么我要你有何用。老话说存在即合理，那来看看CMD是有什么而另外两个都没有的呢？还真有，就是在运行镜像的时候CMD指令是可以被运行指令中带的cmd指令给替换掉。比如:

```shell
docker run my-image /bin/bash -c "ls -l"
```

执行之后Dockerfile中定义的CMD将不会被执行。

实战操作：

```shell
# Dockerfile文件内容
➜  dockerfile cat shell/df                                                         
FROM alpine:3.6
CMD echo "HELLO FROM CMD"

# 编译镜像
➜  dockerfile sudo docker build -t hyongbai/dfshell -f shell/df .                                 
Sending build context to Docker daemon 6.656 kB
Step 1 : FROM alpine:3.6
 ---> a084521541f8
Step 2 : CMD echo "HELLO FROM CMD"
 ---> Running in 273247f2596c
 ---> 405a157a781e
Removing intermediate container 273247f2596c
Successfully built 405a157a781e

# 不带command运行镜像
➜  dockerfile sudo docker run hyongbai/dfshell                                     
HELLO FROM CMD

# 带command运行镜像
➜  dockerfile sudo docker run hyongbai/dfshell /bin/sh -c "echo \"hello from run\""  
hello from run
```

#### ENTRYPOINT

既然CMD可以当做ENTRYPOINT的参数，那么可想而知ENTRYPOINT也是只能在容器运行时作用，跟创建镜像没有啥关系。

用法以及规则同RUN。但是，当同时存在CMD和ENTRYPOINT时，前者(即CMD，包含参数中运行添加的cmd命令)将不会执行。

```shell
# Dockerfile文件
➜  dockerfile cat shell/df 
FROM alpine:3.6
RUN echo "HELLO FROM RUN"
CMD echo "HELLO FROM CMD"
CMD echo "HELLO FROM CMD2"
ENTRYPOINT echo "HELLO FROM ENTRYPOINT"
ENTRYPOINT echo "HELLO FROM ENTRYPOINT2"

# 编译镜像
➜  dockerfile sudo docker build -t hyongbai/dfshell-multi -f shell/df .            
Sending build context to Docker daemon 6.656 kB
Step 1 : FROM alpine:3.6
 ---> a084521541f8
Step 2 : RUN echo "HELLO FROM RUN"
 ---> Running in 80ba67d8f2fc
HELLO FROM RUN
 ---> 7e46a2fcc7f1
Removing intermediate container 80ba67d8f2fc
Step 3 : CMD echo "HELLO FROM CMD"
 ---> Running in d9f0f67d5426
 ---> a73d178d9175
Removing intermediate container d9f0f67d5426
Step 4 : CMD echo "HELLO FROM CMD2"
 ---> Running in 246b895c9413
 ---> eca8e42b75b6
Removing intermediate container 246b895c9413
Step 5 : ENTRYPOINT echo "HELLO FROM ENTRYPOINT"
 ---> Running in 668cde2c5287
 ---> a16fe68c522b
Removing intermediate container 668cde2c5287
Step 6 : ENTRYPOINT echo "HELLO FROM ENTRYPOINT2"
 ---> Running in 1f9b0579479a
 ---> 34b169a7f29e
Removing intermediate container 1f9b0579479a
Successfully built 34b169a7f29e

# 运行，不加外部命令
➜  dockerfile sudo docker run hyongbai/dfshell-multi                  
HELLO FROM ENTRYPOINT2

# 运行，加外部命令
➜  dockerfile sudo docker run hyongbai/dfshell-multi /bin/sh -c "echo \"hello from run\""
HELLO FROM ENTRYPOINT2
```

这里可以完整看到：

- ENTRYPOINT只会执行最后一个。
- 有ENTRYPOINT时，CMD不会执行。
- 有ENTRYPOINT时，即使是外部的cmd也会被覆盖掉。
- RUN只在编译镜像时运行, CMD和ENTRYPOINT则只能在运行容器时运行。

#### SHELL

可以用来修改默认的shell，在1.12以及后面版本的Docker上才有。且可以多次修改，修改时不会改变前面的指令，只会影响后续后的指令。

在linux上面你可以在sh/bash/zsh等之间切换。

修改SHELL需改根据镜像基于的操作系统而定，也就是说此系统支持你才能修改。

基本用法：

```shell
SHELL ["executable", "parameters"]
```

实战操作：

```shell
# 切换到sh
SHELL ["/bin/sh", "-c"]
# 切换到zsh
SHELL ["/bin/zsh", "-c"]
# 切换到bash
SHELL ["/bin/bash", "-c"]
# 切换到powershell
SHELL ["powershell", "-command"]
# 切换到cmd
SHELL ["cmd", "/S"", "/C"]
```

这里简单解释下上面提到的"parameters"，以`zsh`为例：`-c`的command，表示后面所有的参数都被当做command执行。但是，我用RUN或者CMD等的时候明明都是command啊，那为什么不能一定要加`-c`呢？很简单，因为zsh本身也提供了各种各样的参数，你不加`-c`它怎么知道你这个是comamnd参数呢。

通过上面RUN关于`shell`/`exec`/`/bin/bash -c exec`的不同可以知道，指定的SHELL只对shell方式执行的指令(RUN/CMD/ENTRYPOINT)有效，对exec完全不起作用。第三种方式的exec需要手动指定shell解释器，完全不是自动的，也就是说不管SHELL设定了什么，一切都以你运行时指定的为准，因此说SHELL完全不能操作于exec。

#### ADD

Dockerfile支持将文件复制到镜像中去。这个文件可以是本地地址，也可以是远端地址。使用方法也很简单：

```shell
ADD <src>... <dest>
ADD ["<src>",..., "<dest>"]
```

按照Docker官方的说法，含有空格的地址需要使用第二种方式。

所有创建的文件或者文件夹的GID和UID都将会是0.

**源地址**

`<src>`既可以文件、文件夹也可以是网络地址（远端地址）。**注意**:此地址必须是相对于上下文地址的子路径(即：不存在`../path`)，也不能是绝对路径(即：不存在/path)。即`path/`或者`path/...`

`<src>`支持Go's的`filepath.Match`规则的通配符。下面给出官方的示例：

```shell
ADD hom* /mydir/        # adds all files starting with "hom"
ADD hom?.txt /mydir/    # ? is replaced with any single character, e.g., "home.txt"
```

值得提醒的是：复制的是文件夹里面的所有内容，而不是整个文件夹。

- 远程地址

创建出来的文件的权限都将是600.如果当前的http请求中包含了`Last-Modified`这个HEADER的话，此时间将会设定再文件的`mtime`上面(所谓mtime是指文件的上次更改时间)。

> 如果远程路径需要验证的话，你需要先使用`RUN get/curl`将其预先下载下来。因为ADD本身不支持身份验证。

> 远程文件会先下载到物理设备中，然后再从物理社保copy到镜像中去，而不是直接下载到镜像中去的。

- 上下文(Context)

使用Dockerfile构建镜像的时候很重要的一个概念，就是上下文。首先，上下文是指路径。其次，上下文不等同于Dcokerfile所在的路径。因为上下文是需要指定的。比如，`docker build .`表示当前路径是上下文。再比如同一个Dockerfile，`docker build -f app/cmd/Dockerfile app/`表示当前路径下的`app/`是上下文。

下面是实际操作：

```shell
# 这个是Dockerfile文件内容

FROM alpine
ADD . /hello
RUN ls -l /hello

# 这个是在test-docker/目录运行。当前目录下面有一个文件叫做123

➜  test-docker docker build .   
Sending build context to Docker daemon 3.584 kB
Step 1 : FROM alpine
 ---> a084521541f8
Step 2 : ADD . /hello
 ---> 5bf0746b6116
Removing intermediate container b4178eb2d5a9
Step 3 : RUN ls -l /hello
 ---> Running in 566084a12c9a
total 8
-rw-r--r--    1 root     root            42 Aug 31 19:20 Dockerfile
-rw-r--r--    1 root     root             0 Aug 31 19:21 abc
drwxr-xr-x    2 root     root          4096 Aug 31 19:21 app
 ---> 49a92dfe1497
Removing intermediate container 566084a12c9a
Successfully built 49a92dfe1497

# 这个是创建了一个子文件夹app/, 并在其中创建文件123，并将Dockerfile放到子目录cmd/中

➜  test-docker docker build -f app/cmd/Dockerfile app
Sending build context to Docker daemon 3.072 kB
Step 1 : FROM alpine
 ---> a084521541f8
Step 2 : ADD . /hello
 ---> 5c36e2d3f4d0
Removing intermediate container 03b0936341cf
Step 3 : RUN ls -l /hello
 ---> Running in 74b33361f531
total 4
-rw-r--r--    1 root     root             0 Aug 31 19:21 123
drwxr-xr-x    2 root     root          4096 Aug 31 19:24 cmd
 ---> 1cb804777c96
Removing intermediate container 74b33361f531
Successfully built 1cb804777c96
```

他们都是再同一个目录中执行的命令。当不指定Dockerfile时，使用的是当前目录中的Dockerfile，同时指定上下文为当前文件夹，那么镜像中当前路径下的所有文件，即：Dockerfile、abc和app文件。当指定子目录app/cmd中的Dockerfile，并且指定上下文为app/时，镜像中有的是abc目录下的所有文件而不是当前目录。有此可以证明上下文与当前执行路径以及Dockerfile所在路径并无直接关系。

*注意*，Dockerfile不能超出上下文路径。也就是说要么同级，要么在上下文子目录中。

> 也可以不指定上下文，但是只能通过STDIN这种方式。比如:`docker build - < ${file}`。如果文件是压缩文件，那么Docker会自动从压缩文件的根目录查找Dockerfile，其他文件将被当作是上下文。

**目标地址**

`<dest>`地址必须是绝对路径，也就是容器中的地址。但是如果是你设定了`WORKDIR`的话，你写的相对路径都是相对于`WORKDIR`的地址。只有此两种方式。下面给出官方示例：

```shell
ADD test relativeDir/          # adds "test" to `WORKDIR`/relativeDir/
ADD test /absoluteDir/         # adds "test" to /absoluteDir/
```

后面的注释很能说明问题了。

- 如果`<src>`是URL，`<dest>`不是以"/"结尾的话，那么镜像里面的目标文件名将为`<dest>`；
- 如果`<src>`是URL，`<dest>`是以"/"结尾的话，那么镜像中目标文件的路径将为`<dest>/<filename>
- 如果`<src>`是URL，那么它必须一个能够发现文件名称的地址，比如："http://google.com/file"是合法的，"http://google.com"则是不受支持的。
- 如果`<src>`是本地路径，且是特定格式的压缩文件(identity, gzip, bzip2 or xz等文件)，则是复制并自动解压到目标目录，并且在目标路径源压缩文件4中会被自动删除掉。

实际操作：

```shell
FROM alpine:3.6
ADD . /local0
ADD df /local1
ADD df /local2/
ADD con.tar /local3
ADD con.tar /local4/
ADD con.zip /local5
ADD "http://0.0.0.0:8000/con" /remote0
ADD "http://0.0.0.0:8000/con.tar" /remote1
ADD "http://0.0.0.0:8000/con.tar" /remote2/
ADD "http://0.0.0.0:8000/con.zip" /remote3/
ADD "http://0.0.0.0:8000/dir" /remote4
ADD "http://0.0.0.0:8000/dir" /remote5/
ENTRYPOINT ls -l /local* /remote* /dir*

➜  docker build -t hyb/df-add -f add/df add && docker run --name df_add hyb/df-add
// 省略编译
-rw-------  1 root  root  266 Jan  1  1970 /dir1
-rw-r--r--  1 root  root  405 Sep  1 10:01 /local1
-rw-r--r--  1 root  root  336 Sep  1 09:20 /local5
-rw-------  1 root  root   45 Sep  1 09:48 /remote0
-rw-------  1 root  root  187 Sep  1 08:57 /remote1

/dir2:
total 4
-rw-------  1 root  root  266 Jan  1  1970 dir

/local0:
total 12
-rw-r--r--  1 root  root  187 Sep  1 08:57 con.tar
-rw-r--r--  1 root  root  336 Sep  1 09:20 con.zip
-rw-r--r--  1 root  root  405 Sep  1 10:01 df

/local2:
total 4
-rw-r--r--  1 1000  1000  405 Sep  1 10:01 df

/local3:
total 4
-rw-r--r--  1 1000  1000   45 Sep  1 08:57 tmp_wpa_supplicant.conf

/local4:
total 4
-rw-r--r--  1 1000  1000   45 Sep  1 08:57 tmp_wpa_supplicant.conf

/remote2:
total 4
-rw-------  1 root  root  187 Sep  1 08:57 con.tar

/remote3:
total 4
-rw-------  1 root  root  336 Sep  1 08:53 con.zip
```

可以看到：

**本地路径**
 
- 如果是不支持的压缩文件。以“/”结尾，则覆盖目标文件；反之，放在文件夹内。
- 如果是文件夹或者支持的压缩文件，怎全部被copy或者解压到文件夹内，不管有没有“/”。

**远端路径**

- 以“/”结尾，则将其当做文件夹，放在内部。
- 反之，则覆盖目标文件。
- 如果是目录的话，只在本地创建对应文件/文件夹，不下载内部内容。

**总结**

只要是【本地文件夹】或者【本地支持的压缩文件】，则全部copy/解压到【目标文件夹】内。否则(不论本地还是远端)都根据目标文件是否带有“/”结尾来决定。

#### COPY

使用此指令可以将文件复制到镜像中去。那你一定会想：WTF，那跟ADD有啥区别啊？区别是有的：COPY只支持本地路径，不支持远端路径，且不会解压压缩文件。

#### USER

为后续指令指定当前的用户：用户名或者ID。

#### STOPSIGNAL

> Docker1.9之后支持。

用来设定，告诉容器停止时传入的停止信号。它也可以在crate/run的时候通过`--stop-signal`设置。

之处传入无符号数字(比如：9、12等)或者标准的SIGNAME(比如：SIGKILL)。

示例：

```shell
STOPSIGNAL 9
```

#### ONBUILD

顾名思义，是在构建的时候触发的指令，但是这个构建是说被当做base image也就是说“FROM xxx”的时候。也就是说我们在构建含有ONBUILD的镜像时，ONBUILD指令并没有实际执行。

但是ONBUILD并不表示具体的指令，它需要配上上面的指令一起完成。比如：`ONBUILD RUN ls -l`等等。当时，ONBUILD中不能嵌套ONBUILD。因为是BaseImage，所以ONBUILD不会执行FROM/MAINTAINER/部分LABEL命令。

ONBUILD是在执行FROM的时候被执行的。当ONBUILD执行完了之后，才会继续执行Dockerfile中的其他指令。如果ONBUILD执行失败了，那么整个Dockfile也就不会继续执行下去。

BaseImage中的ONBUILD命令执行结束之后就会被清除，不会被应用到使用此BaseImage的镜像中去。

#### HEALTHCHECK

> Docker1.12之后支持。

它是一个用来检测容器是否正常运行的指令，需要配合`CMD`指令一起运行。同CMD以及ENTRYPOINT等一样，多个HEALTHCHECK的话只有最后一个会生效。

参数：

- `--interval=` 检查间隔，固定时间去检查容器状态。默认30秒检查一次。
- `--timeout=` 超时时间，每次检测超过此时间则记为失败。默认30秒。
- `--start-period=`  初次运行的容忍时间，初次运行时这个时间内的错误次数不记在retries中。默认0秒。
- `--retries=` 重试次数，超过这个次数则被认为`UNHEALTHY`，默认3次。

状态：

- **0** HEALTHY
- **1** UNHEALTHY
- **2** RESERVED


使用方式：

```shell
HEALTHCHECK NONE  # 可以用来清除BaseImage中的HEALTHCHECK指令。
HEALTHCHECK [options] CMD command
```

实例：

```shell
HEALTHCHECK --interval=2m --timeout=25s --retries=2 CMD curl http://localhost:8000 || exit 1
```

上面的含义是每2分钟(25秒算超时，最多重试2次)去`http://localhost:8000`这个地址检查一次运行状态，如果失败则返回1(即UNHEALTHY)。


> <https://itbilu.com/linux/docker/VyhM5wPuz.html>
>
> <https://docs.docker.com/engine/reference/builder>
>
> <https://deepzz.com/post/dockerfile-reference.html>
>
> <http://seanlook.com/2014/11/17/dockerfile-introduction/>
>
> <https://blog.fundebug.com/2017/05/15/write-excellent-dockerfile/>
>
> <https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices/>
>
> <http://blog.flux7.com/blogs/docker/docker-tutorial-series-part-3-automation-is-the-word-using-dockerfile>
> 