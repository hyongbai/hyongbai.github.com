---
layout: post
title: "OkHttp实现原理"
category: all-about-tech
tags: -[Square] -[Okhttp] -[Android]
date: 2017-03-29 14:55:57+00:00
---

前面在[OkHttp使用入门]({% post_url 2017-03-24-okhttp-hello-world %})中讲了，OKHttp的基本使用姿势。接下来将OKHttp的内部实现机制。

注: 本文基于OkHttp3.4.1写

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
- **ConnectInterceptor** 主要是生成网络连接。调用StreamAllocation.newStream，分配一个复用的Connection。然后以HttpStream和RealConnection的形式交给下一个Interceptor(即CallServerInterceptor)。其中在HttpStream中来确定使用http1x还是HTTP/2x(HTTP/2 and SPDY)协议。
- **CallServerInterceptor** 请求服务器。与服务器进行交互。获取数据并且封装起来返回给ConnectInterceptor。然后逐级分发回去。最后getResponseWithInterceptorChain接受数据，返回给用户。

其实这中设计思路有点类似Fresco中的Pipeline。知道Fesco的应该知道它的Producer的实现逻辑就是一条一条连通着的管道，可以截流上游封装完之后传递给下游，也可以直接截断上游从自己的缓存策略中直接给下游数据。这里的Interceptor也是一样，比如CacheInterceptor。也可以自己定义Intercepter截断整个连接通路。

## 连接复用

大家可能都知道OkHttp支持连接复用。但是传说中的连接复用是如何实现的呢？怎样释放的呢？

在上面我们提到ConnectInterceptor所做的事情就是为CallServerInterceptor准备好请求服务器所需要的HttpStream、RealConnection等。

好了背景交待好了之后我们来分析ConnectInterceptor的实现:

```java
  @Override public Response intercept(Chain chain) throws IOException {
    RealInterceptorChain realChain = (RealInterceptorChain) chain;
    Request request = realChain.request();
    StreamAllocation streamAllocation = realChain.streamAllocation();

    // We need the network to satisfy this request. Possibly for validating a conditional GET.
    boolean doExtensiveHealthChecks = !request.method().equals("GET");
    HttpStream httpStream = streamAllocation.newStream(client, doExtensiveHealthChecks);
    RealConnection connection = streamAllocation.connection();

    return realChain.proceed(request, streamAllocation, httpStream, connection);
  }
```

这里面最关键的部分就是`streamAllocation.newStream(client, doExtensiveHealthChecks)`，后面一句拿到的RealConnection也是在这个过程中处理好的，仅仅是执行了一个get行为。

代码继续往下写，思路继续跟着走，我们来到了StreamAllocation。

看看究竟发生了什么神奇的事情:

```java
  public HttpStream newStream(OkHttpClient client, boolean doExtensiveHealthChecks) {
    int connectTimeout = client.connectTimeoutMillis();
    int readTimeout = client.readTimeoutMillis();
    int writeTimeout = client.writeTimeoutMillis();
    boolean connectionRetryEnabled = client.retryOnConnectionFailure();

    try {
      RealConnection resultConnection = findHealthyConnection(connectTimeout, readTimeout,
          writeTimeout, connectionRetryEnabled, doExtensiveHealthChecks);

      HttpStream resultStream;
      if (resultConnection.framedConnection != null) {
        resultStream = new HTTP/2xStream(client, this, resultConnection.framedConnection);
      } else {
        resultConnection.socket().setSoTimeout(readTimeout);
        resultConnection.source.timeout().timeout(readTimeout, MILLISECONDS);
        resultConnection.sink.timeout().timeout(writeTimeout, MILLISECONDS);
        resultStream = new Http1xStream(
            client, this, resultConnection.source, resultConnection.sink);
      }

      synchronized (connectionPool) {
        stream = resultStream;
        return resultStream;
      }
    } catch (IOException e) {
      throw new RouteException(e);
    }
  }
```

这里其实分为两部分。一部分获取到RealConnection，一部分生成HttpStream。后者是根据前者是不是存在framedConnection，来判断使用Http1x还是HTTP/2x。如果存在framedConnection，那么使用的就是HTTP/2x，因为frame是HTTP/2、SPDY里面很重要的一个元素。我们先抛弃1.x和2的实现部分，主要来看看RealConnection是如何拿到的。

