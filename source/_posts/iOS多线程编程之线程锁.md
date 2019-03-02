---
title: iOS多线程编程之线程锁
date: 2017-02-24 18:04:15
tags: [iOS线程锁, 多线程]
categories: 多线程
---

# 何所谓线程安全

线程安全就是在多线程访问的同时，采用用了加锁机制，当一个线程访问该线程外的某个数据时，进行保护，其他线程不能进行访问，直到该线程读取完毕，其他线程才可以访问。保护线程安全无在乎就是对线程进行加锁。

在iOS开发中常用的加锁方式有以下几种：

<!-- more -->

# NSLock

在iOS程序中NSLock中实现了一个简单的互斥锁，实现了NSLocking协议，

lock为加锁，

unlock为解锁，

tryLock为尝试加锁，如果加锁失败则不会阻塞线程，只会立即回调，需要注意的是，使用tryLock并不能加锁成功 ，如果获取锁失败，则不会执行加锁。

NOLockBforeDate:在指定的date之前暂时阻塞线程（如果没有获取锁），如果在指定的时间仍然没有获取到🔐的话。线程会被立即唤醒，函数立即返回NO。

```
- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queueA = dispatch_queue_create("queueA", nil);
    dispatch_queue_t queueB = dispatch_queue_create("queueB", nil);
    dispatch_group_async(group, queueA, ^{
        [weakSelf getWithArray:weakSelf.array];
        NSLog(@"%@线程A",weakSelf.array);
    });
    dispatch_group_async(group, queueB, ^{
        [weakSelf getWithArray:weakSelf.array];
        NSLog(@"%@线程B",weakSelf.array);
    });
    NSLog(@"%@主线程",weakSelf.array);
}

- (void)getWithArray:(NSMutableArray *)array {
    [self.lock lock];
    if (array.count > 0) {
        NSLog(@"%@...objc",array.lastObject);
        [array removeLastObject];
    }
    [self.lock unlock];
}
```

不加锁的打印：可看出线程A和线程B同时操作了getWithArray:\(NSMutableArray \*\)array，由于资源抢占，导致了数组越界而崩溃

```
2016-07-22 22:18:55.695827+0800 ThreadLock[10764:315922] 4444...objc
2016-07-22 22:18:55.695827+0800 ThreadLock[10764:315923] 4444...objc
2016-07-22 22:18:55.695892+0800 ThreadLock[10764:315824] (
    1111,
    2222,
    3333,
    4444
)主线程
2016-07-22 22:18:55.696036+0800 ThreadLock[10764:315922] (
    1111,
    2222,
    3333
)线程A
2016-07-22 22:18:55.697056+0800 ThreadLock[10764:315923] *** Terminating app due to uncaught exception 'NSRangeException', reason: '*** -[__NSArrayM removeObjectsInRange:]: range {3, 1} extends beyond bounds [0 .. 2]'
```

加锁打印：加锁后，线程A先跑，跑的过程中由于线程加锁，线程B无法访问getWithArray:\(NSMutableArray \*\)array，线程A结束之后，线程B发现array中只剩下3个元素，所以把最后一个元素3333给remove掉了，从而达到了线程运行的安全。

```
2016-07-22 22:10:40.114063+0800 ThreadLock[10425:305487] 4444...objc
2016-07-22 22:10:40.113988+0800 ThreadLock[10425:305421] (
    1111,
    2222,
    3333,
    4444
)主线程
2016-07-22 22:10:40.117108+0800 ThreadLock[10425:305487] (
    1111,
    2222,
    3333
)线程A
2016-07-22 22:10:40.117076+0800 ThreadLock[10425:305486] 3333...objc
2016-07-22 22:10:40.117703+0800 ThreadLock[10425:305486] (
    1111,
    2222
)线程B
```

# @synchronized

@synchronized在早期接触的iOS开发中经常接触，尤其是在创建单利模式的时候。

代码以及打印如下：

```
- (void)getWithArray:(NSMutableArray *)array {
    @synchronized (self) {
        if (array.count > 0) {
            NSLog(@"%@...objc",array.lastObject);
            [array removeLastObject];
        }
    }
}
```

