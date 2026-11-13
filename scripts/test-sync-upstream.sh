#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/gkd-sync-test.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT

configure_git() {
  git -C "$1" config user.name 'Sync Test'
  git -C "$1" config user.email 'sync-test@example.invalid'
  git -C "$1" config commit.gpgsign false
}

create_repositories() {
  local case_dir="$1"
  mkdir -p "$case_dir"
  git init -q --initial-branch=main "$case_dir/seed"
  configure_git "$case_dir/seed"
  mkdir -p "$case_dir/seed/scripts" "$case_dir/seed/.github/workflows"
  cp "$script_dir/sync-upstream.sh" "$case_dir/seed/scripts/sync-upstream.sh"
  printf 'protected workflow\n' > "$case_dir/seed/.github/workflows/sync_upstream_main.yml"
  printf 'personal template\n' > "$case_dir/seed/Template.md"
  mkdir -p "$case_dir/seed/src"
  cat > "$case_dir/seed/src/subscription.ts" <<'EOF'
export default {
  name: 'base name',
  author: 'base author',
  supportUri: 'https://example.invalid/base',
  feature: 'base feature',
};
EOF
  printf 'base rule\n' > "$case_dir/seed/rules.txt"
  git -C "$case_dir/seed" add .
  git -C "$case_dir/seed" commit -qm 'base'
  git clone -q --bare "$case_dir/seed" "$case_dir/origin.git"
  git clone -q --bare "$case_dir/seed" "$case_dir/upstream.git"
  git clone -q "$case_dir/origin.git" "$case_dir/fork"
  git clone -q "$case_dir/upstream.git" "$case_dir/upstream"
  configure_git "$case_dir/fork"
  configure_git "$case_dir/upstream"
}

prepare_merge() {
  local case_dir="$1"
  (
    cd "$case_dir/fork"
    UPSTREAM_URL="$case_dir/upstream.git" \
      GITHUB_OUTPUT="$case_dir/output" \
      GITHUB_STEP_SUMMARY="$case_dir/summary" \
      bash "$script_dir/sync-upstream.sh" > "$case_dir/log" 2>&1
  )
}

case_dir="$test_dir/no-updates"
create_repositories "$case_dir"
before="$(git -C "$case_dir/fork" rev-parse HEAD)"
prepare_merge "$case_dir"
test "$(git -C "$case_dir/fork" rev-parse HEAD)" = "$before"
test -z "$(git -C "$case_dir/fork" status --porcelain)"
grep -qx 'changed=false' "$case_dir/output"
printf 'PASS: 无上游更新时不修改工作区或提交。\n'

case_dir="$test_dir/clean-merge"
create_repositories "$case_dir"
printf 'personal rule\n' > "$case_dir/fork/custom.txt"
git -C "$case_dir/fork" add custom.txt
git -C "$case_dir/fork" commit -qm 'personal rule'
git -C "$case_dir/fork" push -q origin main
printf 'new upstream rule\n' > "$case_dir/upstream/upstream.txt"
printf 'upstream workflow\n' > "$case_dir/upstream/.github/workflows/sync_upstream_main.yml"
git -C "$case_dir/upstream" add .
git -C "$case_dir/upstream" commit -qm 'upstream rule'
git -C "$case_dir/upstream" push -q origin main
prepare_merge "$case_dir"
grep -qx 'changed=true' "$case_dir/output"
grep -qx 'personal rule' "$case_dir/fork/custom.txt"
grep -qx 'new upstream rule' "$case_dir/fork/upstream.txt"
grep -qx 'protected workflow' "$case_dir/fork/.github/workflows/sync_upstream_main.yml"
cmp "$script_dir/sync-upstream.sh" "$case_dir/fork/scripts/sync-upstream.sh"
git -C "$case_dir/fork" commit -qm 'merge upstream'
git -C "$case_dir/fork" push -q origin main
git -C "$case_dir/fork" merge-base --is-ancestor \
  "$(git -C "$case_dir/upstream.git" rev-parse main)" HEAD
printf 'PASS: 普通合并保留自定义规则和同步策略，并可普通推送。\n'

