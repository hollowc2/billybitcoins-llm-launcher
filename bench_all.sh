#!/bin/bash
# ============================================================
#   BillyBitcoins LLM Launcher — Benchmark Suite
#   Runs llama-bench across all models and prints a summary
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib/ui.sh"


# ---- Helpers -----------------------------------------------
parse_ts() {
    echo "$1" | grep -oP '[\d]+\.[\d]+(?=\s*±)' | head -1
}

bar() {
    local val=$1 max=$2 width=20
    local filled=$(echo "$val $max $width" | awk '{printf "%d", ($1/$2)*$3}')
    local empty=$(( width - filled ))
    printf '%0.s█' $(seq 1 $filled) 2>/dev/null
    printf '%0.s░' $(seq 1 $empty) 2>/dev/null
}

# ---- Results storage ---------------------------------------
declare -a RES_NAME RES_FILE RES_SIZE RES_NGL RES_PP RES_TG RES_NOTE RES_STATUS

print_banner \
    "BillyBitcoins LLM Launcher — Benchmark Suite" \
    "Settings  :  Prompt $PROMPT_TOKENS tokens  |  Generate $GEN_TOKENS tokens  |  $REPETITIONS runs avg"


# ============================================================
#   RUN BENCHMARKS
# ============================================================
idx=0
for entry in "${MODELS[@]}"; do
    IFS='|' read -r name file layers notes <<< "$entry"
    model_path="$MODELS_DIR/$file"

    echo "  [$((idx+1))/${#MODELS[@]}]  $name"

    if [ ! -f "$model_path" ]; then
        echo "         ✗  Skipped — file not found: $file"
        echo ""
        RES_NAME[$idx]="$name"
        RES_FILE[$idx]="$file"
        RES_NGL[$idx]="$layers"
        RES_NOTE[$idx]="$notes"
        RES_SIZE[$idx]="—"
        RES_PP[$idx]="—"
        RES_TG[$idx]="—"
        RES_STATUS[$idx]="missing"
        (( idx++ ))
        continue
    fi

    size_bytes=$(stat -c%s "$model_path" 2>/dev/null)
    size_gb=$(echo "$size_bytes" | awk '{printf "%.1f GB", $1/1073741824}')

    echo "         Size: $size_gb  |  GPU layers: $layers"
    echo -n "         Running benchmark "

    raw_output=$(
        "$BUILD_DIR/llama-bench" \
            -m "$model_path" \
            -ngl "$layers" \
            -p "$PROMPT_TOKENS" \
            -n "$GEN_TOKENS" \
            -r "$REPETITIONS" \
            -t "$THREADS" \
            -fa 1 \
            --no-warmup \
            -o md 2>/dev/null
    )

    echo "  done."

    pp_line=$(echo "$raw_output" | grep "pp${PROMPT_TOKENS}")
    tg_line=$(echo "$raw_output" | grep "tg${GEN_TOKENS}")

    pp_ts=$(parse_ts "$pp_line")
    tg_ts=$(parse_ts "$tg_line")

    [ -z "$pp_ts" ] && pp_ts="err"
    [ -z "$tg_ts" ] && tg_ts="err"

    RES_NAME[$idx]="$name"
    RES_FILE[$idx]="$file"
    RES_NGL[$idx]="$layers"
    RES_NOTE[$idx]="$notes"
    RES_SIZE[$idx]="$size_gb"
    RES_PP[$idx]="$pp_ts"
    RES_TG[$idx]="$tg_ts"
    RES_STATUS[$idx]="ok"

    echo "         PP (prompt)  :  ${pp_ts} t/s"
    echo "         TG (generate):  ${tg_ts} t/s"
    echo ""
    (( idx++ ))
done


# ============================================================
#   RESULTS TABLE
# ============================================================

max_tg=1
for i in "${!RES_TG[@]}"; do
    v="${RES_TG[$i]}"
    [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] && max_tg=$(echo "$v $max_tg" | awk '{print ($1>$2)?$1:$2}')
done

max_pp=1
for i in "${!RES_PP[@]}"; do
    v="${RES_PP[$i]}"
    [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] && max_pp=$(echo "$v $max_pp" | awk '{print ($1>$2)?$1:$2}')
done

echo ""
echo "  ══════════════════════════════════════════════════════════════════════════════════════════"
echo "  BENCHMARK RESULTS"
echo "  ══════════════════════════════════════════════════════════════════════════════════════════"
printf "\n"
printf "  %-26s  %7s  %4s  %10s  %-22s  %10s  %-22s\n" \
    "Model" "Size" "NGL" "PP t/s" "Prompt speed" "TG t/s" "Generation speed"
printf "  %-26s  %7s  %4s  %10s  %-22s  %10s  %-22s\n" \
    "─────────────────────────" "───────" "────" "──────────" "──────────────────────" "──────────" "──────────────────────"

for i in "${!RES_NAME[@]}"; do
    name="${RES_NAME[$i]}"
    size="${RES_SIZE[$i]}"
    ngl="${RES_NGL[$i]}"
    pp="${RES_PP[$i]}"
    tg="${RES_TG[$i]}"
    status="${RES_STATUS[$i]}"

    if [ "$status" = "missing" ]; then
        printf "  %-26s  %7s  %4s  %10s  %-22s  %10s  %-22s\n" \
            "$name" "—" "$ngl" "—" "(file not found)" "—" ""
        continue
    fi

    pp_bar=""; tg_bar=""
    [[ "$pp" =~ ^[0-9]+(\.[0-9]+)?$ ]] && pp_bar=$(bar "$pp" "$max_pp")
    [[ "$tg" =~ ^[0-9]+(\.[0-9]+)?$ ]] && tg_bar=$(bar "$tg" "$max_tg")

    printf "  %-26s  %7s  %4s  %10s  %-22s  %10s  %-22s\n" \
        "$name" "$size" "$ngl" "${pp} t/s" "$pp_bar" "${tg} t/s" "$tg_bar"
done

printf "\n"
echo "  ──────────────────────────────────────────────────────────────────────────────────────────"
echo "  PP = prompt processing (ingesting your input)"
echo "  TG = token generation  (what you feel as response speed)"
echo "  Bar charts normalized to fastest result."
echo "  ══════════════════════════════════════════════════════════════════════════════════════════"
echo ""


# ============================================================
#   WINNER CALLOUT
# ============================================================
best_tg_idx=0
best_tg_val=0
for i in "${!RES_TG[@]}"; do
    v="${RES_TG[$i]}"
    if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        if (( $(echo "$v > $best_tg_val" | bc -l) )); then
            best_tg_val="$v"
            best_tg_idx=$i
        fi
    fi
done

if [[ "$best_tg_val" != "0" ]]; then
    echo "  Fastest generation  →  ${RES_NAME[$best_tg_idx]}  at  ${best_tg_val} t/s"
    echo "  ${RES_NOTE[$best_tg_idx]}"
    echo ""
fi


# ============================================================
#   SAVE CACHE
# ============================================================
{
    echo "# last run: $(date '+%Y-%m-%d %H:%M')"
    for i in "${!RES_FILE[@]}"; do
        echo "${RES_FILE[$i]}|${RES_PP[$i]}|${RES_TG[$i]}"
    done
} > "$BENCH_CACHE"

echo "  Results saved to $BENCH_CACHE"
echo ""