```
2016-07-22 22:20:33.083045+0800 ThreadLock[10837:317900] 4444...objc
2016-07-22 22:20:33.083278+0800 ThreadLock[10837:317693] (
    1111,
    2222,
    3333,
    4444
)主线程
2016-07-22 22:20:33.083437+0800 ThreadLock[10837:317900] (
    1111,
    2222,
    3333
)线程A
2016-07-22 22:20:33.083438+0800 ThreadLock[10837:317899] 3333...objc
2016-07-22 22:20:33.083814+0800 ThreadLock[10837:317899] (
    1111,
    2222
)线程B
```

---

# 条件信号量dispatch\_semaphore\_t

条件信号量详细用法见上一遍，GCD的用法

---

# dispatch\_barrier\_async/dispatch\_barrier\_sync

详细用法见上一遍，GCD的用法，但有一点值得注意的是：

> 如果在当前线程调用dispatch\_barrier\_sync阻塞线程会发生死锁

---

# NSCondition

NSCondition同样实现了NSLocking协议，所以它和NSLock一样，也有NSLocking协议的lock和unlock方法，可以当做NSLock来使用解决线程同步问题，用法完全一样。

```
- (void)getWithArray:(NSMutableArray *)array {
    [self.lock lock];
    if (array.count > 0) {
        NSLog(@"%@...objc",array.lastObject);
        [array removeLastObject];
    }
    [self.lock unlock];
}
```

同时，NSCondition提供更高级的用法。wait和signal，和条件信号量类似。

比如我们要监听imageNames数组的个数，当imageNames的个数大于0的时候就执行清空操作。思路是这样的，当imageNames个数大于0时执行清空操作，否则，wait等待执行清空操作。当imageNames个数增加的时候发生signal信号，让等待的线程唤醒继续执行。

NSCondition和NSLock、@synchronized等是不同的是，NSCondition可以给每个线程分别加锁，加锁后不影响其他线程进入临界区。这是非常强大。但是正是因为这种分别加锁的方式，NSCondition使用wait并使用加锁后并不能真正的解决资源的竞争。比如我们有个需求：不能让m&lt;0。假设当前m=0,线程A要判断到m&gt;0为假,执行等待；线程B执行了m=1操作，并唤醒线程A执行m-1操作的同时线程C判断到m&gt;0，因为他们在不同的线程锁里面，同样判断为真也执行了m-1，这个时候线程A和线程C都会执行m-1,但是m=1，结果就会造成m=-1.

当我用数组做删除试验时，做增删操作并不是每次都会出现，大概3-4次后会出现。单纯的使用lock、unlock是没有问题的。

---

# 条件锁NSConditionLock

也有人说这是个互斥锁。NSConditionLock同样实现了NSLocking协议，试验过程中发现性能很低。

```
- (void)getIamgeName:(NSMutableArray *)imageNames{
    NSString *imageName;
    [lock lock];
    if (imageNames.count>0) {
        imageName = [imageNames lastObject];
        [imageNames removeObject:imageName];
    }
    [lock unlock];
}
```

NSConditionLock也可以像NSCondition一样做多线程之间的任务等待调用，而且是线程安全的。

```
- (void)getIamgeName:(NSMutableArray *)imageNames{
    NSString *imageName;
    [lock lockWhenCondition:1];    //加锁
    if (imageNames.count>0) {
        imageName = [imageNames lastObject];
        [imageNames removeObjectAtIndex:0];
    }
    [lock unlockWithCondition:0];     //解锁
}
- (void)createImageName:(NSMutableArray *)imageNames{
    [lock lockWhenCondition:0];
    [imageNames addObject:@"0"];
    [lock unlockWithCondition:1];
}

#pragma mark - 多线程取出图片后删除
- (void)getImageNameWithMultiThread{
    NSMutableArray *imageNames = [[NSMutableArray alloc]init];
    dispatch_group_t dispatchGroup = dispatch_group_create();
    __block double then, now;
    then = CFAbsoluteTimeGetCurrent();
    for (int i=0; i<10000; i++) {
        dispatch_group_async(dispatchGroup, self.synchronizationQueue, ^(){
            [self getIamgeName:imageNames];
        });
        dispatch_group_async(dispatchGroup, self.synchronizationQueue, ^(){
            [self createImageName:imageNames];
        });
    }
    dispatch_group_notify(dispatchGroup, self.synchronizationQueue, ^(){
        now = CFAbsoluteTimeGetCurrent();
        printf("thread_lock: %f sec\nimageNames count: %ld\n", now-then,imageNames.count);
    });
}
```

