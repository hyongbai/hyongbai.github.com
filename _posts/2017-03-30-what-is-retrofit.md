---
layout: post
title: "Retrofit如何使用如何work"
category: all-about-tech
tags: -[Square] -[Okhttp] -[Android] -[Retrofit]
date: 2017-03-30 16:01:57+00:00
---

## 介绍

Retrofit的出现让我们使用API变地更简单更直观更人性化了。它是Square出品的一块很有用API框架库，需要跟OkHttp配合使用。你甚至不用多谢代码只要写好配置文件即可实现API调用了。

另外它还支持市面上大多数的数据格式。比如gson/jackson/wire/protobuf等。你只要导入官方的Converter加入到Retrofit的配置中即可了。

下面讲讲如何使用以及如何作用的。

## 使用姿势

Retrofit本身就已经依赖OkHttp了。所以你不用再添加它的依赖了。

#### 添加依赖

```groovy
compile "com.squareup.retrofit2:retrofit:2.2.0"
```

如果你想支持GSON的话，还可以:

```groovy
compile "com.squareup.retrofit2:converter-gson"
```

#### API介绍

- **HTTP方法**如果你想发送一个POST请求，只需要添加添加@POST即可。
- **URL**@POST/@GET(等)的value就是url，比如你可以这样@POST("/file/{id}/comment")，注意如果你没有添加域名的话，它会认为你是相对地址。
- **Path**上面的说到URL的时候看了{id}是不是，这表示它是一个路径。在你的参数里面加上@Path("id")即可。
- **还有很多** 不列举了，具体的可以看<http://square.github.io/retrofit>

#### 基本使用

它的API其实很简单，只需要添加注解就可以了。下面是我使用时写的简单的Sample。

```java
public class RetrofitFragment extends BNFragment {
    private Callback callback = new Callback<String>() {
        @Override
        public void onResponse(Call<String> call, Response<String> response) {
            result.setText("onResponse:\nREQUEST:" + call.request().url().uri() + "\nRESPONSE:" + response.body());
        }

        @Override
        public void onFailure(Call<String> call, Throwable t) {
            result.setText("onFailure:\nREQUEST:" + call.request().url().uri() + "\nRESPONSE:" + Log.getStackTraceString(t));
        }
    };

    @BindView(R.id.result)
    TextView result;

    public RetrofitFragment() {
        setLayoutId(R.layout.frag_okhttp);
    }

    @OnClick(R.id.get)
    public void get(View view) {
        create().build().create(Api.class).sina(LONG_URL).enqueue(callback);
    }

    @OnClick(R.id.post)
    public void post(View view) {
        create().build().create(Api.class).baidu("url='" + LONG_URL + "'").enqueue(callback);
    }

    public interface Api {
        @GET("http://api.t.sina.com.cn/short_url/shorten.json?source=2483680040")
        retrofit2.Call<String> sina(@Query("url_long") String longUrl);

        @POST("http://dwz.cn/create.php")
        retrofit2.Call<String> baidu(@Body String body);
    }

    public static Retrofit.Builder create() {
        return new Retrofit.Builder().client(okClient).baseUrl("http://yourbay.me").addConverterFactory(new Converter.Factory() {
            @Override
            public Converter<ResponseBody, String> responseBodyConverter(Type type, Annotation[] an, Retrofit re) {
                return v -> v.toString() + " " + v.string();
            }

            @Override
            public Converter<String, RequestBody> requestBodyConverter(Type type, Annotation[] pAn, Annotation[] an, Retrofit re) {
                return v -> RequestBody.create(null, v);
            }
        });
    }
}
```

例中不是标准的Fragment请忽略关于Fragment的逻辑。

这里面主要发送了两个请求，一个GET和一个POST。

在使用的时候你需要build一个Retrofit对象，然后Create你写的Api接口(注意必须是interface)。之后它会自动实现里面的接口就可以使用那个接口了。注意你的接口返回值必须是一个Call。

注意，你必须要加上baseUrl，否则不能呢个创建Retrofit。当你的注解里面写的是绝对地址的时候这个地址不会用到。

当用户点击GET按钮的时候，我调用了sina这个接口，此时返回了一个Call熟悉OkHttp的小伙伴应该知道这个是很重要的返回类，你需要做的是调用它的enqueue或者execute即可以实现异步或者同步请求了。可以移步这里看看OkHttp，[OkHttp使用入门 ]({% post_url 2017-03-24-okhttp-hello-world %})  / [OkHttp实现原理]({% post_url 2017-03-29-okhttp-inner-logic %})

