#!/usr/bin/env bash
set -euo pipefail

target_branch="${TARGET_BRANCH:-main}"
upstream_repo="${UPSTREAM_REPO:-Lin-arm/GKD_subscription}"
upstream_url="${UPSTREAM_URL:-https://github.com/${upstream_repo}.git}"

restore_subscription_metadata() {
  local base_sha="$1"
  local source_file='src/subscription.ts'
  local personal_source
  personal_source="$(mktemp "${TMPDIR:-/tmp}/gkd-subscription-metadata.XXXXXX")"
  git show "${base_sha}:${source_file}" > "$personal_source"
  if ! python3 - "$personal_source" "$source_file" <<'PY'
import re
import sys
from pathlib import Path

personal_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
fields = ("name", "author", "supportUri")
personal_lines = personal_path.read_text(encoding="utf-8").splitlines(keepends=True)
target_lines = target_path.read_text(encoding="utf-8").splitlines(keepends=True)

for field in fields:
    pattern = re.compile(rf"^\s*{re.escape(field)}\s*:")
    personal_matches = [line for line in personal_lines if pattern.match(line)]
    target_indexes = [index for index, line in enumerate(target_lines) if pattern.match(line)]
    if len(personal_matches) != 1 or len(target_indexes) != 1:
        raise SystemExit(
            f"无法安全恢复 {field}: personal={len(personal_matches)}, "
            f"merged={len(target_indexes)}"
        )
    target_lines[target_indexes[0]] = personal_matches[0]

target_path.write_text("".join(target_lines), encoding="utf-8")
PY
  then
    rm -f -- "$personal_source"
    return 1
  fi
  rm -f -- "$personal_source"
  git add -- "$source_file"
}

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
  mapfile -t conflicts < <(git diff --name-only --diff-filter=U)
  generated_conflicts=()
  fork_owned_conflicts=()
  metadata_conflicts=()
  unhandled_conflicts=()
  for conflict in "${conflicts[@]}"; do
    case "$conflict" in
      README.md | dist/CHANGELOG.md | dist/README.md | dist/gkd.json5 | dist/gkd.version.json5)
        generated_conflicts+=("$conflict")
        ;;
      Template.md)
        fork_owned_conflicts+=("$conflict")
        ;;
      src/subscription.ts)
        metadata_conflicts+=("$conflict")
        ;;
      *)
        unhandled_conflicts+=("$conflict")
        ;;
    esac
  done

  if [[ "${#conflicts[@]}" -gt 0 && "${#unhandled_conflicts[@]}" -eq 0 ]]; then
    if [[ "${#generated_conflicts[@]}" -gt 0 ]]; then
      # 这些文件由 pnpm run build 重新生成。先保留个人分支版本完成预合并。
      git checkout --ours -- "${generated_conflicts[@]}"
      git add -- "${generated_conflicts[@]}"
    fi
    if [[ "${#fork_owned_conflicts[@]}" -gt 0 ]]; then
      git checkout --ours -- "${fork_owned_conflicts[@]}"
      git add -- "${fork_owned_conflicts[@]}"
    fi
    if [[ "${#metadata_conflicts[@]}" -gt 0 ]]; then
      # 先接受上游入口文件，随后仅恢复个人订阅元数据。
      git checkout --theirs -- "${metadata_conflicts[@]}"
      git add -- "${metadata_conflicts[@]}"
    fi
    printf '冲突仅涉及个人文件、订阅元数据或生成文件，已按同步策略预处理：\n%s\n' \
      "$(printf '%s\n' "${conflicts[@]}")"
  else
    if git rev-parse --verify -q MERGE_HEAD >/dev/null; then
      git merge --abort
    fi
    printf '::error::上游合并失败，已停止；没有提交或推送。\n' >&2
    if [[ "${#conflicts[@]}" -gt 0 ]]; then
      printf '冲突文件：\n%s\n' "$(printf '%s\n' "${conflicts[@]}")" >&2
    fi
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      {
        printf '### 上游同步停止\n\n存在源文件冲突，远端分支未修改。请手动处理。\n\n'
        printf '```text\n%s\n```\n' "$(printf '%s\n' "${conflicts[@]}")"
      } >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 1
  fi
fi

# 保留本分支的文档模板和同步策略，避免上游覆盖个人订阅说明或重新引入强制覆盖逻辑。
git restore --source="$base_sha" --staged --worktree -- \
  Template.md .github/workflows/sync_upstream_main.yml scripts/sync-upstream.sh

# 入口文件继续接收上游功能修改，但固定使用个人订阅名称、作者和支持地址。
if ! restore_subscription_metadata "$base_sha"; then
  if git rev-parse --verify -q MERGE_HEAD >/dev/null; then
    git merge --abort
  fi
  printf '::error::无法安全恢复个人订阅元数据，已停止；没有提交或推送。\n' >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'changed=true\n' >> "$GITHUB_OUTPUT"
fi
printf '上游预合并成功，等待检查、构建和普通推送。\n'
