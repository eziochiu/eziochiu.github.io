---
title: iOS Reveal2Loader修复版（iOS13修复）
date: 2020-09-14 15:20:00
tags: [Reveal2Loader, 越狱插件]
top: 0
need_not_copyright: true
categories: 越狱插件
banner_img:
---

今天同事说这个插件在iOS13越狱下失效了，所以就修复了在iOS13下无法窥探的bug，把RevealLoader库也更新到了24，附带[Reveal24下载地址](https://www.macwk.com/soft/reveal)。

修复后的Reveal源地址：https://eziochiu.cn/cydia/

~~随着iOS12 越狱的发布，又可以在iOS12的机器上随便搞事情了，但是今天突然发现安装bigBoss上的Reveal2Loader插件替换RevealLoader的库之后竟然无法窥探系统APP和第三方APP，然后在插间内部看到了作者的源码，于是心血来潮就进行了修改一番。~~

<!-- more -->

具体修改过程就不说了，[修改后的源码](https://github.com/eziochiu/Reveal2Loader-Fixed-or-iOS12),[作者源码](https://github.com/zidaneno5/Reveal2Loader)

# 打包及安装方法

1、cd 到工程目录reveal2Loader文件夹下 执行下列语句

> find . -name .DS_Store -print0 | xargs -0 git rm -f --ignore-unmatch 删除当前目录的DS_Store隐藏文件
>
> sudo dpkg-deb -b Package reveal2Loader.deb (前提是必须安装dpkg，可以用brew安装也可以用macport安装)

然后会在目录下生成reveal2Loader.deb

2、将reveal2Loader.deb拷贝到手机

3、将原来的reveal2Loader插件卸载，注销SpringBoard

4、直接用filza找到该文件进行安装，前提是卸载之前的旧版本，否则会报错。

enjoy！！！

<div style="width: 900px; margin: auto">![样例](QQ20190225-124715@2x.png)</div>

<div style="width: 900px; margin: auto">![样例](QQ20190225-124731@2x.png)</div>