注意：需要说明的时候由于我需要的返回值是String，而Retrofit默认是不支持返回值为String的，如果自己不实现Converter的话，在请求之前之初它会抛出"Unable to create converter for String  for method xxx"的IllegalArgumentException。还有我在`baidu(@Body String body)`这个API中添加了Body，它也会抛出"Unable to create @Body converter for String"的异常。所以我自定义了一个`ConverterFactory`。

大概使用姿势就是这样，但是我们的目的不仅仅是用，要知道怎么实现才能够提升自己。

## 运行原理

Retrofit要求使用接口主要是因为它的实现是通过JAVA中的动态代理来动态实现接口的。这就解决了只需要写接口不需要写实现的麻烦了。

其次，Retrofit通过注解的方式来表达api就注定它需要使用反射来最终读取这些配置。

### 动态代理

上面的例子可以知道当用户build一个Retrofit实例之后需要通过Create来实现接口中的API。所以这里是关键入口。

来来来我们看看这个入口做了什么:

```java
//Retrofit
  public <T> T create(final Class<T> service) {
    Utils.validateServiceInterface(service);
    if (validateEagerly) {
      eagerlyValidateMethods(service);
    }
    return (T) Proxy.newProxyInstance(service.getClassLoader(), new Class<?>[] { service },
        new InvocationHandler() {
          private final Platform platform = Platform.get();

          @Override public Object invoke(Object proxy, Method method, Object[] args)
              throws Throwable {
            // If the method is a method from Object then defer to normal invocation.
            if (method.getDeclaringClass() == Object.class) {
              return method.invoke(this, args);
            }
            if (platform.isDefaultMethod(method)) {
              return platform.invokeDefaultMethod(method, service, proxy, args);
            }
            ServiceMethod<Object, Object> serviceMethod =
                (ServiceMethod<Object, Object>) loadServiceMethod(method);
            OkHttpCall<Object> okHttpCall = new OkHttpCall<>(serviceMethod, args);
            return serviceMethod.callAdapter.adapt(okHttpCall);
          }
        });
  }
```
Proxy运行的基本逻辑是，当你使用某一个接口时InvocationHandler里面invoke会被回调到，这里会返回调用的Method和参数。因此我们只要在这里拿到这个Method中我们已经配置好的Annotation就可以去处理相应的逻辑了哈。

那么我们来看看Retrofit是如何将接口和参数整合好并且可以发起网络请求的呢？请继续看。

### 解析注解

上面讲到我们最需要知道的是有什么注解有什么注解信息，那么我们必然要去反射拿到注解信息了。因此这里最核心的逻辑是查看`loadServiceMethod`的处理过程。

```java
//Retrofit.java
  ServiceMethod<?, ?> loadServiceMethod(Method method) {
    ServiceMethod<?, ?> result = serviceMethodCache.get(method);
    if (result != null) return result;

    synchronized (serviceMethodCache) {
      result = serviceMethodCache.get(method);
      if (result == null) {
        result = new ServiceMethod.Builder<>(this, method).build();
        serviceMethodCache.put(method, result);
      }
    }
    return result;
  }
```
这里其实会缓存Method处理结果。以便下次可以直接使用，从而提高性能。好，那么我们来看耗时的过程。也就是Build出一个ServiceMethod的过程：

