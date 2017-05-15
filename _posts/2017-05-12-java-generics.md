---
layout: post
title: "Java之泛型"
category: all-about-tech
tags: -[Java] -[Generic] -[Type]
date: 2017-05-12 23:03:00+00:00
---

泛型的出现，让我们写一些容器的时候变的更爽了。比如我只想在列表中添加Message，非Message不能添加进来的话，我们就需要使用泛型了。再比如RxJava的出现，让泛型的使用更加出神入化了。

泛型是从Java5开始被支持的，泛型的出现可以让编译器提前告知你类型错误，从而避免(减少)运行时出现类型错误等等。

下面我们来先举个例子：

```java
// Case 1
final List<Integer> integers = new ArrayList<>();
final List<Object> objects = integers;

// Case 2
final Integer[] aI = new Integer[1];
final Object[] aO = aI;
```

当我们IDE中写出如上语句的时候，你会发现`Case 1`会报错误，而`Case 2`不会报错。主要原因是Java中泛型默认是不允许协变，而数组是允许协变的。如果`Case 1`也能像`Case 2`一样的话，那么就破坏了泛型的安全性。

## 类型擦除

其实泛型是在编译器层面实现的，简单来说就是编译的时候编译器会将泛型给擦除，只留下RawType。比如：List\<String\>编译后会变成List。

之所以会出现泛型擦除主要原因是泛型是Java1.5之后才出现的，也就是说我们之前写的代码是没法使用的。主要是兼容性方面的考虑，故而编译器编译的时候会进行泛型擦除。

正因为会类型擦除，从而不会存在`List<String>.class`这种class发生。如果我们写代码的时候想要告诉调用的类型是这样的方式怎么办呢？一种方式是反射，一种是自己实现一个`ParameterizedType`。下面将Type的时候会讲到。

## 通配符

`extends`表示的是类型的上界，即表示类型的最上层的超类。故而其表示的类型是其本身或者其子类。

`super`表示的是类型的下界，即表示类型的最下层的子类。故而其表示的是类型本身或者其超类，一直到Object。

下面分别距离讲讲extent和super的读取逻辑。

### extends

```java
// 可以使用Number本身
List<? extends Number> list = new ArrayList<Number>();
// Integer继承自Number
List<? extends Number> list = new ArrayList<Integer>();
// Long继承自Number
List<? extends Number> list = new ArrayList<Long>();
```

读取的时候，以上面代码为例，列表可以保证的是读取的数据类型一定是Number或者其子类。

但是使用extend方式的通配符没法进行写入，因为没法知道list具体是什么类型。比如你想往里面add一个Number，但是list有可能是ArrayList<Integer>；如果你想往里面写入一个Integer的时候，list也有可能是ArrayList<Long>。所以使用extends的时候是没法往list里面写入的。

但是，在list初始化的时候可以直接引用另一个list。比如：
```java
final List<? extends Number> list = new ArrayList<Long>();
final List<? extends Number> list2 = list;
```

### super

```java
final Integer integer = Integer.valueOf(0);
final List<? super Integer> numbers = new ArrayList<Number>();// Number是Integer的父类
final List<? super Integer> objects = new ArrayList<Object>();// Object是所有对象的父类
final List<? super Integer> integers = new ArrayList<Integer>();// 可以使用Integer本身
numbers.add(integer);
objects.add(integer);
integers.add(integer);
```

读取的数据的时候，由于不知道具体的泛型是什么，所以没法确认其类型。但是可以肯定的是，必然是Object或者其子类(废话)。

而super则可以直接往里面写入数据。如上，不论list是一个`ArrayList<Integer>`还是一个`ArrayList<Number>`，我们都可以往里面写入一个Integer。因为可以确定的是list中的泛型必然是Integer或者其父类。但是，Integer的父类比如`Number`是不允许写入的，因为编译器不能确定list是一个`ArrayList<Number>`，编译器只知道当前的泛型是Integer或者其父类。

### 协变

前面提到了协变，在Java中数据时支持协变的。对于数组而言，Number是Integer的父类，那么Number[]也是Integer[]的父类了。而泛型的出现就是为了让我们写代码的时候类型安全，如果List<Number>是List<Integer>的父类的话，我们编译器会运行我们往list里面添加一个Long，但是它需要的是Integer，故而就破坏了泛型的初衷：类型安全。所以默认泛型是不支持协变的。

但是，使用通配符的时候泛型是支持协变的。比如:

```java
final List<Number> numbers = new ArrayList<>();
final List<? extends Object> list = integers;
```
原因是使用extends的时候，编译器要求list的泛型必须是Object的子类，故而Number可以支持。

下面这种方式是`逆变`，它与协变是反过来的。

```java
final List<Number> numbers = new ArrayList<>();
final List<? super Integer> list = numbers;
```

对了，开头提到的那种不能编译通过的方式是`不变`。


## Type

Type是所有类型的父接口，比如Class本身就是继承自Type的。
在我们使用反射的时候通常会用到Type。

```java
public final
    class Class<T> implements java.io.Serializable,
                              java.lang.reflect.GenericDeclaration,
                              java.lang.reflect.Type,
                              java.lang.reflect.AnnotatedElement {
```

它大概会分为下面几种方式：

### Class

除泛型之外Class本身就是一种Type，包括PrimitiveType也会被box成对应的Class对象。

### PrimitiveType

基本类型

