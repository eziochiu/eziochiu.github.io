---
title: iOS多线程编程之GCD(更新swift3.0用法)
tags: [GCD, 多线程]
top: 0
need_not_copyright: true
date: 2018-04-20 17:38:52
categories: 多线程
banner_img:
---

> iOS多线程编程之GCD

<!-- more -->

## iOS多线程编程之GCD(更新swift3.0用法)

**如果不考虑到其他任何因素和技术**，多线程其实是百害而无一利的，只能浪费时间，降低CPU的运行效率。

试想一下，一个任务由十个子任务组成。现在有两种方式去完成这个任务：

1、新建是个线程，把每个子任务放到对应的子线程中去执行。执行完一个线程就切换到另外一个线程；

2、把是个人物放在一个线程里，按顺序执行。

线程，是执行程序的最基本单元，他有自己的栈和自己的寄存器。说的具体一点，**线程就是“一个CPU执行一条无分叉的命令列”**。

对于第一种方法，在十条线程之间来回切换，就意味着有十组栈和寄存器的值需要不断地备份、替换。而对于第二种方法，只需要一组寄存器和栈的存在，显然效率更加高效。

---

### 并发和并行

通过刚刚的分析，我们可以看到，多线程本身并不能带来效率上的提升。严格意义上来说多线程在处理并发任务时，并不能提高其运行效率，反而会降低程序的运行效率。

那么什么是并发呢？它和并行不一样

> 并发指的是一种现象，一种经常出现，无可避免的现象。它描述的是“多个任务同时发生，需要被处理”这一现象。它的侧重点在于“发生”。

比如或者站排队检票。

> 并行指的是一种技术，一个同时处理多个任务的技术。它描述了一种能够同时处理多个任务的能力，侧重点在于“运行”。

比如景点开放了多个检票窗口，同一时间内能服务多个游客。这种情况可以理解为并行。

并行的反义词就是串行，表示任务必须按顺序来，一个一个执行，前一个执行完了才能执行后一个。

然而我们经常挂载嘴边的“多线程”其实正是采用了并行技术，从而提高执行效率。因为有多个线程，所以CPU有多个内核可以同时工作。并同时处理不同线程内的指令。

然而并发是一种现象，面向这一对象，我们首先需要先创建多个线程，然而真正加快程序运行速度的，是并行技术。也就是让多个CPU内核同时工作，而多线程的技术，正是让多个CPU同时进行工作。

---

### 同步与异步

同步方法就是我们平时调用的哪些方法。因为任何有编程经验的人都知道，比如在第一行调用`foo()`方法，那么程序运行到第二行的时候，foo\(\)方法肯定是执行完了。

所谓的异步，就是允许在执行某一个任务时，函数立刻返回，但是真正要执行的任务稍后完成。

比如我们在点击保存按钮之后，要先把数据写到磁盘，然后更新UI。同步方法就是等到数据保存完再更新UI，而异步则是立刻从保存数据的方法返回并向后执行代码，同时真正用来保存数据的指令将在稍后执行。

---

### GCD简介

GCD是以block为单位，一个block中的代码可以为一个任务。下文中提到的任务，可以理解为执行某个block。

同时GCD有两个很重要的概念：列队和执行方式。

#### 三种队列：

* 串行列队：先入先出，每次只只执行一个任务；
* 并发列队：依然是先入先出，但是可以多个任务并发执行；
* 主列队：在主线程中执行；

#### 两种执行方式：

* 同步执行
* 异步执行

其关系如下

|  | 同步 | 异步 |
| :---: | :---: | :---: |
| 主列队 | 在主线程中执行 | 在当前主线程中执行 |
| 串行列队 | 在当前线程中执行 | 新建线程执行 |
| 并发列队 | 在当前线程中执行 | 新建线程执行 |

---

### GCD死锁

下面的代码会造成死锁：

```
DispatchQueue.main.sync {
    print("当前线程\(Thread.current)")
}
其写法相当于OC中的：
dispatch_sync(dispatch_get_main_queue(){
    NSLog(@"当前线程%@",NSThread.currentThread);
})
```

