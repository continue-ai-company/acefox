#!/usr/bin/env bash
# 生成 acefox.diff ：仅包含你相对上游(@{u})的本地提交 + 工作区未提交改动
# 逐文件输出补丁（含二进制），避免“参数过长”；过滤 obj-*/.mozbuild/build/dist/node_modules 等
set -e

OUT="${OUT:-acefox.diff}"

# 0) 必须在 git 仓库
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "❌ 不是 Git 仓库"; exit 1; }

# 1) 确定上游分支（tracking branch）
UP="@{u}"
if ! git rev-parse --verify -q "$UP" >/dev/null 2>&1; then
  echo "⚠️ 当前分支没有设置上游，将仅导出未提交改动。"
  UP=""
fi

# 2) 基线：以 fork-point 为准（更贴近你“开始改动”的节点）
if [ -n "$UP" ]; then
  BASE="$(git merge-base --fork-point "$UP" HEAD 2>/dev/null || git merge-base "$UP" HEAD)"
else
  BASE="HEAD"
fi
echo "🧭 上游：${UP:-<none>}"
echo "🪢 基线：$BASE"

# 3) 让未跟踪文件也能出现在 diff（intent-to-add；不真正提交）
git ls-files --others --exclude-standard -z | xargs -0 -I{} git add -N "{}" 2>/dev/null || true

# 4) 过滤规则（构建产物/缓存）
FILTER='(^|/)(obj-[^/]+|\.mozbuild|\.gradle|node_modules|dist|target|out|build)(/|$)|\.(pyc|log|o|a|so|dylib|dll|exe|class)$|(^|/)\.DS_Store$'

# 5) 收集改动文件（相对 BASE 的“已提交” + 相对 HEAD 的“未提交”）
COMMITTED="$(git diff --name-only --diff-filter=ACMRDTUXB "$BASE"..HEAD -- . 2>/dev/null || true)"
WORKTREE="$(git diff --name-only --diff-filter=ACMRDTUXB HEAD -- . 2>/dev/null || true)"

# 6) 合并去重并过滤构建产物
CHANGED="$( { echo "$COMMITTED"; echo "$WORKTREE"; } \
  | grep -v '^$' | sort -u | egrep -v "$FILTER" || true )"

COUNT="$(printf "%s\n" "$CHANGED" | grep -c . || true)"
echo "📄 需要导出的文件数：$COUNT"
[ "$COUNT" -eq 0 ] && { : > "$OUT"; echo "ℹ️ 无需导出，已生成空补丁：$OUT"; exit 0; }

# 7) 逐文件导出两段补丁：① BASE..HEAD（已提交）；② HEAD..WT（未提交）
: > "$OUT"
printf "%s\n" "$CHANGED" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  echo "→ 导出：$f"
  /usr/bin/git -c core.quotepath=false -c diff.renameLimit=999999 diff --binary "$BASE".."HEAD" -- "$f" >> "$OUT" || true
  /usr/bin/git -c core.quotepath=false -c diff.renameLimit=999999 diff --binary "HEAD" -- "$f" >> "$OUT" || true
done

if [ ! -s "$OUT" ]; then
  echo "⚠️ 生成的补丁为空（可能改动仅为权限/换行符，或被过滤规则排除了）。"
else
  echo "✅ 生成完成：$OUT"
  du -h "$OUT" | awk '{print "   大小：" $1}'
  echo "   文件数：$COUNT"
fi