```java
//ServiceMethod.java
    Builder(Retrofit retrofit, Method method) {
      this.retrofit = retrofit;
      this.method = method;
      this.methodAnnotations = method.getAnnotations();
      this.parameterTypes = method.getGenericParameterTypes();
      this.parameterAnnotationsArray = method.getParameterAnnotations();
    }

    public ServiceMethod build() {
      callAdapter = createCallAdapter();
      responseType = callAdapter.responseType();
      if (responseType == Response.class || responseType == okhttp3.Response.class) {
        throw methodError("'"
            + Utils.getRawType(responseType).getName()
            + "' is not a valid response body type. Did you mean ResponseBody?");
      }
      responseConverter = createResponseConverter();

      for (Annotation annotation : methodAnnotations) {
        parseMethodAnnotation(annotation);
      }

      if (httpMethod == null) {
        throw methodError("HTTP method annotation is required (e.g., @GET, @POST, etc.).");
      }

      if (!hasBody) {
        if (isMultipart) {
          throw methodError(
              "Multipart can only be specified on HTTP methods with request body (e.g., @POST).");
        }
        if (isFormEncoded) {
          throw methodError("FormUrlEncoded can only be specified on HTTP methods with "
              + "request body (e.g., @POST).");
        }
      }

      int parameterCount = parameterAnnotationsArray.length;
      parameterHandlers = new ParameterHandler<?>[parameterCount];
      for (int p = 0; p < parameterCount; p++) {
        Type parameterType = parameterTypes[p];
        if (Utils.hasUnresolvableType(parameterType)) {
          throw parameterError(p, "Parameter type must not include a type variable or wildcard: %s",
              parameterType);
        }

        Annotation[] parameterAnnotations = parameterAnnotationsArray[p];
        if (parameterAnnotations == null) {
          throw parameterError(p, "No Retrofit annotation found.");
        }

        parameterHandlers[p] = parseParameter(p, parameterType, parameterAnnotations);
      }

      if (relativeUrl == null && !gotUrl) {
        throw methodError("Missing either @%s URL or @Url parameter.", httpMethod);
      }
      if (!isFormEncoded && !isMultipart && !hasBody && gotBody) {
        throw methodError("Non-body HTTP method cannot contain @Body.");
      }
      if (isFormEncoded && !gotField) {
        throw methodError("Form-encoded method must contain at least one @Field.");
      }
      if (isMultipart && !gotPart) {
        throw methodError("Multipart method must contain at least one @Part.");
      }

      return new ServiceMethod<>(this);
    }
```
大概经历了下面几个过程：

- **生成CallAdapter** 这里会先去Retrofit中调用`CallAdapter.Factory`生成一个CallAdapter。CallAdapter的主要目的是实现里面的`adapt`，也就是上面create的代理中返回最终的Call的时调用的接口。主要作用就是让你可以代理OkHttpCall。从而让Retrofit更灵活。
- **生成Converter** Converter的作用是当获取到ResponseBody之后可以用它来将数据转化成你想要的数据结构，比如我上面就转化成了String。你也可以用Gson来解析之。主要通过Retrofit中的ConverterFactory实现，过程很简单。
- **解析MethodAnnotation** 
通过method.getAnnotations()拿到方法的所有注解。然后用parseMethodAnnotation一个个解析注解。

```java
//ServiceMethod.java
    private void parseMethodAnnotation(Annotation annotation) {
      if (annotation instanceof DELETE) {
        parseHttpMethodAndPath("DELETE", ((DELETE) annotation).value(), false);
      } else if (annotation instanceof GET) {
        parseHttpMethodAndPath("GET", ((GET) annotation).value(), false);
      } else if (annotation instanceof HEAD) {
        parseHttpMethodAndPath("HEAD", ((HEAD) annotation).value(), false);
        if (!Void.class.equals(responseType)) {
          throw methodError("HEAD method must use Void as response type.");
        }
      } else if (annotation instanceof PATCH) {
        parseHttpMethodAndPath("PATCH", ((PATCH) annotation).value(), true);
      } else if (annotation instanceof POST) {
        parseHttpMethodAndPath("POST", ((POST) annotation).value(), true);
      } else if (annotation instanceof PUT) {
        parseHttpMethodAndPath("PUT", ((PUT) annotation).value(), true);
      } else if (annotation instanceof OPTIONS) {
        parseHttpMethodAndPath("OPTIONS", ((OPTIONS) annotation).value(), false);
      } else if (annotation instanceof HTTP) {
        HTTP http = (HTTP) annotation;
        parseHttpMethodAndPath(http.method(), http.path(), http.hasBody());
      } else if (annotation instanceof retrofit2.http.Headers) {
        String[] headersToParse = ((retrofit2.http.Headers) annotation).value();
        if (headersToParse.length == 0) {
          throw methodError("@Headers annotation is empty.");
        }
        headers = parseHeaders(headersToParse);
      } else if (annotation instanceof Multipart) {
        if (isFormEncoded) {
          throw methodError("Only one encoding annotation is allowed.");
        }
        isMultipart = true;
      } else if (annotation instanceof FormUrlEncoded) {
        if (isMultipart) {
          throw methodError("Only one encoding annotation is allowed.");
        }
        isFormEncoded = true;
      }
    }
```

可以看到不仅仅是Method还有Headers也是在方法的注解里面实现的。

下面看看Method和Path是如何处理的。

