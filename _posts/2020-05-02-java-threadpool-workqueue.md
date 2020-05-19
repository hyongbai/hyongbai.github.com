---
layout: post
title: "Java线程池工作原理以及常用WorkQueue"
description: "Java线程池工作原理以及常用WorkQueue"
category: all-about-tech
tags: -[aosp，art, android]
date: 2020-05-02 02:59:57+00:00
---

涉及到：ThreadPoolExecutor及其参数、Executors、SynchronousQueue、LinkedBlockingQueue

## ThreadPoolExecutor

```java
// ThreadPoolExecutor.java
public void execute(Runnable command) {
    if (command == null)
        throw new NullPointerException();
    int c = ctl.get();
    // 如果当前线程数量未超过核心线程数
    if (workerCountOf(c) < corePoolSize) {
        if (addWorker(command, true))
            return;
        c = ctl.get();
    }
    // 如果任务队列接收新任务加入
    if (isRunning(c) && workQueue.offer(command)) {
        int recheck = ctl.get();
        if (! isRunning(recheck) && remove(command))
            reject(command);
        else if (workerCountOf(recheck) == 0)
            addWorker(null, false);
    }
    // 前面两个条件都不满足，则添加worker
    // 注意如果工作线程超过maxPoolSize这里很有可能会失败
    else if (!addWorker(command, false))
        reject(command);
}
```

- 如果线程数量小于coreSize，则创建新的core线程。

- 如果workQueue(阻塞任务队列)允许加入队列，则加入队列，等待线程重用。

- 最后，创建普通线程。如果当前线程数量已超过maxThreadSize，则直接reject。

其中：

- core线程会一直存在不会退出(正常情况下)。

- maxSize说的是总线程的数量，包含了coreSize。coreSize如果大于`maxSize`，那么核心线程最后会退出直到数量达到maxSize

- keepAliveTime说的是普通线程闲置时间，在这个时间内getTask为null则退出。

### # addWorkder

线程池里面每个工作线程都是以Worker为单位的方式运行的。

```java
// ThreadPoolExecutor.java
private boolean addWorker(Runnable firstTask, boolean core) {
    retry:
    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c);
        // 如果线程池已关闭(HUTDOWN) -> 不接手新任务
        // 或者当前的任务为空 -> 无效任务
        // 或者当前workQueue为空 -> 直接加入workQueue等待线程复用
        if (rs >= SHUTDOWN &&
            ! (rs == SHUTDOWN &&
               firstTask == null &&
               ! workQueue.isEmpty()))
            return false;

        for (;;) {
            int wc = workerCountOf(c);
            // CAPACITY 为`2^29 - 1`
            // (默认最大值，小于MAX_VALUE)
            // 如果线程数大于CAPACITY
            // 或者大于核心size(创建核心线程时)
            // 或者大于最大线程数(创建普通线程时)
            if (wc >= CAPACITY ||
                wc >= (core ? corePoolSize : maximumPoolSize))
                return false;
            if (compareAndIncrementWorkerCount(c))
                break retry;
            c = ctl.get();
            // 线程状态变化，重新检查
            if (runStateOf(c) != rs) continue retry;
        }
    }

    boolean workerStarted = false;
    boolean workerAdded = false;
    Worker w = null;
    try {
        // 创建worker，并接收firstTask最为初始任务
        w = new Worker(firstTask);
        final Thread t = w.thread;
        if (t != null) {
            final ReentrantLock mainLock = this.mainLock;
            mainLock.lock();
            try {
                // 重新检查线程池状态
                int rs = runStateOf(ctl.get());
                if (rs < SHUTDOWN ||
                    (rs == SHUTDOWN && firstTask == null)) {
                    if (t.isAlive()) // precheck that t is startable
                        throw new IllegalThreadStateException();
                    // 添加到workers队列，即工作线程队列
                    workers.add(w);
                    int s = workers.size();
                    // 记录最大线程数量，可参考用于查看线程复用效率。
                    if (s > largestPoolSize)
                        largestPoolSize = s;
                    workerAdded = true;
                }
            } finally {
                mainLock.unlock();
            }
            if (workerAdded) {
                // 启动工作线程
                t.start();
                workerStarted = true;
            }
        }
    } finally {
        if (! workerStarted)
            addWorkerFailed(w);
    }
    // 返回启动结果
    return workerStarted;
}
```

