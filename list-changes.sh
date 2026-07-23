#!/usr/bin/env bash
# 列出当前分支相对上游(@{u})的所有改动文件（已提交 + 未提交），过滤构建产物
set -e

echo "== 变动文件列表 =="

# 0) 检查是否是 git 仓库
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "❌ 不是 Git 仓库"; exit 1; }

# 1) 确定上游分支（tracking branch）
UP="@{u}"
if ! git rev-parse --verify -q "$UP" >/dev/null 2>&1; then
  echo "⚠️ 当前分支没有上游，将仅列出未提交改动。"
  UP=""
fi

# 2) 找到基线（fork-point）
if [ -n "$UP" ]; then
  BASE="$(git merge-base --fork-point "$UP" HEAD 2>/dev/null || git merge-base "$UP" HEAD)"
else
  BASE="HEAD"
fi
echo "🪢 基线：$BASE"

# 3) 把未跟踪文件标记为 intent-to-add，让 diff 能识别
git ls-files --others --exclude-standard -z | xargs -0 -I{} git add -N "{}" 2>/dev/null || true

# 4) 过滤规则（构建产物等）
FILTER='(^|/)(obj-[^/]+|\.mozbuild|\.gradle|node_modules|dist|target|out|build)(/|$)|\.(pyc|log|o|a|so|dylib|dll|exe|class)$|(^|/)\.DS_Store$'

# 5) 已提交但未推送的改动
COMMITTED="$(git diff --name-only --diff-filter=ACMRDTUXB "$BASE"..HEAD -- . 2>/dev/null || true)"
# 6) 未提交的改动
WORKTREE="$(git diff --name-only --diff-filter=ACMRDTUXB HEAD -- . 2>/dev/null || true)"
# 7) 合并去重并过滤
ALL_CHANGED="$( { echo "$COMMITTED"; echo "$WORKTREE"; } | grep -v '^$' | sort -u | egrep -v "$FILTER" || true )"

COUNT="$(printf "%s\n" "$ALL_CHANGED" | grep -c . || true)"
echo "📄 变动文件数（已过滤构建产物）：$COUNT"
echo "-----------------------------------"

if [ "$COUNT" -eq 0 ]; then
  echo "没有检测到改动（可能都在被过滤的目录里）"
else
  printf "%s\n" "$ALL_CHANGED"
fi
