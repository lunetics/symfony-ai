#!/usr/bin/env bash
# Runs one model lane sequentially: 5 runs per instruction variant.
# Usage: run-lane.sh <lane>   (terra|luna|sol|grok|dsv4|qwen|kimi|oss|q27|coder)
# Env: MATE70_EV (output dir, required) - MATE70_VARIANTS (default: "pre post";
#      "pre" = current upstream wording, "post" = reworded, "bare" = no files)
#      MATE70_CHANNEL=discovery (disable each CLI's AGENTS.md auto-load)
#      MATE70_RELAY_SOCK (codex lanes only, see SETUP.md)
set -uo pipefail

LANE="$1"
SLOT="${MATE_EVAL_ROOT:?set MATE_EVAL_ROOT}"
BASE="$SLOT/fixtures/mate-eigenlauf"
CONT=mate-fix-84f2
TOOLS="$SLOT/tools/mate70"
EV="${MATE70_EV:?set MATE70_EV}"
TSV="$EV/status-$LANE.tsv"

declare -A PORT=(
  [terra-pre]=8101 [terra-post]=8102 [luna-pre]=8103 [luna-post]=8104
  [sol-pre]=8105 [sol-post]=8106 [grok-pre]=8107 [grok-post]=8108
  [dsv4-pre]=8109 [dsv4-post]=8110 [qwen-pre]=8111 [qwen-post]=8112
  [terra-bare]=8113 [luna-bare]=8114 [sol-bare]=8115
  [grok-bare]=8116 [dsv4-bare]=8117 [qwen-bare]=8118
  [kimi-bare]=8119 [kimi-pre]=8120 [kimi-post]=8121
  [oss-bare]=8122 [oss-pre]=8123 [oss-post]=8124
  [q27-bare]=8125 [q27-pre]=8126 [q27-post]=8127
  [coder-bare]=8128 [coder-pre]=8129 [coder-post]=8130
)

RUN_CAP=1500
[ "$LANE" = qwen ] && RUN_CAP=2400
case "$LANE" in oss|q27|coder) RUN_CAP=3000;; esac  # local models are slower

# Discovery cells: neutralize each CLI's native AGENTS.md/CLAUDE.md auto-load,
# so the run measures whether the agent finds the files by itself.
CODEX_DOC_FLAG=""
[ "${MATE70_CHANNEL:-}" = discovery ] && CODEX_DOC_FLAG="-c project_doc_max_bytes=0"

log() { echo "[$(date +%H:%M:%S)] $LANE: $*"; }

