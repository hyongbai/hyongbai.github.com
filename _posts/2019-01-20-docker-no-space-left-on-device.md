---
layout: post
title: "Docker-解决空间不足的问题以及修改默认配置"
description: "Docker-解决空间不足的问题以及修改默认配置"
category: all-about-tech
tags: -[Docker]
date: 2019-01-20 12:05:57+00:00
---


## 问题

```bash
dpkg: error processing archive /var/cache/apt/archives/libc6-dev-i386_2.23-0ubuntu10_amd64.deb (--unpack):
 cannot copy extracted data for './usr/lib32/libresolv.a' to '/usr/lib32/libresolv.a.dpkg-new': failed to write (No space left on device)
```

Google了一圈之后，大多人的解决方案是删除所有不用的VOLUME、容器以及镜像等等。本质上只是腾出位置而已。但是如果业务需要所有的这些东西必不可删除的的话。这个问题还是无解。

## 定位问题

- 查看磁盘信息

```bash
pi@raspberrypi:~$ df -lh
Filesystem             Size  Used Avail Use% Mounted on
udev                    32G     0   32G   0% /dev
tmpfs                  6.3G  599M  5.8G  10% /run
/dev/mapper/vg00-root   19G  1.7G   17G  10% /
tmpfs                   32G     0   32G   0% /dev/shm
tmpfs                  5.0M     0  5.0M   0% /run/lock
tmpfs                   32G     0   32G   0% /sys/fs/cgroup
/dev/sda1              180M   54M  113M  33% /boot
/dev/mapper/vg00-tmp   945M   56M  825M   7% /tmp
/dev/mapper/vg00-var   3.7G  3.1G  462M  88% /var
/dev/mapper/vg00-data  1.6T  631G  882G  42% /data
tmpfs                  6.3G     0  6.3G   0% /run/user/25439
```

我是在/data分区上面挂载的VOLUME。一开始以为是硬盘存储不够导致的问题，后来发现不是这个问题(很明显我的空间剩余非常大)。

再想，其实这个是镜像内部在下载依赖的时候导致的空间不足，并没有对VOLUME进行任何IO操作。也就是说应当是docker本身的镜像/容器挂载点出现了问题。

- 查看 docker信息

```bash
pi@raspberrypi:~$ docker info
Containers: 2
 Running: 0
 Paused: 0
 Stopped: 2
Images: 3
Server Version: 18.09.1
Storage Driver: overlay2
 Backing Filesystem: extfs
 Supports d_type: true
 Native Overlay Diff: true
Logging Driver: json-file
Cgroup Driver: cgroupfs
Plugins:
 Volume: local
 Network: bridge host macvlan null overlay
 Log: awslogs fluentd gcplogs gelf journald json-file local logentries splunk syslog
Swarm: inactive
Runtimes: runc
Default Runtime: runc
Init Binary: docker-init
containerd version: 9754871865f7fe2f4e74d43e2fc7ccd237edcbce
runc version: 96ec2177ae841256168fcf76954f7177af9446eb
init version: fec3683
Security Options:
 apparmor
 seccomp
  Profile: default
Kernel Version: 4.4.0-87-generic
Operating System: Ubuntu 16.04.5 LTS
OSType: linux
Architecture: x86_64
CPUs: 24
Total Memory: 62.89GiB
Name: raspberrypi
ID: 2MO2:4Z6P:X2RQ:RPW7:PGWL:AJXZ:NX7M:66FR:GSUH:5PBC:2QFK:WH4O
Docker Root Dir: /var/lib/docker
Debug Mode (client): false
Debug Mode (server): false
Registry: https://index.docker.io/v1/
Labels:
Experimental: false
Insecure Registries:
 127.0.0.0/8
Live Restore Enabled: false
Product License: Community Engine

WARNING: No swap limit support
```

注意上面的一句`Docker Root Dir: /var/lib/docker`, 这应该是跟Docker存储镜像等有关。于是做了几个小实验：删除和创建容器/镜像并观察`/var`分区。发现此分区同步改变体积，于是我的思路就是修改`Docker Root Dir`。后来问询得知可以通过修改`DOCKER_OPTS`(添加-g /xxx)可以修改挂载点。

