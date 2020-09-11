---
title: iOS底层之Block
tags: [Block, 底层原理]
top: 0
need_not_copyright: true
date: 2018-06-22 18:38:52
categories: 底层原理
banner_img:
---

* 在此之前需要先了解一个概念 - 闭包（swift中叫闭包），在维基百科中，闭包的定义如下：

```
 In programming languages, a closure is a function or reference to a function together with a referencing
 environment—a table storing a reference to each of the non-local variables (also called free variables 
 or upvalues) of that function.
```

实际上就是一个指向函数的指针。而block实际上就是一个闭包。

---

<!-- more -->

# block的数据结构

* 在讲解block之前，我们先需要知道block的数据结构，鉴于苹果block和runtime的开源，block的源代码可以再
  [libclosure](https://opensource.apple.com/tarballs/libclosure/)
  找得到，大约在源码中的runtime.c的第44行可以找到如下定义：

```
#define BLOCK_DESCRIPTOR_1 1
struct Block_descriptor_1 {
    uintptr_t reserved;
    uintptr_t size;
};
```

第64行中找到block的数据布局：

```
struct Block_layout {
    void *isa;
    volatile int32_t flags; // contains ref count
    int32_t reserved; 
    void (*invoke)(void *, ...);
    struct Block_descriptor_1 *descriptor;
    // imported variables
};
```

根据runtime.c中的对象定义，凡是首地址为\*isa的结构体指针，都认为是对象。然而在OC中，block其实也被默认定义为对象。

通过上面的2附图其实我们可以知道，一个block实际上是由6部分组成：

> 1、isa指针，所有对象都有一个isa指针，上面也讲到过了，它用于实现对象的一些相关的功能；  
> 2、flags，用于按bit位表示的block的附加信息，后面讲block为什么要用copy的时候会讲到；  
> 3、reserved，保留的变量；  
> 4、invoke，函数指针，用于具体指向block内部实现的函数的调用地址；  
> 5、descriptor，表示该block的附加描述信息；
> 6、variables，捕获过来的变量，block之所以能够访问外部的局部变量，是因为将这些变量或者变量的地址拷贝到了这个block的结构体中

写一个简单的例子：

```
void foo_(){
    int i = 2;
    NSNumber *num = @3;

    long (^myBlock)(void) = ^long() {
        return i * num.intValue;
    };

    long r = myBlock();
}
```

在终端中用clang进行反编译会得到如下的代码

```
struct __block_impl {
    void *isa;
    int Flags;
    int Reserved;
    void *FuncPtr;
};

struct __foo_block_desc_0 {
    size_t reserved;
    size_t Block_size;
    void (*copy)(struct __foo_block_impl_0*, struct __foo_block_impl_0*);
    void (*dispose)(struct __foo_block_impl_0*);
};

//myBlock的数据结构定义
struct __foo_block_impl_0 {
    struct __block_impl impl;
    struct __foo_block_desc_0* Desc;
    int i;
    NSNumber *num;
};

//block数据的描述
static struct __foo_block_desc_0 __foo_block_desc_0_DATA = {
    0,
    sizeof(struct __foo_block_impl_0),
    __foo_block_copy_0,
    __foo_block_dispose_0
};

//block中的方法
static long __foo_block_func_0(struct __foo_block_impl_0 *__cself) {
    int i = __cself->i; // bound by copy
    NSNumber *num = __cself->num; // bound by copy
    return i * num.intValue;
}

void foo(){
    int i = 2;
    NSNumber *num = @3;
    struct __foo_block_impl_0 myBlockT;
    struct __foo_block_impl_0 *myBlock = &myBlockT;
    myBlock->impl.isa = &_NSConcreteStackBlock;
    myBlock->impl.Flags = 570425344;
    myBlock->impl.FuncPtr = __foo_block_func_0;
    myBlock->Desc = &__foo_block_desc_0_DATA;
    myBlock->i = i;
    myBlock->num = num;
    long r = myBlock->impl.FuncPtr(myBlock);
}
```

> **编译器会根据block捕获的变量，生成具体的结构体定义。block内部的代码将会提取出来，成为一个单独的C函数，创建block时实际上会在实现方法中声明一个结构体（struct），并且初始化该结构体的成员变量。而在执行block时会去调用这个单独的C函数，并把该结构体的指针传递过去。**

---

# block定义的类型

在libclosure的block.h（在data.c中也可以找得到）的源码中，我们可以找到block定义的类型：

```
void * _NSConcreteStackBlock[32] = { 0 };
void * _NSConcreteMallocBlock[32] = { 0 };
void * _NSConcreteAutoBlock[32] = { 0 };
void * _NSConcreteFinalizingBlock[32] = { 0 };
void * _NSConcreteGlobalBlock[32] = { 0 };
void * _NSConcreteWeakBlockVariable[32] = { 0 };
```

在C语言中定义了6中block，然而在OC当中的block只有3种类型，即：

* NSConcreteStackBlock 定义为栈上创建的block

* NSConcreteMallocBlock 定义为堆上创建的block

* NSConcreteGlobalBlock 作为全局变量的block

PS：在最新的源码中_NSConcreteStackBlock和_NSConcreteGlobalBlock已经被废弃，取而代之的是是_NSConcreteAutoBlock,可能是由于ARC自动管理block内存的原因。

## 全局的block

前面已经提到过

> **在编译器完成编译之后，block会将其内部的代码全部提取出来，形成一个单独的C语言函数，在创建block时实际上它就是在方法声实现中声明一个结构体，并初始化该结构体的成员变量。而在执行block时，会去调用这个单独的C语言函数，并把该结构体的指针传递过去**

于是全局的block就由此而生，其效果就相当于C语言中的匿名函数，因为全局的block是当一个block内部没有捕获任何外部变量时，就会使一个全局的block类型，此时，他就是一个函数，所以他也具备函数的一些特性，当调用block是后面会加上小括号：block()。

那么既然全局的block具有函数的特性，就不必在考虑其生命周期（函数是一执行完就被释放）

---

## 栈中的block

这个block其实是在编译器发现block内部调用或者说引用了外部的一些变量之后才生成的block。

> **在block内部有引用外部变量是，当block内部的结构体第一次被创建时，它会存在与该函数的函数调用栈中，其捕获的变量是会赋值到结构体的成员变量中的，所以当block完成初始化之后是不能更改其内部变量的，所以就知道为什么需要改变block内部的变量需要用到 __block了。**

> **当函数调用结束或者返回时，函数的调用栈就会被销毁，这时block的内存也会被销毁，所以如果后续仍然需要使用这个block的时候，就必须将block以Block_Copy()的方法拷贝到堆上。也就是直接在堆上面申请内存，将block复制过去，最后在捕获到的对象发送retain，增加block的引用计数，保证block在堆上不被释放掉。**

举个例子：

```
#include <stdio.h>

int main() {
    int a = 100;
    void (^block2)(void) = ^{
        printf("%d\n", a);
    };
    block2();
    return 0;
}
```

让clang反编译重写之后：

```
struct __main_block_impl_0 {
    struct __block_impl impl;
    struct __main_block_desc_0* Desc;
    int a;
    __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int _a, int flags=0) : a(_a) {
        impl.isa = &_NSConcreteStackBlock;
        impl.Flags = flags;
        impl.FuncPtr = fp;
        Desc = desc;
    }
};
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
    int a = __cself->a; // bound by copy
    printf("%d\n", a);
}
static struct __main_block_desc_0 {
    size_t reserved;
    size_t Block_size;
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0)};
int main()
{
    int a = 100;
    void (*block2)(void) = (void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, a);
    ((void (*)(__block_impl *))((__block_impl *)block2)->FuncPtr)((__block_impl *)block2);
    return 0;
}
```

---

## 堆中的block

> **在栈中的block提到过，当函数调用结束，函数的调用栈会被销毁，那么栈中的block也会被销毁，但是我们一般都需要在函数结束之后任然使用这个block，所以就需要把栈中的block拷贝到堆上，在copy的同时，栈上的block的类型就转换成了堆上的block。**

> **所以，在MRC时代，block的属性关键字必须是copy。这样就能保证再给block的属性复制的时候，能把栈上的block复制到堆上。**

---

# ARC时代的block之循环引用

在开启ARC后，block的内存会比较微妙。ARC会自动处理block的内存，不用手动copy/release。

但是，和非ARC的情况有所不同：

```
void (^aBlock)(void);
aBlock = ^{ 
	printf("ok"); 
};
```

block是对象，所以aBlock默认是有\_\_strong修饰符的，即aBlock对该block有strong references。即aBlock在被赋值的那一刻，这个block会被copy。所以，ARC开启后，所能接触到的block基本都是在堆上的。。

当block被copy之后\(如开启了ARC、或把block放入dispatch queue\)，该block对它捕获的对象产生strong references \(非ARC下是retain\)，所以有时需要避免block copy后产生的循环引用。

如果用self引用了block，block又捕获了self，这样就会有循环引用。  
因此，需要用weak来声明self

```
- (void)configureBlock {
    XYZBlockKeeper * __weak weakSelf = self;
    self.block = ^{
        [weakSelf doSomething]; //捕获到的是弱引用
    }
}
```

如果捕获到的是当前对象的成员变量对象，同样也会造成对self的引用，同样也要避免。

```
- (void)configureBlock {
    id tmpIvar = _ivar; //临时变量,避免了self引用
    self.block = ^{
        [tmpIvar msg];
    }
}
```

为了避免循环引用，可以这样理解block：block就是一个对象，它捕获到的值就是这个对象的@property (strong)。