- 运行状态

如果线程池已关闭(HUTDOWN) -> 不接手新任务
或者当前的任务为空 -> 无效任务
或者当前workQueue为空 -> 直接加入workQueue等待线程复用

- Worker数量

CAPACITY 为`2^29 - 1`
(默认最大值，小于MAX_VALUE)
如果线程数大于CAPACITY
或者大于核心size(创建核心线程时)
或者大于最大线程数(创建普通线程时)

- 启动线程

创建Worker添加到workers队列，即工作线程队列。同时更新最大线程数量。最后调用线程的start方法，启动线程。

### # Worker

下面看看Worker是如何工作的。

```java
// ThreadPoolExecutor.java
private final class Worker
    extends AbstractQueuedSynchronizer
    implements Runnable
{
    ...
    final Thread thread;
    Runnable firstTask;
    volatile long completedTasks;
    Worker(Runnable firstTask) {
        setState(-1); // inhibit interrupts until runWorker
        this.firstTask = firstTask;
        // 使用线程池中的线程工厂创建新线程
        this.thread = getThreadFactory().newThread(this);
    }

    /** Delegates main run loop to outer runWorker. */
    public void run() {
        // 实现的run方法，调用runWork方法工作
        runWorker(this);
    }
    ...
}
```

Worker基于AQS，构造时会调用ThreadFactory创建新的线程并持有。

本身实现了Runnable对象，因此其具体工作逻辑在runWorker方法中。

### # runWorker

