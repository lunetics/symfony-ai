#!/usr/bin/env bash
# Builds one fixture copy per model and instruction variant. Per copy: reset to
# the snapshot tag, rebuild the compiled Symfony container (it holds absolute
# paths), start its own php -S inside the container, verify the 21-query baseline
# against a freshly issued debug token, then re-tag the copy as snapshot.
set -euo pipefail

BASE="${MATE_EVAL_ROOT:?set MATE_EVAL_ROOT}"/fixtures/mate-eigenlauf
CONT=mate-fix-84f2

declare -A PORT=(
  [terra-pre]=8101 [terra-post]=8102
  [luna-pre]=8103  [luna-post]=8104
  [sol-pre]=8105   [sol-post]=8106
  [grok-pre]=8107  [grok-post]=8108
  [dsv4-pre]=8109  [dsv4-post]=8110
  [qwen-pre]=8111  [qwen-post]=8112
)

mkdir -p "$BASE/lanes" "$BASE/lane-logs"

for lane in terra luna sol grok dsv4 qwen; do
  for variant in pre post; do
    name="$lane-$variant"
    dst="$BASE/lanes/$name"
    port="${PORT[$name]}"
    src=mate-skills
    [ "$variant" = post ] && src=mate-skills-c1

    if [ -d "$dst" ]; then
      echo "SKIP $name (already exists)"
      continue
    fi

    cp -a "$BASE/$src" "$dst"
    git -C "$dst" reset --hard snapshot -q
    git -C "$dst" clean -fdx -q
    # Without this the copy silently serves the source arm's compiled container.
    rm -rf "$dst/var/cache/dev"

    docker exec -d -w "/fix/lanes/$name" "$CONT" php -S 127.0.0.1:"$port" -t public
    sleep 1

    for i in 1 2 3; do
      docker exec "$CONT" curl -s -o /dev/null "http://127.0.0.1:$port/books"
    done
    tok=$(docker exec "$CONT" curl -s -D- -o /dev/null "http://127.0.0.1:$port/books" \
      | tr -d '\r' | awk -F': ' 'tolower($1)=="x-debug-token"{print $2}')
    out=$(docker exec -w /fix "$CONT" php check-queries.php "/fix/lanes/$name")
    if ! printf '%s\n' "$out" | grep -q "token=$tok .*queries=21"; then
      echo "ERROR $name: 21-query verification failed (token=$tok)"
      printf '%s\n' "$out"
      exit 1
    fi

    git -C "$dst" add -A
    git -C "$dst" commit -q -m "lane baseline $name: rebuilt cache + profiler warmup"
    git -C "$dst" tag -f snapshot >/dev/null
    echo "OK $name port=$port tag=$(git -C "$dst" describe --tags) token=$tok"
  done
done
echo "BUILD COMPLETE"
