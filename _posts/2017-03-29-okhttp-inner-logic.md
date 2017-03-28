---
layout: post
title: "OkHttp实现原理"
category: all-about-tech
tags: -[Square] -[Okhttp] -[Android]
date: 2017-03-29 14:55:57+00:00
---

前面在[OkHttp使用入门]({% post_url 2017-03-24-okhttp-hello-world %})中讲了，OKHttp的基本使用姿势。接下来将OKHttp的内部实现机制。


## Call

在上面我们提到使用OkHttp请求网络的时候主要是通过OkHttpClient.newCall(Request)生成一个Call然后使用同步/移步的方式来请求。这里Call其实是一个RealCall的实例。

下面我们分别来看看其同步和移步相关的逻辑：

#### 同步

```java
//RealCall.java
  @Override public Response execute() throws IOException {
    synchronized (this) {
      if (executed) throw new IllegalStateException("Already Executed");
      executed = true;
    }
    try {
      client.dispatcher().executed(this);
      Response result = getResponseWithInterceptorChain();
      if (result == null) throw new IOException("Canceled");
      return result;
    } finally {
      client.dispatcher().finished(this);
    }
  }
```
这里主要是将当前的call加入到OkHttpClient的dispatcher里面去，标记为正在加载。之后使用getResponseWithInterceptorChain去过具体的请求逻辑。之后再将自己从dispatcher中移除。先忽略getResponseWithInterceptorChain的实现部分。

#### 异步

```java
//RealCall.java
  @Override public void enqueue(Callback responseCallback) {
    synchronized (this) {
      if (executed) throw new IllegalStateException("Already Executed");
      executed = true;
    }
    client.dispatcher().enqueue(new AsyncCall(responseCallback));
  }
  
  final class AsyncCall extends NamedRunnable {
    private final Callback responseCallback;

    private AsyncCall(Callback responseCallback) {
      super("OkHttp %s", redactedUrl().toString());
      this.responseCallback = responseCallback;
    }

    String host() {
      return originalRequest.url().host();
    }

    Request request() {
      return originalRequest;
    }

    RealCall get() {
      return RealCall.this;
    }

    @Override protected void execute() {
      boolean signalledCallback = false;
      try {
        Response response = getResponseWithInterceptorChain();
        if (retryAndFollowUpInterceptor.isCanceled()) {
          signalledCallback = true;
          responseCallback.onFailure(RealCall.this, new IOException("Canceled"));
        } else {
          signalledCallback = true;
          responseCallback.onResponse(RealCall.this, response);
        }
      } catch (IOException e) {
        if (signalledCallback) {
          // Do not signal the callback twice!
          Platform.get().log(INFO, "Callback failure for " + toLoggableString(), e);
        } else {
          responseCallback.onFailure(RealCall.this, e);
        }
      } finally {
        client.dispatcher().finished(this);
      }
    }
  }
```

enqueue的时候，会生成一个AsyncCall。然后将这个Call代入到Dispatcher里面的enqueue中等待被调用。其实我们翻开那个AsyncCall的逻辑发现和同步中的实现没有区别。也是通过getResponseWithInterceptorChain获取到Response，结束的时候也会调用Dispathcer的finished()

下面我们看Dispatcher里面是如何实现的呢？

## Dispatcher

Dispatcher顾名思义就是调度之意。它里面主要维护了一个idleRunnable和三个Call队列。

```java
  private Runnable idleCallback;

  /** Executes calls. Created lazily. */
  private ExecutorService executorService;

  /** Ready async calls in the order they'll be run. */
  private final Deque<AsyncCall> readyAsyncCalls = new ArrayDeque<>();

  /** Running asynchronous calls. Includes canceled calls that haven't finished yet. */
  private final Deque<AsyncCall> runningAsyncCalls = new ArrayDeque<>();

  /** Running synchronous calls. Includes canceled calls that haven't finished yet. */
  private final Deque<RealCall> runningSyncCalls = new ArrayDeque<>();
```
其中idleCallback是当前没有任何任务的时候(即idle状态)被执行到的一个回调。这个待会会讲到。

下面讲讲三个队列：

- **readyAsyncCalls** 表示等待被执行的异步Call的队列。
- **runningAsyncCalls** 表示当前正在运行的异步步Call，会从readyAsyncCalls中移除。
- **runningSyncCalls** 表示运行当中的同步Call队列。

回到上面移步代码的部分，当Dispatcher调用enqueue之后的逻辑如下：

