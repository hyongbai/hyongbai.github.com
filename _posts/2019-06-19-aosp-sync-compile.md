---
layout: post
title: "下载编译AOSP源码"
description: "sync compile aosp"
category: all-about-tech
tags: -[aosp]
date: 2019-06-19 11:05:57+00:00
---

## 准备

由于 aosp 需要支持大小敏感，但 OSX 上面不建议使用官方说的创建 dmg 文件的方式来编译。因为这可能会由于空间只增不减，即使删除文件也不会变化，导致空间不够。

建议使用磁盘空间重新分区：缩小现有空间大小，留出足够空间创建一个大小写敏感的分区，将这个分区给 aosp 使用。

## 下载

使用清华的镜像，在国内比较快。

```sh
export REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/' && \
repo init -u https://aosp.tuna.tsinghua.edu.cn/platform/manifest -b android-8.1.0_r60 && \
repo sync -j4
```

源码目录：

![aosp-source-structure.png](https://raw.githubusercontent.com/hyongbai/resources/master/img/aosp/aosp-source-structure.png)

#### 修改源码路径

如果已经下载了源码，此时就没法通过修改环境变量达到修改的目地了。

- 第一步：修改 `.repo/manifest.xml` 中的 aosp 这个 remote 的 fetch。

```xml
<manifest>
   <remote  name="aosp"
            fetch="https://android.googlesource.com"
            review="android-review.googlesource.com" />
```

- 第一步：修改 `.repo/manifests.git/config` remote的url。如下:

```
[core]
        repositoryformatversion = 0
        filemode = true
[filter "lfs"]
        smudge = git-lfs smudge --skip -- %f
[remote "origin"]
        url = /mirror/platform/manifest.git
        fetch = +refs/heads/*:refs/remotes/origin/*
[branch "default"]
        remote = origin
        merge = refs/heads/android-9.0.0_r22
```

> 示例因为同步了mirror，因此使用本地相对路径也是可以的。

## 搭建源码浏览程序

类似于 <http://androidxref.com>

#### 搭建opengrok环境

<https://hub.docker.com/r/opengrok/docker>

```
docker run -d --name aospxref \
-v ~/aosp-root/aosp:/aosp \
-v ~/aosp-root/xref:/opengrok/data \
-p 18080:8080 \
opengrok/docker:latest
```

#### 建立索引文件

- 进入容器

```
docker exec -it aospxref bash
```

- 调用opengrok

容器的安装路径在中：/opengrok/

```bash
java -jar /opengrok/lib/opengrok.jar -P -S \
 -s /aosp/android-8.1.0_r60/art/ \
 -d /opengrok/data/ \
 -W /var/opengrok/etc/configuration.xml \
 --progress
```

或者通过如下方式直接在容器中运行，而无需先进入容器中:

```bash
docker exec aospxref bash -c '\
java -jar /opengrok/lib/opengrok.jar -P -S \
 -s /aosp/android-8.1.0_r60/art/ \
 -d /opengrok/data/ \
 -W /var/opengrok/etc/configuration.xml \
 --progress
 '
```

参数介绍：

```
  -P, --projects
    Generate a project for each top-level directory in source root.

  -S, --search
    Search for "external" source repositories and add them.

  -s, --source /path/to/source/root
    The root directory of the source tree.
    
  -d, --dataRoot /path/to/data/root
    The directory where OpenGrok stores the generated data.
    
  -W, --writeConfig /path/to/configuration
    Write the current configuration to the specified file
    (so that the web application can use the same configuration)

  --progress
    Print per project percentage progress information.
    (I/O extensive, since one read through directory structure is
    made before indexing, needs -v, otherwise it just goes to the log)
```

opengro官方镜像中tomcat的设置的文件路径为：

```
/usr/local/tomcat/webapps/ROOT/WEB-INF/web.xml
```

可以看到他们的默认路径为`/var/opengrok/etc/configuration.xml`, 如下：

```xml
    <context-param>
        <description>Full path to the configuration file where OpenGrok can read its configuration</description>
        <param-name>CONFIGURATION</param-name>
        <param-value>/var/opengrok/etc/configuration.xml</param-value>
    </context-param>
```

- 重启docker

```
docker restart aospxref
```

#### 浏览

<http://localhost:18080>

效果如下:

![aosp-xref-source-search-result.png](http://t.cn/AiNneC9s)

## 编译系统

```sh
# 目前只支持 bash 环境。
bash
# 载入aosp环境脚本
source build/envsetup.sh && \
# 设定需要启动的编译目标
lunch ${arch:-aosp_arm-eng} && \
make -j4
```

注：开启`ccache`可以加速编译，但是Android Q 源码已不包含 ccahe 命令。

#### 编译目标：

如果不知道自己的编译目标可以不给 lunch 命令添加参数。编译时会列出当前系统支持的编译目标。比如 `Nexus5X` 对应的是 `bullhead`。


- -user 表示正常的 ROM。

- -userdebug 在正常机型基础上添加了 root。

- -eng 表示工程模式，带有 root 和一些调试信息。适合用户开发。

#### 编译结果：

![aosp-build-success.png](https://raw.githubusercontent.com/hyongbai/resources/master/img/aosp/aosp-build-success.png)

![aosp-android-8.1.0_r60-bullhead-sizes.png](http://t.cn/EofBBa5)

## 启动emulator

编译完之后可以通过如下方式启动模拟器。

```sh
# 载入aosp环境脚本
source build/envsetup.sh && \

# 设定需要启动的编译目标
lunch ${arch:-aosp_arm-eng} && \

# prebuilts/android-emulator/{os}/emulator
emulator -writable-system
```

正常来说执行如下操作：

```sh
adb root && sleep 0.3
adb remount && sleep 0.3
# dm_verity is enabled on the system partition.
# Use "adb disable-verity" to disable verity.
# If you do not, remount may succeed, however, you will still not be able to write to these volumes.
adb disable-verity && sleep 0.3
```

就可以在 system 分区拥有 RW 权限了。

但是模拟器可能不允许对 system 进行修改。即使`mount -o rw,remount -t ext4  /system`重新挂载也不能RW。其实可以在启动的时候，添加-writable-system参数。

## 编译Framework

```sh
# 载入aosp环境脚本
source build/envsetup.sh && \

# 编译 ide 模块
mmm development/tools/idegen/ && \
# cd development/tools/idegen/ && mm && cd - && \
fas
source development/tools/idegen/idegen.sh && ls android.*
```

## 烧录

oem unlock 之后，重启手机到 bootloader 页面。

- #### 方法一：

一步到位

```
# w 表示是否清除数据
fastboot flashall -w
```

- #### 方法二：

各个单刷

```sh
$ cd <AOSP_TOP>/out/target/product/<product_name>/
$ fastboot flash system system.img
# boot.img 包含了 kernel and ramdisk
$ fastboot flash boot boot.img
$ fastboot flash userdata userdata.img
# 如果要更新 recovery partition
$ fastboot flash recovery recovery.img
$ fastboot reboot
```

- #### 方法三

创建系统镜像，比如pixel手机。代号sailfish

生成:
```
source device/google/marlin/factory-images_sailfish/generate-factory-images-package.sh
```

- #### 方法四

```
make updatepackage
```

```
fastboot update  <AOSP_TOP>/out/target/product/<product_name>/aosp_sailfish-img-eng.aosp.zip
```


## 编译模块

```sh
在命令行运行：

m 编译所有
mm 编译当前目录
mmm 编译指定目录

比如：
mmm packages/apps/Launcher3/
```

## LineageOS

```sh
# img
IMG=~/android/SourceCode/aosp.dmg;
# volume
#VOLUME=/Users/hanyongbai/android/SourceCode/lineage/lineage-15.1;
VOLUME=/Volumes/aosp
# create
mountCreate() { hdiutil create -type SPARSE -fs 'Case-sensitive Journaled HFS+' -size 100g ${IMG}; };
mountResize() { hdiutil resize -size 200g ${IMG}.sparseimage; };
# mount
mountAndroid() { hdiutil attach ${IMG}.sparseimage -mountpoint ${VOLUME}; };
# umount
umountAndroid() { hdiutil detach ${VOLUME}.sparseimage; };
#
mountAndroid && \
export USE_CCACHE=1 && ccache -M 50G && \
cd ${VOLUME}/lineage/lineage-15.1 && \
repo init -u https://github.com/LineageOS/android.git -b lineage-15.1 && \
repo sync -j4 && \
source build/envsetup.sh && \
breakfast bullhead && \
croot && \
brunch bullhead && \
ls -l ${OUT}

export JAVA_HOME='/Applications/Android Studio.app/Contents/jre/jdk/Contents/Home'
export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar
export PATH=${JAVA_HOME}/bin:${PATH}
```

> LineageOS没有编译成功。

## 编译错误

- #### 不支持当前 OSX 版本

```sh
ninja: no work to do.
[1/1] /Volumes/aosp/lineage/lineage-15.1/out/soong/.bootstrap/bin/soong_build /Volumes/aosp/lineage/lineage-15.1/out/soong/build.ninja
FAILED: /Volumes/aosp/lineage/lineage-15.1/out/soong/build.ninja
/Volumes/aosp/lineage/lineage-15.1/out/soong/.bootstrap/bin/soong_build  -t -b /Volumes/aosp/lineage/lineage-15.1/out/soong -d /Volumes/aosp/lineage/lineage-15.1/out/soong/build.ninja.d -o /Volumes/aosp/lineage/lineage-15.1/out/soong/build.ninja Android.bp
internal error: Could not find a supported mac sdk: ["10.10" "10.11" "10.12"]
ninja: build stopped: subcommand failed.
10:17:00 soong failed with: exit status 1

#### failed to build some targets (20 seconds) ####
```

去这里下载支持的版本：

<https://github.com/phracker/MacOSX-SDKs/releases>

解压到：

```
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs
```

下面的方式为直接修改aosp支持的版本号，可能会导致兼容问题。

```
ls -l /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/
nano build/soong/cc/config/x86_darwin_host.go
# 找到 darwinSupportedSdkVersions 添加当前电脑支持的最接近的 sdk 即可。
```

---

- #### JDK版本问题

Android8.1上面只能使用Sun/OracleJDK！

```
10:28:57 *******************************************************
10:28:57 You are attempting to build with an unsupported JDK.
10:28:57
10:28:57 You use OpenJDK, but only Sun/Oracle JDK is supported.
10:28:57
10:28:57 Please follow the machine setup instructions at:
10:28:57     https://source.android.com/source/initializing.html
10:28:57 *******************************************************
10:28:57 stop

#### failed to build some targets (01:00 (mm:ss)) ####
```

使用 aosp 中预编译出来的 jdk，具体路径为：

```bash
jh=prebuilts/jdk/jdk8/darwin-x86/
或者
jh=prebuilts/jdk/jdk8/linux-x86/
export JAVA_HOME=${jh} && \
export PATH=${JAVA_HOME}/bin:${PATH} && \
export CLASSPATH=.:${JAVA_HOME}/lib/dt.jar:${JAVA_HOME}/lib/tools.jar
```

或者 去 Oracle 官方下载 jdk 即可。

Linux:

```
# https://askubuntu.com/questions/593433/error-sudo-add-apt-repository-command-not-found

sudo apt-get install software-properties-common
add-apt-repository ppa:webupd8team/java && \
apt-get update && \
apt-get install oracle-java8-installer && \
update-alternatives --config java
```

---

- #### LineageOS bootanimation 编译失败

```
[1058/1068] including ./vendor/lineage/bootanimation/Android.mk ...
**********************************************
The boot animation could not be generated as
ImageMagick is not installed in your system.

Please install ImageMagick from this website:
https://imagemagick.org/script/binary-releases.php
**********************************************
./vendor/lineage/bootanimation/Android.mk:49: error: stop.
11:03:24 ckati failed with: exit status 1

#### failed to build some targets (04:24 (mm:ss)) ####
```

安装 ImageMagick 即可。比如在 OSX 上:

```
brew install ImageMagick
```

---

- #### curl 版本错误导致jack 启动失败

```
[  2% 1220/40672] Ensuring Jack server is installed and started
FAILED: setup-jack-server
/bin/bash -c "(prebuilts/sdk/tools/jack-admin install-server prebuilts/sdk/tools/jack-launcher.jar prebuilts/sdk/tools/jack-server-4.11.ALPHA.jar  2>&1 || (exit 0) ) && (JACK_SERVER_VM_ARGUMENTS=\"-Dfile.encoding=UTF-8 -XX:+TieredCompilation\" prebuilts/sdk/tools/jack-admin start-server 2>&1 || exit 0 ) && (prebuilts/sdk/tools/jack-admin update server prebuilts/sdk/tools/jack-server-4.11.ALPHA.jar 4.11.ALPHA 2>&1 || exit 0 ) && (prebuilts/sdk/tools/jack-admin update jack prebuilts/sdk/tools/jacks/jack-4.32.CANDIDATE.jar 4.32.CANDIDATE || exit 47 )"
Unsupported curl, please use a curl not based on SecureTransport
Launching Jack server java -XX:MaxJavaStackTraceDepth=-1 -Djava.io.tmpdir=/var/folders/_c/53_jz9t57r7b1t5spjnx7t2r0000gn/T/ -Dfile.encoding=UTF-8 -XX:+TieredCompilation -cp /Users/buyuntao/.jack-server/launcher.jar com.android.jack.launcher.ServerLauncher
Jack server failed to (re)start, try 'jack-diagnose' or see Jack server log
Unsupported curl, please use a curl not based on SecureTransport
Unsupported curl, please use a curl not based on SecureTransport
[  3% 1225/40672] target R.java/Manifest.java: messaging (/Volumes/aosp/lineage/lineage-15.1/out/target/common/obj/APPS/messaging_intermediates/src/R.stamp)
ninja: build stopped: subcommand failed.
11:13:51 ninja failed with: exit status 1

#### failed to build some targets (14:55 (mm:ss)) ####
```

解决：

- 使用 brew

```
brew install curl --with-openssl
export PATH=$(brew --prefix curl)/bin:$PATH
# see https://stackoverflow.com/a/35024131/1017629

# https://github.com/lfex/lfetool/issues/110#issuecomment-55548297
```

- 或者下载源码编译

```
# 下载
wget https://curl.haxx.se/download/curl-7.64.1.zip

# 解压之后配置，--with-ssl版本号可能不同，可以在父目录看看当前版本

./configure --prefix=/usr/local/curl --with-ssl=/usr/local/Cellar/openssl/1.0.2q

# 编译

sudo make && sudo make install

# 替换默认 curl
export PATH=/usr/local/curl/bin:$PATH
```

---

- #### stat: cannot read file system information for ‘%z’: No such file or directory

原因：安装了`coreutils`导致使用了错误的 stat 版本。

解决方案 1：使用/usr/bin/stat 即可。最简单的方法：

```sh
export PATH=/usr/bin:${PATH}
```

解决方案 2：将当前使用的 stat 设置为不可执行。这样就会使用默认的 stat 了。

```sh
chmod -x $(which stat)
#或 chmod -x /usr/local/opt/coreutils/libexec/gnubin/stat #各平台路径不同
```

<https://stackoverflow.com/questions/28784392/building-aosp-on-mac-yosemite-and-xcode>

- #### file not found

多半是在case insensetive的分区上面同步代码导致的。

解决办法就是下载对应的文件即可到指定目录即可。

比如：

```sh
frameworks/av/media/libstagefright/DataSource.cpp:29:10: fatal error: 'media/stagefright/DataURISource.h' file not found
```

```
https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-8.1.0_r63/media/libstagefright/include/media/stagefright/DataURISource.h
```

> 注意你的Android版本！保持一致。

遇到的大小写敏感的文件有：

```
frameworks/av/media/libstagefright/DataSource.cpp
external/iptables/include/linux/netfilter/xt_DSCP.h
```

---

ninja: error: 'out/host/darwin-x86/framework/host-libprotobuf-java-nano.jar', needed by 'out/host/common/obj/JAVA_LIBRARIES/launcher_proto_lib_intermediates/classes-full-debug.jar', missing and no known rule to make it

- #### /external/selinux/checkpolicy:checkpolicy yacc policy_parse.y [darwin] FAILED:

> [  0% 391/82033] //external/selinux/checkpolicy:checkpolicy yacc policy_parse.y [darwin]
> FAILED: out/soong/.intermediates/external/selinux/checkpolicy/checkpolicy/darwin_x86_64/gen/yacc/external/selinux/checkpolicy/policy_parse.c out/soong/.intermediates/external/selinux/checkpolicy/checkpolicy/darwin_x86_64/gen/yacc/external/selinux/checkpolicy/policy_parse.h
> BISON_PKGDATADIR=external/bison/data prebuilts/misc/darwin-x86/bison/bison -d  --defines=out/soong/.intermediates/external/selinux/checkpolicy/checkpolicy/darwin_x86_64/gen/yacc/external/selinux/checkpolicy/policy_parse.h -o out/soong/.intermediates/external/selinux/checkpolicy/checkpolicy/darwin_x86_64/gen/yacc/external/selinux/checkpolicy/policy_parse.c external/selinux/checkpolicy/policy_parse.y
> ninja: build stopped: subcommand failed.
> 08:09:51 ninja failed with: exit status 1

```
cd external/bison
git cherry-pick c0c852bd6fe462b148475476d9124fd740eba160
# 或者
git pull "https://android.googlesource.com/platform/external/bison" refs/changes/40/517740/1
mm
cp out/host/darwin-x86/bin/bison prebuilts/misc/darwin-x86/bison/
```

如果找不到代码可以重新下载：

git pull "https://android.googlesource.com/platform/external/bison" refs/changes/40/517740/1

> - <https://alset0326.github.io/aosp-on-macos-high-sierra.html>
> - <https://android-review.googlesource.com/c/platform/external/bison/+/517740>

## 其他

aosp on OSX Docker编译非常之慢。不推荐使用Docker 上面编译。

Windows 上面使用 Docker 编译可能会出现无法创建软链接的情况。

- <https://www.cnblogs.com/larack/p/9646860.html>
- <https://wiki.lineageos.org/devices/bullhead/build>
- <https://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html>