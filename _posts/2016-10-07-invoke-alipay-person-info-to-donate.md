---
layout: post
title: "Intent调用支付宝转账"
category: all-about-tech
tags: [Alipay]
date: 2016-10-08 23:59:00+00:00
---
 
## 1

事情的是这样的，国庆期间有人邮件反馈使用空调狗时想无私捐款，但是现在空调狗的捐款太TMD麻烦了。

大致是：

- 打开捐款页面 [http://yourbay.me/donate](http://yourbay.me/donate)
- 扫描支付宝(也有微信)二维码。(由于在手机打开，因此在手机上做这件事很难)
- 点击支付宝链接
- 支付宝唤起失败(大概是因为支付宝被冻结了)
- 此路不通

于是想，既然支付宝可以通过WEB端唤起，那么一定可以找到相关的Intent。

## 2

然而，Google了一下基本都是告诉你怎么使用支付宝的sdk云云(也许是我没搜好:))

失望之余，想到了要不问问支付宝的基友。然而消息都写好了，点击发送之余我还是放弃了。这不是解决问题的方式嘛。于是就研究起了支付宝跳转的逻辑。

再次之前有两件事情需要准备：

> - 生成收款二维码
> 
> 可以到支付宝官网(具体Google下吧)生成一个二维码，我的如下：
> ![](/media/imgs/qr_alipay_hyongbai.jpg)
>
> - 获取支付链接
>
> 二维码其实最终被扫描出来后是一串字符，而这串字符其实就是一个链接。我的扫描结果是:
>
> [https://qr.alipay.com/ap9meauipfitn4t148](https://qr.alipay.com/ap9meauipfitn4t148)

## 3

在电脑端用Chrome访问得到的链接。注意， 此时由于是电脑访问，不会使用网页的方式呈现，并且会跳转到支付宝的移动端下载页。然而，这并没有什么大碍，因为Chrome可以通过`右键` → `检查` 进入到调试模式。那么接下来就好办了。

注意，此时UA需要切换到mobile，选择一款Android手机，如图:

![](/media/imgs/chrome-switch-mobile.png)

注意，此时页面仍然是支付宝移动端下载页，在浏览器中重新输入支付链接。

切换到`Sources`, 查看页面源码时，在js中猛然发现了一句注释:

>  // android 下 chrome 浏览器通过 intent 协议唤起钱包

整段代码如下：

```js
// android 下 chrome 浏览器通过 intent 协议唤起钱包
var packageKey = 'AlipayGphone';
if (isRc) {
    packageKey = 'AlipayGphoneRC';
}
var intentUrl = 'intent://platformapi/startapp?'+o.params+'#Intent;scheme='+ schemePrefix +';package=com.eg.android.'+ packageKey +';end';

var openIntentLink = document.getElementById('openIntentLink');
if (!openIntentLink) {
    openIntentLink = document.createElement('a');
    openIntentLink.id = 'openIntentLink';
    openIntentLink.style.display = 'none';
    document.body.appendChild(openIntentLink);
}
openIntentLink.href = intentUrl;
// 执行click
openIntentLink.dispatchEvent(customClickEvent());
```

因此我们只需要查看`intentUrl`对应的值即可，于是在330行处加了一个断点。

刷新：

![](/media/imgs/chrome-alipay-intent.jpg)

于是嘿嘿，答案就来了:

```js
	intent://platformapi/startapp?saId=10000007
	&clientVersion=3.7.0.0718
	&qrcode=https%3A%2F%2Fqr.alipay.com%2Fap9meauipfitn4t148%3F_s%3Dweb-other
	&_t=1475976145153#Intent;
	scheme=alipayqr;
	package=com.eg.android.AlipayGphone;
	end
```

翻译成Android可以理解的URI为：

```java
    public static boolean openAlipayPayPage(Context context) {
        return openAlipayPayPage(context, "https://qr.alipay.com/ap9meauipfitn4t148");
    }

    public static boolean openAlipayPayPage(Context context, String qrcode) {
        try {
            //https%3A%2F%2Fqr.alipay.com%2Fap9meauipfitn4t148
            qrcode = URLEncoder.encode(qrcode, "utf-8");
        } catch (Exception e) {
        }
        try {
            final String alipayqr = "alipayqr://platformapi/startapp?saId=10000007&clientVersion=3.7.0.0718&qrcode=" + qrcode;
            openUri(context, alipayqr + "%3F_s%3Dweb-other&_t=" + System.currentTimeMillis(), false);
            return true;
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }
```

看了一下js代码，其中`_t`是当前的时间戳，因此上面这个值使用的是调用时的时间戳`System.currentTimeMillis()`


## 4

说了一大堆废话，最终只是拿到一个uri而已。

但是，这其实是解决问题的一整个思路。