---

# 递归锁NSRecursiveLock

有时候“加锁代码”中存在递归调用，**递归开始前加锁，递归调用开始后会重复执行此方法以至于反复执行加锁代码最终造成死锁，这个时候可以使用递归锁来解决。使用递归锁可以在一个线程中反复获取锁而不造成死锁，这个过程中会记录获取锁和释放锁的次数，只有最后两者平衡锁才被最终释放。**

```
- (void)getIamgeName:(NSMutableArray *)imageNames{
    NSString *imageName;
    [lock lock];
    if (imageNames.count>0) {
        imageName = [imageNames firstObject];
        [imageNames removeObjectAtIndex:0];
        [self getIamgeName:imageNames];
    }
    [lock unlock];
}
- (void)getImageNameWithMultiThread{
    NSMutableArray *imageNames = [NSMutableArray new];
    int count = 1024*10;
    for (int i=0; i<count; i++) {
        [imageNames addObject:[NSString stringWithFormat:@"%d",i]];
    }
    dispatch_group_t dispatchGroup = dispatch_group_create();
    __block double then, now;
    then = CFAbsoluteTimeGetCurrent();
    dispatch_group_async(dispatchGroup, self.synchronizationQueue, ^(){
        [self getIamgeName:imageNames];
    });
    dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^(){
        now = CFAbsoluteTimeGetCurrent();
        printf("thread_lock: %f sec\nimageNames count: %ld\n", now-then,imageNames.count);
    });

}
```

---

# NSDistributedLock

NSDistributedLock是MAC开发中的跨进程的分布式锁，底层是用文件系统实现的互斥锁。NSDistributedLock没有实现NSLocking协议，所以没有lock方法，取而代之的是非阻塞的tryLock方法。

```
NSDistributedLock *lock = [[NSDistributedLock alloc] initWithPath:@"/Users/mac/Desktop/lock.lock"];
    while (![lock tryLock])
    {
        sleep(1);
    }

    //do something
    [lock unlock];
```

当执行到do something时程序退出,程序再次启动之后tryLock就再也不能成功了,陷入死锁状态.其他应用也不能访问受保护的共享资源。在这种情况下，你可以使用breadLock方法来打破现存的锁以便你可以获取它。但是通常应该避免打破锁，除非你确定拥有进程已经死亡并不可能再释放该锁。

因为是MAC下的线程锁，所以demo里面没有，这里也不做过多关注。

---

# 互斥锁POSIX

POSIX和dispatch\_semaphore\_t很像，但是完全不同。POSIX是Unix/Linux平台上提供的一套条件互斥锁的API。

新建一个简单的POSIX互斥锁，引入头文件`#import <pthread.h>`声明并初始化一个pthread\_mutex\_t的结构。使用pthread\_mutex\_lock和pthread\_mutex\_unlock函数。调用pthread\_mutex\_destroy来释放该锁的数据结构。

```
#import <pthread.h>
@interface MYPOSIXViewController ()
{
    pthread_mutex_t mutex;  //声明pthread_mutex_t的结构
}
@end

@implementation MYPOSIXViewController
- (void)dealloc{
    pthread_mutex_destroy(&mutex);  //释放该锁的数据结构
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    pthread_mutex_init(&mutex, NULL);
    /**
     *  初始化
     *
     */
}

- (void)getIamgeName:(NSMutableArray *)imageNames{
    NSString *imageName;
    /**
     *  加锁
     */
    pthread_mutex_lock(&mutex);
    if (imageNames.count>0) {
        imageName = [imageNames firstObject];
        [imageNames removeObjectAtIndex:0];
    }
    /**
     *  解锁
     */
    pthread_mutex_unlock(&mutex);
}
```

POSIX还可以创建条件锁，提供了和NSCondition一样的条件控制，初始化互斥锁同时使用pthread\_cond\_init来初始化条件数据结构，

```
// 初始化
    int pthread_cond_init (pthread_cond_t *cond, pthread_condattr_t *attr);

    // 等待（会阻塞）
    int pthread_cond_wait (pthread_cond_t *cond, pthread_mutex_t *mut);

    // 定时等待
    int pthread_cond_timedwait (pthread_cond_t *cond, pthread_mutex_t *mut, const struct timespec *abstime);

    // 唤醒
    int pthread_cond_signal (pthread_cond_t *cond);

    // 广播唤醒
    int pthread_cond_broadcast (pthread_cond_t *cond);

    // 销毁
    int pthread_cond_destroy (pthread_cond_t *cond);
```

