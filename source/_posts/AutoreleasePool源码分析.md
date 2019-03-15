---
title: AutoreleasePool源码分析
date: 2018-03-15 10:53:48
tags: [Autorelease, RunLoop, 底层原理]
top: 0
need_not_copyright: true
categories: 底层原理
banner_img:
---

> AutoreleasePool（自动释放池）是OC中的一种内存自动回收机制，它可以延迟加入AutoreleasePool中的变量release的时机。在正常情况下，创建的变量会在超出其作用域的时候release，但是如果将变量加入AutoreleasePool，那么release将延迟执行。

<!-- more -->

需要了解AutoreleasePool的工作原理，我们需要知道它的底层到底做了什么事情，那我们就先从汇编代码入手，新建一个命令行工程，创建一个新的对象继承自NSObject：

```
#import <Foundation/Foundation.h>
#import "object.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        object *oc = [[object alloc] init]];
    }
    return 0;
}

```
我们利用命令将OC代码重写为c++代码：

```
xcrun -sdk iphoneos clang -arch arm64 -rewrite-objc main.m
```

我们可以大约得到3万2千行的c++代码的cpp文件，但是不要紧，因为最终的核心代码在该cpp的最底部：

```
int main(int argc, const char * argv[]) {
    /* @autoreleasepool */ { __AtAutoreleasePool __autoreleasepool; 

        object *o1 = ((object *(*)(id, SEL))(void *)objc_msgSend)((id)((object *(*)(id, SEL))(void *)objc_msgSend)((id)((object *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("object"), sel_registerName("alloc")), sel_registerName("init")), sel_registerName("autorelease"));
    }
    return 0;
}

```

中间的代码层是object对象的创建过程，发送objc_msgSend消息创建对象。那其实最核心的代码就在下面这这两句上了

>__AtAutoreleasePool __autoreleasepool; 

# __AtAutoreleasePool

我们在cpp文件中搜索__AtAutoreleasePool会找到如下代码,__AtAutoreleasePool具体定义如下：

```
extern "C" __declspec(dllimport) void * objc_autoreleasePoolPush(void);
extern "C" __declspec(dllimport) void objc_autoreleasePoolPop(void *);

struct __AtAutoreleasePool {
  __AtAutoreleasePool() { // 构造函数，在创建结构体的时候调用
      atautoreleasepoolobj = objc_autoreleasePoolPush();
  }
  ~__AtAutoreleasePool() { // 析构函数，在结构体销毁的时候调用
    objc_autoreleasePoolPop(atautoreleasepoolobj);
  }
  void * atautoreleasepoolobj;
};
```
上面两个调用，分别是构造函数和析构函数，根据构造函数和析构函数的特点：自动局部变量的构造函数是在程序执行到声明这个对象的位置时调用的，而对应的析构函数是在程序执行到离开这个对象的作用域时调用。苹果实际上是通过声明一个__AtAutoreleasePool类型的局部变量__autoreleasepool实现了@autoreleasepool{},那么实际上单个自动释放池的执行过程就是：

```
objc_autoreleasePoolPush() —> [object autorelease] —> objc_autoreleasePoolPop(void *)
```


想了解objc_autoreleasePoolPush和objc_autoreleasePoolPop具体都做了些什么，其实很简单，我们只要到runtime->NSObject.mm的源码中就能窥探它的真是面目了，这里我们分析的runtime源码是objc-750的版本。
在源码中我们可以发现这样一段代码：

```
void *objc_autoreleasePoolPush(void) {
    return AutoreleasePoolPage::push();
}

void objc_autoreleasePoolPop(void *ctxt) {
    AutoreleasePoolPage::pop(ctxt);
}
```

objc_autoreleasePoolPush和objc_autoreleasePoolPop分别是由AutoreleasePoolPage调用了push方法入栈和pop方法出栈，其本质实际上是AutoreleasePoolPage对应的静态方法push和pop的封装。那么问题就显而易见了，如果要知道这个push和pop方法到底做了什么，我们还得从源码里获取到AutoreleasePoolPage相关的内容以及其实现原理。