```java
//ServiceMethod.java
   private void parseHttpMethodAndPath(String httpMethod, String value, boolean hasBody) {
      if (this.httpMethod != null) {
        throw methodError("Only one HTTP method is allowed. Found: %s and %s.",
            this.httpMethod, httpMethod);
      }
      this.httpMethod = httpMethod;
      this.hasBody = hasBody;

      if (value.isEmpty()) {
        return;
      }

      // Get the relative URL path and existing query string, if present.
      int question = value.indexOf('?');
      if (question != -1 && question < value.length() - 1) {
        // Ensure the query string does not have any named parameters.
        String queryParams = value.substring(question + 1);
        Matcher queryParamMatcher = PARAM_URL_REGEX.matcher(queryParams);
        if (queryParamMatcher.find()) {
          throw methodError("URL query string \"%s\" must not have replace block. "
              + "For dynamic query parameters use @Query.", queryParams);
        }
      }

      this.relativeUrl = value;
      this.relativeUrlParamNames = parsePathParameters(value);
    }
```
 
其实Method主要是外面传过来的，url直接用注解中的value即可。**注意**这里会检查url中是不是有query信息，有则抛出异常。

关于header的处理如下:

```java
    private Headers parseHeaders(String[] headers) {
      Headers.Builder builder = new Headers.Builder();
      for (String header : headers) {
        int colon = header.indexOf(':');
        if (colon == -1 || colon == 0 || colon == header.length() - 1) {
          throw methodError(
              "@Headers value must be in the form \"Name: Value\". Found: \"%s\"", header);
        }
        String headerName = header.substring(0, colon);
        String headerValue = header.substring(colon + 1).trim();
        if ("Content-Type".equalsIgnoreCase(headerName)) {
          MediaType type = MediaType.parse(headerValue);
          if (type == null) {
            throw methodError("Malformed content type: %s", headerValue);
          }
          contentType = type;
        } else {
          builder.add(headerName, headerValue);
        }
      }
      return builder.build();
    }
```

Headers对应的value其实是一个String数组。数组的key和value使用":"隔开的。这段代码就是解析KV。

- **解析ParamentAnnotation**

这里需要用到parameterTypes数据和parameterAnnotationsArray数组，前者是所有的参数类型的数据，后者是单个参数对应的[多个注解]。这两个数据的长度一一对应。这里逻辑很多。最后生成一个parameterHandler。也是跟前面是对应的。


之后创建一个OkHttpCall，并将这个Call使用CallAdapter包裹返回给用户。让用户自己来决定同步或者移步来调用。

### 处理请求

在动态代理中我们知道生成ServiceMethod之后，会将ServiceMethod和参数一起生成一个OkHttpCall。然后将这个call用CallAdapter一起生成一个新的Call，Retrofit默认生成的Call为`ExecutorCallbackCall`。

所以用户那边拿到的是ExecutorCallbackCall实例。因此对Call的操作的重任都放在了ExecutorCallbackCall身上。

但是翻开ExecutorCallbackCall的源码可以发现：这里面其实就是使用OkHttpCall做代理而已。但是需要说明的是移步请求时回调会被放在callbackExecutor中再次回调给到OkHttpCall.

```java
//ExecutorCallAdapterFactory.java
    @Override public void enqueue(final Callback<T> callback) {
      if (callback == null) throw new NullPointerException("callback == null");

      delegate.enqueue(new Callback<T>() {
        @Override public void onResponse(Call<T> call, final Response<T> response) {
          callbackExecutor.execute(new Runnable() {
            @Override public void run() {
              if (delegate.isCanceled()) {
                // Emulate OkHttp's behavior of throwing/delivering an IOException on cancellation.
                callback.onFailure(ExecutorCallbackCall.this, new IOException("Canceled"));
              } else {
                callback.onResponse(ExecutorCallbackCall.this, response);
              }
            }
          });
        }

        @Override public void onFailure(Call<T> call, final Throwable t) {
          callbackExecutor.execute(new Runnable() {
            @Override public void run() {
              callback.onFailure(ExecutorCallbackCall.this, t);
            }
          });
        }
      });
    }
```

所以请求的部分还是要到OkHttpCall中一探究竟。其实它在处理同步和移步是没多大区别，我们就一同步为例吧。

```java
  @Override public Response<T> execute() throws IOException {
    okhttp3.Call call;

    synchronized (this) {
      if (executed) throw new IllegalStateException("Already executed.");
      executed = true;

      if (creationFailure != null) {
        if (creationFailure instanceof IOException) {
          throw (IOException) creationFailure;
        } else {
          throw (RuntimeException) creationFailure;
        }
      }

      call = rawCall;
      if (call == null) {
        try {
          call = rawCall = createRawCall();
        } catch (IOException | RuntimeException e) {
          creationFailure = e;
          throw e;
        }
      }
    }

    if (canceled) {
      call.cancel();
    }

    return parseResponse(call.execute());
  }
```