```java
  synchronized void enqueue(AsyncCall call) {
    if (runningAsyncCalls.size() < maxRequests && runningCallsForHost(call) < maxRequestsPerHost) {
      runningAsyncCalls.add(call);
      executorService().execute(call);
    } else {
      readyAsyncCalls.add(call);
    }
  }
```
其实enqueue做了主要做了两件事。第一件事情就是查看runningAsyncCalls是否达上限已经查看runningCallsForHost(即某个HOST同时请求数量)是否达到上限。如果都没有的话，就直接加入到运行队列当中，同时并且放入线程池中间去。否则，就放入等待队列readyAsyncCalls中间去。

当call被加入到线程池中等待执行很好理解。那么加入到异步等待队列中之后呢？谁来消费呢？

在上面AsyncCall就说过，当它处理结束之后会调用到Dispatcher里面的finished，那么我们不妨去finished中去一探究竟。

热腾腾的源码如下：

```java
  /** Used by {@code AsyncCall#run} to signal completion. */
  void finished(AsyncCall call) {
    finished(runningAsyncCalls, call, true);
  }
  
  private <T> void finished(Deque<T> calls, T call, boolean promoteCalls) {
    int runningCallsCount;
    Runnable idleCallback;
    synchronized (this) {
      if (!calls.remove(call)) throw new AssertionError("Call wasn't in-flight!");
      if (promoteCalls) promoteCalls();
      runningCallsCount = runningCallsCount();
      idleCallback = this.idleCallback;
    }

    if (runningCallsCount == 0 && idleCallback != null) {
      idleCallback.run();
    }
  }
```
可以看到，此处在AsyncCall被从runningAsyncCalls中移除之后，会调用`promoteCalls()`。

妈的idleCallback不干了，怎么不说我？插入一下广告：当finished之后，如果发现当前的运行队列中(runningAsyncCalls+runningSyncCalls)没有任何call并且idleCallback不为空的时候就会被触发。

好了回到promoteCalls()，我们去看看它到底做了什么呢?

```java
  private void promoteCalls() {
    if (runningAsyncCalls.size() >= maxRequests) return; // Already running max capacity.
    if (readyAsyncCalls.isEmpty()) return; // No ready calls to promote.

    for (Iterator<AsyncCall> i = readyAsyncCalls.iterator(); i.hasNext(); ) {
      AsyncCall call = i.next();

      if (runningCallsForHost(call) < maxRequestsPerHost) {
        i.remove();
        runningAsyncCalls.add(call);
        executorService().execute(call);
      }

      if (runningAsyncCalls.size() >= maxRequests) return; // Reached max capacity.
    }
  }
```

可以很清晰地看到，这里的逻辑基本与上面提到enqueue没多大区别。也会判断当前运行的队列大小，以及同一个HOST的请求量。如果都满足，就从readyAsyncCalls中移除一个Call，加入到runningAsyncCalls以及线程池当中。

注意，此处会最大限度地把等待中的Call加入到工作状态。直到队列被读完或者超过maxRequests。

Dispatcher的部分到此就结束了。OkHttp将工作队列以及HOST的同时请求还有idle回调全部都在此实现。这里完全只是处理任务的分发与具体的请求没有任何关系。

## Chain

上面讲到Dispatcher对于OkHttp里面线程的处理。但是并没有涉及到如何去发起请求，已经OkHttp神奇的地方。

上面讲到Call的时候我们提到`getResponseWithInterceptorChain`，下面我们来看看它是如何取得Response的:

```java
  private Response getResponseWithInterceptorChain() throws IOException {
    // Build a full stack of interceptors.
    List<Interceptor> interceptors = new ArrayList<>();
    interceptors.addAll(client.interceptors());
    interceptors.add(retryAndFollowUpInterceptor);
    interceptors.add(new BridgeInterceptor(client.cookieJar()));
    interceptors.add(new CacheInterceptor(client.internalCache()));
    interceptors.add(new ConnectInterceptor(client));
    if (!retryAndFollowUpInterceptor.isForWebSocket()) {
      interceptors.addAll(client.networkInterceptors());
    }
    interceptors.add(new CallServerInterceptor(
        retryAndFollowUpInterceptor.isForWebSocket()));

    Interceptor.Chain chain = new RealInterceptorChain(
        interceptors, null, null, null, 0, originalRequest);
    return chain.proceed(originalRequest);
  }
```
这段代码的核心就是RealInterceptorChain。初始化的时候加入了一个Interceptor列表和Request。这里我们先忽略掉这个Intercepter列表。继续看RealInterceptorChain的实现逻辑：