# AutoreleasePoolPage定义

在runtime源码中对AutoreleasePoolPage的定义是这样的：

```
class AutoreleasePoolPage  {
    // EMPTY_POOL_PLACEHOLDER is stored in TLS when exactly one pool is 
    // pushed and it has never contained any objects. This saves memory 
    // when the top level (i.e. libdispatch) pushes and pops pools but 
    // never uses them.
#   define EMPTY_POOL_PLACEHOLDER ((id*)1)

#   define POOL_BOUNDARY nil
    static pthread_key_t const key = AUTORELEASE_POOL_KEY;
    static uint8_t const SCRIBBLE = 0xA3;  // 0xA3A3A3A3 after releasing
    static size_t const SIZE = 
#if PROTECT_AUTORELEASEPOOL
        PAGE_MAX_SIZE;  // must be multiple of vm page size
#else
        PAGE_MAX_SIZE;  // size and alignment, power of 2
#endif
    static size_t const COUNT = SIZE / sizeof(id);

    magic_t const magic;
    id *next;
    pthread_t const thread;
    AutoreleasePoolPage * const parent;
    AutoreleasePoolPage *child;
    uint32_t const depth;
    uint32_t hiwat;
}
```
去除那些静态成员变量,AutoreleasePoolPage的成员变量的解释如下：

```
class AutoreleasePoolPage  {
    magic_t const magic; //检查校验完整性的变量
    id *next; //指向新添加到AutoreleasePoolPage的对象
    pthread_t const thread; //AutoreleasePoolPage当前所在的线程，AutoreleasePool是按线程一一对应的（结构中的thread指针指向当前线程）
    AutoreleasePoolPage * const parent; //指向上一个AutoreleasePoolPage
    AutoreleasePoolPage *child; //指向下一个AutoreleasePoolPage
    uint32_t const depth; //depth 链表的深度，节点个数
    uint32_t hiwat; //数据容纳的一个上限
}
```

这里需要注意的是AutoreleasePoolPage有一个成员变量是PAGE_MAX_SIZE，这个表示一个AutoreleasePoolPage最大内存大小，这个宏其实在上面可以找得到，也就是说一个AutoreleasePoolPage的最大内存大小是PAGE_MAX_SIZE（也就是4096）：

```
#define I386_PGBYTES        4096        /* bytes per 80386 page */
#define I386_PGSHIFT        12      /* bitshift for pages */

#define PAGE_SIZE       I386_PGBYTES
#define PAGE_SHIFT      I386_PGSHIFT
#define PAGE_MASK       (PAGE_SIZE - 1)

#define PAGE_MAX_SHIFT          PAGE_SHIFT
#define PAGE_MAX_SIZE           PAGE_SIZE
#define PAGE_MAX_MASK           PAGE_MASK

#define PAGE_MIN_SHIFT          PAGE_SHIFT
#define PAGE_MIN_SIZE           PAGE_SIZE
#define PAGE_MIN_MASK           PAGE_MASK
```
# AutoreleasePoolPage工作原理

每个AutoreleasePoolPage对象的内存大小事4096字节，除去AutoreleasePoolPage的成员变量所占用的空间，剩下的空间用来存放Autorelease对象的地址，知道了AutoreleasePoolPage的定义，现在我们回到objc_autoreleasePoolPush这个方法，我们发现了，实际上这个方法是调用了AutoreleasePoolPage的push方法：

```
static inline void *push() {
    id *dest;
    if (DebugPoolAllocation) {
        // Each autorelease pool starts on a new pool page.
        dest = autoreleaseNewPage(POOL_BOUNDARY);
    } else {
        dest = autoreleaseFast(POOL_BOUNDARY);
    }
    assert(dest == EMPTY_POOL_PLACEHOLDER || *dest == POOL_BOUNDARY);
    return dest;
}
```
细心的你肯定会发现，在调用push方法的时候autoreleaseFast会将一个POOL_BOUNDARY的对象放在临界点上。POOL_BOUNDARY这个对象属于比较关键的对象，关系到AutoreleasePoolPage的释放过程。

