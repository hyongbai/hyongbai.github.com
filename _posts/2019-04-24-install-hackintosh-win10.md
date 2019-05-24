---
layout: post
title: "安装黑苹果和Windows双系统"
description: "安装黑苹果和Windows双系统"
category: all-about-tech
tags: -[osx]
date: 2019-04-24 00:05:57+00:00
---

## 硬件

- 主板: [华硕B360M](http://t.cn/ESXcjpN)
> - Intel® I219V, 1 x 千兆网卡
> - Realtek® ALC 887 8 声道 高清晰音频编码解码器

- CPU: Intel i7-8700

- 显卡：推荐使用AMD

- 内存: 金士顿8+16GB

- SSD: EVO 860, 500GB

- 硬盘: WD蓝盘, 4TB

- BT:
> - bcm4360/4352z/4350(ngff：wifi+bt，免驱)
> - BCM20702(同bcm4360等，仅bt息)
> - CSR8510(仅bt，免驱，便宜但距离短)，目前使用中
> - 其他：hmb是pcie，cd是m2

***可以去这里看看推荐的装机配置: http://t.cn/ESf27ul***

## 硬盘格式

![osx-disk-manager-plans](http://t.cn/EaKiFvi)

- GPT: 即GUID分区图，磁盘最大8ZB。

- APM: Apple分区图，磁盘最大2TB。不推荐使用。
 
- MBR: (Master boot record)主引导记录，磁盘最大2TB。且最多4个分区。不推荐使用。

## 引导分区。

- EFI分区: 300MB。FAT16/FAT32。

> - 系统引导分区，也叫ESP(EFI SystemPartition)，GPT分区格式**第一个分区**。分区标识是EF。保存着硬盘上各个操作系统的引导程序。自动生成。
> - 挂载指令: `sudo mount -t msdos /dev/disk0s1 {TARGET}`

https://zh.wikipedia.org/wiki/EFI系统分区

## 刷Windows

可以去官方下载msdn版本windows, 或者去<http://msdn.itellyou.cn>下载。

- windows 无法打开所需的文件 install.wim

> utraliso制作启动盘使用的是fat32格式，无法存储超过4gb的文件。
>
> 使用rufus制作Windows启动盘即可。
>
> <http://suzukaze.lofter.com/post/ec9e4_604148b>

- 提示Windows检测到EFI系统分区格式化为NIFS，将EFI系统分区格式化为FAT32

> 拆除机械硬盘，只保留一个SSD, 同时删除所有的系统分区/恢复区。 <https://blog.csdn.net/Waitfou/article/details/79018010>

## Hackintosh

### bios

- Load Optimized Defaults
- `VT-d`: disable
- `CFG-Lock`: disable
- `Secure Boot Mode`: disable
- `OS Type`: Other OS
- `IO Serial Port`: disable
- `XHCI Handoff`: Enabled
- If you have a 6 series or x58 system with AWARD BIOS, disable USB 3.0

Advances\SystemAgent(SA)\Graphics Configuration:

- Primary Display: Auto -> CPU Graphics
- DVMT Pre-Allocated: 64MB
- IGPU Multi-Monitor: enable

### Flash Mojave

#### * unibeast

- 从APP Store下载Mojave。

- 使用unibeast制作启动盘。英文环境+32GB以下 + HFS格式(大小写不敏感)

- multibeast添加驱动。

#### * 自己制作

自定义efi，安装驱动。可以参考： [**知乎帖子**](https://zhuanlan.zhihu.com/p/55991446)。大致步骤如下：

- 从APP Store下载Mojave。

- 安装clover clover configurator(clover bootloader)

- cloverefiboot： <https://sourceforge.net/projects/cloverefiboot>

- clover-configurator： <https://mackie100projects.altervista.org/download-clover-configurator/>

#### * 别人制作好的镜像

使用`balenaEther`制作即可。

- 镜像：<http://t.cn/EaaZsci>

- balenaEther：<https://github.com/balena-io/etcher>

### 安装

- 第一阶段：从启动盘进入，选择USB(即启动盘烧录的系统)。

> - 先磁盘工具分区
> - 分区时选择HFS，记住分区名，比如: ABC。
> - 再进行安装，耗时5分钟左右。

- 第二阶段：从启动盘进入，选择上次的安装盘ABC(非USB/U盘)。

> - 自动安装，耗时15分钟左右。
> - 这里可能会重启多次。

- 第三阶段：从启动盘进入，选择上次的安装盘ABC(非USB/U盘)。进入macOS系统初始化设置。

> - 安装驱动
> - 脱离启动盘。即从电脑硬盘自己的EFI引导。
> - 卸载并拔掉U盘。

### 驱动

- [MAC 10.14 安装教程10-基于黑果小兵大神EFI文件的修改过程](http://t.cn/ESXcbKr)

- 声卡：Realtek® ALC 887

https://github.com/acidanthera/AppleALC/releases

- 以太网卡：Intel® I219V

https://bitbucket.org/RehabMan/os-x-intel-network/downloads/

- 无线网卡/蓝牙

- CSR 8510免驱。或者BCM20702。

- WiFi+蓝牙推荐BCM943602CS。

我的RMBP内建的就是20702:

![osx-mbpr-internal-bt-hub.png](http://t.cn/ESii0xb)

## 成果

![ss-hackintosh-system-overview-graphics-2048MB.png](http://t.cn/ES94psT)

## 问题汇总

- #### 如何隐藏开机项

可以通过`Clover Configurator`打开plist文件，在gui的hide(exclude)添加你想隐藏的选项。(或者直接以文本形式打开找到gui-hide，在arrary中直接添加子项)

比如：

- Preboot

- Recovery

- #### [ PCI configuration end ]: 

> <https://www.tonymacx86.com/threads/unibeast-installer-hang-at-pci-configuration-end.144119>

- #### 卡在apfs_module_start:1340:load com.apple.filesystem.apfs, v954.214.4附近。

> UEFI Advance Mode\Advanced\PCH Configuration\System Time and Alarm Source\ Source:Legacy rtc

- #### The system has POSTed in safe mode

> 原因：系统自引导没完成之前BIOS认为你的系统是坏的。
> - 方法1：在电脑的开屏页面按下F8(不同主板按键可能不同)。选择U盘启动就行。
> - 方法2：按下F1进入BIOS，之后按下F10，如果第一启动顺序是U盘，啥也不用做退出即可。如果不是，则在当前页面再执行方法1。

- #### Intel集成显卡只有7MB显存

(命令行远程ssh登录通过system_profiler看到内存确实是0x600MB-即1.5GB。由于我是用的是B360M，会导致黑屏。参考下面的`UHD630 黑屏`即可)

Kext utility下载地址：<http://cvad-mac.narod.ru/index/0-4>

> - https://www.youtube.com/watch?v=Mi52oZCkpXs
> - [[Solved]ASUS H370-i I7-8700 Mojave 10.14.1 UHD630 driving need help!](http://t.cn/ESXFnHC)
> - https://www.elitemacx86.com/threads/fix-intel-uhd-graphics-620-630-on-laptop.207
> - https://www.tonymacx86.com/threads/intel-uhd-630-graphics-0x3e918086-i3-8100-native-support-with-gfxid-injection.240585
> - https://www.tonymacx86.com/threads/guide-intel-framebuffer-patching-using-whatevergreen.256490/
> - https://www.insanelymac.com/forum/topic/334899-intel-framebuffer-patching-using-whatevergreen
> - https://hackintosher.com/forums/thread/coffee-lake-uhd-630-graphics-framebuffer-injection-0x3e918086-0x3e928086-for-high-sierra.210

- #### UHD630 黑屏

> - [H310&B360&H370主板10.14 mojave 核显UHD630 DVI HDMI黑屏解决及探讨](http://t.cn/ES9LQoT)

> - [【黑果小兵】CoffeeLake UHD 630黑屏、直接亮屏及亮度调整的正确插入姿势](http://t.cn/ESX5KlE)

> - [关于 CoffeeLake UHD630 和亮度调节](http://t.cn/ESKDuri)

- #### Please go to https://panic.apple.com to report this panic

一般是显卡配置错误导致。`Clover引导`中选择`Option`找到`Graphics Injector`, 取消选中`Inject Intel`(获取其他的)。

> http://bbs.pcbeta.com/forum.php?mod=viewthread&tid=1797185

- #### Error allocating 0x#### pages at 0x####alloc type 2

> 在/EFI/CLOVER/drivers64UEFI中将OsxAptioFixDrv替换OsxAptioFix2Drv。试着多启动几次。
> 具体可见: http://t.cn/ESKRxe6

- #### Fatal error: Supervisor has failed, shutting down: Supervisor caught an error

> [enable VT-x, it works on my Hackintosh 10.13.5.](http://t.cn/ESQXeWA)
> 试过了，无用。

- #### clover自动引导无效

> `Clover configerator`中设置`default boot volume`为自己的默认分区(使用lastBootedVolume不生效)。
>
> ![ss-hackintosh-clover-autoboot.png](http://t.cn/ESRpRlO)

- #### 待机之后无法唤醒

> - 在boot的Arguments中添加`-gux_defer_usb2`。修复使用 GenericUSBXHCI.kext 驱动产生的待机唤醒问题，i7 系列适用。


- #### Couldn’t allocate runtime area

*该问题并未解决*

Error allocating 0x11c8d pages at 0x000000000xxxxxxx alloc type 2

> 删除`/EFI/ClOVER/drivers64UEFI`里面所有的AptioFixDrv相关的文件。然后使用[OsxAptioFix2Drv-free2000.efi ](http://www.mediafire.com/file/aks1kkyj6l1xf9n/OsxAptioFix2Drv-free2000.efi.zip)即可。
> https://mrmad.com.tw/error-allocating-0x11c8d-pages-at-0x0000-alloc-type-2
> https://nickwoodhams.com/x99-hackintosh-osxaptiofixdrv-allocaterelocblock-error-update/

## 其他

硬件很重要。与人品无关。

选的对，可能你压根就没机会遇到坑。

不然，可能买了蓝牙键盘你折腾半天都连不上，最后重新买。

附上我的EFI下载文件: [HACKINTOSH-EFI_i7-8700_ASUS-B360M.zip](http://t.cn/ES95OSr) 。供想折腾的人使用。

## 参考

- <https://zhuanlan.zhihu.com/p/55991446>
- <http://xiaogegexl.blogspot.com/2018/03/boot.html>
- <https://www.weibo.com/p/230418bc5a5e580102wos9>