```java
// ThreadPoolExecutor.java
final void runWorker(Worker w) {
    Thread wt = Thread.currentThread();
    Runnable task = w.firstTask;
    w.firstTask = null;
    w.unlock(); // allow interrupts
    boolean completedAbruptly = true;
    try {
        // task的默认值为firstTask，为创建线程时入线程池的任务
        // firstTask并未加入到任务队列。
        // 如果task不存在，那么调用getTask()获取新任务
        while (task != null || (task = getTask()) != null) {
            w.lock();
            // 检查状态，这里逻辑比较绕。
            //
            // 1. 如果线程池已经STOP，则确保当前线程中断。
            //    这段逻辑清晰: 如果已STOP，且线程未中断则调用interrupt
            //
            // 2. 或者线程池没有STOP，那么确保线程不中断：
            // 2.1 `interrupted()`用于清除(取消)中断，并返回清除前状态。
            // 2.2 如果此时线程池未中断，不用关心清除前是否已中断，只管清除。
            // 2.3 如果清除前线程已中断，同时发现此时线程池也STOP了，
            //     此时重新判断中断状态并重新设定为中断。
            if ((runStateAtLeast(ctl.get(), STOP) ||
                 (Thread.interrupted() &&
                  runStateAtLeast(ctl.get(), STOP))) &&
                !wt.isInterrupted())
                wt.interrupt();
            try {
                beforeExecute(wt, task);
                Throwable thrown = null;
                try {
                    // 执行task，即execute中传入的runnable对象
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

- 获取任务

初次使用firstTask，如不存在在直接getTask获取阻塞任务队列的task

- 判断状态

检查状态，这里逻辑比较绕。

1.  如果线程池已经STOP，则确保当前线程中断。

> 这段逻辑清晰: 如果已STOP，且线程未中断则调用interrupt

2.  或者线程池没有STOP，那么确保线程不中断：

> 2.1 `interrupted()`用于清除(取消)中断，并返回清除前状态。
>
> 2.2 如果此时线程池未中断，不用关心清除前是否已中断，只管清除。
> >
> 2.3 如果清除前线程已中断，同时发现此时线程池也STOP了，
> 此时重新判断中断状态并重新设定为中断。

- 执行任务

Task由Runnable封装，调用其run方法。

### # getTask

```java
// ThreadPoolExecutor.java
private Runnable getTask() {
    boolean timedOut = false; // Did the last poll() time out?
    // 如果这里返回null，那么Worker将退出。
    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c);

        // 如果已STOP或者SHUTDOWN+任务列表为空，则返回null
        if (rs >= SHUTDOWN && (rs >= STOP || workQueue.isEmpty())) {
            decrementWorkerCount();
            return null;
        }

        int wc = workerCountOf(c);

        // 线程数量超过核心线程或者运行核心线程闲时超时退出，则标记为timed
        boolean timed = allowCoreThreadTimeOut || wc > corePoolSize;
        // 如果满足工作线程数量超过maximumPoolSize，
        // 同时满足工作线程数量超过1或者任务队列为空，则返回null。
        if ((wc > maximumPoolSize || (timed && timedOut))
            && (wc > 1 || workQueue.isEmpty())) {
            // 这里可能存在多线程竞争的情况：
            // 通过CAS方式，如果线程数量成功减一则退出当前线程。
            // 否则继续下一个循环。
            if (compareAndDecrementWorkerCount(c))
                return null;
            continue;
        }

        try {
            // 如果线程数量不超过核心线程数量，那么一直阻塞而不超时。
            // Worker本身并不区分到底是核心线程还是普通线程，
            // 只通过线程数量是否超核心线程数确定等待的任务是否应该超时
            // 如果超时，那么当前Worker就退出。
            Runnable r = timed ?
                workQueue.poll(keepAliveTime, TimeUnit.NANOSECONDS) :
                workQueue.take();
            if (r != null) return r;
            timedOut = true;
        } catch (InterruptedException retry) {
            timedOut = false;
        }
    }
}
```

getTask时，如果返回null则会导致Worker退出。

- 线程池退出逻辑

如果已STOP或者SHUTDOWN+任务列表为空，则返回null。也就是说：

如果线程池SHUTDOWN，并不会取消任务队列中的任务，线程池会一直运行到workQueue为空。

如果线程池状态为STOP，那么将抛弃任务队列。不过正常来说，STOP状态是要经过SHUTDOWN状态的。

注意：线程池为SHUTDOWN状态时，将不接收新任务。

- maxPoolSize逻辑

如果满足工作线程数量超过maximumPoolSize，同时满足工作线程数量超过1或者任务队列为空，则返回null。

也就说一切以maximumPoolSize为准，如果coreSize大于maximumPoolSize，最终也会导致核心线程退出。

- 从阻塞线程消费任务

如果线程数量不超过核心线程数量，那么一直阻塞而不超时。Worker本身并不区分到底是核心线程还是普通线程，只通过线程数量是否超核心线程数确定等待的任务是否应该超时如果超时，那么当前Worker就退出。

如果在这过程中，有新任务加入到workQueue，那么这里将会得到回应。


### # 总结

参数比较：

- coreSize表示核心线程数量。
- keepLiveTime则表示非核心线程获取任务超时时间，超时则退出。
- maximumSize表示当前存活总线程的数量，超过的线程将退出。
- workQueue用于缓存任务的阻塞队列。
- threadFactory用于线程池创建线程。
- handler用于处理拒绝任务。

线程池退出时，不接收新任务。线程池直到旧任务运行结束才会从SHUTDOWN变成STOP。
coreSize只用于添加核心线程池时用于判断，而线程是否存活则基于maximumSize，超过maximumSize的线程都会退出。换言之，maximumSize小于coreSize，那么添加任务时允许创建线程，而复用线程准备执行新任务时将退出。

## Executors

Java的线程池通常说的是ThreadPoolExecutor，而Executors则封装了多个实例化ThreadPoolExecutor的方法。如下：

### # newCachedThreadPool

```java
// Executors.java
public static ExecutorService newCachedThreadPool(ThreadFactory threadFactory) {
    return new ThreadPoolExecutor(0, Integer.MAX_VALUE,
                                  60L, TimeUnit.SECONDS,
                                  new SynchronousQueue<Runnable>(),
                                  threadFactory);
}
```

这里的CoreSize为0，线程存活时间为60秒，同时workQueue为`SynchronousQueue`。

SynchronousQueue是一个特殊队列，写入时如果没有读取再等待，则无法入列。也就是说线程池中所有线程都在工作时，新任务的加入一定会伴随着新工作线程的创建。

### # newFixedThreadPool

```java
// Executors.java
public static ExecutorService newFixedThreadPool(int nThreads, ThreadFactory threadFactory) {
    return new ThreadPoolExecutor(nThreads, nThreads,
                                  0L, TimeUnit.MILLISECONDS,
                                  new LinkedBlockingQueue<Runnable>(),
                                  threadFactory);
}
```

CoreSize和maximumSize相同，然后workQueue为LinkedBlockingQueue。

LinkedBlockingQueue默认的capacity为Integer.MAX_VALUE，也可以手动设置容量。

`newFixedThreadPool`这里capacity为默认值，也就说这个队列理论上可以一直往里面加入任务。

### # newScheduledThreadPool

```java
// Executors.java
public static ScheduledExecutorService newScheduledThreadPool(
        int corePoolSize, ThreadFactory threadFactory) {
    return new ScheduledThreadPoolExecutor(corePoolSize, threadFactory);
}