比如: boolean.class/byte.class/char.class/double.class/float.class/int.class/long.class/short.class。当我们反射需要用到的时候需要将其转换成对应的Class，比如Boolean.class等等。

### ParameterizedType

参数化类型。

比如: List<String>/Map<Integer,String>等等。

主要三个方法：

- `Type[] getActualTypeArguments();` 返回的是泛型的参数的类型，比如`List<String>`会返回`String`,如果是`Map<String,Integer>`则为`String和Integer`组成的数组
- `Type getRawType();` 返回的是泛型擦除后的类型，比如上面的`List<String>`会返回`List`
- `Type getOwnerType();` 一般返回的是类的Owner，比如声明为`A.B`，则此处返回为A

例如：

```java
public static class LIST<T extends View & Comparable & Cloneable> extends ArrayList<T> {
    private T key;
    private OBJ<T>[] array = new OBJ[0];
}
//
public static class OBJ extends View implements Comparable<OBJ>, Cloneable {

    public OBJ(Context context) {
        super(context);
    }

    @Override
    public int compareTo(@NonNull OBJ o) {
        return 0;
    }
}
//
private final ReflectTypeFragment.LIST<OBJ> list = new ReflectTypeFragment.LIST<>();
private void testParameterizedType() throws NoSuchFieldException {
    final Field field = this.getClass().getDeclaredField("list");
    final Type type = field.getGenericType();
    final ParameterizedType pt = (ParameterizedType) type;
    log(String.format("type = %s (%s)\nActualTypeArguments=%s\nOwnerType = %s", print(type), (type instanceof ParameterizedType), print(pt.getActualTypeArguments()), print(pt.getOwnerType())));
}
```

最后的结果为：

```
type = ReflectTypeFragment$LIST<ReflectTypeFragment$OBJ>(true)
ActualTypeArguments = class ReflectTypeFragment$OBJ
OwnerType = class ReflectTypeFragment
```

### TypeVariable

类型变量

- `Type[] getBounds()` , 返回的是泛型的上边界。也就是说是只能通过"extends"方式声明类型。
- `D getGenericDeclaration()`, 返回的是声明的此类型的地方。
- `String getName()`, 源码中定义泛型时的名字。

例如：

```java    
private void testVariable() throws NoSuchFieldException {
    final Field field = LIST.class.getDeclaredField("key");
    final Type type = field.getGenericType();
    final TypeVariable t = (TypeVariable) type;
    log(String.format("type = %s (%s)\nBounds = %s\nGenericDeclaration = %s\nName = %s", print(type), (type instanceof TypeVariable), print(t.getBounds()), t.getGenericDeclaration(), t.getName()));
}  
```

```
type = T (true)
Bounds = class android.view.View, interface java.lang.Comparable, interface java.lang.Cloneable
GenericDeclaration = class ReflectTypeFragment$LIST
Name = T
```

### GenericArrayType

数组类型。

需要注意的是，只能是TypeVariable或者是ParameterizedType的数组才能称得上是数组类型, 比如String[]，List<String>都不是。

- `Type getGenericComponentType();` 返回的是数组的类型。

```java
private void testGenericArrayType() throws NoSuchFieldException {
    final Field field = LIST.class.getDeclaredField("array");
    final GenericArrayType t = (GenericArrayType) field.getGenericType();
    log(String.format("testGenericArrayType:\ntype = %s\ngetGenericComponentType = %s", print(t), print(t.getGenericComponentType())));
}
```

结果：

```
type = [ GenericArrayType: ReflectTypeFragment$OBJ<T>[] ]
getGenericComponentType = [ ParameterizedType: ReflectTypeFragment$OBJ<T> ]
```

可以看到`t.getGenericComponentType()`返回的是ParameterizedType。

### WildcardType

通配符类型.

- `Type[] getUpperBounds()` 获取到的是类型的上限，如果没有设定上限那么默认会是`Object.class`
- `Type[] getLowerBounds()` 获取到的类型的下限，如果没通过`super`设定那么默认为null。

例如:

```java
private final Map<? super View, ? extends View> map = new HashMap<>();
private void testWildcardType() throws NoSuchFieldException {
    final Field field = this.getClass().getDeclaredField("map");
    final ParameterizedType pt = (ParameterizedType) field.getGenericType();
    for (Type type : pt.getActualTypeArguments()) {
        final WildcardType t = (WildcardType) type;
        log(String.format("testWildcardType:\ntype = %s\ngetUpperBounds = %s\ngetLowerBounds = %s", print(t), print(t.getUpperBounds()), print(t.getLowerBounds())));
    }
}
```

打印结果如下:


```
testWildcardType:
type = [ ? super android.view.View ]
getUpperBounds = [ class java.lang.Object ]
getLowerBounds = [ class android.view.View ]
testWildcardType:
type = [ ? extends android.view.View ]
getUpperBounds = [ class android.view.View ]
getLowerBounds = null
```

在这里使用了一个Map，map对象是一个ParameterizedType，然后通过其`getActualTypeArguments`，获取里面的多个Parameter。之后每个Parameter都是通配符。

> 参考：
> 
- <https://segmentfault.com/a/1190000003831229>
- <http://www.infoq.com/cn/articles/cf-java-generics>
- <https://www.ibm.com/developerworks/cn/java/j-jtp01255.html>
- <http://loveshisong.cn/%E7%BC%96%E7%A8%8B%E6%8A%80%E6%9C%AF/2016-02-16-Type%E8%AF%A6%E8%A7%A3.html>