```java
//RealInterceptorChain.java
  public Response proceed(Request request, StreamAllocation streamAllocation, HttpStream httpStream,
      Connection connection) throws IOException {
    if (index >= interceptors.size()) throw new AssertionError();

    calls++;

    // If we already have a stream, confirm that the incoming request will use it.
    if (this.httpStream != null && !sameConnection(request.url())) {
      throw new IllegalStateException("network interceptor " + interceptors.get(index - 1)
          + " must retain the same host and port");
    }

    // If we already have a stream, confirm that this is the only call to chain.proceed().
    if (this.httpStream != null && calls > 1) {
      throw new IllegalStateException("network interceptor " + interceptors.get(index - 1)
          + " must call proceed() exactly once");
    }

    // Call the next interceptor in the chain.
    RealInterceptorChain next = new RealInterceptorChain(
        interceptors, streamAllocation, httpStream, connection, index + 1, request);
    Interceptor interceptor = interceptors.get(index);
    Response response = interceptor.intercept(next);

    // Confirm that the next interceptor made its required call to chain.proceed().
    if (httpStream != null && index + 1 < interceptors.size() && next.calls != 1) {
      throw new IllegalStateException("network interceptor " + interceptor
          + " must call proceed() exactly once");
    }

    // Confirm that the intercepted response isn't null.
    if (response == null) {
      throw new NullPointerException("interceptor " + interceptor + " returned null");
    }

    return response;
  }
```

这里最核心的就是通过获取前面传进来的Interceptor列表中当前index对应的Interceptor。并且使用Interceptor列表、下一个位置(index + 1)以及Request生成一个新的RealInterceptorChain。然后把这个RealInterceptorChain给Interceptor调用intercept(Chain)拿到Response。所以其实请求网络的逻辑其实实在Interceptor的实现类里完成的。

所以我相信大家这个时候还是蒙逼的状态。主要疑问会有两个，一个是为什么会index+1并且生成一个新的RealInterceptorChain，同时intercept(Chain)到底做了什么？

第一个问题很好解答。如果当前的Interceptor仅仅是来打酱油的，比如[HttpLoggingInterceptor](https://github.com/square/okhttp/tree/master/okhttp-logging-interceptor)，它是一个用来打印Request和Response的。本身自己并没有做除此之外的任何事情。那么它就可以打酱油把任务交给自己后面的(index + 1)的Interceptor来处理，你处理完之后给我，然后我在"原样返回"即可。这就解释了为什么需要index+1以及Interceptor列表还有Request了。至于HttpLoggingInterceptor的实现，大家可以看看它的源码。

第二个问题Interceptor到底干了嘛事？

## Interceptor

从上面Chain中我们可以了解到OkHttp主要是通过Interceptor一层一层分发调用来获取Response的。

现在我们还要回到RealCall中去看看，看看getResponseWithInterceptorChain到底有哪些Interceptor呢？

```java
//RealCall.java
    interceptors.addAll(client.interceptors());
    interceptors.add(retryAndFollowUpInterceptor);
    interceptors.add(new BridgeInterceptor(client.cookieJar()));
    interceptors.add(new CacheInterceptor(client.internalCache()));
    interceptors.add(new ConnectInterceptor(client));
    if (!retryAndFollowUpInterceptor.isForWebSocket()) {
      interceptors.addAll(client.networkInterceptors());
    }
    interceptors.add(new CallServerInterceptor(
        retryAndFollowUpInterceptor.isForWebSocket()));
```

- **用户自定义的Interceptor** 通过client.interceptors()拿到整个自定义列表。上面提到的HttpLoggingInterceptor就是在这个列表中。
- **RetryAndFollowUpInterceptor** 主要作用就是处理失败之后重试。比如处理未授权、PROXY授权等等。OkHttpClient.Builder中的proxyAuthenticator还有authenticator等都会在这里被调用。Chain里面的StreamAllocation在这里开始实例化，前面都是null。
- **BridgeInterceptor** 字面意思是桥梁连接应用和网络。主要会完善(添加)请求的Header、处理cookie、自动解压Gzip等等。
- **CacheInterceptor** 主要作用是缓存Response。官方推荐在OkHttpClient.Builder中使用`okhttp3.Cache`。
- **ConnectInterceptor** 主要是生成网络连接。调用StreamAllocation.newStream。分配一个复用的Connection。已经确定使用http1x还是http2x(HTTP/2 and SPDY)协议。
- **CallServerInterceptor** 请求服务器。与服务器进行交互。

## 连接复用
## 请求网络

未完待续