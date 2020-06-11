---
layout: post
title: "Flutter状态管理-Redux"
description: "Flutter状态管理-Redux"
category: all-about-tech
tags: -[flutter, redux]
date: 2020-06-11 23:03:57+00:00
---

项目地址:

<https://github.com/brianegan/flutter_redux>

<https://github.com/fluttercommunity/redux.dart>

## Demo

```dart
enum Actions { Increment }

int counterReducer(int state, dynamic action) {
  if (action == Actions.Increment) {
    return state + 1;
  }
  return state;
}

void main() {
  // Redux的数据都存储在Store中
  // 同时Store关联了Reducer用于处理Action
  final store = Store<int>(counterReducer, initialState: 0);
  runApp(FlutterReduxApp(
    title: 'Flutter Redux Demo',
    store: store,
  ));
}

class FlutterReduxApp extends StatelessWidget {
  final Store<int> store;
  final String title;

  FlutterReduxApp({Key key, this.store, this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // StoreProvider本质上是一个InheritedWidget。
    // 用于给子Widget共享数据(Store)。
    return StoreProvider<int>(
      child: MaterialApp(
        theme: ThemeData.dark(),
        title: title,
        home: Scaffold(
          appBar: AppBar(
            title: Text(title),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'You have pushed the button this many times:',
                ),
                // StoreConnector用于获取Store,
                // 以及提供Converter和Builder用于构建子Widget
                StoreConnector<int, String>(
                  // converter如字面意思用于提供将store映射的逻辑。
                  converter: (store) => store.state.toString(),
                  // builder第二个参数为coverter返回的数据
                  builder: (context, count) {
                    // 使用处理好的数据, 构建新的Widget展示
                    return Text(
                      count,
                      style: Theme.of(context).textTheme.display1,
                    );
                  },
                )
              ],
            ),
          ),
          floatingActionButton: StoreConnector<int, VoidCallback>(
            converter: (store) {
              // 这里与上面不同的是, 返回的是一个闭包。
              // 里面的逻辑则是向store发送一个Increment的Action
              return () => store.dispatch(Actions.Increment);
            },
            builder: (context, callback) {
              return FloatingActionButton(
                // 点击的回调直接执行上面的闭包。
                // 即向Store发送Action, 用于更新界面。
                onPressed: callback,
                tooltip: 'asdasdasd',
                child: Icon(Icons.add),
              );
            },
          ),
        ),
      ),
    );
  }
}
```

## 内部逻辑


Redux的类图如下:

