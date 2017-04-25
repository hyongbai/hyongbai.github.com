---
layout: post
title: "Android类加载ClassLoader"
category: all-about-tech
tags: -[Android] -[ClassLoader]
date: 2017-04-25 21:57:00+00:00
---

## 基本知识

Java的类加载设计了一套双亲代理的模式，使得用户没法替换系统的核心类，从而让应用更安全。所谓双亲代理就是指，当加载类的时候首先去Bootstrap中加载类，如果没有则去Extension中加载，如果再没有才去AppClassLoader中去加载。从而实现安全和稳定。

## Java ClassLoader

### BootstrapClassLoader

`引导类加载器`，用来加载Java的核心库。通过底层代码来实现的，基本上只要parent为null，那就表示引导类加载器。

> 比如：charsets.jar、deploy.jar、javaws.jar、jce.jar、jfr.jar、jfxswt.jar、jsse.jar、management-agent.jar、plugin.jar、resources.jar、rt.jar

### ExtClassLoader

`拓展类加载器`，用来加载Java的拓展的类库，`${JAVA_HOME}/jre/lib/ext/`目录中的所有jar。

> 比如：cldrdata.jar、dnsns.jar、jfxrt.jar、localedata.jar、nashorn.jar、sunec.jar、sunjce_provider.jar、sunpkcs11.jar、zipfs.jar等等

### AppClassLoader

`系统类加载器`(不要被名字给迷惑)，用来加载Java应用中的类。一般来说自己写的类都是通过这个加载的。而Java中`ClassLoader.getSystemClassLoader()`返回的就是AppClassLoader。(Android中修改了ClassLoader的逻辑，返回的会是一个PathClassLoader)

### 自定义ClassLoader

用户如果想自定义ClassLoader的话，只需要继承自`java.lang.ClassLoader`即可。

ClassLoader中与加载类相关的方法：

* **getParent()** 返回该类加载器的父类加载器。
* **loadClass(String name)** 加载名称为 name的类，返回的结果是 java.lang.Class类的实例。
* **findClass(String name)** 查找名称为 name的类，返回的结果是 java.lang.Class类的实例。
* **findLoadedClass(String name)** 查找名称为 name的已经被加载过的类，返回的结果是 java.lang.Class类的实例。
* **defineClass(String name, byte[] b, int off, int len)** 把字节数组 b中的内容转换成 Java 类，返回的结果是 java.lang.Class类的实例。这个方法被声明为 final的。

也许你不太了解上面几个函数的区别，没关系，我们来看下源码是如何实现的。

```java
//ClassLoader.java
protected Class<?> loadClass(String name, boolean resolve)
    throws ClassNotFoundException
{
        // First, check if the class has already been loaded
        Class c = findLoadedClass(name);
        if (c == null) {
            long t0 = System.nanoTime();
            try {
                if (parent != null) {
                    c = parent.loadClass(name, false);
                } else {
                    c = findBootstrapClassOrNull(name);
                }
            } catch (ClassNotFoundException e) {
                // ClassNotFoundException thrown if class not found
                // from the non-null parent class loader
            }

            if (c == null) {
                // If still not found, then invoke findClass in order
                // to find the class.
                long t1 = System.nanoTime();
                c = findClass(name);

                // this is the defining class loader; record the stats
            }
        }
        return c;
}
```

所以优先级大概如下:

loadClass → findLoadedClass → parent.loadClass/findBootstrapClassOrNull → findClass → defineClass

## Android ClassLoader

在Android中ClassLoader主要有两个直接子类，叫做`BaseDexClassLoader`和`SecureClassLoader`。而前者有两个直接子类是`PathClassLoader`和`DexClassLoader`(Android O添加了`InMemoryDexClassLoader`，略)。

我们只讨论PathClassLoader和DexClassLoader

### PathClassLoader

用来加载安装了的应用中的dex文件。它也是Android里面的一个最核心的ClassLoader了。相当于Java中的那个AppClassLoader。