POSIX还提供了很多函数，有一套完整的API，包含Pthreads线程的创建控制等等，非常底层，可以手动处理线程的各个状态的转换即管理生命周期，甚至可以实现一套自己的多线程，感兴趣的可以继续深入了解。推荐一篇详细文章，但不是基于iOS的，是基于Linux的，但是介绍的非常详细 [Linux 线程锁详解](http://blog.chinaunix.net/uid-26885237-id-3207962.html)

---

# 自旋锁OSSpinLock

首先要提的是OSSpinLock已经出现了BUG，导致并不能完全保证是线程安全的。

> 新版 iOS 中，系统维护了 5 个不同的线程优先级/QoS: background，utility，default，user-initiated，user-interactive。高优先级线程始终会在低优先级线程前执行，一个线程不会受到比它更低优先级线程的干扰。这种线程调度算法会产生潜在的优先级反转问题，从而破坏了 spin lock。
>
> 具体来说，如果一个低优先级的线程获得锁并访问共享资源，这时一个高优先级的线程也尝试获得这个锁，它会处于 spin lock 的忙等状态从而占用大量 CPU。此时低优先级线程无法与高优先级线程争夺 CPU 时间，从而导致任务迟迟完不成、无法释放 lock。这并不只是理论上的问题，libobjc 已经遇到了很多次这个问题了，于是苹果的工程师停用了 OSSpinLock。

> 苹果工程师 Greg Parker 提到，对于这个问题，一种解决方案是用 truly unbounded backoff 算法，这能避免 livelock 问题，但如果系统负载高时，它仍有可能将高优先级的线程阻塞数十秒之久；另一种方案是使用 handoff lock 算法，这也是 libobjc 目前正在使用的。锁的持有者会把线程 ID 保存到锁内部，锁的等待者会临时贡献出它的优先级来避免优先级反转的问题。理论上这种模式会在比较复杂的多锁条件下产生问题，但实践上目前还一切都好。

> OSSpinLock 自旋锁，性能最高的锁。原理很简单，就是一直 do while 忙等。它的缺点是当等待时会消耗大量 CPU 资源，所以它不适用于较长时间的任务。对于内存缓存的存取来说，它非常合适。
>
> -摘自[ibireme](http://blog.ibireme.com/author/ibireme/)

```
<libkern/OSAtomic.h>

#import <libkern/OSAtomic.h>
@interface MYOSSpinLockViewController ()
{
    OSSpinLock spinlock;  //声明pthread_mutex_t的结构
}
@end

@implementation MYOSSpinLockViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    spinlock = OS_SPINLOCK_INIT;
    /**
     *  初始化
     *
     */
}

- (void)getIamgeName:(NSMutableArray *)imageNames{
    NSString *imageName;
    /**
     *  加锁
     */
    OSSpinLockLock(&spinlock);
    if (imageNames.count>0) {
        imageName = [imageNames firstObject];
        [imageNames removeObjectAtIndex:0];
    }
    /**
     *  解锁
     */
    OSSpinLockUnlock(&spinlock);
}
@end
```

---

# 总结

**@synchronized：适用线程不多，任务量不大的多线程加锁；**

**NSLock：其实NSLock并没有想象中的那么差，不知道大家为什么不推荐使用；**

**dispatch\_semaphore\_t：使用信号来做加锁，性能提升显著；**

**NSCondition：使用其做多线程之间的通信调用不是线程安全的；**

**NSConditionLock：单纯加锁性能非常低，比NSLock低很多，但是可以用来做多线程处理不同任务的通信调用；**

**NSRecursiveLock：递归锁的性能出奇的高，但是只能作为递归使用,所以限制了使用场景；**

**NSDistributedLock：因为是MAC开发的，就不讨论了；**

**POSIX\(pthread\_mutex\)：底层的api，复杂的多线程处理建议使用，并且可以封装自己的多线程；**

**OSSpinLock：性能也非常高，可惜出现了线程问题；**

**dispatch\_barrier\_async/dispatch\_barrier\_sync：测试中发现dispatch\_barrier\_sync比dispatch\_barrier\_async性能要高，真是大出意外。**

