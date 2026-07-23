#!/usr/bin/env bash
# 最保守版：始终有输出；兼容老 Git/老 bash

# 调试：DEBUG=1 bash detect-base.sh 可以看命令回显
[ "${DEBUG:-0}" = "1" ] && set -x

echo "== Detecting Firefox BASE =="

# 0) 确认在 Git 仓库
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ 当前目录不是 Git 仓库"
  exit 1
fi

# 1) 打印当前 HEAD
HEAD_SHORT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
HEAD_LINE="$(git show -s --format='%ci %s' HEAD 2>/dev/null || echo '<no commit info>')"
echo "HEAD: ${HEAD_SHORT} — ${HEAD_LINE}"

# 2) 选择上游分支（按优先级）
UPSTREAM=""
for up in origin/mozilla-release origin/releases/mozilla-release origin/mozilla-esr origin/mozilla-central; do
  if git rev-parse --verify -q "$up" >/dev/null 2>&1; then
    UPSTREAM="$up"
    break
  fi
done
echo "Upstream candidate: ${UPSTREAM:-<none>}"

# 3) 计算共同祖先（无上游则用首提交）
if [ -n "$UPSTREAM" ]; then
  MB="$(git merge-base HEAD "$UPSTREAM" 2>/dev/null || true)"
else
  MB="$(git rev-list --max-parents=0 HEAD 2>/dev/null | head -n1)"
fi
if [ -z "$MB" ]; then
  # 再兜底一次
  MB="$(git rev-list --max-parents=0 HEAD 2>/dev/null | head -n1)"
fi
MB_DATE="$( [ -n "$MB" ] && git show -s --format='%ci' "$MB" 2>/dev/null )"
echo "Merge-base: ${MB:-<none>}   Date: ${MB_DATE:-<unknown>}"

# 4) 在 merge-base 附近找最近的 FIREFOX_*_RELEASE tag；失败则从 HEAD 祖先里找
TAG="$( [ -n "$MB" ] && git describe --tags --match 'FIREFOX_*_RELEASE' --abbrev=0 "$MB" 2>/dev/null || true )"
if [ -z "$TAG" ]; then
  TAG="$(git tag --merged HEAD 2>/dev/null | grep -E '^FIREFOX(_[0-9]+)+_RELEASE$' | tail -n 1)"
fi
if [ -n "$TAG" ]; then
  TAG_COMMIT="$(git rev-list -n1 "$TAG" 2>/dev/null)"
  TAG_DATE="$(git show -s --format='%ci' "$TAG_COMMIT" 2>/dev/null)"
  echo "Nearest release tag: ${TAG}"
  echo "Tag commit: ${TAG_COMMIT}   Date: ${TAG_DATE}"
else
  echo "Nearest release tag: <not found>"
fi

# 5) 祖先关系检查（Yes/No）
is_ancestor() { git merge-base --is-ancestor "$1" "$2" >/dev/null 2>&1 && echo Yes || echo No; }
[ -n "$TAG" ] && echo "TAG ancestor of HEAD?  $(is_ancestor "$(git rev-list -n1 "$TAG")" HEAD)"
[ -n "$MB"  ] && echo "MB  ancestor of HEAD?  $(is_ancestor "$MB" HEAD)"

# 6) 推荐的 BASE：优先 tag，否则 merge-base
RECOMMENDED="${TAG:-$MB}"
echo "--------------------------------"
echo "Recommended BASE: ${RECOMMENDED:-<none>}"