reset_and_verify() { # $1=name $2=port - tag reset, shim, warmup, 21-query check
  local name="$1" port="$2" copy="$BASE/lanes/$1" tok out attempt
  git -C "$copy" reset --hard snapshot -q && git -C "$copy" clean -fdx -q || return 1
  cp "$copy/vendor/bin/mate" "$copy/vendor/bin/mate.real"
  sed "s|__LOGPATH__|/fix/lane-logs/$name.log|" "$TOOLS/mate-shim.php.tpl" > "$copy/vendor/bin/mate"
  chmod +x "$copy/vendor/bin/mate"
  : > "$BASE/lane-logs/$name.log"
  if [ "${MATE70_CHANNEL:-}" = discovery ]; then
    case "$LANE" in
      grok|dsv4|qwen|oss|q27|coder)
        # grok and opencode auto-load AGENTS.md AND CLAUDE.md (code-word probe),
        # so the content moves byte-identical to a name outside their catalogue.
        mv "$copy/AGENTS.md" "$copy/AGENT_GUIDE.md"
        rm -f "$copy/CLAUDE.md"
        [ -f "$copy/README.md" ] && sed -i 's/AGENTS\.md/AGENT_GUIDE.md/g' "$copy/README.md"
        ;;
      kimi)
        # kimi auto-loads AGENTS.md only, so CLAUDE.md may stay; its import
        # pointer follows the rename.
        mv "$copy/AGENTS.md" "$copy/AGENT_GUIDE.md"
        [ -f "$copy/CLAUDE.md" ] && sed -i 's/AGENTS\.md/AGENT_GUIDE.md/g' "$copy/CLAUDE.md"
        [ -f "$copy/README.md" ] && sed -i 's/AGENTS\.md/AGENT_GUIDE.md/g' "$copy/README.md"
        ;;
    esac
  fi
  # A lane's php -S can die between runs; restart it before verifying.
  if [ "$(docker exec "$CONT" curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/books")" = "000" ]; then
    docker exec -d -w "/fix/lanes/$name" "$CONT" php -S 127.0.0.1:"$port" -t public
    sleep 1
  fi
  for attempt in 1 2 3 4 5 6; do
    docker exec "$CONT" curl -s -o /dev/null "http://127.0.0.1:$port/books"
    docker exec "$CONT" curl -s -o /dev/null "http://127.0.0.1:$port/books"
    tok=$(docker exec "$CONT" curl -s -D- -o /dev/null "http://127.0.0.1:$port/books" \
      | tr -d '\r' | awk -F': ' 'tolower($1)=="x-debug-token"{print $2}')
    out=$(docker exec -w /fix "$CONT" php check-queries.php "/fix/lanes/$name" 2>/dev/null)
    printf '%s\n' "$out" | grep -q "token=$tok .*queries=21" && return 0
    sleep 2
  done
  log "VERIFY-FAIL $name (last token=$tok)"; printf '%s\n' "$out"
  return 1
}

queries_after() { # $1=name $2=port - fresh request, query count for that token
  local tok
  tok=$(docker exec "$CONT" curl -s -D- -o /dev/null "http://127.0.0.1:$2/books" \
    | tr -d '\r' | awk -F': ' 'tolower($1)=="x-debug-token"{print $2}')
  docker exec -w /fix "$CONT" php check-queries.php "/fix/lanes/$1" 2>/dev/null \
    | grep "token=$tok " | grep -o 'queries=[0-9]*' | cut -d= -f2
}

invoke_cli() { # $1=copy $2=prompt - run the model CLI, stream output to caller
  local copy="$1" prompt="$2"
  case "$LANE" in
    terra|luna|sol)
      ( cd "$copy" && DOCKER_HOST="unix://${MATE70_RELAY_SOCK:?set MATE70_RELAY_SOCK}" \
        timeout "$RUN_CAP" ~/.local/share/mise/shims/codex exec \
          -s workspace-write -m "gpt-5.6-$LANE" \
          -c model_reasoning_effort=medium \
          -c sandbox_workspace_write.network_access=true \
          $CODEX_DOC_FLAG \
          --skip-git-repo-check "$prompt" </dev/null ) ;;
    grok)
      ( cd "$copy" && timeout "$RUN_CAP" ~/.grok/bin/grok \
          --always-approve -m grok-4.5 -p "$prompt" </dev/null ) ;;
    dsv4)
      ( cd "$copy" && DEEPSEEK_API_KEY=$(jq -r .deepseek_api_key "$DEEPSEEK_KEY_FILE") \
          timeout "$RUN_CAP" ~/.local/share/mise/shims/opencode run --pure --auto \
          -m deepseek/deepseek-v4-pro "$prompt" </dev/null ) ;;
    qwen)
      ( cd "$copy" && timeout "$RUN_CAP" ~/.local/share/mise/shims/opencode run --pure --auto \
          -m 'ollama-local/qwen3:14b' "$prompt" </dev/null ) ;;
    kimi)
      ( cd "$copy" && timeout "$RUN_CAP" ~/.local/share/mise/shims/kimi \
          -m kimi-code/k3 -p "$prompt" </dev/null ) ;;
    oss)
      ( cd "$copy" && timeout "$RUN_CAP" ~/.local/share/mise/shims/opencode run --pure --auto \
          -m 'ollama-local/gpt-oss:20b' "$prompt" </dev/null ) ;;
    q27)
      ( cd "$copy" && timeout "$RUN_CAP" ~/.local/share/mise/shims/opencode run --pure --auto \
          -m 'ollama-local/qwen38-27b-32k' "$prompt" </dev/null ) ;;
    coder)
      ( cd "$copy" && timeout "$RUN_CAP" ~/.local/share/mise/shims/opencode run --pure --auto \
          -m 'ollama-local/qwen2.5-coder:14b' "$prompt" </dev/null ) ;;
  esac
}