case_dir="$test_dir/generated-conflict"
create_repositories "$case_dir"
mkdir -p "$case_dir/fork/dist" "$case_dir/upstream/dist"
printf 'personal generated subscription\n' > "$case_dir/fork/dist/gkd.json5"
git -C "$case_dir/fork" add dist/gkd.json5
git -C "$case_dir/fork" commit -qm 'personal generated subscription'
git -C "$case_dir/fork" push -q origin main
printf 'upstream generated subscription\n' > "$case_dir/upstream/dist/gkd.json5"
printf 'new upstream source\n' > "$case_dir/upstream/upstream.txt"
git -C "$case_dir/upstream" add dist/gkd.json5 upstream.txt
git -C "$case_dir/upstream" commit -qm 'upstream generated subscription'
git -C "$case_dir/upstream" push -q origin main
prepare_merge "$case_dir"
grep -qx 'changed=true' "$case_dir/output"
grep -qx 'personal generated subscription' "$case_dir/fork/dist/gkd.json5"
grep -qx 'new upstream source' "$case_dir/fork/upstream.txt"
test -f "$case_dir/fork/.git/MERGE_HEAD"
test -z "$(git -C "$case_dir/fork" diff --name-only --diff-filter=U)"
git -C "$case_dir/fork" commit -qm 'merge upstream with regenerated files pending'
git -C "$case_dir/fork" push -q origin main
git -C "$case_dir/fork" merge-base --is-ancestor \
  "$(git -C "$case_dir/upstream.git" rev-parse main)" HEAD
printf 'PASS: 仅生成文件冲突时保留个人临时版本并继续，等待后续重新构建。\n'

case_dir="$test_dir/fork-owned-conflict"
create_repositories "$case_dir"
cat > "$case_dir/fork/src/subscription.ts" <<'EOF'
export default {
  name: 'personal name',
  author: 'personal author',
  supportUri: 'https://example.invalid/personal',
  feature: 'base feature',
};
EOF
printf 'personal template\n' > "$case_dir/fork/Template.md"
git -C "$case_dir/fork" add src/subscription.ts Template.md
git -C "$case_dir/fork" commit -qm 'personal metadata and template'
git -C "$case_dir/fork" push -q origin main
cat > "$case_dir/upstream/src/subscription.ts" <<'EOF'
export default {
  name: 'base name',
  author: 'upstream author warning',
  supportUri: 'https://example.invalid/base',
  feature: 'upstream feature',
};
EOF
printf 'upstream template notice\n' > "$case_dir/upstream/Template.md"
git -C "$case_dir/upstream" add src/subscription.ts Template.md
git -C "$case_dir/upstream" commit -qm 'upstream metadata and template'
git -C "$case_dir/upstream" push -q origin main
prepare_merge "$case_dir"
grep -qx 'changed=true' "$case_dir/output"
grep -qx 'personal template' "$case_dir/fork/Template.md"
grep -q "name: 'personal name'" "$case_dir/fork/src/subscription.ts"
grep -q "author: 'personal author'" "$case_dir/fork/src/subscription.ts"
grep -q "supportUri: 'https://example.invalid/personal'" \
  "$case_dir/fork/src/subscription.ts"
grep -q "feature: 'upstream feature'" "$case_dir/fork/src/subscription.ts"
test -f "$case_dir/fork/.git/MERGE_HEAD"
test -z "$(git -C "$case_dir/fork" diff --name-only --diff-filter=U)"
git -C "$case_dir/fork" commit -qm 'merge upstream with personal metadata'
git -C "$case_dir/fork" push -q origin main
git -C "$case_dir/fork" merge-base --is-ancestor \
  "$(git -C "$case_dir/upstream.git" rev-parse main)" HEAD
printf 'PASS: 个人模板和元数据保持不变，同时接收上游入口功能修改。\n'

case_dir="$test_dir/conflict"
create_repositories "$case_dir"
printf 'personal rule\n' > "$case_dir/fork/rules.txt"
git -C "$case_dir/fork" commit -qam 'personal rule'
git -C "$case_dir/fork" push -q origin main
printf 'conflicting upstream rule\n' > "$case_dir/upstream/rules.txt"
git -C "$case_dir/upstream" commit -qam 'upstream rule'
git -C "$case_dir/upstream" push -q origin main
before="$(git -C "$case_dir/fork" rev-parse HEAD)"
if prepare_merge "$case_dir"; then
  printf 'FAIL: 有冲突时错误地继续执行。\n' >&2
  exit 1
fi
test "$(git -C "$case_dir/fork" rev-parse HEAD)" = "$before"
test "$(git -C "$case_dir/origin.git" rev-parse main)" = "$before"
test -z "$(git -C "$case_dir/fork" status --porcelain)"
test ! -f "$case_dir/fork/.git/MERGE_HEAD"
test ! -f "$case_dir/output"
grep -qx 'personal rule' "$case_dir/fork/rules.txt"
grep -q 'rules.txt' "$case_dir/summary"
printf 'PASS: 冲突时退出失败，恢复合并前状态，远端和自定义规则不变。\n'
