---
title: 如何利用RunLoop的知识来监测APP卡顿?
date: 2019-09-11 17:50:48
tags: [RunLoop]
top: 0
need_not_copyright: true
categories: RunLoop
banner_img:
---

卡顿问题，就是在主线程上无法响应用户交互的问题。如果一个 App 时不时地就给你卡一下，有时还长时间无响应，这时你还愿意继续用它吗？所以说，卡顿问题对 App 的伤害是巨大的

## <!-- more -->

## 前言

用runloop来监测卡顿其实并不是什么比较前沿的技术，也不算什么新奇的技术，实际上开发者也用的比较少。一来，应为 `XCode` 的`instrument`足够的优秀，几乎所有的监控操作都有对应的工具。二来，大多数项目上都是集成第三方的统计工具，比如Bugly、友盟之类的等等。但是这样也暴露了一些问题，集成第三方会担心自己的APP信息泄露，那怎么办呢？所以这套自己通过runloop的检测也就营运而生。

## 卡顿可能产生的原因

一般来讲卡顿产生的原因可以大致分为以下几种类型：

1、复杂 UI 、图文混排的绘制量过大；

2、在主线程上做网络同步请求；

4、在主线程做大量的 IO 操作；

4、运算量过大，CPU 持续高占用；死锁和主子线程抢锁