首先它会再次生成一个新的Call。注意这个Call是okhttp3.Call了，为什么呢？因为接下来的时候就要交给OkHttp处理了。处理完之后的结果会放在parseResponse中做反序列化，使用converter生成我们需要的对象。

下面重点讲讲生成Call的故事。

```java
  private okhttp3.Call createRawCall() throws IOException {
    Request request = serviceMethod.toRequest(args);
    okhttp3.Call call = serviceMethod.callFactory.newCall(request);
    if (call == null) {
      throw new NullPointerException("Call.Factory returned null.");
    }
    return call;
  }
```

首先会使用serviceMethod将我们的参数生成一个Request。然后使用这个这个Request调用Retrofit中的CallFactory生成一个新的okhttp3.Call，还记得前面生成Retrofit时Builder中的client吗，那就是CallFatory。且Retrofit默认的CallFactory是新建一个OkHttpClient。这里接下来就是OkHttp里面的基本使用姿势了。

那么我们来看看这个Request是如何生成的呢？

我们回到ServiceMethod中去看看。

```java
//ServiceMethod.java
  /** Builds an HTTP request from method arguments. */
  Request toRequest(Object... args) throws IOException {
    RequestBuilder requestBuilder = new RequestBuilder(httpMethod, baseUrl, relativeUrl, headers,
        contentType, hasBody, isFormEncoded, isMultipart);

    @SuppressWarnings("unchecked") // It is an error to invoke a method with the wrong arg types.
    ParameterHandler<Object>[] handlers = (ParameterHandler<Object>[]) parameterHandlers;

    int argumentCount = args != null ? args.length : 0;
    if (argumentCount != handlers.length) {
      throw new IllegalArgumentException("Argument count (" + argumentCount
          + ") doesn't match expected count (" + handlers.length + ")");
    }

    for (int p = 0; p < argumentCount; p++) {
      handlers[p].apply(requestBuilder, args[p]);
    }

    return requestBuilder.build();
  }
```

首先会用之前解析好的Method，URL，Header等等创建一个RequestBuilder。然后就是将参数注解一个个放到里面去了。很巧妙的一点是，它将参数注解给抽象出一个ParameterHandler。然后将RequestBuilder以参数的形式交给这个ParameterHandler。如果某个注解是处理Body的，那么你就在Body ParameterHandler中实现Body的部分即可。完美解耦了。

以Body为例：

```java
  static final class Body<T> extends ParameterHandler<T> {
    private final Converter<T, RequestBody> converter;

    Body(Converter<T, RequestBody> converter) {
      this.converter = converter;
    }

    @Override void apply(RequestBuilder builder, T value) {
      if (value == null) {
        throw new IllegalArgumentException("Body parameter value must not be null.");
      }
      RequestBody body;
      try {
        body = converter.convert(value);
      } catch (IOException e) {
        throw new RuntimeException("Unable to convert " + value + " to RequestBody", e);
      }
      builder.setBody(body);
    }
  }
```

它在解析Body注解的时候build是解析好的`requestBodyConverter`就放入其中了。然后交给这个responseConverter把参数生成对应的RequestBody。就很灵活，从而实现各种各样复杂的行为。

当okhttp3.Call执行完返回Response后，在OkHttpCall中调用parserResponse反序列化结果。

```java

  Response<T> parseResponse(okhttp3.Response rawResponse) throws IOException {
    ResponseBody rawBody = rawResponse.body();
    //...省略
    try {
      T body = serviceMethod.toResponse(catchingBody);
      return Response.success(body, rawResponse);
    } catch (RuntimeException e) {
      // If the underlying source threw an exception, propagate that rather than indicating it was
      // a runtime exception.
      catchingBody.throwIfCaught();
      throw e;
    }
  }
```

其中`T Body`就是我们在API接口中定义返回的Call中的泛型。反序列化的过程也是在ServiceMethod中处理的。

```java
//ServiceMethod.java
  R toResponse(ResponseBody body) throws IOException {
    return responseConverter.convert(body);
  }
```

这里就用到了build ServiceMethod时的responseConverter。

## 总结

看了Retrofit的实现过程不难发现，它是全程使用了反射。故而如果你对性能上面有严格要求的话还是要谨慎使用。不过，我们是不是可以通过其他方式来降低(消除)这个性能缺陷呢？

比如，在编译的时候提前将Interface给自动实现，这样用户只要就可以脱离Retrofit从而达到目的。