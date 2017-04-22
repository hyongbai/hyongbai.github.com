---
layout: post
title: "Java线程池"
category: all-about-tech
tags: -[Android] -[Java] -[Thread] -[Executor]
date: 2017-04-22 17:41:00+00:00
---

## 类介绍

- **Executor** 只有一个execute接口
- **ExecutorService** 继承自Executor主要添加了`shutdown`和`submit`等接口
- **AbstractExecutorService** 一个抽象的线程池基类，基本实现了除`execute`和`shutdown`之外所有的接口
- **ThreadPoolExecutor**
- **Executors** 线程池实例化的帮助类，创建新的线程池可以通过此类操作。

## 参数介绍

ThreadPoolExecutor提供了多个参数供我们来设置，下面列出其中主要的几个参数并讲解起主要的作用。

- **int corePoolSize** 核心线程的数量。提交一个任务进来的时候，不论当前有没有空闲的线程，只要当前的线程数量不超过此值，线程池都会创建一个`Worker`(里面会创建一个新的Thread)。调用`prestartAllCoreThreads`的时候线程池会一次性将所有的线程都创建好，等待任务进来。
- **BlockingQueue<Runnable> workQueue** 当前正在等待的任务列表，阻塞式队列。当当前核心线程达到上限的时候，新进来的任务会被放到此队列中等待调用。
	- **SynchronousQueue** 一个不存储元素的阻塞队列。每个插入操作必须等到另一个线程调用移除操作，否则插入操作一直处于阻塞状态，吞吐量通常要高于LinkedBlockingQueue，静态工厂方法Executors.newCachedThreadPool使用了这个队列。
	- **DelayedWorkQueue** ScheduledThreadPoolExecutor使用的阻塞队列。
	- **ArrayBlockingQueue** 基于数组结构的有界阻塞队列，此队列按 FIFO（先进先出）原则对元素进行排序。
	- **LinkedBlockingQueue** 基于链表结构的阻塞队列，此队列按FIFO （先进先出） 排序元素，吞吐量通常要高于ArrayBlockingQueue。
	- **PriorityBlockingQueue** 一个具有优先级的无限阻塞队列。
- **int maximumPoolSize** 允许线程池中同时存在的最大线程数量。如果workQueue已经满了，只要没达到次上限，那么线程池仍然会继续创建新的线程。
- **long keepAliveTime** 线程休息下来(IDLE)之后最大的超时时间。精确到纳秒。后边会有描述。
- **ThreadFactory threadFactory** 创建新线程的工厂类。可以自己定义一个工厂类，主要是可以给线程命名，以方便调试。
- **RejectedExecutionHandler handler** 比如：当队列满了且已达到最大线程数量时新任务就没法加入线程池了，此时会使用这个Handler来处理Reject异常。
	- 默认使用AbortPolicy，直接抛出RejectedExecutionException

## 常用线程池

Java中提供了Executors这个线程池工厂类，提供了多个生成线程池的方式。下面就列出其中有代表性的4类。

### newFixedThreadPool 

固定核心线程数量的线程池

```java
//Executors.java
public static ExecutorService newFixedThreadPool(int nThreads) {
    return new ThreadPoolExecutor(nThreads, nThreads,
                                  0L, TimeUnit.MILLISECONDS,
                                  new LinkedBlockingQueue<Runnable>());
}
```

可见该线程池的core和max数量一模一样。且线程池中的线程会一直保留下来。

注意这里使用的是LinkedBlockingQueue中默认的`capacity`，翻开它的源码可以发现，默认值是`Integer.MAX_VALUE`。所以基本上不用考虑max的问题。

### newCachedThreadPool

```java
//Executors.java
public static ExecutorService newCachedThreadPool() {
    return new ThreadPoolExecutor(0, Integer.MAX_VALUE,
                                  60L, TimeUnit.SECONDS,
                                  new SynchronousQueue<Runnable>());
}
```

核心线程数量为0，但是最大线程数量为Integer.MAX_VALUE。且每个线程的IDLE存活寿命会有60秒。

### newScheduledThreadPool

可以延时执行的线程池

### newSingleThreadExecutor

顾名思义单线程的线程池。同newFixedThreadPool，区别在于核心线程和最大线程均为1.

## 工作原理

我们以ThreadPoolExecutor为例来看看Java中线程池的运作方式。