```java
  private RealConnection findHealthyConnection(int connectTimeout, int readTimeout,
      int writeTimeout, boolean connectionRetryEnabled, boolean doExtensiveHealthChecks)
      throws IOException {
    while (true) {
      RealConnection candidate = findConnection(connectTimeout, readTimeout, writeTimeout,
          connectionRetryEnabled);

      // If this is a brand new connection, we can skip the extensive health checks.
      synchronized (connectionPool) {
        if (candidate.successCount == 0) {
          return candidate;
        }
      }

      // Do a (potentially slow) check to confirm that the pooled connection is still good. If it
      // isn't, take it out of the pool and start again.
      if (!candidate.isHealthy(doExtensiveHealthChecks)) {
        noNewStreams();
        continue;
      }

      return candidate;
    }
  }
```

上面代码可以发现RealConnection其实主要是通过`findConnection`拿到，接着会检测这个Connection是否有效，如果有效则返回。继续通过isHealthy是否有效，有效则使用。无效则会重新调用`findConnection`重新获取，并且将其标记为noNewFrame。这个`noNewFrame`的主要意思为无法进行读写操作了。

看一下isHealthy的实现：

```java
  /** Returns true if this connection is ready to host new streams. */
  public boolean isHealthy(boolean doExtensiveChecks) {
    if (socket.isClosed() || socket.isInputShutdown() || socket.isOutputShutdown()) {
      return false;
    }

    if (framedConnection != null) {
      return true; // TODO: check framedConnection.shutdown.
    }

    if (doExtensiveChecks) {
      try {
        int readTimeout = socket.getSoTimeout();
        try {
          socket.setSoTimeout(1);
          if (source.exhausted()) {
            return false; // Stream is exhausted; socket is closed.
          }
          return true;
        } finally {
          socket.setSoTimeout(readTimeout);
        }
      } catch (SocketTimeoutException ignored) {
        // Read timed out; socket is good.
      } catch (IOException e) {
        return false; // Couldn't read; socket is closed.
      }
    }

    return true;
  }
```

可以看到当socket关闭或者输入/输入流被关闭或者source(类似InputStream)进入exhausted状态都认为是不健康的。有一种状态。都标记为noNewFrame。此时这个Connection将不会被复用了。接下来会讲为什么不会被复用。

差不多了解了noNewFrame之后我们回到`findConnection`里面去看看如何拿到Conection的。

```java
//StreamAllocation.java
  private RealConnection findConnection(int connectTimeout, int readTimeout, int writeTimeout,
      boolean connectionRetryEnabled) throws IOException {
    Route selectedRoute;
    synchronized (connectionPool) {
      if (released) throw new IllegalStateException("released");
      if (stream != null) throw new IllegalStateException("stream != null");
      if (canceled) throw new IOException("Canceled");

      RealConnection allocatedConnection = this.connection;
      if (allocatedConnection != null && !allocatedConnection.noNewStreams) {
        return allocatedConnection;
      }

      // Attempt to get a connection from the pool.
      RealConnection pooledConnection = Internal.instance.get(connectionPool, address, this);
      if (pooledConnection != null) {
        this.connection = pooledConnection;
        return pooledConnection;
      }

      selectedRoute = route;
    }

    if (selectedRoute == null) {
      selectedRoute = routeSelector.next();
      synchronized (connectionPool) {
        route = selectedRoute;
        refusedStreamCount = 0;
      }
    }
    RealConnection newConnection = new RealConnection(selectedRoute);
    acquire(newConnection);

    synchronized (connectionPool) {
      Internal.instance.put(connectionPool, newConnection);
      this.connection = newConnection;
      if (canceled) throw new IOException("Canceled");
    }

    newConnection.connect(connectTimeout, readTimeout, writeTimeout, address.connectionSpecs(),
        connectionRetryEnabled);
    routeDatabase().connected(newConnection.route());

    return newConnection;
  }
```

首先它会检查自己的状态是不是有效的，如果released/canceled或者stream!=null的时候都会抛出异常结束请求，如果connection不为空并且没有标记为noNewFrame的话就直接使用当前的connection，那么问题来了。这个connection一开始不应该是空的吗？还记得上面说的RetryAndFollewUpInterceptor吗，我们知道StreamAllaction是在那里生成的，痛失那里会做不断重试，只要followUp里面的host/post/scheme不变的话，就会复用一开始的StreamAllaction对象。如果前次已经生成了Connection并且有效的话，为什么还要新的呢？这就是connection这个字段的由来。