为什么会造成死锁？首先这是swift3.0的写法，DispatchQueue.main表示已经在主队列中执行，而sync中的代码块也是在当前的主队列中执行，那么，如果sync代码块中的代码要执行，则需要等待DispatchQueue.main执行完成才能执行，而DispatchQueue.main的代码要执行，则需要sync中的代码块执行完成才能执行，那么这样主队列中的两个任务就处在相互等待的状态，都在等对方先执行，而造成了死锁的问题。

其实这种解决方案很简单，只带代码写成下面这样就不会造成死锁：

```
DispatchQueue.main.async {
    print("当前线程\(Thread.current)")
}
```

async是一个异步执行方式，由于是在异步执行，那么就不会存在主队列相互等待的状态，这样就不会造成死锁的问题。

---

### GCD中的group

代码如下：

```
let group = DispatchGroup()
DispatchQueue(label: "label1").async(group:group) {
    print("当前线程111\(Thread.current)")
}
DispatchQueue(label: "label2").async(group: group) {
    print("当前线程222\(Thread.current)")
}
group.notify(queue: DispatchQueue.main) {
    print("当前线程333\(Thread.current)")
}
```

在一个gcd队列组中并发执行线程111和线程222，所有并发线程完成之后通过队列组中的notify方法，回调到主线程。

---

### GCD中的barrier

GCD中的barrier是用来控制GCD线程的先后顺序的方法，代码如下：

```
let group = DispatchGroup()
let queue = DispatchQueue.init(label: "queue")
queue.async(group:group) {
    for i in 0..<10 {
        print("\(i)")
    }
    print("当前线程111\(Thread.current)")
}
queue.async(group: group, qos: .default, flags: .barrier) {
    print("线程阻塞中。。。")
}
queue.async(group: group) {
    for i in 0..<20 {
        print("\(i)")
    }
    print("当前线程222\(Thread.current)")
}
group.notify(queue: DispatchQueue.main) {
    print("当前线程333\(Thread.current)")
}
```

---

### GCD中的信号量（semaphore）

如果你有计算机基础，那么下面这段话应该很简单就能理解

> 信号量就是一个资源计数器，对信号量有两个操作来达到互斥，分别是P和V操作。 一般情况是这样进行临界访问或互斥访问的： 设信号量值为1， 当一个进程1运行是，使用资源，进行P操作，即对信号量值减1，也就是资源数少了1个。这是信号量值为0。系统中规定当信号量值为0是，必须等待，知道信号量值不为零才能继续操作。 这时如果进程2想要运行，那么也必须进行P操作，但是此时信号量为0，所以无法减1，即不能P操作，也就阻塞。这样就到到了进程1排他访问。 当进程1运行结束后，释放资源，进行V操作。资源数重新加1，这是信号量的值变为1. 这时进程2发现资源数不为0，信号量能进行P操作了，立即执行P操作。信号量值又变为0.次数进程2咱有资源，排他访问资源。 这就是信号量来控制互斥的原理

简单点来说，信号量为0时，阻塞线程，大于0是不会阻塞线程，GCD则可以通过信号量的值来达到是否阻塞线程，从而达到线程同步。

简单来说，在GCD中，让线程同步可以用三种方法（就目前我所能想到的）：

* group

* barrier

* semaphore

group和barrier前面我们已经讲解过了，下面我们来说一说semaphore的的用法，在GCD中的信号量有三个函数操作：

* DispatchSemaphore.init   -&gt;   OC代码（dispatch\_semaphore\_create）//**创建一个semaphore信号量**

* dispatch\_semaphore\_signal     //**发送一个信号**

* dispatch\_semaphore\_wait       //**等待信号**

代码如下：

```
let queue = DispatchQueue.init(label: "queue")
let semaphore = DispatchSemaphore.init(value: 2)//初始化的信号量为2
for i in 0...2 {
    print(i)
    _ = semaphore.wait()
    _ = semaphore.wait(timeout: DispatchTime.now() + 10.0)//当前信号量为0时，阻塞线程10秒，10秒过后信号量如果依然为0，将不再等待，继续执行下面的代码
    queue.async {
        for j in 0...3 {
            print("有限资源\(j)")
            sleep(3)//阻塞线程3秒
            print("-------------------")
        }
        semaphore.signal()
    }

}
```