// ScheduledExecutorService.java
public ScheduledThreadPoolExecutor(int corePoolSize,
                                   ThreadFactory threadFactory) {
    super(corePoolSize, Integer.MAX_VALUE,
          DEFAULT_KEEPALIVE_MILLIS, MILLISECONDS,
          new DelayedWorkQueue(), threadFactory);
}
```

顾名思义，这时一个运行定时运行任务的线程池。

同普通线程池不同的地方在于，如果是一个定时任务，那么在任务结束之后，会重新加入任务队列。

并且，它使用了一个不同的Queue，叫做`DelayedWorkQueue`。在吐出任务的时候，会获取任务的delay时间。如果大于0 ，那么就先阻塞超时之后返回当前任务。如果delay时间小于等于0，则直接返回。

具体逻辑见 `DelayedWorkQueue` 和 `ScheduledFutureTask` 。

### # newSingleThreadExecutor

```java
// Executors.java
public static ExecutorService newSingleThreadExecutor(ThreadFactory threadFactory) {
    return new FinalizableDelegatedExecutorService
        (new ThreadPoolExecutor(1, 1,
                                0L, TimeUnit.MILLISECONDS,
                                new LinkedBlockingQueue<Runnable>(),
                                threadFactory));
}
```

单线程线程池，类似于上面的fixedThreadPool，区别在于这里只有一个线程。

## workQueue

下面列出常见的两种线程池队列。

### # SynchronousQueue

SynchronousQueue“本身”是一个无任何容量的队列，其内部无任何容器。

但这并不表明不可以用它存取数据。虽然它本身无任何容器，但是它内部有个Transfer，用来处理所有的实现。同时这个Transfer是实现类存在容器。

```java
// SynchronousQueue.java
public SynchronousQueue(boolean fair) {
    transferer = fair ? new TransferQueue<E>() : new TransferStack<E>();
}
```

Transfer有两个子类，一个是TransferQueue，一个是TransferStack。前者内部有一个链表，而后者有一个堆栈。

前者为FIFO，后者为LIFO。因此前者为公平模式(即先进先出)，后者为非公平模式(即后来者插队进入，很可能导致先来者永远不能执行)。

SynchronousQueue是生产者消费者模式，正常情况下每一个put成功都需要有一个take在等待，反之亦然。也就是说，如果生产的时候没有消费行为那么也是会阻塞知道有消费。

#### - 生产和消费

下面来看看，线程池中所使用到的offer和take/poll函数。

```java
// SynchronousQueue.java
public boolean offer(E e) {
    if (e == null) throw new NullPointerException();
    return transferer.transfer(e, true, 0) != null;
}