接着，它会去使用address去ConnecetionPool去取一个可复用的Connection。看看是怎么获取的：

```java
//ConnecetionPool.java
  RealConnection get(Address address, StreamAllocation streamAllocation) {
    assert (Thread.holdsLock(this));
    for (RealConnection connection : connections) {
      if (connection.allocations.size() < connection.allocationLimit
          && address.equals(connection.route().address)
          && !connection.noNewStreams) {
        streamAllocation.acquire(connection);
        return connection;
      }
    }
    return null;
  }
```
这里会去ConnecetionPool持有的连接队列中遍历，寻找一模一样的地址的并且单个连接同时处理的请求数量不超过上限的，且没有被标记为noNewStreams的。如果条件满足，则返回这个Connection，并且将持有这个Connection的StreamAllocation加入到Connection的allocations列表中(弱引用)。可以去看`streamAllocation.acquire(connection)`。【复用上限】的逻辑待会讲，大兄弟咱不着急。

回到StreamAllocation。如果发现池子里面有有效的Connection的话，则直接使用。否则，就只能自己创建一个了。

创建的时候我们略过Route的过程。这里直接new一个RealConnection对象。之后做的事前跟前面从连接池（ConnectionPool）的操作一样。让后Connection持有当前的StreamAllocation对象。然后把当前Connection放入到连接池里面留给缓存待用。到这里Connection的复用逻辑基本就清晰了。【连接释放】先不说。

由于新创建的Connection并没有连接到服务器，如果此时直接返回的话必然导致isHealthy无法通过。所以在返回之前有必要先连接服务器。不过连接的事情，会放到网络请求的部分去讲。

## 请求网络

上面我们留下了RealConnection是如何连接的问题。接下来就讲讲是如何跟服务器连接，并且是如何发送请求以及处理数据的。

#### 建立连接

我们知道在StreamAllocation中创建一个新的Connection的时候，需要先建立连接方能交给ServerInterceptor。

那么建立连接的过程是怎么样的呢？

```java
//RealConnection.java
  public void connect(int connectTimeout, int readTimeout, int writeTimeout,
      List<ConnectionSpec> connectionSpecs, boolean connectionRetryEnabled) {
    if (protocol != null) throw new IllegalStateException("already connected");

    RouteException routeException = null;
    ConnectionSpecSelector connectionSpecSelector = new ConnectionSpecSelector(connectionSpecs);

    if (route.address().sslSocketFactory() == null) {
      if (!connectionSpecs.contains(ConnectionSpec.CLEARTEXT)) {
        throw new RouteException(new UnknownServiceException("CLEARTEXT communication not enabled for client"));
      }
      String host = route.address().url().host();
      if (!Platform.get().isCleartextTrafficPermitted(host)) {
        throw new RouteException(new UnknownServiceException("CLEARTEXT communication to " + host + " not permitted by network security policy"));
      }
    }

    while (protocol == null) {
      try {
        if (route.requiresTunnel()) {
          buildTunneledConnection(connectTimeout, readTimeout, writeTimeout,connectionSpecSelector);
        } else {
          buildConnection(connectTimeout, readTimeout, writeTimeout, connectionSpecSelector);
        }
      } catch (IOException e) {
        //...
        if (!connectionRetryEnabled || !connectionSpecSelector.connectionFailed(e)) {
          throw routeException;
        }
      }
    }
  }
```

其实吧主要逻辑都在while循环当中。会通过Route来确定是不是需要Tunnel(Tunnel大致是HTTP代理Https的一种方式，只需要记得这里需要特殊处理https即可)。所以`buildTunneledConnection`和`buildConnection`不同的地方在于建立socket连接之后是不是需要再创建一个Tunnel。

那就来看看OkHttp里面是如何建立Http连接的吧。