```java
public class PathClassLoader extends BaseDexClassLoader {
    /**
     * Creates a {@code PathClassLoader} that operates on a given list of files
     * and directories. This method is equivalent to calling
     * {@link #PathClassLoader(String, String, ClassLoader)} with a
     * {@code null} value for the second argument (see description there).
     *
     * @param dexPath the list of jar/apk files containing classes and
     * resources, delimited by {@code File.pathSeparator}, which
     * defaults to {@code ":"} on Android
     * @param parent the parent class loader
     */
    public PathClassLoader(String dexPath, ClassLoader parent) {
        super(dexPath, null, null, parent);
    }

    /**
     * Creates a {@code PathClassLoader} that operates on two given
     * lists of files and directories. The entries of the first list
     * should be one of the following:
     *
     * <ul>
     * <li>JAR/ZIP/APK files, possibly containing a "classes.dex" file as
     * well as arbitrary resources.
     * <li>Raw ".dex" files (not inside a zip file).
     * </ul>
     *
     * The entries of the second list should be directories containing
     * native library files.
     *
     * @param dexPath the list of jar/apk files containing classes and
     * resources, delimited by {@code File.pathSeparator}, which
     * defaults to {@code ":"} on Android
     * @param librarySearchPath the list of directories containing native
     * libraries, delimited by {@code File.pathSeparator}; may be
     * {@code null}
     * @param parent the parent class loader
     */
    public PathClassLoader(String dexPath, String librarySearchPath, ClassLoader parent) {
        super(dexPath, null, librarySearchPath, parent);
    }
}
```

它的实例化是通过调用`ApplicationLoaders.getClassLoader`来实现的。

它是在ActivityThread启动时发送一个BIND_APPLICATION消息后在handleBindApplication中创建ContextImpl时调用LoadedApk里面的`getResources(ActivityThread mainThread)`最后回到ActivityThread中又调用LoadedApk的`getClassLoader`生成的，具体的在LoadedApk的`createOrUpdateClassLoaderLocked`。

那么问题来了，当Android加载class的时候，LoadedApk中的ClassLoader是怎么被调用到的呢？

其实Class里面，如果你不给ClassLoader的话，它默认会去拿Java虚拟机栈里面的`CallingClassLoader`，而这个就是LoadedApk里面的同一个ClassLoader。

```java
//Class.java
public static Class<?> forName(String className)
            throws ClassNotFoundException {
    return forName(className, true, VMStack.getCallingClassLoader());
}
```

查看VMStack的源码发现`getCallingClassLoader`其实是一个native函数，Android通过底层实现了这个。

```java
//dalvik.system.VMStack
/**
 * Returns the defining class loader of the caller's caller.
 *
 * @return the requested class loader, or {@code null} if this is the
 *         bootstrap class loader.
 */
@FastNative
native public static ClassLoader getCallingClassLoader();
```

底层想必最终也是拿到LoadedApk里面的ClassLoader。

### DexClassLoader

它是一个可以用来加载包含dex文件的jar或者apk文件的，但是它可以用来加载非安装的apk。比如加载sdcard上面的，或者NetWork的。

```java
public class DexClassLoader extends BaseDexClassLoader {
    /**
     * Creates a {@code DexClassLoader} that finds interpreted and native
     * code.  Interpreted classes are found in a set of DEX files contained
     * in Jar or APK files.
     *
     * <p>The path lists are separated using the character specified by the
     * {@code path.separator} system property, which defaults to {@code :}.
     *
     * @param dexPath the list of jar/apk files containing classes and
     *     resources, delimited by {@code File.pathSeparator}, which
     *     defaults to {@code ":"} on Android
     * @param optimizedDirectory directory where optimized dex files
     *     should be written; must not be {@code null}
     * @param librarySearchPath the list of directories containing native
     *     libraries, delimited by {@code File.pathSeparator}; may be
     *     {@code null}
     * @param parent the parent class loader
     */
    public DexClassLoader(String dexPath, String optimizedDirectory,
            String librarySearchPath, ClassLoader parent) {
        super(dexPath, new File(optimizedDirectory), librarySearchPath, parent);
    }
}
```

比如现在很流行的插件化/热补丁，其实都是通过DexClassLoader来实现的。具体思路是：
创建一个DexClassLoader，通过反射将前者的DexPathList跟系统的PathClassLoader中的DexPathList合并，就可以实现优先加载我们自己的新类，从而替换旧类中的逻辑了。