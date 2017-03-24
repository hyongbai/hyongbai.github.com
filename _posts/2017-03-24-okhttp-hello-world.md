---
layout: post
title: "OkHttp - 基本使用"
category: all-about-tech
tags: -[Square] -[Okhttp] -[Android]
date: 2017-03-24 13:39:57+00:00
---

## 关于

balababala(http)

## 使用

- 引入

在`build.gradle`的dependencies中引入`'com.squareup.okhttp3:okhttp:3.6.0'`(目前最新版是3.6)，即可添加OKHttp依赖。

```groovy
compile 'com.squareup.okhttp3:okhttp:3.6.0'
```

- 全局OkHttpClient

比如在Application中创建一个static的OkHttpClient或者在自己的OkHttpManager单例中创建一个，留以复用。而不必到处创建对象，也方便管理。

从源码的可以看到OkHttpClient支持两种方式创建。如下:

直接创建对象：

```java
public final OkHttpClient client = new OkHttpClient();
```


Builder模式：

```java
public final OkHttpClient client = new OkHttpClient.Builder()
  .addInterceptor(new HttpLoggingInterceptor())
  .cache(new Cache(cacheDir, cacheSize))
  .build();
```

貌似不太一样，其实`new OkHttpClient()`的时候调用的是`new OkHttpClient(new Builder())`, 也就是说默认会帮你配置一个`Builder`。根据自己的业务需要灵活配置。

需要注意的是：这些配置都是final的大多是不可重新设置的。其中`protocols`和`networkInterceptors`是immutable的。也就是说build完成之后就不可以更改的。其他对象参见其具体实现。

如下是Builder中可以配置的信息:

```java
  final Dispatcher dispatcher;
  final Proxy proxy;
  final List<Protocol> protocols;
  final List<ConnectionSpec> connectionSpecs;
  final List<Interceptor> interceptors;
  final List<Interceptor> networkInterceptors;
  final ProxySelector proxySelector;
  final CookieJar cookieJar;
  final Cache cache;
  final InternalCache internalCache;
  final SocketFactory socketFactory;
  final SSLSocketFactory sslSocketFactory;
  final CertificateChainCleaner certificateChainCleaner;
  final HostnameVerifier hostnameVerifier;
  final CertificatePinner certificatePinner;
  final Authenticator proxyAuthenticator;
  final Authenticator authenticator;
  final ConnectionPool connectionPool;
  final Dns dns;
  final boolean followSslRedirects;
  final boolean followRedirects;
  final boolean retryOnConnectionFailure;
  final int connectTimeout;
  final int readTimeout;
  final int writeTimeout;
```

- 创建Request

想要发送请求，那么你得有一个具体的请求。比如请求方式(GET/POST/PUT/DELETE等等)，服务器和API，需要发送到服务器的各种HEADER以及需要上传的内容(上传文件或者一段文字等)。因此`OkHttp`封装了一个`Request`，用来承载以上的需求。

下面分别创建一个GET和POST的`Request`

GET请求：

```java
 final Request request = new Request.Builder()
                .url("http://yourbay.me/AirFrozen")
                .addHeader("key", "name")
                .get()
                .build();
```

POST请求:

```java
final MediaType JsonType = MediaType.parse("application/json; charset=utf-8");
final RequestBody body = RequestBody.create(JsonType, jsonStr);
final Request request = new Request.Builder()
        .url("http://yourbay.me/AirFrozen")
        .addHeader("key", "name")
        .post(body)
        .build();
```

是不是很方便呢。其实还可以上传文件等等。只要创建一个RequestBody即可。比如上传文件可以使用`put(RequestBody)`:


```java
MediaType imageType = MediaType.parse("image/jpeg; charset=utf-8");//上传一个jpg文件
final RequestBody body = RequestBody.create(imageType, file);
final Request request = new Request.Builder()
        .url("http://yourbay.me/AirFrozen")
        .addHeader("key", "name")
        .put(body)
        .build();
```

- newCall

请求的时候OkHttp支持同步和异步两种方式供使用。

同步:

```java
final Response response = client//
                    .newCall(request)//
                    .execute();//
```

异步：

```java
client//
        .newCall(request)//
        .enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
            }

            @Override
            public void onResponse(Call call, Response response) throws IOException {
            }
        });//
```

不论是同步还是异步都是通过调用`OkHttpClient`的`newCall`来创建一个`Call`实体。通过`execute`或者`enqueue`即可实现同步或者异步调用。这也是标题为何使用`newCall`的原因。

- Response

同步或者异步最终都会返回一个`Response`, 通过此Response即可以得到请求结果。包含必要的信息出来，有意思的是`OkHttpClient`封装比较方便的地方在于其中会包含有一个`ResponseBody`(还记得请求的时候有一个`RequestBody`吗)，通过这个我们可以拿到服务器返回来的数据流。从而可以直接对其进行读取。

```java
if (response == null) return;
final ResponseBody responseBody = response.body();
if (responseBody == null) return;
final String result = responseBody.string();//直接获取字符串信息
final InputStream input = responseBody.byteStream();//拿到InputStream
final BufferedSource source = responseBody.source();//Okio接口,类似InputStream
```

相信你一定会使用OkHttp来进行网络请求了。但，这只是入门而已。既然是一个大家公认的好的网络请求框架，一定有其独特的一面，不妨多看看源码。或许会有更深的见解呢：）

## 其他


- MediaType

其实只是用来标识内容类型，可以简单理解为mime加上charset。可以参考源码。

```java

  /**
   * Returns the high-level media type, such as "text", "image", "audio", "video", or
   * "application".
   */
  public String type() {
    return type;
  }

  /**
   * Returns a specific media subtype, such as "plain" or "png", "mpeg", "mp4" or "xml".
   */
  public String subtype() {
    return subtype;
  }

  /**
   * Returns the charset of this media type, or null if this media type doesn't specify a charset.
   */
  public Charset charset() {
    return charset != null ? Charset.forName(charset) : null;
  }
```

## 计划

此处仅仅是浅显地介绍接一下OKHttp入门姿势，接下来会讲一讲OKHttp实现原理等等。如果不正，请打脸斧正。