public void put(E e) throws InterruptedException {
    if (e == null) throw new NullPointerException();
    if (transferer.transfer(e, false, 0) == null) {
        Thread.interrupted();
        throw new InterruptedException();
    }
}
```

可以看到offer和put的区别，在于是否超时。

offer方法，超时时间为0，也就说offer函数本身并不会产生阻塞。

put，则会阻塞当前线程。

```java
// SynchronousQueue.java
public E take() throws InterruptedException {
    E e = transferer.transfer(null, false, 0);
    if (e != null)
        return e;
    Thread.interrupted();
    throw new InterruptedException();
}
public E poll(long timeout, TimeUnit unit) throws InterruptedException {
    E e = transferer.transfer(null, true, unit.toNanos(timeout));
    if (e != null || !Thread.interrupted())
        return e;
    throw new InterruptedException();
}
```

take方法，则并不是超时阻塞。但是与上面不同的地方在于，第一个参数为null。

poll方法，为超时阻塞，超时时间为`keepAliveTime`，即worker闲下来超过`keepAliveTime`则被释放。

Transfer中是通过第一个参数是否为null来判断是否isData。是否isData，则意味着当前队列是生产任务还是消费任务。

下面以公平模式为例：

#### - TransferQueue

上面提到的基类`Transferer`是一个只有一个transfer方法的基类：

```java
// SynchronousQueue.java
abstract static class Transferer<E> {
    /**
     * Performs a put or take.
     *
     * @param e if non-null, the item to be handed to a consumer;
     *          if null, requests that transfer return an item
     *          offered by producer.
     * @param timed if this operation should timeout
     * @param nanos the timeout, in nanoseconds
     * @return if non-null, the item provided or received; if null,
     *         the operation failed due to timeout or interrupt --
     *         the caller can distinguish which of these occurred
     *         by checking Thread.interrupted.
     */
    abstract E transfer(E e, boolean timed, long nanos);
}
```

子类只需要实现transfer方法即可，下面是TransferQueue的实现：

```java
// SynchronousQueue$TransferQueue.java
E transfer(E e, boolean timed, long nanos) {
    QNode s = null; // constructed/reused as needed
    boolean isData = (e != null);

    for (;;) {
        QNode t = tail;
        QNode h = head;
        if (t == null || h == null)         // saw uninitialized value
            continue;                       // spin
        // 这里可能比较难懂：
        // head等于tail，表示目前链表中无数据。
        // 而isData同t.isData表示，新的操作同旧操作一样。
        // 比如，之前是put，现在也是put，那么就直接往链表添加数据。
        // 否则读取数据。比如先PUT现在TAKE，或者先TAKE现在PUT，唤起阻塞。
        if (h == t || t.isData == isData) {
            // 这个block是写入(生产)行为
            QNode tn = t.next;
            if (t != tail)                  // inconsistent read
                continue;
            if (tn != null) {               // lagging tail
                advanceTail(t, tn);
                continue;
            }
            // 如果超时，但是超时时间不大于0 ，则不阻塞。
            // offer函数，就是这个情况。也就是说线程池入队是不阻塞的。
            if (timed && nanos <= 0L) return null;
            if (s == null) s = new QNode(e, isData);
            // tail的next设定为S
            if (!t.casNext(null, s)) continue;
            // CAS方式将S设定为tail。此时tail为S。
            advanceTail(t, s);
            // 阻塞并返回s数值，如返回的是它自己
            // 则这个任务因为超时被cancel了。
            Object x = awaitFulfill(s, e, timed, nanos);
            if (x == s) {
                // 将s从链表清除。并返回null
                clean(t, s);
                return null;
            }
            // offList表示cancel，比如超时等。
            if (!s.isOffList()) {
                // 如果此时head等于tail，则将s也设定为head
                // 这种情况下head和tail都设定为s。
                advanceHead(t, s);
                // 则将QNode的item设定为其本身，标记为CANCEL
                if (x != null)              // and forget fields
                    s.item = s;
                // 清除线程
                s.waiter = null;
            }
            return (x != null) ? (E)x : e;

        } else {
            // 这个block是读取(消费)行为                         // complementary-mode
            QNode m = h.next;               // node to fulfill
            // t不等于tail或者h不等于head或者head.next为null
            // 均表示数据发生变化，则继续自。
            if (t != tail || m == null || h != head)
                continue;                   // inconsistent read

            Object x = m.item;
            // 当前为数据类型，并且Qnode中的数据也是数据类型。
            // 因为这都是写入行为，则继续自旋
            if (isData == (x != null) ||
                // `awaitFulfill`函数中cancel时，将item设定为自己。
                x == m ||
                // CAS失败，比如别人捷足先登。
                // 否则将QNode的item数据设定为e，即当前操作的数据。
                // 如：put/offer则是待入列数据; take时为null表消费。
                !m.casItem(x, e)) {
                // 将head往后移动
                advanceHead(h, m);
                continue;
            }
            // 将head往后移动
            advanceHead(h, m);
            // 唤起阻塞，即将获得锁的线程唤起。
            // 而waiter就是阻塞方对应的锁，由`awaitFulfill`设定。
            LockSupport.unpark(m.waiter);
            return (x != null) ? (E)x : e;
        }
    }
}
```

下面来看看`阻塞`是如何处理的：

```java
// SynchronousQueue$TransferQueue.java
Object awaitFulfill(QNode s, E e, boolean timed, long nanos) {
    /* Same idea as TransferStack.awaitFulfill */
    // deadline, 当前时间加上timeout
    final long deadline = timed ? System.nanoTime() + nanos : 0L;
    // 当前线程。
    Thread w = Thread.currentThread();
    // 适应性自旋的次数。只有s是第一个对象，才会自旋。
    // 自旋次数同是否设定超时有关。超时则使用MAX_TIMED_SPINS。
    // MAX_TIMED_SPINS为多核心时，32倍核心数。单核为0。
    // MAX_UNTIMED_SPINS为MAX_TIMED_SPINS的16倍。
    int spins = (head.next == s)
        ? (timed ? MAX_TIMED_SPINS : MAX_UNTIMED_SPINS)
        : 0;
    // 开始自旋或者阻塞
    for (;;) {
        if (w.isInterrupted())
            s.tryCancel(e);
        // item为volatile标记
        Object x = s.item;
        // 如果数值改变，则认为有成对操作出现。
        // 比如当前是put，那么e为真实数据，等待take执行
        // 从可知take拿到item后，将item设为null。此时item数值由e变为null。
        // 反之，先take后put也是一样，即由null变为真实数据。
        if (x != e)
            return x;
        if (timed) {
            // 如果设定为超时，但是已经超过超时时间
            // 那么就结束当前QNode
            nanos = deadline - System.nanoTime();
            if (nanos <= 0L) {
                s.tryCancel(e);
                continue;
            }
        }
        // 如果自旋次数还有剩余，则继续自旋。
        if (spins > 0)
            --spins;
        // 给QNode设定阻塞线程。
        else if (s.waiter == null)
            s.waiter = w;
        // 阻塞当前线程
        else if (!timed)
            LockSupport.park(this);
        // 超时阻塞当前线程
        else if (nanos > SPIN_FOR_TIMEOUT_THRESHOLD)
            LockSupport.parkNanos(this, nanos);
    }
}
```

可以看到SynchronousQueue会先自旋一定次数之后才会阻塞。也就是，说这里它是阻塞，其实只说对了一半。因为它先执行了适应性自旋之后才会阻塞，下面统称为“阻塞”。

可以得出`Fulfill`过程其实就是等待当前QNode被读取的过程，这个读取说的是相对于TransferQueue而言，而非SynchronousQueue来说的。比如，先执行了put，那么后面的take叫读取；反过来，如果先take，那么后将等待一个put行为，读取当前的TransferQueue的QNode。

如果TransferQueue无数据，可分为下面情况：

- 先take

则插入链表新的QNode中的数据即item为`null`，并“阻塞”当前线程。之后等待put将Node填充数据并返回同时唤起线程。如果继续take，则继续在链表插入新的QNode。

- 先put

则插入链表新的QNode中的数据即item为`真实数据`，并“阻塞”当前线程。等待take行为，take之后QNode的数据为null，这样就产生了变化。如果继续put，则继续在链表插入新的QNode。

### # LinkedBlockingQueue

`LinkedBlockingQueue`的写入和读取操作是两把可重入锁，分别为putLock和takeLock。

同时，队列满或者空的时候，也对应着分别由putLock和takeLock创建的两个Condition，用于阻塞操作。

`LinkedBlockingQueue`是不允许插入空数据的，否则抛出NPE。

#### - 写入

```java
// LinkedBlockingQueue.java
public void put(E e) throws InterruptedException {
    if (e == null) throw new NullPointerException();
    int c = -1;
    Node<E> node = new Node<E>(e);
    final ReentrantLock putLock = this.putLock;
    final AtomicInteger count = this.count;
    // 写入锁，
    putLock.lockInterruptibly();
    try {
        // 如果队列达到容量上限，那么阻塞。
        while (count.get() == capacity) {
            notFull.await();
        }
        // 加入队列尾部
        enqueue(node);
        // 队列长度加一
        c = count.getAndIncrement();
        // 注意，这里的c是加一之前的数量
        // 如果未超过容量，则通知写操作释放阻塞
        if (c + 1 < capacity)
            notFull.signal();
    } finally {
        // 释放写入锁
        putLock.unlock();
    }
    // 发送队列不为空的消息，通知读操作释放阻塞(notEmpty)
    if (c == 0)
        signalNotEmpty();
}