那么问题来了，我们如何来做卡顿的监测呢？只是单纯的检测FPS的波动吗？FPS又是什么呢？维基百科显示FPS，即每秒显示帧数 或者 每秒显示张数 - [影格率](https://zh.wikipedia.org/wiki/帧率)测量单位（这里牵扯到CPU和GPU同步的问题，相关只是点就不在陈述了）。也就是说简单地通过监视 FPS 是很难确定是否会出现卡顿，所以FPS是不能作为用来检测卡顿的标准的。那我们应该通过什么来监测卡顿呢？

## 关于RunLoop

对于iOS开发人员来说，runloop相信大家一定不会陌生，因为他是在日常开发中的一个基础概念，我们都知道，线程的消息事件是依赖于 RunLoop 的，所以从 RunLoop 入手，就可以知道主线程上都调用了哪些方法。我们通过监听 RunLoop 的状态，就能够发现调用方法是否执行时间过长，从而判断出是否会出现卡顿。

当然，如果你要在RunLoop中监测哪些方法的运行时间过长，首先你必须得清楚RunLoop的运行原理，知道了运行原理之后才能知道我们要在RunLoop的哪个环节进行监测。

### 第一步：通知Observers：即将进入RunLoop

我们在[CFRunLoop-1153.18](http://opensource.apple.com/tarballs/CF/CF-1153.18.tar.gz)的源码的第2676行中的`CFRunLoopRun(void)`中，开启一个`do..while`循环来保活

```objective-c
void CFRunLoopRun(void) {	/* DOES CALLOUT */
    int32_t result;
    do {
        result = CFRunLoopRunSpecific(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 1.0e10, false);
        CHECK_FOR_FORK();
    } while (kCFRunLoopRunStopped != result && kCFRunLoopRunFinished != result);
}
```

那我们的重点就在`CFRunLoopRunSpecific`这个方法内部是如何实现的了，我们接下来往下看。`CFRunLoopRunSpecific`是`runloop`的启动入口

```objective-c
//即将进入runloop
if (currentMode->_observerMask & kCFRunLoopEntry ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopEntry);
result = __CFRunLoopRun(rl, currentMode, seconds, returnAfterSourceHandled, previousMode);
if (currentMode->_observerMask & kCFRunLoopExit ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopExit);
```

### 第二步：通知Observers：即将处理Timers和即将处理Sources和blocks

触发times、source0

```objective-c
__CFRunLoopUnsetIgnoreWakeUps(rl);
if (rlm->_observerMask & kCFRunLoopBeforeTimers) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeTimers);//即将处理Timers
if (rlm->_observerMask & kCFRunLoopBeforeSources) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeSources);//即将处理Sources
__CFRunLoopDoBlocks(rl, rlm);//处理blocks
```

### 第三步：处理 Source0 

到了这一步可能会再次处理一遍blocks

如果有 Source1 是 ready 状态的话，就会跳转到 handle_msg 去处理消息。代码如下：

```objective-c
 Boolean sourceHandledThisLoop = __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
    if (sourceHandledThisLoop) {
    __CFRunLoopDoBlocks(rl, rlm);
}
    Boolean poll = sourceHandledThisLoop || (0ULL == timeout_context->termTSR);

    if (MACH_PORT_NULL != dispatchPort && !didDispatchPortLastTime) {
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
       msg = (mach_msg_header_t *)msg_buffer;
      //MachPort处于等待中，runloop则会去处理handle_msg
       if (__CFRunLoopServiceMachPort(dispatchPort, &msg, sizeof(msg_buffer), &livePort, 0, &voucherState, NULL)) {
           goto handle_msg;
       }
#elif DEPLOYMENT_TARGET_WINDOWS
       if (__CFRunLoopWaitForMultipleObjects(NULL, &dispatchPort, 0, 0, &livePort, NULL)) {
           goto handle_msg;
       }
#endif
    }
    didDispatchPortLastTime = false;
```

### 第四步：通知Observers：开始休眠（等待消息唤醒）

```objective-c
//通知Observers：开始休眠
if (!poll && (rlm->_observerMask & kCFRunLoopBeforeWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeWaiting);
__CFRunLoopSetSleeping(rl);
```

### 第五步：通知Observers：结束休眠（被某个消息唤醒）

RunLoop 被唤醒后就要开始处理消息了：（这一段代码太长，就不直接贴出来了）

- 如果是 Timer 时间到的话，就触发 Timer 的回调；

- 处理 GCD Async To Main Queue；

- 如果是 source1(MachPor) 事件的话，就处理这个事件。
- 再次处理Blocks

```objc
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
#if USE_DISPATCH_SOURCE_FOR_TIMERS
        do {
            if (kCFUseCollectableAllocator) {
                // objc_clear_stack(0);
                // <rdar://problem/16393959>
                memset(msg_buffer, 0, sizeof(msg_buffer));
            }
            msg = (mach_msg_header_t *)msg_buffer;
            __CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy);
            
            if (modeQueuePort != MACH_PORT_NULL && livePort == modeQueuePort) {
                // Drain the internal queue. If one of the callout blocks sets the timerFired flag, break out and service the timer.
                while (_dispatch_runloop_root_queue_perform_4CF(rlm->_queue));
                if (rlm->_timerFired) {
                    // Leave livePort as the queue port, and service timers below
                    rlm->_timerFired = false;
                    break;
                } else {
                    if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);
                }
            } else {
                // Go ahead and leave the inner loop.
                break;
            }
        } while (1);
(省略)........
```

### 第六步：根据上一步的操作决定是退出runloop还是继续执行runloop

根据上一步的操作决定是退出runloop还是继续执行runloop

```objc
if (sourceHandledThisLoop && stopAfterHandle) {
	    retVal = kCFRunLoopRunHandledSource;
        } else if (timeout_context->termTSR < mach_absolute_time()) {
            retVal = kCFRunLoopRunTimedOut;
	} else if (__CFRunLoopIsStopped(rl)) {
            __CFRunLoopUnsetStopped(rl);
	    retVal = kCFRunLoopRunStopped;
	} else if (rlm->_stopped) {
	    rlm->_stopped = false;
	    retVal = kCFRunLoopRunStopped;
	} else if (__CFRunLoopModeIsEmpty(rl, rlm, previousMode)) {
	    retVal = kCFRunLoopRunFinished;
	}
```



### RunLoop的六个状态

```objc
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0),						//即将进入RunLoop
    kCFRunLoopBeforeTimers = (1UL << 1),		//即将处理Timers
    kCFRunLoopBeforeSources = (1UL << 2),		//即将处理Source
    kCFRunLoopBeforeWaiting = (1UL << 5),		//即将休眠
    kCFRunLoopAfterWaiting = (1UL << 6),		//即将唤醒
    kCFRunLoopExit = (1UL << 7),						//退出RunLoop
    kCFRunLoopAllActivities = 0x0FFFFFFFU
};
```

用一张图概括RunLoop的运行轨迹

![runloop](5f51c5e05085badb689f01b1e63e1c7d.png)

## 思路

通过上面的runloop运行轨迹我们能够知道，RunLoop`处理事件的时间主要出在两个阶段：

- `kCFRunLoopBeforeSources`和`kCFRunLoopBeforeWaiting`之间
- `kCFRunLoopAfterWaiting`之后

试想如果 RunLoop 的线程，进入睡眠前方法的执行时间过长而导致无法进入睡眠，或者线程唤醒后接收消息时间过长而无法进入下一步的话，就可以认为是线程受阻了。如果这个线程是主线程的话，表现出来的就是出现了卡顿。所以，如果我们要利用 RunLoop 原理来监控卡顿的话，就是要关注这三个阶段。

接下来，我们就一起分析一下，如何对 loop 的这两个状态进行监听，以及监控的时间值如何设置才合理。

## 监控RunLoop状态检测超时

通过`RunLoop`的源码我们已经知道了主线程处理事件的时间，那么如何检测应用是否发生了卡顿呢？为了找到合理的处理方案，我们得先在项目中得到runloop的监听状态。

```objc
static void runLoopObserverCallback(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void * info) {
    [RunloopMonitor shareInstance].currentActivity = activity;
    dispatch_semaphore_signal([RunloopMonitor shareInstance].semphore);
    switch (activity) {
        case kCFRunLoopEntry:
            NSLog(@"runloop entry");
            break;
        case kCFRunLoopExit:
            NSLog(@"runloop exit");
            break;
        case kCFRunLoopAfterWaiting:
            NSLog(@"runloop after waiting");
            break;
        case kCFRunLoopBeforeTimers:
            NSLog(@"runloop before timers");
            break;
        case kCFRunLoopBeforeSources:
            NSLog(@"runloop before sources");
            break;
        case kCFRunLoopBeforeWaiting:
            NSLog(@"runloop before waiting");
            break;
        default:
            break;
    }
};
```

UITableView代理代码：

```objc
- (NSInteger)tableView: (UITableView *)tableView numberOfRowsInSection: (NSInteger)section {
    return 500;
}

- (UITableViewCell *)tableView: (UITableView *)tableView cellForRowAtIndexPath: (NSIndexPath *)indexPath {
    UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier: @"cell"];
    cell.textLabel.text = [NSString stringWithFormat: @"第%lu行", indexPath.row];
    if (indexPath.row > 0 && indexPath.row % 30 == 0) {
        sleep(2.0);
    }
    return cell;
}

- (void)tableView: (UITableView *)tableView didSelectRowAtIndexPath: (NSIndexPath *)indexPath {
    sleep(2.0);
}
```

运行之后输出的结果是滚动引发的`Sources`事件总是被快速的执行完成，然后进入到`kCFRunLoopBeforeWaiting`状态下。假如在滚动过程中发生了卡顿现象，那么`RunLoop`必然会保持`kCFRunLoopAfterWaiting`或者`kCFRunLoopBeforeSources`这两个状态之一。

为了实现卡顿的检测，首先需要注册`RunLoop`的监听回调，保存`RunLoop`状态；其次，通过创建子线程循环监听主线程`RunLoop`的状态来检测是否存在停留卡顿现象: `收到Sources相关的事件时，将超时阙值时间内分割成多个时间片段，重复去获取当前RunLoop的状态。如果多次处在处理事件的状态下，那么可以视作发生了卡顿现象`

```objc
- (void)startMonitoring {
    if (_isMonitoring) { return; }
    _isMonitoring = YES;
    CFRunLoopObserverContext context = { 0, (__bridge void *)self, NULL, NULL};
    _observer = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, &runLoopObserverCallback, &context);
    CFRunLoopAddObserver(CFRunLoopGetMain(), _observer, kCFRunLoopCommonModes);
    
    dispatch_async(event_monitor_queue(), ^{
        while ([RunloopMonitor shareInstance].isMonitoring) {
            if ([RunloopMonitor shareInstance].currentActivity == kCFRunLoopBeforeWaiting) {
                __block BOOL timeOut = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    timeOut = NO;
                    dispatch_semaphore_signal([RunloopMonitor shareInstance].eventSemphore);
                });
                [NSThread sleepForTimeInterval: time_out_interval];
                if (timeOut) {
                }
                dispatch_wait([RunloopMonitor shareInstance].eventSemphore, DISPATCH_TIME_FOREVER);
            }
        }
    });
    
    dispatch_async(fluecy_monitor_queue(), ^{
        while ([RunloopMonitor shareInstance].isMonitoring) {
            long waitTime = dispatch_semaphore_wait(self.semphore, dispatch_time(DISPATCH_TIME_NOW, wait_interval));
            if (waitTime != 0) {
                if (![RunloopMonitor shareInstance].observer) {
                    [RunloopMonitor shareInstance].outTime = 0;
                    [[RunloopMonitor shareInstance] stopMonitoring];
                    continue;
                }
                if ([RunloopMonitor shareInstance].currentActivity == kCFRunLoopBeforeSources || [RunloopMonitor shareInstance].currentActivity == kCFRunLoopAfterWaiting) {
                    if (++[RunloopMonitor shareInstance].outTime < 5) {
                        continue;
                    }
                    [NSThread sleepForTimeInterval: restore_interval];
                }
            }
            [RunloopMonitor shareInstance].outTime = 0;
        }
    });
}
```



## 标记位检测线程超时

与UI卡顿不同的事，事件处理往往是处在`kCFRunLoopBeforeWaiting`的状态下收到了`Sources`事件源，最开始笔者尝试同样以多个时间片段查询的方式处理。但是由于主线程的`RunLoop`在闲置时基本处于`Before Waiting`状态，这就导致了即便没有发生任何卡顿，这种检测方式也总能认定主线程处在卡顿状态。

于是github上查看了下卡顿检测第三方监测卡顿的工具，他们的卡顿监控方案大致思路为：创建一个子线程进行循环检测，每次检测时设置标记位为`YES`，然后派发任务到主线程中将标记位设置为`NO`。接着子线程沉睡超时阙值时长，判断标志位是否成功设置成`NO`。如果没有说明主线程发生了卡顿，无法处理派发任务：

![图片 1](图片 1.png)

## 获取堆栈

子线程监控发现卡顿后，还需要记录当前出现卡顿的方法堆栈信息，并适时推送到服务端供开发者分析，从而解决卡顿问题。那么，在这个过程中，如何获取卡顿的方法堆栈信息呢？

这里我选择了魔改[BSBacktraceLogger](https://github.com/bestswifter/BSBacktraceLogger)

## 小结

多数开发者对于`RunLoop`可能并没有进行实际的应用开发过，或者说即便了解`RunLoop`也只是处在理论的认知上。本文仅仅是对采用runloop来进行APP卡顿的一些个人观点，有纰漏还望指出。

[Demo](https://github.com/eziochiu/RunLoopMonitor.git)