[![redux.dart-class-uml.png](https://j.mp/3f8aJmU)](https://j.mp/2zm1TCY)

### # Store

```dart
/// Reducer用于接收Action并改变State
typedef State Reducer<State>(State state, dynamic action);

/// 中间件类似于Reducer, 可以有多个。
/// Action最终都是经过Middleware, 最终到达Reducer完成
/// 对State的一系列处理和转化
typedef dynamic Middleware<State>(
  Store<State> store,
  dynamic action,
  NextDispatcher next,
);

/// NextDispatcher为Store内部的dispatchers列表所持有的item。
typedef dynamic NextDispatcher(dynamic action);

class Store<State> {
  Reducer<State> reducer;

  final StreamController<State> _changeController;
  State _state;
  List<NextDispatcher> _dispatchers;

  Store(
    this.reducer, {
    State initialState,
    List<Middleware<State>> middleware = const [],
    bool syncStream = false,
    bool distinct = false,
  }) :
  // 创建一个BroadcastStreamController, 这是数据发送端和接收端的非常重要的桥梁。
  _changeController = StreamController.broadcast(sync: syncStream) {
    _state = initialState;
    _dispatchers = _createDispatchers(
      middleware,
      _createReduceAndNotify(distinct),
    );
  }

  State get state => _state;

  // 通过Store的onChange获得数据流,
  // 这里直接返回的是controller中的stream对象
  Stream<State> get onChange => _changeController.stream;

  NextDispatcher _createReduceAndNotify(bool distinct) {
    return (dynamic action) {
      final state = reducer(_state, action);
      if (distinct && state == _state) return;
      _state = state;
      // 发送数据。此时会回调所有的StreamSubscription
      _changeController.add(state);
    };
  }

  List<NextDispatcher> _createDispatchers(
    List<Middleware<State>> middleware,
    NextDispatcher reduceAndNotify,
  ) {
    // 创建`dispatchers`列表, 并向其中加入上面的`_createReduceAndNotify`
    // 即Store在构造时持有的外部的`Reducer`。
    final dispatchers = <NextDispatcher>[]..add(reduceAndNotify);

    // 颠倒`middleware`, 这样的目地则是保持原先`middleware`的顺序。
    for (var nextMiddleware in middleware.reversed) {
    // 将列表的最后一个当作下一个的next,
    // 即当前位置的next为上一位置。这么做是因为最终存储的是倒置的列表。
      final next = dispatchers.last;
    // 将`nextMiddleware`生成新的NextDispatcher加入列表
      dispatchers.add(
        (dynamic action) => nextMiddleware(this, action, next),
      );
    }

    // 颠倒dispatchers列表, 则上面的`next`逻辑看起来就很正常了。
    return dispatchers.reversed.toList();
  }

  dynamic dispatch(dynamic action) {
    // 获取`_dispatchers`列表的第一个并运行。
    // 如果存在`middleware`则跑完middleware最后执行到reducer。
    return _dispatchers[0](action);
  }
}
```

调用`Store.dispatch(action)`方法以向Reducer发送Action。

而dispatch方法本身, 则是直接调用Store内部`dispatchers`列表的第一个`NextDispatcher`。如果存在中间件(即middleware), 那么这第一个`NextDispatcher`则是`middleware`原始顺序的第一个。

同时Middleware在处理完之后必须调用其next, 以实现对整个`dispatchers`列表的完全遍历, 这其中最后一个则是Store中的Reducer。


Redux支持中间件之后的架构如下:

[![redux.dart-arch.png](https://j.mp/3f6rSgP)](https://j.mp/2Ymv0P7)

### # StoreProvider

`StoreProvider`本身只是一个`InheritedWidget`, 存在的目地就是为了在整个Widget树中共享`Store`对象。如下:

```dart
class StoreProvider<S> extends InheritedWidget {
  final Store<S> _store;
  const StoreProvider({
    Key key,
    @required Store<S> store,
    @required Widget child,
  })  : assert(store != null),
        assert(child != null),
        _store = store,
        super(key: key, child: child);

  static Store<S> of<S>(BuildContext context, {bool listen = true}) {
    // listen与否在于是否将自己(Element)加入到ancestor的`依赖列表`中。
    final provider = (listen
        ? context.dependOnInheritedWidgetOfExactType<StoreProvider<S>>()
        : context
            .getElementForInheritedWidgetOfExactType<StoreProvider<S>>()
            ?.widget) as StoreProvider<S>;
    ...
    return provider._store;
  }

  // Workaround to capture generics
  static Type _typeOf<T>() => T;

  @override
  bool updateShouldNotify(StoreProvider<S> oldWidget) =>
      _store != oldWidget._store;
}
```

可见, 它提供了`of`函数(与Provider的逻辑可以说是完全一致)。用于获取当前树中往上的第一个`StoreProvider`, 并返回其持有的store对象。

listen的逻辑可以参考Provider或者查看Element的`dependOnInheritedElement`方法, 略。

### # StoreConnector

StoreConnector是Redux的消费端, 即将`builder`和`store`绑定起来。store通过stream下发数据, 当数据发生变化时StoreConnector的子(孙)Widget的State通过setState刷新数据。

```dart
class StoreConnector<S, ViewModel> extends StatelessWidget {
  ...
  const StoreConnector({
    this.distinct = false,
    this.rebuildOnChange = true,
  })  : ...;

  @override
  Widget build(BuildContext context) {
    return _StoreStreamListener<S, ViewModel>(
      store: StoreProvider.of<S>(context),
      builder: builder,
      converter: converter,
      distinct: distinct,
      onInit: onInit,
      onDispose: onDispose,
      rebuildOnChange: rebuildOnChange,
      ignoreChange: ignoreChange,
      onWillChange: onWillChange,
      onDidChange: onDidChange,
      onInitialBuild: onInitialBuild,
    );
  }
}
```

`rebuildOnChange`默认为true, build中创建了一个`_StoreStreamListener`。

```dart
class _StoreStreamListener<S, ViewModel> extends StatefulWidget {
  ...
  const _StoreStreamListener({
    Key key,
    @required this.builder,
    @required this.store,
    @required this.converter,
    this.distinct = false,
    this.onInit,
    this.onDispose,
    this.rebuildOnChange = true,
    this.ignoreChange,
    this.onWillChange,
    this.onDidChange,
    this.onInitialBuild,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _StoreStreamListenerState<S, ViewModel>();
  }
}

class _StoreStreamListenerState<S, ViewModel>
    extends State<_StoreStreamListener<S, ViewModel>> {
  Stream<ViewModel> stream;
  ViewModel latestValue;

  @override
  void initState() {
    ...
    // 获取初始数据的映射/转化。
    latestValue = widget.converter(widget.store);
    // 创建Stream
    _createStream();

    super.initState();
  }

  @override
  void didUpdateWidget(_StoreStreamListener<S, ViewModel> oldWidget) {
    // 更新数据
    latestValue = widget.converter(widget.store);
    // 如果Widget变化则重新创建Stream
    if (widget.store != oldWidget.store) {
      _createStream();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    if (widget.onDispose != null) {
      widget.onDispose(widget.store);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `rebuildOnChange`默认为true, 在StreamBuilder实现对Stream数据的监听。
    // 当`onData`被回调到, 则执行`setState`刷新Widget, 即回调builer。
    return widget.rebuildOnChange
        ? StreamBuilder<ViewModel>(
            stream: stream,
            builder: (context, snapshot) => widget.builder(
              context,
              latestValue,
            ),
          )
        : widget.builder(context, latestValue);
  }

  ViewModel _mapConverter(S state) {
    return widget.converter(widget.store);
  }
  ...
  void _createStream() {
            //
    stream = widget.store.onChange
        .where(_ignoreChange)
        // 映射数据, 回调converter方法。
        .map(_mapConverter)
        // Don't use `Stream.distinct` because it cannot capture the initial
        // ViewModel produced by the `converter`.
        .where(_whereDistinct)
        // After each ViewModel is emitted from the Stream, we update the
        // latestValue. Important: This must be done after all other optional
        // transformations, such as ignoreChange.
        .transform(StreamTransformer.fromHandlers(handleData: _handleChange));
  }
}
```

可见, 在`_StoreStreamListenerState`创建stream时直接调用了store的onChange, 并进行了一系列的转化操作。

最终处理完的数据, 存放在`latestValue`中, 在build时, 直接执行StoreConnector的builder闭包, 实现对数据最终的convert。

注意, build函数中, 如果`rebuildOnChange`为true, 则实际上widget的构建是由`StreamBuilder`触发的。

### # StreamBuilder

`StreamBuilder`完成了对stream的监控, 当数据变化时, 其内部setState完成View的刷新。

- _BroadcastStreamController

上面说到StoreConnector构建Widget时会从Store中获取新的stream(onChange), 而这个`stream`则是来自`_BroadcastStreamController`。下面看看`_BroadcastStreamController`的stream的get函数:

```dart
abstract class _BroadcastStreamController<T>
    implements _StreamControllerBase<T> {
  ...
  // 获取stream的时候, 直接创建一个_BroadcastStream
  // 而_BroadcastStream中的关键函数, 比如listen最终会回调到
  // _BroadcastStreamController的_subscribe以及相关方法。
  Stream<T> get stream => new _BroadcastStream<T>(this);

  StreamSink<T> get sink => new _StreamSinkWrapper<T>(this);
  ...
  /** Adds subscription to linked list of active listeners. */
  void _addListener(_BroadcastSubscription<T> subscription) {
    assert(identical(subscription._next, subscription));
    subscription._eventState = (_state & _STATE_EVENT_ID);
    // Insert in linked list as last subscription.
    _BroadcastSubscription<T> oldLast = _lastSubscription;
    _lastSubscription = subscription;
    // 修改subscription链表, 插入到尾部(多个的时候, 否则就是head)
    subscription._next = null;
    subscription._previous = oldLast;
    if (oldLast == null) {
      _firstSubscription = subscription;
    } else {
      oldLast._next = subscription;
    }
  }
  ...
  StreamSubscription<T> _subscribe(void onData(T data), Function onError,
      void onDone(), bool cancelOnError) {
    if (isClosed) {
      onDone ??= _nullDoneHandler;
      return new _DoneStreamSubscription<T>(onDone);
    }
    StreamSubscription<T> subscription = new _BroadcastSubscription<T>(
        this, onData, onError, onDone, cancelOnError);
    // 订阅本质上也是在当前的监听链表中添加一个Listener, 即`StreamSubscription`。
    _addListener(subscription);
    if (identical(_firstSubscription, _lastSubscription)) {
      // Only one listener, so it must be the first listener.
      _runGuarded(onListen);
    }
    return subscription;
  }
  ...
}
```

- _StreamImpl

获取Store的onChange最终拿到的是一个`_BroadcastStream`对象, 这是一个`_StreamImpl`子类的实例。

[![redux.dart-Store-to-BroadcastStream.png](https://j.mp/2MKBUIA)](https://j.mp/30oreXQ)

如下:

```dart
class _BroadcastStream<T> extends _ControllerStream<T> {
  _BroadcastStream(_StreamControllerLifecycle<T> controller)
      : super(controller);
  bool get isBroadcast => true;
}

class _ControllerStream<T> extends _StreamImpl<T> {
  _StreamControllerLifecycle<T> _controller;
  _ControllerStream(this._controller);

  StreamSubscription<T> _createSubscription(void onData(T data),
          Function onError, void onDone(), bool cancelOnError) =>
      _controller._subscribe(onData, onError, onDone, cancelOnError);
  ...
}

abstract class _StreamImpl<T> extends Stream<T> {
  // ------------------------------------------------------------------
  // Stream interface.

  StreamSubscription<T> listen(void onData(T data),
      {Function onError, void onDone(), bool cancelOnError}) {
    cancelOnError = identical(true, cancelOnError);
    // 对stream的监听, 则是通过实现其`_createSubscription`方法实现的。
    StreamSubscription<T> subscription =
        _createSubscription(onData, onError, onDone, cancelOnError);
    _onListen(subscription);
    return subscription;
  }
  // -------------------------------------------------------------------
  ...
}
```

`_BroadcastStream`的主要作用是调用listen方法后, 会跟_BroadcastStreamController关联起来。

这个`Controller`也就是Store内部持有的`_changeController`, 而在reducer的最后调用了其add方法, 向其中所有的StreamSubscription(即listener)发送回调。

- _StreamBuilderBaseState

回到`StoreConnector`的build方法, 这里创建了一个`StreamBuilder`对象。

[![redux.dart-StoreConnector-to-StreamBuilderBaseState.png](https://j.mp/2YhEsTM)](https://j.mp/3haWgIS)

如下:

```dart
class StreamBuilder<T> extends StreamBuilderBase<T, AsyncSnapshot<T>> {
  const StreamBuilder({
    Key key,
    this.initialData,
    Stream<T> stream,
    @required this.builder,
  }) : assert(builder != null),
       super(key: key, stream: stream);
  ...
  // StreamBuilder在build子Widget时, 直接调用builder。
  @override
  Widget build(BuildContext context, AsyncSnapshot<T> currentSummary) => builder(context, currentSummary);
}

abstract class StreamBuilderBase<T, S> extends StatefulWidget {
  ...
  // 创建_StreamBuilderBaseState, State中会对当前stream监听。
  @override
  State<StreamBuilderBase<T, S>> createState() => _StreamBuilderBaseState<T, S>();
}

class _StreamBuilderBaseState<T, S> extends State<StreamBuilderBase<T, S>> {
  StreamSubscription<T> _subscription;
  S _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.initial();
    // 初始化, 监听stream
    _subscribe();
  }

  @override
  void didUpdateWidget(StreamBuilderBase<T, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // widget变化之后, 重新监听stream
    if (oldWidget.stream != widget.stream) {
      if (_subscription != null) {
        _unsubscribe();
        _summary = widget.afterDisconnected(_summary);
      }
      _subscribe();
    }
  }

  // 这个State最终调用的是StreamBuilder的builder方法。
  @override
  Widget build(BuildContext context) => widget.build(context, _summary);

  void _subscribe() {
    if (widget.stream != null) {
      // 在StreamController(_BroadcastStream的最终的实现也是StreamController)
      // 中注册listener(调用其_subcribe方法), 返回的是BroadcastSubscription。
      // 这里, listen方法默认参数为其_onData
      _subscription = widget.stream.listen((T data) {
        // 当stream变化之后, 重新绘制Widget(StreamBuilder)
        setState(() {
          _summary = widget.afterData(_summary, data);
        });
      });
      _summary = widget.afterConnected(_summary);
    }
  }
}
```

可以看到`StreamBuilder`最终创建了一个`_StreamBuilderBaseState`, 这个State在初始化以及更新的时候会监听`StreamBuilder`内部持有的stream, 当stream数据发生变化时执行setState触发Widget的刷新, 此时StoreConnector的builer将会被调用完成View的更新。

下面来看具体的更新过程。

### # dispatch

通过上面demo可知, 向Store发送Action的时候是通过其`dispatch`方法完成的, 如下:

```dart
class Store<State> {
  dynamic dispatch(dynamic action) {
    return _dispatchers[0](action);
  }

  NextDispatcher _createReduceAndNotify(bool distinct) {
    return (dynamic action) {
      final state = reducer(_state, action);

      if (distinct && state == _state) return;

      _state = state;
      _changeController.add(state);
    };
  }
}
```

dispatch内部调用`_dispatchers`列表, 经过middleware最终运行`_createReduceAndNotify`, 即reducer。在这一步的最后调用`_changeController`的add方法完成数据变化的分发。

继续来看`_BroadcastStreamController`是如何处理add方法的:

```dart
abstract class _BroadcastStreamController<T>
    implements _StreamControllerBase<T> {
  ...
  void add(T data) {
    if (!_mayAddEvent) throw _addEventError();
    _sendData(data);
  }
  ...
  void _sendData(T data) {
    if (_isEmpty) return;
    if (_hasOneListener) {
      遍历所有的subscription, 分别调用其add方法。
      _state |= _BroadcastStreamController._STATE_FIRING;
      _BroadcastSubscription<T> subscription = _firstSubscription;
      subscription._add(data);
      _state &= ~_BroadcastStreamController._STATE_FIRING;
      if (_isEmpty) {
        _callOnCancel();
      }
      return;
    }
    _forEachListener((_BufferingStreamSubscription<T> subscription) {
      subscription._add(data);
    });
  }
  ...
}
```

遍历所有的`_BroadcastSubscription`并调用其add方法。

处理如下:

```dart
class _BroadcastSubscription<T> extends _ControllerSubscription<T> {
  ...
}

class _ControllerSubscription<T> extends _BufferingStreamSubscription<T> {
  ...
}

class _BufferingStreamSubscription<T>
    implements StreamSubscription<T>, _EventSink<T>, _EventDispatch<T> {
  ...
  void _add(T data) {
    assert(!_isClosed);
    if (_isCanceled) return;
    if (_canFire) {
      // sync
      _sendData(data);
    } else {
      // async
      _addPending(new _DelayedData<T>(data));
    }
  }
  ...
  void _sendData(T data) {
    assert(!_isCanceled);
    assert(!_isPaused);
    assert(!_inCallback);
    bool wasInputPaused = _isInputPaused;
    _state |= _STATE_IN_CALLBACK;
    // 回调_onData
    _zone.runUnaryGuarded(_onData, data);
    _state &= ~_STATE_IN_CALLBACK;
    _checkState(wasInputPaused);
  }
}
```

到这里就可以跟`_StreamBuilderBaseState`的`_subscribe`方法串联起来了。当reducer执行之后调用StreamController的add方法, 此时会遍历其内部所有的BroadcastSubscription。

在`BroadcastSubscription`的`_add`方法最终会回调_StreamBuilderBaseState注册的回调(即onData), 此时会触发`setState`完成数据的刷新。