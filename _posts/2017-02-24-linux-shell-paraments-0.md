---
layout: post
title: "Shell中参数($0,$1,$#,$NF,$@等)的含义"
category: all-about-tech
tags:
 - shell
 - awk
 - function
date: 2017-02-24 11:59:00+00:00
---
 
此处仅仅从来记录平时常用的命令的参数。以免下次忘记时及时找到。也方便更多的人。

## sed

```bash
ll | sed '2!d' # show the 2nd line
ll | sed '2d' # hide the 2nd line
ll | sed -n '$p' # show the last one
ll | sed -n '/aaa/,$p' # after aaa
ll | sed -n '/aaa/,/bbb/p' # after aaa  before bbb
echo abcabcdefghijk | sed -e 's#a#4#g' # 替换所有的a
echo abcabcdefghijk | sed -e 's/a/4/1' # 1表示替换第一个
```

## awk

- $0 表示所有。
- $1 表示第一个。
- $NF 表示最后一个。
- $(NF-1) 表示倒数第二个。

比如：

	echo 'a b c d' | awk '{print $0}' 的结果是'a b c d'
	echo 'a b c d' | awk '{print $1}' 的结果是'a'
	echo 'a b c d' | awk '{print $NF}' 的结果是'd'
	echo 'a b c d' | awk '{print $(NF-1)}' 的结果是'c'

## function

- $0  当前脚本的文件名或者函数名。
- $n  传递给脚本或函数的参数。n 表示position。例如，第一个参数是$1，第二个参数是$2。
- $#  传递给脚本或函数的参数个数。比如fuc a b c d, 共4个参数返回的值是就是4。
- $*  传递给脚本或函数的所有参数。
- $@  传递给脚本或函数的所有参数。与$*的区别在于加上""后，前者是将所有参数合成一个，后者不变。
- $?  上个命令的退出状态，或函数的返回值。
- $$  当前Shell进程ID。对于 Shell 脚本，就是这些脚本所在的进程ID。

```Shell
#!/bin/bash
function bfunc()
{
	echo "$1"
}
function afunc()
{
	echo "\$0 = ${0}"
	echo "\$1 = ${1}"
	echo "\$# = ${#}"
	echo "\$* = ${*}"
	echo "\$@ = ${@}"
	echo "\$$ = ${$}"
	echo "\"\$@\" = $(bfunc "${@}")"
	echo "\"\$*\" = $(bfunc "${*}")"
}

afunc "a" "b" "c" "d"
```

上述代码的执行结果是:

	$0 = ./test.sh
	$1 = a
	$# = 4
	$* = a b c d
	$@ = a b c d
	$$ = 44076
	"$@" = a
	"$*" = a b c d


可以清晰地看到`$@`和`$*`的区别了吧.

需要指出的是此处`$0`的值是"./test.sh"为文件的名称。当我们把执行从`./test.sh`改成`source test.sh`(或者直接执行`afunc a b c d`)的时候值就变成了"afunc"，也就是函数名了。