```java
//RealConnection.java
  /** Does all the work necessary to build a full HTTP or HTTPS connection on a raw socket. */
  private void buildConnection(int connectTimeout, int readTimeout, int writeTimeout,
      ConnectionSpecSelector connectionSpecSelector) throws IOException {
    connectSocket(connectTimeout, readTimeout);
    establishProtocol(readTimeout, writeTimeout, connectionSpecSelector);
  }

  private void connectSocket(int connectTimeout, int readTimeout) throws IOException {
    Proxy proxy = route.proxy();
    Address address = route.address();

    rawSocket = proxy.type() == Proxy.Type.DIRECT || proxy.type() == Proxy.Type.HTTP
        ? address.socketFactory().createSocket()
        : new Socket(proxy);

    rawSocket.setSoTimeout(readTimeout);
    try {
      Platform.get().connectSocket(rawSocket, route.socketAddress(), connectTimeout);
    } catch (ConnectException e) {
      throw new ConnectException("Failed to connect to " + route.socketAddress());
    }
    source = Okio.buffer(Okio.source(rawSocket));
    sink = Okio.buffer(Okio.sink(rawSocket));
  }
```

这里其实就是通过RouteSelector里面生成的route。创建一个Socket并且创建socket连接。连接成功之后顺便把Socket里面的Input/Output转化成Okio中的Source/Sink。

之后调用establishProtocol确定当前的使用的protocol是http1x还是HTTP/2或者SPDY。这里就提到了上面讲连接复用时提到的单个连接同时处理多个请求的上限了。

#### 多路复用

其实就是多路复用。实现如下:

```java
//RealConnection.java
  private void establishProtocol(int readTimeout, int writeTimeout,
      ConnectionSpecSelector connectionSpecSelector) throws IOException {
    if (route.address().sslSocketFactory() != null) {
      connectTls(readTimeout, writeTimeout, connectionSpecSelector);
    } else {
      protocol = Protocol.HTTP_1_1;
      socket = rawSocket;
    }

    if (protocol == Protocol.SPDY_3 || protocol == Protocol.HTTP_2) {
      socket.setSoTimeout(0); // Framed connection timeouts are set per-stream.

      FramedConnection framedConnection = new FramedConnection.Builder(true)
          .socket(socket, route.address().url().host(), source, sink)
          .protocol(protocol)
          .listener(this)
          .build();
      framedConnection.start();

      // Only assign the framed connection once the preface has been sent successfully.
      this.allocationLimit = framedConnection.maxConcurrentStreams();
      this.framedConnection = framedConnection;
    } else {
      this.allocationLimit = 1;
    }
  }
```
可以看到如果当前的网络协议是HTTP/1X的时候为1。其实在这里讨论没啥意义。因为多路复用其实只有在HTTP/2/SPDY出来之后才实现的。HTTP/0.9只能一个连接完成后创建一个新连接不能复用。而HTTP/1x之后添加了Keep-Alive可以将多个请求放进一个连接中，但是只能前面处理完了后面才开始相应。而HTTP/2则将多个请求合并在一起，给每个frame标记然后同时处理就可以拜托1X时代顺序的问题了。

去看到FramedConnection初始化可以看到`peerSettings.set(Settings.MAX_FRAME_SIZE, 0, Http2.INITIAL_MAX_FRAME_SIZE);`对应的值是`0x4000`

#### 发起请求
上面只是说到了OkHttp如何建立连接。但是到目前为止没有发送任何数据。现在我们可以回到ConnectInterceptor了。

此时ConnectInterceptor将任务通过RealInterceptorChain交给下一个Interceptor了。

```java
//ConntectInterceptor.java
realChain.proceed(request, streamAllocation, httpStream, connection)
```

上面我们知道接下来就是CallServerInterceptor上场来耍了。

```java
 @Override public Response intercept(Chain chain) throws IOException {
    HttpStream httpStream = ((RealInterceptorChain) chain).httpStream();
    StreamAllocation streamAllocation = ((RealInterceptorChain) chain).streamAllocation();
    Request request = chain.request();

    long sentRequestMillis = System.currentTimeMillis();
    httpStream.writeRequestHeaders(request);

    if (HttpMethod.permitsRequestBody(request.method()) && request.body() != null) {
      Sink requestBodyOut = httpStream.createRequestBody(request, request.body().contentLength());
      BufferedSink bufferedRequestBody = Okio.buffer(requestBodyOut);
      request.body().writeTo(bufferedRequestBody);
      bufferedRequestBody.close();
    }

    httpStream.finishRequest();

    Response response = httpStream.readResponseHeaders()
        .request(request)
        .handshake(streamAllocation.connection().handshake())
        .sentRequestAtMillis(sentRequestMillis)
        .receivedResponseAtMillis(System.currentTimeMillis())
        .build();

    if (!forWebSocket || response.code() != 101) {
      response = response.newBuilder()
          .body(httpStream.openResponseBody(response))
          .build();
    }

    if ("close".equalsIgnoreCase(response.request().header("Connection"))
        || "close".equalsIgnoreCase(response.header("Connection"))) {
      streamAllocation.noNewStreams();
    }

    int code = response.code();
    if ((code == 204 || code == 205) && response.body().contentLength() > 0) {
      throw new ProtocolException(
          "HTTP " + code + " had non-zero Content-Length: " + response.body().contentLength());
    }

    return response;
  }
```