public boolean offer(E e) {
    if (e == null) throw new NullPointerException();
    final AtomicInteger count = this.count;
    // 如果容量满了，那么将直接返回入列失败，无需阻塞。
    if (count.get() == capacity)
        return false;
    int c = -1;
    Node<E> node = new Node<E>(e);
    final ReentrantLock putLock = this.putLock;
    putLock.lock();
    try {
        // 如果容量满足，则加入队列。
        if (count.get() < capacity) {
            enqueue(node);
            // 更新数量
            c = count.getAndIncrement();
            if (c + 1 < capacity)
                notFull.signal();
        }
    } finally {
        putLock.unlock();
    }
    // 通知读操作释放阻塞(notEmpty)
    if (c == 0)
        signalNotEmpty();
    return c >= 0;
}
```

写入的前后，上了一把写入的锁，完成之后释放锁。

如果发现当前容量已超过capacity，则会阻塞直到有消息被读取。其中，capacity默认为Integer.MAX_VALUE。原则上在移动客户端，这个容量可能永远都不会达到上限。

加入队列之后，会在锁内通知notFull其他写操作进行释放，在锁外释放notEmpty通知释放读取锁。

#### - 读取

```java
public E take() throws InterruptedException {
    E x;
    int c = -1;
    final AtomicInteger count = this.count;
    // 这是一个可重入锁
    final ReentrantLock takeLock = this.takeLock;
    // 上锁
    takeLock.lockInterruptibly();
    try {
        while (count.get() == 0) {
            // 如果队列中无数据，那么将一直阻塞
            notEmpty.await();
        }
        // 从队列头部移除一个任务并返回
        x = dequeue();
        // 更新任务数量
        c = count.getAndDecrement();
        if (c > 1)
            notEmpty.signal();
    } finally {
    // 释放锁
        takeLock.unlock();
    }
    // 这里c表示的是出队之前的数量，
    // 也就是说目前的容量，必然是小于capacity了。
    // 则告知写入端容量未满，释放锁执行写入动作。
    if (c == capacity)
        // 通知notFull进行释放
        signalNotFull();
    return x;
}