```
static inline id *autoreleaseFast(id obj) {
    AutoreleasePoolPage *page = hotPage();
    if (page && !page->full()) {
        return page->add(obj);
    } else if (page) {
        return autoreleaseFullPage(obj, page);
    } else {
        return autoreleaseNoPage(obj);
    }
}
```

上述方法分三种情况选择不同的代码执行：

1、有 hotPage 并且当前 page 不满，调用 page->add(obj) 方法将对象添加至 AutoreleasePoolPage 的栈中
2、有 hotPage 并且当前 page 已满，调用 autoreleaseFullPage 初始化一个新的页，调用 page->add(obj) 方法将对象添加至 AutoreleasePoolPage 的栈中
3、无 hotPage，调用 autoreleaseNoPage 创建一个 hotPage，调用 page->add(obj) 方法将对象添加至 AutoreleasePoolPage 的栈中

最后的都会调用 page->add(obj) 将对象添加到自动释放池中。而hotPage 可以理解为当前正在使用的 AutoreleasePoolPage。

接下来我们看一看objc_autoreleasePoolPop方法调用pop的实现：

```
static inline void pop(void *token) {
    AutoreleasePoolPage *page;
    id *stop;

    if (token == (void*)EMPTY_POOL_PLACEHOLDER) {
        // Popping the top-level placeholder pool.
        if (hotPage()) {
            // Pool was used. Pop its contents normally.
            // Pool pages remain allocated for re-use as usual.
            pop(coldPage()->begin());
        } else {
            // Pool was never used. Clear the placeholder.
            setHotPage(nil);
        }
        return;
    }

    page = pageForPointer(token);
    stop = (id *)token;
    if (*stop != POOL_BOUNDARY) {
        if (stop == page->begin()  &&  !page->parent) {
            // Start of coldest page may correctly not be POOL_BOUNDARY:
            // 1. top-level pool is popped, leaving the cold page in place
            // 2. an object is autoreleased with no pool
        } else {
            // Error. For bincompat purposes this is not 
            // fatal in executables built with old SDKs.
            return badPop(token);
        }
    }

    if (PrintPoolHiwat) printHiwat();

    page->releaseUntil(stop);

    // memory: delete empty children
    if (DebugPoolAllocation  &&  page->empty()) {
        // special case: delete everything during page-per-pool debugging
        AutoreleasePoolPage *parent = page->parent;
        page->kill();
        setHotPage(parent);
    } else if (DebugMissingPools  &&  page->empty()  &&  !page->parent) {
        // special case: delete everything for pop(top) 
        // when debugging missing autorelease pools
        page->kill();
        setHotPage(nil);
    } 
    else if (page->child) {
        // hysteresis: keep one empty child if page is more than half full
        if (page->lessThanHalfFull()) {
            page->child->kill();
        }
        else if (page->child->child) {
            page->child->child->kill();
        }
    }
}
```

顺着源码一步一步找就会发现，autorelease函数和push函数一样，关键代码都是调用autoreleaseFast函数向自动释放池的链表栈中添加一个对象，不过push函数的入栈的是一个边界对象，而autorelease函数入栈的是需要加入autoreleasepool的对象。自动释放池释放是传入 push 返回的边界对象（POOL_BOUNDARY）,autoreleasepool在调用autorelease时逐渐kill存在在autoreleasepool中的对象的地址，直到找到POOL_BOUNDARY对象所在的地址才会停止。

那么这就衍生了一个问题，如果AutoreleasePoolPage在添加需要释放的对象的地址超过了4096的空间或者是说有多个AutoreleasePoolPage的时候它是如何存入需要释放对象的地址，又是如何一层一层的释放的呢？

# AutoreleasePoolPage双向链表

其实AutoreleasePoolPage并没有单独的结构，而是由若干个AutoreleasePoolPage以双向链表的形式组合而成的栈结构在AutoreleasePoolPage的成员变量内部，我们可以清晰的看到有两个成员变量：

