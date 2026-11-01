#!/usr/bin/env bash
set -euo pipefail

target_branch="${TARGET_BRANCH:-main}"
upstream_repo="${UPSTREAM_REPO:-Lin-arm/GKD_subscription}"
upstream_url="${UPSTREAM_URL:-https://github.com/${upstream_repo}.git}"

if [[ -n "$(git status --porcelain)" ]]; then
  printf '工作区有未提交修改，停止同步。\n' >&2
  exit 1
fi

git switch "$target_branch"
git fetch --no-tags origin "$target_branch:refs/remotes/origin/$target_branch"
git merge --ff-only "origin/$target_branch"

if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream "$upstream_url"
else
  git remote add upstream "$upstream_url"
fi
git fetch --no-tags upstream "$target_branch:refs/remotes/upstream/$target_branch"

if git merge-base --is-ancestor "upstream/$target_branch" HEAD; then
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'changed=false\n' >> "$GITHUB_OUTPUT"
  fi
  printf '已包含上游最新提交，无需同步。\n'
  exit 0
fi

base_sha="$(git rev-parse HEAD)"
if ! git merge --no-ff --no-commit --no-edit "upstream/$target_branch"; then
  conflicts="$(git diff --name-only --diff-filter=U)"
  if git rev-parse --verify -q MERGE_HEAD >/dev/null; then
    git merge --abort
  fi
  printf '::error::上游合并失败，已停止；没有提交或推送。\n' >&2
  if [[ -n "$conflicts" ]]; then
    printf '冲突文件：\n%s\n' "$conflicts" >&2
  fi
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      printf '### 上游同步停止\n\n合并失败，远端分支未修改。请手动处理冲突。\n\n'
      printf '```text\n%s\n```\n' "$conflicts"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
fi

# 保留本分支的同步策略，避免上游重新引入强制覆盖逻辑。
git restore --source="$base_sha" --staged --worktree -- \
  .github/workflows/sync_upstream_main.yml scripts/sync-upstream.sh

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'changed=true\n' >> "$GITHUB_OUTPUT"
fi
printf '上游预合并成功，等待检查、构建和普通推送。\n'