这里的逻辑其实非常之简单了。简而言之只有三个步骤：

- 写Header
- 写Body
- 读Response

由于在Socket连接的时候确定了protocol。所以在这里HttpStream使用了对应的HttpStream去实现具体的请求。Http1xStream没什么好说的。Http2xStream里面主要用到了FramedConnection来写入和读取数据。至于协议的实现先不说了。

复杂的逻辑都在HttpStream(Http1xStream/Http2xStream)中。:)

## 连接释放



#### 后台扫描

在StreamAllocation我们知道当创建一个新的Connection之后，这个Connection会被放到ConnectionPool中。此时Pool会启动一个扫描的任务。所做的事情就是每个一定时间不断扫描当前的连接池一直到没有连接为止，如果某个连接超过一定时间没被使用并且超过最大idle限制则主动释放之。

```java
//ConnectionPool.java
  void put(RealConnection connection) {
    assert (Thread.holdsLock(this));
    if (!cleanupRunning) {
      cleanupRunning = true;
      executor.execute(cleanupRunnable);
    }
    connections.add(connection);
  }
```
这点代码就是先将清理扫描的任务启动，之后将连接放到队列中。那么我们来看是如何清理的。

```java
  private final Runnable cleanupRunnable = new Runnable() {
    @Override public void run() {
      while (true) {
        long waitNanos = cleanup(System.nanoTime());
        if (waitNanos == -1) return;
        if (waitNanos > 0) {
          long waitMillis = waitNanos / 1000000L;
          waitNanos -= (waitMillis * 1000000L);
          synchronized (ConnectionPool.this) {
            try {
              ConnectionPool.this.wait(waitMillis, (int) waitNanos);
            } catch (InterruptedException ignored) {
            }
          }
        }
      }
    }
  };
```

可以看到只要cleanup返回的等待时间为-1才会主动停止任务。否则会等待唤醒之后继续清理。所以核心的代码还是在`cleanup`中。

```java
//ConnectionPool.java
  long cleanup(long now) {
    int inUseConnectionCount = 0;
    int idleConnectionCount = 0;
    RealConnection longestIdleConnection = null;
    long longestIdleDurationNs = Long.MIN_VALUE;

    // Find either a connection to evict, or the time that the next eviction is due.
    synchronized (this) {
      for (Iterator<RealConnection> i = connections.iterator(); i.hasNext(); ) {
        RealConnection connection = i.next();

        // If the connection is in use, keep searching.
        if (pruneAndGetAllocationCount(connection, now) > 0) {
          inUseConnectionCount++;
          continue;
        }

        idleConnectionCount++;

        // If the connection is ready to be evicted, we're done.
        long idleDurationNs = now - connection.idleAtNanos;
        if (idleDurationNs > longestIdleDurationNs) {
          longestIdleDurationNs = idleDurationNs;
          longestIdleConnection = connection;
        }
      }

      if (longestIdleDurationNs >= this.keepAliveDurationNs
          || idleConnectionCount > this.maxIdleConnections) {
        // We've found a connection to evict. Remove it from the list, then close it below (outside
        // of the synchronized block).
        connections.remove(longestIdleConnection);
      } else if (idleConnectionCount > 0) {
        // A connection will be ready to evict soon.
        return keepAliveDurationNs - longestIdleDurationNs;
      } else if (inUseConnectionCount > 0) {
        // All connections are in use. It'll be at least the keep alive duration 'til we run again.
        return keepAliveDurationNs;
      } else {
        // No connections, idle or in use.
        cleanupRunning = false;
        return -1;
      }
    }

    closeQuietly(longestIdleConnection.socket());

    // Cleanup again immediately.
    return 0;
  }
```

这段逻辑主要是通过`pruneAndGetAllocationCount`来断定当前的Connection是不是idle状态。在for循环中会过滤出最大空闲时间以及对应的连接。