```
 AutoreleasePoolPage * const parent; //指向上一个AutoreleasePoolPage
 AutoreleasePoolPage *child; //指向下一个AutoreleasePoolPage
```
parent指针和child指针，parent指向的上一个AutoreleasePoolPage的内存空间地址而child则指向下一个AutoreleasePoolPage的内存地址，当一个AutoreleasePoolPage的空间被占满时，会新建一个AutoreleasePoolPage对象，连接链表，后来的autorelease对象在新的page加入。这样无论在添加autorelease对象地址和释放autorelease对象地址的时候都能很准确的找到对应的AutoreleasePoolPage的地址
![双向链表](双向链表.png)

具体查看AutoreleasePoolPage的工作原理，可以用_objc_autoreleasePoolPrint这个私有函数来查看

# Runloop和AutoreleasePool的关系

我们新建一个空的工程，在viewDidLoad打印[NSRunLoop mainRunLoop]的详细信息，我们会在observers发现两个关于AutoreleasePool的Handler操作_wrapRunLoopWithAutoreleasePoolHandler：

```
observers = (
    "<CFRunLoopObserver 0x600001f68140 [0x1053f6b68]>{valid = Yes, activities = 0x1, repeats = Yes, order = -2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x107fe51b1), context = <CFArray 0x600002020330 [0x1053f6b68]>{type = mutable-small, count = 1, values = (\n\t0 : <0x7ff476808058>\n)}}",
    "<CFRunLoopObserver 0x600001f6c1e0 [0x1053f6b68]>{valid = Yes, activities = 0x20, repeats = Yes, order = 0, callout = _UIGestureRecognizerUpdateObserver (0x107bb7473), context = <CFRunLoopObserver context 0x60000056dea0>}",
    "<CFRunLoopObserver 0x600001f68c80 [0x1053f6b68]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 1999000, callout = _beforeCACommitHandler (0x108014dfc), context = <CFRunLoopObserver context 0x7ff475d024b0>}",
    "<CFRunLoopObserver 0x600001f68960 [0x1053f6b68]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 2000000, callout = _ZN2CA11Transaction17observer_callbackEP19__CFRunLoopObservermPv (0x109a136ae), context = <CFRunLoopObserver context 0x0>}",
    "<CFRunLoopObserver 0x600001f68be0 [0x1053f6b68]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 2001000, callout = _afterCACommitHandler (0x108014e75), context = <CFRunLoopObserver context 0x7ff475d024b0>}",
    "<CFRunLoopObserver 0x600001f68b40 [0x1053f6b68]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x107fe51b1), context = <CFArray 0x600002020330 [0x1053f6b68]>{type = mutable-small, count = 1, values = (\n\t0 : <0x7ff476808058>\n)}}"
)
```
我们查看它的activities，分别是在0x1和0xa0，那这两个分别有代表是什么呢？在runloop 的源码里我们可以找到runloop的相关枚举：

```
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
     kCFRunLoopEntry = (1UL << 0),  // 1
     kCFRunLoopBeforeTimers = (1UL << 1), // 2
     kCFRunLoopBeforeSources = (1UL << 2), // 4
     kCFRunLoopBeforeWaiting = (1UL << 5), // 32
     kCFRunLoopAfterWaiting = (1UL << 6), // 64
     kCFRunLoopExit = (1UL << 7), // 128
     kCFRunLoopAllActivities = 0x0FFFFFFFU
 };
```
根据位运算可以的出上述结果：0x1 = 1 等价于kCFRunLoopEntry，0xa0 = 64 + 128 等价于 kCFRunLoopBeforeWaiting | kCFRunLoopExit，意味着runloop会在kCFRunLoopEntry时进行一次push操作，在kCFRunLoopBeforeWaiting进行一次pop操作，然后在进行一次push操作，最后会在kCFRunLoopExit时进行一次pop操作。

也就是说runloop会在即将进行休眠和退出runloop是将AutoreleasePool进行释放。