public E poll(long timeout, TimeUnit unit) throws InterruptedException {
    E x = null;
    int c = -1;
    long nanos = unit.toNanos(timeout);
    final AtomicInteger count = this.count;
    final ReentrantLock takeLock = this.takeLock;
    takeLock.lockInterruptibly();
    try {
        while (count.get() == 0) {
        // poll同take差不多，只不过这里多了超时的逻辑
            if (nanos <= 0L)
                return null;
            nanos = notEmpty.awaitNanos(nanos);
        }
        x = dequeue();
        c = count.getAndDecrement();
        if (c > 1)
            notEmpty.signal();
    } finally {
        takeLock.unlock();
    }
    if (c == capacity)
        signalNotFull();
    return x;
}
```

读取同写入类似，在操作前获取takeLock，完成后释放。

如果当前队列中无数据，那么将会进行阻塞。当有新数据写入成功并通过notEmpty通知当前进行释放。

## 总结

往线程池的workQueue添加数据的时候，不会产生阻塞。而读取任务时，如果是核心线程，则将会一直阻塞下去；普通线程则会在超过keepAlive后还没有获取新任务，那么这个线程将会退出。

线程池中并不存在核心线程和普通线程的区别，只会按照getTask时当前的线程数量来确定。如果当前的Worker数量超过CoreSize则所有Worker在getTask的时候都有超时阻塞。只要超时并且超过核心线程数，同时线程数量大于1或者workQueue为空，那么这个线程将会退出。同时，如果线程数量超过maximumSize则也会将线程直接退出。这种情况发生在coreSize大于maximumSize的时候。

线程退出的条件为：

1. 线程数量超过maximumSize，或者超过coreSize同时poll已超时。

2. 线程数量大于1，或者workQueue为空。
