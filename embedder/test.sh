#!/usr/bin/env bash
set -uo pipefail

BASE_URL="${EMBEDDER_URL:-http://localhost:8001}"
failures=0

pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# --- /health ---
if curl -sf "$BASE_URL/health" >/dev/null; then
  pass "/health returns success"
else
  fail "/health did not return success"
fi

# --- /embed: batch shape (count + dimensionality) ---
resp=$(curl -sf -X POST "$BASE_URL/embed" \
  -H 'Content-Type: application/json' \
  -d '{"texts": ["hello world", "install a package"]}')
if [ -z "$resp" ]; then
  fail "/embed (batch) request failed"
else
  count=$(echo "$resp" | jq '.embeddings | length')
  dim=$(echo "$resp" | jq '.embeddings[0] | length')
  if [ "$count" = "2" ] && [ "$dim" = "384" ]; then
    pass "/embed returns 2 vectors of dim 384"
  else
    fail "/embed shape mismatch (count=$count dim=$dim)"
  fi
fi

# --- /embed: order preservation (semantic, not just shape) ---
# A text's embedding, requested alone, should be cosine-similar (~1.0) to that
# same text's embedding at the matching position in a batch. A genuinely
# different text sits far lower (~0.6-0.7 for these two sample sentences) —
# calibrated empirically against this model, not guessed — so a 0.99
# threshold reliably catches a swapped/reversed response while tolerating
# tiny batch-padding floating-point noise. Exact equality was tried first and
# rejected: it produced false failures from that same harmless noise.
cosine_similarity() {
  jq -n --argjson a "$1" --argjson b "$2" '
    ([range(0; ($a | length))] | map($a[.] * $b[.]) | add) as $dot
    | ($a | map(. * .) | add | sqrt) as $norm_a
    | ($b | map(. * .) | add | sqrt) as $norm_b
    | $dot / ($norm_a * $norm_b)
  '
}

vec_a_alone=$(curl -sf -X POST "$BASE_URL/embed" -H 'Content-Type: application/json' \
  -d '{"texts": ["alpha text"]}' | jq -c '.embeddings[0]')
vec_b_alone=$(curl -sf -X POST "$BASE_URL/embed" -H 'Content-Type: application/json' \
  -d '{"texts": ["beta text"]}' | jq -c '.embeddings[0]')
resp=$(curl -sf -X POST "$BASE_URL/embed" -H 'Content-Type: application/json' \
  -d '{"texts": ["alpha text", "beta text"]}')
vec_a_in_batch=$(echo "$resp" | jq -c '.embeddings[0]')
vec_b_in_batch=$(echo "$resp" | jq -c '.embeddings[1]')
sim_a=$(cosine_similarity "$vec_a_alone" "$vec_a_in_batch")
sim_b=$(cosine_similarity "$vec_b_alone" "$vec_b_in_batch")
if awk -v a="$sim_a" -v b="$sim_b" 'BEGIN{exit !(a>0.99 && b>0.99)}'; then
  pass "/embed preserves input order (position 0/1 match single-text embeddings, similarity=$sim_a/$sim_b)"
else
  fail "/embed does not preserve input order (position 0/1 similarity to single-text embeddings: $sim_a/$sim_b, expected >0.99)"
fi

# --- /embed: empty list ---
resp=$(curl -sf -X POST "$BASE_URL/embed" \
  -H 'Content-Type: application/json' \
  -d '{"texts": []}')
if [ "$(echo "$resp" | jq -c '.embeddings')" = "[]" ]; then
  pass "/embed with empty list returns []"
else
  fail "/embed with empty list did not return []"
fi

# --- /rerank: query + candidates, order + relevance ---
resp=$(curl -sf -X POST "$BASE_URL/rerank" \
  -H 'Content-Type: application/json' \
  -d '{"query": "copy a file", "candidates": ["the copy module transfers files", "the apt module manages packages"]}')
if [ -z "$resp" ]; then
  fail "/rerank (batch) request failed"
else
  count=$(echo "$resp" | jq '.scores | length')
  s0=$(echo "$resp" | jq '.scores[0]')
  s1=$(echo "$resp" | jq '.scores[1]')
  if [ "$count" = "2" ] && awk -v a="$s0" -v b="$s1" 'BEGIN{exit !(a>b)}'; then
    pass "/rerank returns 2 scores, in order, relevant candidate scores higher"
  else
    fail "/rerank shape/ordering mismatch (count=$count scores=[$s0, $s1])"
  fi
fi

# --- /rerank: empty candidate list ---
resp=$(curl -sf -X POST "$BASE_URL/rerank" \
  -H 'Content-Type: application/json' \
  -d '{"query": "copy a file", "candidates": []}')
if [ "$(echo "$resp" | jq -c '.scores')" = "[]" ]; then
  pass "/rerank with empty candidates returns []"
else
  fail "/rerank with empty candidates did not return []"
fi

echo ""
if [ "$failures" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "$failures check(s) failed."
  exit 1
fi
