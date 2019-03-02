#!/bin/bash

# hexo generate
# cp -R public/* .deploy/wangwanjie.github.io
# cd .deploy/wangwanjie.github.io
# git add .
# git commit -m "Website updated"
# git push origin master


hexo clean
hexo generate
hexo d -g
