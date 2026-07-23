#!/bin/bash
# 复制 Firefox 源码到 C:\firefox（排除构建产物和 git 历史以加速复制）

SRC="//Mac/Home/Workspaces/firefox"
DST="/c/firefox"

echo "开始复制 $SRC -> $DST ..."

# 使用 rsync 排除大目录
rsync -av --progress \
  --exclude='obj-*' \
  --exclude='.git' \
  --exclude='node_modules' \
  "$SRC/" "$DST/"

echo "完成！"
echo "进入目录: cd /c/firefox"
