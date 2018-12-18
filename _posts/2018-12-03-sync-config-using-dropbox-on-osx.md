---
layout: post
title: "多台电脑配合Dropbox共享环境配置"
category: all-about-tech
tags: -[OSX] -[Dropbox]
date: 2018-12-03 09:00:00+00:00
---

通常情况下，大家会不得不使用多台电脑的，问题也接踵而来。

比如家里一台自用电脑，公司一台工作电脑。各种开发环境配置信息需要经常在两台电脑之间保持一致，如果一次更改永不变动还好说，频繁变动需要同步的话就会非常之不方便了。

好在问题是可以解决的。Dropbox给提供了一个很好的文件同步方案，但空间有限，不过用来备份/同步各种配置信息再好不过了。

思路说起来很简单，把各种设置扔到dropbox对应的文件夹中，然后使用链接的方式跟软件设置的存储路径关联起来。

最终效果是，一修改Dropbox就同步，一同步到云端另一台电脑就自动更新。皆大欢喜。

下面列出常见软件的配置之道。

## Alfred

路径：Alfred Preferences -> Advanced -> Syncing

> Set sync folder, 设置自己的配置文件所在的路径。在次之前，记得想原先的备份文件拷贝到Dropbox中。

![](https://i.postimg.cc/MGLH8tMc/QQ20181203-111043.png)

## iTerm

路径：Preference -> General -> Preferences

> Load preferences from a custom folder or URL: 选中自己的备份文件夹的路径。

比如我的是:

```
~/Dropbox/baks/iTerms
```

注意，选中的是所在的`文件夹`。iTerm启动时会自动去加载里面的备份文件。

![](https://i.postimg.cc/qMG77p6H/QQ20181203-112101.png)

设置完之后可以将当前的设置通过「Save Current Settings to Folder」保存到目前路径。

## OSX

#### 按键绑定

比如苹果不支持「HOME」「END」，但是可以通过启动方式给这两个键值绑定相应的行为，可以某些编辑器里面生效。

格式如下：

```shell
{
    "\UF729"  = moveToBeginningOfLine:; // home
    "\UF72B"  = moveToEndOfLine:; // end
    "$\UF729" = moveToBeginningOfLineAndModifySelection:; // shift-home
    "$\UF72B" = moveToEndOfLineAndModifySelection:; // shift-end
}
```

存放在自己的Dropbox对应的路径即可。

苹果默认的按键绑定的配置文件位于`~/Library/KeyBindings/DefaultKeyBinding.dict`

可以通过如下命令设定一个软连接：

```shell
ln -s ~/Dropbox/baks/osx/DefaultKeyBinding.dic ~/Library/KeyBindings/
```

## Sublime

#### 同步插件列表

Package Control会把安装的插件存在一个配置文件中，每次启动的时候都会读取这个文件并自动下载本地没有安装了的插件。

比如我的插件列表：

```json
{
	"bootstrapped": true,
	"in_process_packages":
	[
	],
	"installed_packages":
	[
		"A File Icon",
		"Codecs33",
		"CodeFormatter",
		"ConvertToUTF8",
		"DocBlockr",
		"Dockerfile Syntax Highlighting",
		"Ethereum",
		"FileBrowser",
		"FileIcons",
		"GoSublime",
		"Highlighter",
		"JavaScript Completions",
		"JsFormat",
		"Markdown Extended",
		"Monokai Extended",
		"OpenGL Shading Language (GLSL)",
		"Package Control",
		"Python PEP8 Autoformat",
		"SideBarEnhancements",
		"SublimeAStyleFormatter",
		"SublimePythonIDE"
	]
}
```

```shell
ln -s ~/Dropbox/baks/sublime/Package\ Control.sublime-settings ~/Library/Application\ Support/Sublime\ Text\ 3/Packages/User/
```

#### 同步文件配置

```
ln -s ~/Dropbox/baks/sublime/Preferences.sublime-settings ~/Library/Application\ Support/Sublime\ Text\ 3/Packages/User/
```

```json
{
	"color_scheme": "Packages/User/Monokai Extended (SublimePythonIDE).tmTheme",
	"font_size": 13,
	"ignored_packages":
	[
		"Vintage"
	],
	"theme": "Default.sublime-theme",
	"update_check": false,
	"word_wrap": true
}
```

## VSCode

我主要是将vscode的设置以及按键绑定通过Dropbox同步了。

```shell
ln -s ~/Dropbox/baks/vscode/settings.json ~/Library/Application\ Support/Code/User/
ln -s ~/baks/vscode/keybindings.json ~/Library/Application\ Support/Code/User/
```