```java
//ThreadPoolExecutor.java
public void execute(Runnable command) {
    if (command == null) throw new NullPointerException();
    int c = ctl.get();
    if (workerCountOf(c) < corePoolSize) {
        if (addWorker(command, true))
            return;
        c = ctl.get();
    }
    if (isRunning(c) && workQueue.offer(command)) {
        int recheck = ctl.get();
        if (! isRunning(recheck) && remove(command))
            reject(command);
        else if (workerCountOf(recheck) == 0)
            addWorker(null, false);
    }
    else if (!addWorker(command, false))
        reject(command);
}
```

首先，捣乱的比如空的task会抛出NPE。
然后如果当前的核心线程数量没达到上线，则会直接创建一个Worker(包含一个新线程)。即：`addWorker(command, true)`;
如果核心线程已达上线，那么会将新任务放到阻塞队列中。即：`isRunning(c) && workQueue.offer(command)`。有种情况，比如`newCachedThreadPool`这种会出现核心数量为0的情况，此时加入到阻塞队列其不是瞎了？不会，这是他会调用`addWorker(null, false)`创建一个Worker，这样队列就有人来消费了。
如果阻塞队列也满了，但是没有达到最大线程数那么会创建一个新的Worker。否则就会调用reject。默认是抛出`RejectedExecutionException`异常。

好了，基本逻辑是这样的。那么我们来看看两个逻辑，一个是创建线程，一个是消费任务。

### 创建线程

主要逻辑在于addWorkder中。

```java
//ThreadPoolExecutor
private boolean addWorker(Runnable firstTask, boolean core) {
    retry:
    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c);

        // Check if queue empty only if necessary.
        if (rs >= SHUTDOWN &&
            ! (rs == SHUTDOWN &&
               firstTask == null &&
               ! workQueue.isEmpty()))
            return false;

        for (;;) {
            int wc = workerCountOf(c);
            if (wc >= CAPACITY ||
                wc >= (core ? corePoolSize : maximumPoolSize))
                return false;
            if (compareAndIncrementWorkerCount(c))
                break retry;
            c = ctl.get();  // Re-read ctl
            if (runStateOf(c) != rs)
                continue retry;
            // else CAS failed due to workerCount change; retry inner loop
        }
    }

    boolean workerStarted = false;
    boolean workerAdded = false;
    Worker w = null;
    try {
        w = new Worker(firstTask);
        final Thread t = w.thread;
        if (t != null) {
            final ReentrantLock mainLock = this.mainLock;
            mainLock.lock();
            try {
                // Recheck while holding lock.
                // Back out on ThreadFactory failure or if
                // shut down before lock acquired.
                int rs = runStateOf(ctl.get());

                if (rs < SHUTDOWN ||
                    (rs == SHUTDOWN && firstTask == null)) {
                    if (t.isAlive()) // precheck that t is startable
                        throw new IllegalThreadStateException();
                    workers.add(w);
                    int s = workers.size();
                    if (s > largestPoolSize)
                        largestPoolSize = s;
                    workerAdded = true;
                }
            } finally {
                mainLock.unlock();
            }
            if (workerAdded) {
                t.start();
                workerStarted = true;
            }
        }
    } finally {
        if (! workerStarted)
            addWorkerFailed(w);
    }
    return workerStarted;
}
```

这段代码貌似挺长的，其实做的事情很简单。

- 检查当前线程池状态是否`RUNNING`。
- 检测是否已达到线程数量上限。`core ? corePoolSize : maximumPoolSize`
- 创建一个新的Workder并将其放入`workers`中去。注意，对`workers`列表的操作都是使用`mainLock`加了锁的。之后从队列移除也是一样。
- 启动`Worker`中的线程。如果启动失败则会调用`addWorkerFailed`将刚刚创建的Worker从队列中移除。

### 消费任务

看了上面的介绍小伙伴们大概知道了，线程池里面很重要的一个角色是`Worker`，下面就来看看这是个什么玩意。

Workder其实是ThreadPoolExecutor的一个私有内部类。如下：

```java
//ThreadPoolExecutor$Worker
Worker(Runnable firstTask) {
    setState(-1); // inhibit interrupts until runWorker
    this.firstTask = firstTask;
    this.thread = getThreadFactory().newThread(this);
}
```

