#!/bin/bash
# ============================================================
#   BillyBitcoins LLM Launcher — TUI Helpers
#   Sourced by start_llm.sh and bench_all.sh. Do not run directly.
# ============================================================


# ---- print_banner SUBTITLE INFO_LINE -----------------------
# Clears screen and prints the ASCII logo + header block.
# SUBTITLE  : title line, e.g. "BillyBitcoins LLM Launcher"
# INFO_LINE  : third info row, e.g. "Endpoint  :  OpenAI-compatible REST API"
print_banner() {
    local subtitle="${1:-BillyBitcoins LLM Launcher}"
    local info_line="${2:-Endpoint  :  OpenAI-compatible REST API}"
    clear
    echo ""
    echo "  ██████╗ ██╗██╗     ██╗  ██╗   ██╗"
    echo "  ██╔══██╗██║██║     ██║  ╚██╗ ██╔╝"
    echo "  ██████╔╝██║██║     ██║   ╚████╔╝ "
    echo "  ██╔══██╗██║██║     ██║    ╚██╔╝  "
    echo "  ██████╔╝██║███████╗███████╗██║   "
    echo "  ╚═════╝ ╚═╝╚══════╝╚══════╝╚═╝  "
    echo ""
    echo "  $subtitle"
    echo "  ─────────────────────────────────────────────────────"
    echo "  Hardware  :  RX 7700 XT  |  12 GB VRAM"
    echo "  Backend   :  ROCm 7.2  +  llama.cpp"
    echo "  $info_line"
    echo "  ─────────────────────────────────────────────────────"
    echo ""
}


# ---- read_key PROMPT ---------------------------------------
# Reads a single keypress into $KEY. Detects ESC sequences.
read_key() {
    local prompt="$1"
    printf "%s" "$prompt"
    IFS= read -rsn1 KEY
    if [[ "$KEY" == $'\033' ]]; then
        read -rsn2 -t 0.05 2>/dev/null   # drain arrow-key sequences
        printf "  ←\n"
        KEY=$'\033'
    else
        printf "%s\n" "$KEY"
    fi
}


# ---- show_model_table --------------------------------------
# Displays the model selection table. If benchmark data is loaded
# (BENCH_DATE, BENCH_PP, BENCH_TG), shows speed columns.
# Reads globals: MODELS, BENCH_DATE, BENCH_PP, BENCH_TG
show_model_table() {
    if [ -n "$BENCH_DATE" ]; then
        echo "  Benchmark data from $BENCH_DATE"
        echo "  ─────────────────────────────────────────────────────────────────────────────────────────"
        printf "   %-2s  %-24s  %10s  %9s  %s\n" "#" "Model" "PP prompt" "TG gen" "Notes"
        echo "  ─────────────────────────────────────────────────────────────────────────────────────────"
        local num=1
        for entry in "${MODELS[@]}"; do
            IFS='|' read -r name file layers notes <<< "$entry"
            local pp="${BENCH_PP[$file]:-}"
            local tg="${BENCH_TG[$file]:-}"
            if [[ "$pp" =~ ^[0-9]+\.[0-9]+$ ]] && [[ "$tg" =~ ^[0-9]+\.[0-9]+$ ]]; then
                pp_disp=$(printf "%.0f t/s" "$pp")
                tg_disp=$(printf "%.0f t/s" "$tg")
            else
                pp_disp="—"
                tg_disp="—"
            fi
            printf "   %-2s  %-24s  %10s  %9s  %s\n" "$num)" "$name" "$pp_disp" "$tg_disp" "$notes"
            (( num++ ))
        done
        echo "  ─────────────────────────────────────────────────────────────────────────────────────────"
        echo "  PP = how fast it reads your prompt   |   TG = tokens you see streamed back"
    else
        echo "  ─────────────────────────────────────────────────────────────────────────────────────────"
        printf "   %-2s  %-24s  %s\n" "#" "Model" "Notes"
        echo "  ─────────────────────────────────────────────────────────────────────────────────────────"
        local num=1
        for entry in "${MODELS[@]}"; do
            IFS='|' read -r name file layers notes <<< "$entry"
            printf "   %-2s  %-24s  %s\n" "$num)" "$name" "$notes"
            (( num++ ))
        done
        echo "  ─────────────────────────────────────────────────────────────────────────────────────────"
        echo "  No benchmark data — run option 'b' from the mode menu to generate it."
    fi
}
