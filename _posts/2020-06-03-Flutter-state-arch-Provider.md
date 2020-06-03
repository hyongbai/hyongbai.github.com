---
layout: post
title: "Flutter状态管理-Provider"
description: "Flutter状态管理-Provider"
category: all-about-tech
tags: -[flutter, provider]
date: 2020-06-03 23:03:57+00:00
---

项目地址

<https://github.com/rrousselGit/provider>

## 基本用法

以demo为例:

### 创建ChangeNotifier

`ChangeNotifier`是flutter提供的一个实现了`Listenable`基础类。

它提供了绑定以及解绑观察者(一个闭包)的逻辑。

```dart
class Counter with ChangeNotifier {
  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
    // 通知listener进行刷新
    notifyListeners();
  }
}
```

`ChangeNotifier`更像是ViewModel, 用于处理数据, 已经将数据同View(即Widget)进行绑定。

在这里的Counter, 内部持有了一个`_count`对象, 用于记录数据。同时暴露了一个`increment()`接口, 以便view调用。

### 创建provider

```dart
void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Counter()),
      ],
      child: MyApp(),
    ),
  );
}
```

`Provder`对象用于提供ChangeNotifier。Provider中使用到的ChangeNotifier都是一个对象, 它本身是按照类型的方式存储和提供的。

### 获取ChangeNotifier

```dart
class MyHomePage extends StatelessWidget {
  const MyHomePage({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Example'),
      ),
      body: Center(
        child: Column(
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            const Count(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        // 只读的方式获取Counter对象。用于发送`Action`。
        // 即Counter对象变化不会导致当前Element标记为darty
        onPressed: () => context.read<Counter>().increment(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class Count extends StatelessWidget {
  const Count({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
        // 监听数据并使用。当数据变化时Widget会重建。
        '${context.watch<Counter>().count}',
        style: Theme.of(context).textTheme.headline);
  }
}
```

在新版本的Provider(>4.0.0)中, 提供了一个watch和read函数, 分别用于监听和获取ChangeNotifier。使用方式如上所述。

## 原理

Provider中定义的类的依赖关系如下:

[![Flutter-Provider-InheritedProvider-class.jpg](https://j.mp/2XuBpbK)](https://j.mp/3cwDNmk)

### # Provider注册逻辑

以Demo中的`ChangeNotifierProvider`为例:

```dart
class ChangeNotifierProvider<T extends ChangeNotifier>
    extends ListenableProvider<T> {
  ...
}
```

继承自`ListenableProvider`, 如下:

```dart
class ListenableProvider<T extends Listenable> extends InheritedProvider<T> {
  ListenableProvider({
    Key key,
    @required Create<T> create,
    Dispose<T> dispose,
    bool lazy,
    TransitionBuilder builder,
    Widget child,
  })  : assert(create != null),
        super(
          key: key,
          // 提供了一个默认的_startListening方法, 实现监听。
          startListening: _startListening,
          ...
        );
  ...
  static VoidCallback _startListening(
    InheritedContext<Listenable> e,
    Listenable value,
  ) {
    // 实现绑定
    value?.addListener(e.markNeedsNotifyDependents);
    // 返回解绑方法
    return () => value?.removeListener(e.markNeedsNotifyDependents);
  }
}
```

这里提供了一个关键方法, 即`_startListening`, 这里实现了ChangeNotifier和Element的绑定。

#### - InheritedProvider

```dart
class InheritedProvider<T> extends SingleChildStatelessWidget {
  InheritedProvider({
    Key key,
    Create<T> create,
    T update(BuildContext context, T value),
    UpdateShouldNotify<T> updateShouldNotify,
    void Function(T value) debugCheckInvalidValueType,
    StartListening<T> startListening,
    Dispose<T> dispose,
    TransitionBuilder builder,
    bool lazy,
    Widget child,
  })  : _lazy = lazy,
        _builder = builder,
        // _delegate这里使用的是默认的`_CreateInheritedProvider`
        // _delegate是一个对`_DelegateState`进行抽象的接口。
        // 使用不用的`_delegate`来实现不同的`_DelegateState`。
        _delegate = _CreateInheritedProvider(
          create: create,
          update: update,
          updateShouldNotify: updateShouldNotify,
          debugCheckInvalidValueType: debugCheckInvalidValueType,
          startListening: startListening,
          dispose: dispose,
        ),
        super(key: key, child: child);
  @override
  _InheritedProviderElement<T> createElement() {
    return _InheritedProviderElement<T>(this);
  }

  @override
  Widget buildWithChild(BuildContext context, Widget child) {
    // child为`_InheritedProviderScope`, 这是一个InheritedWidget。
    // child会创建一个固定的InheritedElement即`_InheritedProviderScopeElement`
    // `_InheritedProviderScopeElement`是整个Provider中的核心类。
    return _InheritedProviderScope<T>(
      owner: this,
      child: _builder != null
          ? Builder(builder: (context) => _builder(context, child))
          : child,
    );
  }
}
```

```dart
class _InheritedProviderScope<T> extends InheritedWidget {
  final InheritedProvider<T> owner;
  ...
  @override
  _InheritedProviderScopeElement<T> createElement() {
    // 创建_InheritedProviderScopeElement供`Provider.of`获取
    return _InheritedProviderScopeElement<T>(this);
  }
}
```

#### - _InheritedProviderScopeElement

```dart
class _InheritedProviderScopeElement<T> extends InheritedElement
    implements InheritedContext<T> {
  _InheritedProviderScopeElement(_InheritedProviderScope<T> widget)
      : super(widget);

  bool _shouldNotifyDependents = false;
  bool _debugInheritLocked = false;
  bool _isNotifyDependentsEnabled = true;
  bool _firstBuild = true;
  bool _updatedShouldNotify = false;
  bool _isBuildFromExternalSources = false;
  _DelegateState<T, _Delegate<T>> _delegateState;

  @override
  _InheritedProviderScope<T> get widget =>
      super.widget as _InheritedProviderScope<T>;
  ...

  @override
  void performRebuild() {
    if (_firstBuild) {
      _firstBuild = false;
      // widget为上面的`_InheritedProviderScope`, 其owner为`InheritedProvider`。
      // 这里的_delegate为(_CreateInheritedProvider/_ValueInheritedProvider)
      // 调用_delegate的createState()同时将DelegateState的element设为自己。
      _delegateState = widget.owner._delegate.createState()..element = this;
    }
    super.performRebuild();
  }

  @override
  void didChangeDependencies() {
    _isBuildFromExternalSources = true;
    super.didChangeDependencies();
  }

  @override
  Widget build() {
    if (widget.owner._lazy == false) {
      value; // this will force the value to be computed.
    }
    // 回调update, 数据有可能会更新。
    // 无需再次notifiyListener, 这样效率更高。
    _delegateState.build(_isBuildFromExternalSources);
    _isBuildFromExternalSources = false;
    if (_shouldNotifyDependents) {
      _shouldNotifyDependents = false;
      notifyClients(widget);
    }
    return super.build();
  }

  @override
  void unmount() {
    _delegateState.dispose();
    super.unmount();
  }

  @override
  bool get hasValue => _delegateState.hasValue;

  @override
  void markNeedsNotifyDependents() {
    if (!_isNotifyDependentsEnabled) return;
    // 上面ListenableLister的`_startListening`方法调用的就是这里。
    markNeedsBuild();
    _shouldNotifyDependents = true;
  }

  @override
  // 数据来自detegateState
  T get value => _delegateState.value;
}
```

#### - _Delegate和_DelegateState

_Delegate可以在InheritedProvider的构造函数中自己实现, 用于主要用于实现不同的`_DelegateState`。

`_DelegateState`用于为`_InheritedProviderScopeElement`提供数据, 他是真正的数据提供者。

接口如下:

```dart
abstract class _Delegate<T> {
  _DelegateState<T, _Delegate<T>> createState();

  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}
}

abstract class _DelegateState<T, D extends _Delegate<T>> {
  _InheritedProviderScopeElement<T> element;

  T get value;

  D get delegate => element.widget.owner._delegate as D;

  bool get hasValue;

  bool debugSetInheritedLock(bool value) {
    return element._debugSetInheritedLock(value);
  }

  bool willUpdateDelegate(D newDelegate) => false;

  void dispose() {}

  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}

  void build(bool isBuildFromExternalSources) {}
}
```

默认的Delegate和DelegateState为`_CreateInheritedProvider`和`_CreateInheritedProviderState`。

如果不想实现`create`方法, 则可以直接通过`value`创建provider, 对应的Delegate和DelegateState为`_ValueInheritedProvider`和`_ValueInheritedProviderState`。

### # ChangeNotifer获取过程

在上面的demo可知, 4.0.0版本提供了`read`和`watch`方法供使用, 如下:

```dart
// provider.dart: Provider
extension ReadContext on BuildContext {
  T read<T>() {
    return Provider.of<T>(this, listen: false);
  }
}

extension WatchContext on BuildContext {
  T watch<T>() {
    return Provider.of<T>(this);
  }
}
```

这两个方法是BuildContext的拓展函数, 可以直接通过BuildContext调用。

可知, 这两个方法最终都调用了`Provider.of`函数, 只是最后一个参数值不同。这个参数(即`listen`)的区别在于`ancestor`在update的时候是否更新自己(持有当前Widget对应的Element)。

```dart
// provider.dart: Provider
static T of<T>(BuildContext context, {bool listen = true}) {
  final inheritedElement = _inheritedElementOf<T>(context);
  if (listen) {
    context.dependOnInheritedElement(inheritedElement);
  }
  return inheritedElement.value;
}
```

#### - _inheritedElementOf

`_inheritedElementOf`用于获取指定类型Widget对应的Element, 其中Widgt必须是`InheritedWidget`及其子类实例。`InheritedWidget`是Flutter中提供的一个用于在子树共享自身数据的特殊类型。

逻辑如下:

```dart
// provider.dart: Provider
static _InheritedProviderScopeElement<T> _inheritedElementOf<T>(
  BuildContext context) {
_InheritedProviderScopeElement<T> inheritedElement;

// getElementForInheritedWidgetOfExactType用于从当前的Element树
// 中获取到特定类型Widget(InheritedWidget及其子类)对应的Element。
if (context.widget is _InheritedProviderScope<T>) {
  // 如果当前是_InheritedProviderScope, 那么直接从其parent获取共享Element即可。
  context.visitAncestorElements((parent) {
    inheritedElement = parent.getElementForInheritedWidgetOfExactType<
        _InheritedProviderScope<T>>() as _InheritedProviderScopeElement<T>;
    return false;
  });
} else {
  inheritedElement = context.getElementForInheritedWidgetOfExactType<
      _InheritedProviderScope<T>>() as _InheritedProviderScopeElement<T>;
}

if (inheritedElement == null) {
  throw ProviderNotFoundException(T, context.widget.runtimeType);
}

return inheritedElement;
}
```

这里是对Element的`getElementForInheritedWidgetOfExactType`方法的简单封装, 无具体逻辑。

`getElementForInheritedWidgetOfExactType`的实现其实很简单, 如下:

```dart
// framework.dart: Element
@override
InheritedElement getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() {
  // 从`_inheritedWidgets`中获取对应类型的索引。
  // `_inheritedWidgets`是Element中用于存储Widget类型和对应Element的Map
  final InheritedElement ancestor = _inheritedWidgets == null ? null : _inheritedWidgets[T];
  return ancestor;
}
```

映射`_inheritedWidgets`的写入过程:

```dart
// framework.dart: Element
class InheritedElement extends ProxyElement {
  /// Creates an element that uses the given widget as its configuration.
  InheritedElement(InheritedWidget widget) : super(widget);

  @override
  InheritedWidget get widget => super.widget as InheritedWidget;

  final Map<Element, Object> _dependents = HashMap<Element, Object>();

  @override
  void _updateInheritance() {
    // _updateInheritance()方法在mount以及activate时都会被调用。
    // activate方法在`inflateWidget`时通过`_activateWithParent`传递过来。
    assert(_active);
    final Map<Type, InheritedElement> incomingWidgets = _parent?._inheritedWidgets;
    if (incomingWidgets != null)
      _inheritedWidgets = HashMap<Type, InheritedElement>.from(incomingWidgets);
    else
      _inheritedWidgets = HashMap<Type, InheritedElement>();
    _inheritedWidgets[widget.runtimeType] = this;
  }
  ...
}
```

Element的`_updateInheritance`方法中, 尝试从parent读取对应字段。如存在, 则加入到新的空HashMap中, 否则只创建新的HashMap。最终将当前Element的Widget的Type写入Map。

可见, 这里包含了两个行为:

- 继承parent中对应的缓存, 这样就有了传递过程。

- 将当前Widget的runtimeType当作key把自己写入Map。

#### - dependOnInheritedElement

`dependOnInheritedElement`方法的主要目地是将自己设置为`ancestor`(不一定是parent)的依赖。依赖关系的建立最终目地是当ancestor被`markNeedsBuild`后, 最终当前`Element`也会重建其Widget, 从而实现数据更新之后Widget的刷新。

```dart
// framework.dart: Element
@override
InheritedWidget dependOnInheritedElement(InheritedElement ancestor, { Object aspect }) {
  assert(ancestor != null);
  _dependencies ??= HashSet<InheritedElement>();
  _dependencies.add(ancestor);
  ancestor.updateDependencies(this, aspect);
  return ancestor.widget;
}
```

```dart
// framework.dart: InheritedElement
  @protected
  void setDependencies(Element dependent, Object value) {
    _dependents[dependent] = value;
  }

  @protected
  void updateDependencies(Element dependent, Object aspect) {
    setDependencies(dependent, null);
  }
```

当ancestor更正之后, 会刷新`_dependents`。这一逻辑主要发生在ancestor的`notifyClients`方法中, 如下:

```dart
  @override
  void notifyClients(InheritedWidget oldWidget) {
    assert(_debugCheckOwnerBuildTargetExists('notifyClients'));
    // 遍历_dependents, 通知其中每一个element进行刷新。
    for (final Element dependent in _dependents.keys) {
      ...
      notifyDependent(oldWidget, dependent);
    }
  }

  @protected
  void notifyDependent(covariant InheritedWidget oldWidget, Element dependent) {
    // 这里会见Element标记为dirty
    dependent.didChangeDependencies();
  }
```

```
  @mustCallSuper
  void didChangeDependencies() {
    // 这一行是关键, 即将自己(Element)标记为dirty。
    // 同时加入BuildOwner的`_dirtyElements`中, 等待重新build
    markNeedsBuild();
  }
```

可以看到当ancestor刷新的时候, 对应的Element会被标记为dirty(即`markNeedsBuild`)。这一过程同很熟悉的StatefullWidget内部逻辑一致。

### # 刷新过程

前面说到`dependOnInheritedElement`会将当前Context(即Element)绑定到InheritedElement里, 当被绑定的Element标记为dirty之后, 自身将一会被重新build。

下面来看看被绑定的Element是如何同数据绑定的。

上面提到, 想获取数据都需要先拿到`_InheritedProviderScopeElement`对象, 并访问其`value`对象。这一过程初看并无任何绑定行为。其实`value`的get函数, 访问的是`_delegateState`的value, 如下:

```dart
// inherited_provider.dart
class _InheritedProviderScopeElement<T> extends InheritedElement
    implements InheritedContext<T> {
  ...
  @override
  T get value => _delegateState.value;
  ...
}
```

继续看`_delegateState`的实现, 即`_CreateInheritedProviderState`, 如下:

```dart
// inherited_provider.dart
class _CreateInheritedProviderState<T>
    extends _DelegateState<T, _CreateInheritedProvider<T>> {
  VoidCallback _removeListener;
  bool _didInitValue = false;
  T _value;
  _CreateInheritedProvider<T> _previousWidget;

  @override
  T get value {
    ...
    if (!_didInitValue) {
      _didInitValue = true;
          ...
          // 创建数据, 这里只会被调用一次。
          _value = delegate.create(element);
          ...
          // 刷新数据的回调
          _value = delegate.update(element, _value);
      ...
    }
    // 这里将注册到ChangeNotifier的Listener中去。
    // 当数据发送变化后notifyListener即可刷新`_InheritedProviderScopeElement`
    _removeListener ??= delegate.startListening?.call(element, _value);
    return _value;
  }
  ...
}
```

可以看到`_CreateInheritedProviderState`中, 返回_value之前, 会调用其内部的`delegate`的`startListening`闭包, 将element以及value传递过去。

通过前面Provider初始化可知, 这个`startListening`就是`ListenableProvider`的`_startListening`方法, 如下:

```dart
// listenable_provider.dart
class ListenableProvider<T extends Listenable> extends InheritedProvider<T> {
  static VoidCallback _startListening(
    InheritedContext<Listenable> e,
    Listenable value,
  ) {
    // 注册listener, 用于刷新界面。
    value?.addListener(e.markNeedsNotifyDependents);
    // 返回的是取消注册的闭包。
    return () => value?.removeListener(e.markNeedsNotifyDependents);
  }
}

// inherited_provider.dart: _InheritedPoviderScopeElement
@override
void markNeedsNotifyDependents() {
  if (!_isNotifyDependentsEnabled) return;
  // 将自己标记为dirty
  markNeedsBuild();
  _shouldNotifyDependents = true;
}
```

可见, 最终将`markNeedsNotifyDependents`注册到value(即ChangeNotifier)的listener列表中。

当数据发送变化只, 在数据端触发`notifyListeners()`函数即可。这里会分发所有的listener。如下:

```dart
// change_notifier.dart: ChangeNotifier
  void notifyListeners() {
    if (_listeners != null) {
      final List<VoidCallback> localListeners = List<VoidCallback>.from(_listeners);
      for (final VoidCallback listener in localListeners) {
        try {
          if (_listeners.contains(listener))
            listener();
        } catch (exception, stack) {
          ...
        }
      }
    }
  }
```

此时前面注册的`markNeedsNotifyDependents`方法则会被执行到, 将自己标记为dirty。

对于Value方式, 这一过程也是一样, 如下:

```dart
class _ValueInheritedProviderState<T>
    extends _DelegateState<T, _ValueInheritedProvider<T>> {
  VoidCallback _removeListener;

  @override
  T get value {
    // 少了create, 直接拿到delegate中构造时即存储的value对象。
    // 中间调用`startListening`逻辑同上面一致。
    element._isNotifyDependentsEnabled = false;
    _removeListener ??= delegate.startListening?.call(element, delegate.value);
    element._isNotifyDependentsEnabled = true;
    assert(delegate.startListening == null || _removeListener != null);
    return delegate.value;
  }
  ...
}
```

### # 小结

`Provider`提供一个拥有共享数据能力的`InheritedWidget`(InheritedElement)。

业务层的Widget通过`Provider.of`获取`value`的时候, 将InheritedElement的标记函数绑定到ChangeNotifier的`_listeners`中。

当ChangeNotifier的数据变化后触发`notifyListeners`标记Element及其依赖们重构, 实现数据刷新。