创建Worker实例的时候就会创建一个线程实例。它是通过上面提到的TreadFactory生成的，注意将Worker实例也当做参数带入了。

所以当addWorker时使用`worker.t.start()`启动线程是会回调到Worker实现Runnable的逻辑。最终调用到`ThreadPoolExecutor.runWorker(Worker w)`。

```java
//ThreadPoolExecutor.java
final void runWorker(Worker w) {
    Thread wt = Thread.currentThread();
    Runnable task = w.firstTask;
    w.firstTask = null;
    w.unlock(); // allow interrupts
    boolean completedAbruptly = true;
    try {
        while (task != null || (task = getTask()) != null) {
            w.lock();
            // If pool is stopping, ensure thread is interrupted;
            // if not, ensure thread is not interrupted.  This
            // requires a recheck in second case to deal with
            // shutdownNow race while clearing interrupt
            if ((runStateAtLeast(ctl.get(), STOP) ||
                 (Thread.interrupted() &&
                  runStateAtLeast(ctl.get(), STOP))) &&
                !wt.isInterrupted())
                wt.interrupt();
            try {
                beforeExecute(wt, task);
                Throwable thrown = null;
                try {
                    task.run();
                } catch (RuntimeException x) {
                    thrown = x; throw x;
                } catch (Error x) {
                    thrown = x; throw x;
                } catch (Throwable x) {
                    thrown = x; throw new Error(x);
                } finally {
                    afterExecute(task, thrown);
                }
            } finally {
                task = null;
                w.completedTasks++;
                w.unlock();
            }
        }
        completedAbruptly = false;
    } finally {
        processWorkerExit(w, completedAbruptly);
    }
}
```

如果将这段代码精简一下的话，那就是:

```java
//ThreadPoolExecutor.java
final void runWorker(Worker w) {
    // ...
    boolean completedAbruptly = true;
    try {
        while (task != null || (task = getTask()) != null) {
            // ...
            task.run();
            // ...
        }
        completedAbruptly = false;
    } finally {
        processWorkerExit(w, completedAbruptly);
    }
}
```

所以核心在于`getTask`这一段。其实就是去阻塞队列中获取任务的过程。如果队列消费完了，会调用`processWorkerExit`将线程丢弃掉。

等等，说好的等待IDLE等待时间哪去了？别着急，其实这段代码在`getTask`里面做了。

```java
//ThreadPoolExecutor.java
private Runnable getTask() {
    boolean timedOut = false; // Did the last poll() time out?

    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c);

        // Check if queue empty only if necessary.
        if (rs >= SHUTDOWN && (rs >= STOP || workQueue.isEmpty())) {
            decrementWorkerCount();
            return null;
        }

        int wc = workerCountOf(c);

        // Are workers subject to culling?
        boolean timed = allowCoreThreadTimeOut || wc > corePoolSize;

        if ((wc > maximumPoolSize || (timed && timedOut))
            && (wc > 1 || workQueue.isEmpty())) {
            if (compareAndDecrementWorkerCount(c))
                return null;
            continue;
        }

        try {
            Runnable r = timed ?
                workQueue.poll(keepAliveTime, TimeUnit.NANOSECONDS) :
                workQueue.take();
            if (r != null)
                return r;
            timedOut = true;
        } catch (InterruptedException retry) {
            timedOut = false;
        }
    }
}
```

这里需要注意的有一点：timed。

```java
timed = allowCoreThreadTimeOut || wc > corePoolSize
```
allowCoreThreadTimeOut的默认值为false，也就是说只有当前的线程数量(workerCount)大于核心线程数(corePoolSize)的时候才会执行keepAliveTime这个超时设定。

所以：
- 对于Executors创建的newCachedThreadPool，永远都会执行超时动作。
- 对于Executors创建的newFixedThreadPool，，如果你不将allowCoreThreadTimeOut设定为true的话，基本上永远都不会执行超时的动作。(本身keepAliveTime是0，但是阻塞队列capacity为Integer.MAX)。

## 总结

在使用线程池的时候，我们最好参考CPU的核心数确定线程池coreSize，以便更有效。

待续。

## 参考

> - <http://www.infoq.com/cn/articles/java-threadPool/>
- <http://www.cnblogs.com/dolphin0520/p/3932921.html/>
- <http://wiki.jikexueyuan.com/project/java-concurrency/executor.html/>