## 修改 /etc/default/docker

```bash
pi@raspberrypi:~$ dosu ls -l /etc/default/docker
-rw-r--r-- 1 root root 685 Jan 18 10:49 /etc/default/docker
pi@raspberrypi:~$ dosu cat /etc/default/docker
# Docker Upstart and SysVinit configuration file

#
# THIS FILE DOES NOT APPLY TO SYSTEMD
#
#   Please see the documentation for "systemd drop-ins":
#   https://docs.docker.com/engine/admin/systemd/
#

# Customize location of Docker binary (especially for development testing).
#DOCKERD="/usr/local/bin/dockerd"

# Use DOCKER_OPTS to modify the daemon startup options.
#DOCKER_OPTS="--dns 8.8.8.8 --dns 8.8.4.4"
# 新增路径
DOCKER_OPTS="-g /data/docker/"

# If you need Docker to use an HTTP proxy, it can also be specified here.
#export http_proxy="http://127.0.0.1:3128/"

# This is also a handy place to tweak where Docker's temporary files go.
#export DOCKER_TMPDIR="/mnt/bigdrive/docker-tmp"
pi@raspberrypi:~$
```

重启

```
sudo service docker restart
```

操作。不管用。

后于<https://github.com/moby/moby/issues/9889#issuecomment-109778351>发现这种修改是有限制的。

> Correct, the /etc/default/docker file is only used on systems using "upstart" and "SysVInit", not on systems using systemd.
>
> This is also mentioned at the top of the file;
> https://github.com/docker/docker/blob/44fe8cbbd174b5d85d4a063ed270f6b9d2279b70/contrib/init/sysvinit-debian/docker.default#L1

## 修改 /lib/systemd/system/docker.service

```
pi@raspberrypi:~/docker-config$ dosu cat /lib/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
BindsTo=containerd.service
After=network-online.target firewalld.service
Wants=network-online.target
Requires=docker.socket

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd -g /data/docker/ -H fd://
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always

# Note that StartLimit* options were moved from "Service" to "Unit" in systemd 229.
# Both the old, and new location are accepted by systemd 229 and up, so using the old location
# to make them work for either version of systemd.
StartLimitBurst=3

# Note that StartLimitInterval was renamed to StartLimitIntervalSec in systemd 230.
# Both the old, and new name are accepted by systemd 230 and up, so using the old name to make
# this option work for either version of systemd.
StartLimitInterval=60s

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this option.
TasksMax=infinity

# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

# kill only the docker process, not all processes in the cgroup
KillMode=process

[Install]
WantedBy=multi-user.target
```

直接在ExecStart的启动命令中添加 `-g /xxx` 修改 `Docker Root Dir`。

```bash
# ExecStart=/usr/bin/dockerd -H fd://
ExecStart=/usr/bin/dockerd -g /data/docker/ -H fd://
```

重启。

```bash
pi@raspberrypi:~/docker-config$ dosu service docker restart
Warning: docker.service changed on disk. Run 'systemctl daemon-reload' to reload units.
pi@raspberrypi:~/docker-config$ dosu systemctl daemon-reload
pi@raspberrypi:~$ docker images; docker ps -a
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS
```

什么东西没有了。 继续查看：

```bash
pi@raspberrypi:~$ docker info | grep -i root
Docker Root Dir: /data/docker
pi@raspberrypi:~$
```

所以操作生效了。

*注意：记得将原路径的文件(使用root)拷贝到新的目录。这样docker才能找到原先的镜像和容器以及相关缓存(Layer)等。*


其实也可以在`/etc/docker/daemon.json`中修改做修改。

- <https://stackoverflow.com/a/43689496>
- <https://github.com/moby/moby/issues/9889>
- <https://docs.docker.com/config/daemon/systemd>
- <https://docs.docker.com/engine/reference/commandline/dockerd/>