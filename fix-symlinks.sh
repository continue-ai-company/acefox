#!/bin/bash

APP_PATH="./obj-aarch64-apple-darwin25.2.0/dist/Acefox.app"

echo "开始修复符号链接..."

# 查找所有符号链接并替换为实际文件
find "$APP_PATH" -type l | while IFS= read -r symlink; do
    target=$(readlink "$symlink")

    # 检查目标是否存在
    if [ -e "$target" ]; then
        # 如果目标是文件，复制它
        if [ -f "$target" ]; then
            echo "替换符号链接: $symlink -> $target"
            rm "$symlink"
            cp "$target" "$symlink"
        # 如果目标是目录，复制整个目录
        elif [ -d "$target" ]; then
            echo "替换目录符号链接: $symlink -> $target"
            rm "$symlink"
            cp -R "$target" "$symlink"
        fi
    else
        echo "警告: 符号链接目标不存在，删除: $symlink -> $target"
        rm "$symlink"
    fi
done

echo "符号链接修复完成！"