collect_native_log() { # $1=rundir $2=marker - the CLI's own session log, best effort
  local rundir="$1" marker="$2" f
  case "$LANE" in
    terra|luna|sol)
      for f in $(find ~/.codex/sessions -name 'rollout-*.jsonl' -newer "$marker" 2>/dev/null); do
        grep -ql "lanes/$LANE-" "$f" 2>/dev/null && cp "$f" "$rundir/" && break
      done ;;
    grok)
      f=$(ls -td ~/.grok/sessions/*"$LANE"*/ 2>/dev/null | head -1)
      [ -n "$f" ] && [ "$f" -nt "$marker" ] && cp -r "$f" "$rundir/grok-session/" 2>/dev/null ;;
    *) : ;; # opencode: the captured stdout is enough
  esac
  return 0
}

echo -e "lane\tvariant\trun\trc\tduration_s\tmate_calls\tqueries_after" > "$TSV"
harness_fails=0

for variant in ${MATE70_VARIANTS:-pre post}; do
  name="$LANE-$variant"
  copy="$BASE/lanes/$name"
  port="${PORT[$name]}"
  # The task prompt is German, as in the original study, and identical in every
  # cell: "GET /books is slow, find the cause and fix it; PHP runs in Docker,
  # use docker exec for all PHP calls." It never mentions mate or the files.
  PROMPT='Die Seite GET /books dieser Symfony-App ist langsam. Finde die Ursache und behebe sie. PHP läuft im Docker-Container: nutze `docker exec -w /fix/lanes/'"$name"' mate-fix-84f2 php …` für alle PHP-Aufrufe.'

  for run in 1 2 3 4 5; do
    rundir="$EV/runs/$name-run$run"
    mkdir -p "$rundir"
    if ! reset_and_verify "$name" "$port"; then
      harness_fails=$((harness_fails+1))
      echo -e "$LANE\t$variant\t$run\tHARNESS-FAIL\t0\t-\t-" >> "$TSV"
      if [ "$harness_fails" -ge 3 ]; then log "CIRCUIT-BREAKER: 3 harness failures, stopping lane"; exit 2; fi
      continue
    fi
    harness_fails=0
    marker=$(mktemp); touch "$marker"
    log "START $name run$run"
    t0=$SECONDS
    invoke_cli "$copy" "$PROMPT" > "$rundir/cli-stdout.log" 2> "$rundir/cli-stderr.log"
    rc=$?
    dur=$((SECONDS-t0))
    sleep 5  # let late writes from the agent settle before collecting
    cp "$BASE/lane-logs/$name.log" "$rundir/mate-calls.jsonl" 2>/dev/null || true
    mate_calls=$(wc -l < "$rundir/mate-calls.jsonl" 2>/dev/null || echo 0)
    git -C "$copy" diff snapshot -- . ':(exclude)vendor/bin/mate' ':(exclude)AGENTS.md' ':(exclude)CLAUDE.md' ':(exclude)README.md' > "$rundir/fix.patch" 2>/dev/null
    qa=$(queries_after "$name" "$port"); qa=${qa:--}
    collect_native_log "$rundir" "$marker"; rm -f "$marker"
    echo -e "$LANE\t$variant\t$run\t$rc\t$dur\t$mate_calls\t$qa" >> "$TSV"
    log "DONE $name run$run rc=$rc dur=${dur}s mate=$mate_calls queries_after=$qa"
  done
done
log "LANE COMPLETE"