- 如果idle的时间超过最大空闲时间或者空闲的连接超过最大空闲数量那么最长空闲连接将会被丢弃，并且立马进入下一次清理。
- 如果有空闲的连接，则等待keepAliveDurationNs - longestIdleDurationNs之后继续清理。
- 如果有仍然在使用的连接，那么等等keepAliveDurationNs之后继续清理。
- 否则直接退出扫描。

其中pruneAndGetAllocationCount里面的逻辑就是查看一个连接被请求(被StreamAllocation持有)的数量。如果为0则认为idle状态。有意思的是如果Connection持有的某一个StreamAllocation引用(WeakReference)被释放掉了的话，这个Connection会被标记为noNewStream。


#### 主动释放

当Response被close掉的时候，会调用StreamAllocation里面的streamFinished.

Http1xStream中：

```java
//Http1xStream.java
    protected final void endOfInput(boolean reuseConnection) throws IOException {
      if (state == STATE_CLOSED) return;
      if (state != STATE_READING_RESPONSE_BODY) throw new IllegalStateException("state: " + state);

      detachTimeout(timeout);

      state = STATE_CLOSED;
      if (streamAllocation != null) {
        streamAllocation.streamFinished(!reuseConnection, Http1xStream.this);
      }
    }
  }
```

Http2xStream中：

```java
//Http2xStream
  class StreamFinishingSource extends ForwardingSource {
    public StreamFinishingSource(Source delegate) {
      super(delegate);
    }

    @Override public void close() throws IOException {
      streamAllocation.streamFinished(false, Http2xStream.this);
      super.close();
    }
  }
```
继续看是如何释放的。

```java
//StreamAllocation.java
  public void streamFinished(boolean noNewStreams, HttpStream stream) {
    synchronized (connectionPool) {
      if (stream == null || stream != this.stream) {
        throw new IllegalStateException("expected " + this.stream + " but was " + stream);
      }
      if (!noNewStreams) {
        connection.successCount++;
      }
    }
    deallocate(noNewStreams, false, true);
  }
  
    private void deallocate(boolean noNewStreams, boolean released, boolean streamFinished) {
    RealConnection connectionToClose = null;
    synchronized (connectionPool) {
      if (streamFinished) {
        this.stream = null;
      }
      if (released) {
        this.released = true;
      }
      if (connection != null) {
        if (noNewStreams) {
          connection.noNewStreams = true;
        }
        if (this.stream == null && (this.released || connection.noNewStreams)) {
          release(connection);
          if (connection.allocations.isEmpty()) {
            connection.idleAtNanos = System.nanoTime();
            if (Internal.instance.connectionBecameIdle(connectionPool, connection)) {
              connectionToClose = connection;
            }
          }
          connection = null;
        }
      }
    }
    if (connectionToClose != null) {
      Util.closeQuietly(connectionToClose.socket());
    }
  }
  
    /** Remove this allocation from the connection's list of allocations. */
  private void release(RealConnection connection) {
    for (int i = 0, size = connection.allocations.size(); i < size; i++) {
      Reference<StreamAllocation> reference = connection.allocations.get(i);
      if (reference.get() == this) {
        connection.allocations.remove(i);
        return;
      }
    }
    throw new IllegalStateException();
  }
```

streamFinished的主要作用是将当前的httpStream释放掉。而released这个参数并没有被标记为true，也就是说如果连接被标记为noNewStream之后那么就会将Connection释放掉。而Http2Stream是不会被标记为noNewStream的，Http1Stream中的只要明确数据没有读完那么即使close也不会被标记为noNewStream。所以其实并不会把StreamAllocation从Connection中移除，因此Connection就一直就不会进入idle状态。那么问题来上面不是说idle一段时间后才会被扫描策略释放，那么idle哪里来?

那么我们的思路就转到StreamAllocation被Release的地方看看。前面讲到在RetryAndFollowUpInterceptor中，会根据Response的状态来判断是不是需要Follower，比如代理、权限等出问题时。但是当一个返回是正常的时候，不会进行FollowUp。此时会调用Release释放。关键代码：

```java
//RetryAndFollowUpInterceptor.java
Request followUp = followUpRequest(response);
if (followUp == null) {
if (!forWebSocket) {
  streamAllocation.release();
}
return response;
}
```


### 思考

同时请求两个一模一样的URL时，OkHttp会合并请求吗？

Router、Proxy、DNS