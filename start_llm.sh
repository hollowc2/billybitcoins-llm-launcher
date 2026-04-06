#!/bin/bash
# ============================================================
#   BillyBitcoins LLM Launcher
#   RX 7700 XT (12 GB VRAM)  |  ROCm 7.2  |  llama.cpp
# ============================================================

# ---- Paths & Limits ----------------------------------------
MODELS_DIR="./models"
BENCH_CACHE="./bench_results.cache"
ALL_LAYERS=999      # llama-server clamps this to actual layer count
POLL_TIMEOUT=150    # give up waiting for health check after N seconds

# ---- ROCm / GPU Setup --------------------------------------
export ROCM_PATH=/opt/rocm-7.2.0
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH
export HSA_OVERRIDE_GFX_VERSION=11.0.0   # keeps gfx1101 happy

# ---- Network -----------------------------------------------
TAILSCALE_IP="100.84.150.97"
PORT=8012
THREADS=8

# ---- Model registry ----------------------------------------
# Format: "display_name|file|layers|notes"
MODELS=(
    "Qwen2.5-Coder 14B|Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf|40|Best balance of speed & quality"
    "Qwen2.5-Coder 7B|Qwen2.5-Coder-7B-Instruct-Q8_0.gguf|$ALL_LAYERS|Fastest / lightest  (Q8_0)"
    "Qwen3-Coder 30B-A3B|Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf|29|Strongest  (MoE, partial offload)"
    "Qwen3.5 9B Instruct|Qwen3.5-9B-Q5_K_M.gguf|19|Multimodal — text + vision"
    "DeepSeek-Coder-V2-Lite|DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf|$ALL_LAYERS|16B MoE, 2.4B active  (Q4_K_M)"
)

# ---- Load benchmark cache ----------------------------------
declare -A BENCH_PP BENCH_TG
BENCH_DATE=""

if [ -f "$BENCH_CACHE" ]; then
    BENCH_DATE=$(grep "^# last run:" "$BENCH_CACHE" | sed 's/# last run: //')
    while IFS='|' read -r bfile bpp btg; do
        [[ "$bfile" == \#* ]] && continue
        BENCH_PP["$bfile"]="$bpp"
        BENCH_TG["$bfile"]="$btg"
    done < "$BENCH_CACHE"
fi


# ============================================================
#   WELCOME
# ============================================================
clear
echo ""
echo "  ██████╗ ██╗██╗     ██╗  ██╗   ██╗"
echo "  ██╔══██╗██║██║     ██║  ╚██╗ ██╔╝"
echo "  ██████╔╝██║██║     ██║   ╚████╔╝ "
echo "  ██╔══██╗██║██║     ██║    ╚██╔╝  "
echo "  ██████╔╝██║███████╗███████╗██║   "
echo "  ╚═════╝ ╚═╝╚══════╝╚══════╝╚═╝  "
echo ""
echo "  BillyBitcoins LLM Launcher"
echo "  ─────────────────────────────────────────"
echo "  Hardware  :  RX 7700 XT  |  12 GB VRAM"
echo "  Backend   :  ROCm 7.2  +  llama.cpp"
echo "  Endpoint  :  OpenAI-compatible REST API"
echo "  ─────────────────────────────────────────"
echo ""


# ============================================================
#   Helper — read a single keypress; sets KEY, detects ESC
# ============================================================
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


# ============================================================
#   Helper — display model selection table
# ============================================================
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


# ============================================================
#   Cleanup trap — always kills current server on exit
# ============================================================
SERVER_PID=""
cleanup() {
    echo ""
    echo "  Shutting down..."
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM


# ============================================================
#   MAIN LOOP — wraps everything; ESC at Step 1 exits
# ============================================================
while true; do

    # ── STEP 1 — Choose access mode ──────────────────────────
    echo ""
    echo "  STEP 1  —  Where should the server listen?"
    echo "             (ESC to quit)"
    echo ""
    echo "    1)  Local only  —  127.0.0.1  (just this machine)"
    echo "    2)  Tailscale   —  $TAILSCALE_IP  (remote access)"
    echo "    3)  Run benchmark suite  (~4 min)"
    echo ""
    read_key "  Your choice [1/2/3]: "
    echo ""

    [[ "$KEY" == $'\033' ]] && { echo "  GG."; exit 0; }

    case $KEY in
        1)
            HOST="127.0.0.1"
            MODE_DESC="Local (127.0.0.1)"
            ;;
        2)
            HOST="$TAILSCALE_IP"
            MODE_DESC="Tailscale ($TAILSCALE_IP)"
            ;;
        3)
            ./bench_all.sh
            echo "  Restarting launcher with fresh results..."
            sleep 2
            exec "$0"
            ;;
        *)
            echo "  ✗  Invalid choice."
            continue
            ;;
    esac


    # ── MODEL LOOP — ESC here goes back to Step 1 ────────────
    while true; do

        echo ""
        echo "  STEP 2  —  Pick a model  (mode: $MODE_DESC)"
        echo "             (ESC to go back)"
        echo ""
        show_model_table
        echo ""
        read_key "  Your choice [1-${#MODELS[@]}]: "
        echo ""

        [[ "$KEY" == $'\033' ]] && break   # back to Step 1

        if ! [[ "$KEY" =~ ^[1-9]$ ]] || (( KEY < 1 || KEY > ${#MODELS[@]} )); then
            echo "  ✗  Invalid choice."
            continue
        fi

        IFS='|' read -r MODEL_NAME MODEL_FILE LAYERS MODEL_NOTES <<< "${MODELS[$((KEY-1))]}"

        CTX=32768
        EXTRA_FLAGS=()
        EXTRA_NOTE=""

        if [ "$KEY" = "4" ]; then
            EXTRA_NOTE="Vision enabled — pass images via /v1/chat/completions"
        fi

        MODEL_PATH="$MODELS_DIR/$MODEL_FILE"

        if [ ! -f "$MODEL_PATH" ]; then
            echo "  ✗  Model file not found: $MODEL_PATH"
            echo "     Models folder: $(realpath "$MODELS_DIR")"
            continue
        fi

        # ── STEP 3 — Launch server ───────────────────────────
        pp="${BENCH_PP[$MODEL_FILE]:-}"
        tg="${BENCH_TG[$MODEL_FILE]:-}"

        echo "  ─────────────────────────────────────────"
        echo "  Launching  :  $MODEL_NAME"
        echo "  Mode       :  $MODE_DESC"
        echo "  GPU layers :  $LAYERS"
        echo "  Context    :  $CTX tokens"
        echo "  Threads    :  $THREADS"
        if [[ "$pp" =~ ^[0-9]+\.[0-9]+$ ]]; then
            printf "  Speed      :  PP %.0f t/s  |  TG %.0f t/s\n" "$pp" "$tg"
        fi
        [ -n "$EXTRA_NOTE" ] && echo "  Note       :  $EXTRA_NOTE"
        echo "  ─────────────────────────────────────────"
        echo ""

        ./build/bin/llama-server \
            -m "$MODEL_PATH" \
            --host "$HOST" \
            --port "$PORT" \
            --n-gpu-layers "$LAYERS" \
            --ctx-size "$CTX" \
            --flash-attn on \
            --jinja \
            --threads "$THREADS" \
            --no-warmup \
            "${EXTRA_FLAGS[@]}" > llama_server.log 2>&1 &

        SERVER_PID=$!

        echo "  Loading model into VRAM — this usually takes 30–90 seconds..."
        printf "  "

        elapsed=0
        server_ok=true
        until curl -s --fail "http://$HOST:$PORT/health" | grep -q '{"status":"ok"}'; do
            if ! kill -0 "$SERVER_PID" 2>/dev/null; then
                echo ""
                echo "  ✗  Server crashed on startup. Last 30 lines of llama_server.log:"
                echo ""
                tail -n 30 llama_server.log
                server_ok=false
                break
            fi
            if (( elapsed >= POLL_TIMEOUT )); then
                echo ""
                echo "  ✗  Timed out after ${POLL_TIMEOUT}s. Check llama_server.log for details."
                kill "$SERVER_PID" 2>/dev/null
                server_ok=false
                break
            fi
            printf "·"
            sleep 2
            (( elapsed += 2 ))
        done

        if [ "$server_ok" = false ]; then
            SERVER_PID=""
            continue
        fi

        echo ""
        echo ""
        echo "  ✓  Server is live!"
        echo ""
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Model      :  $MODEL_NAME"
        echo "  Base URL   :  http://$HOST:$PORT/v1"
        echo "  Chat API   :  http://$HOST:$PORT/v1/chat/completions"
        echo "  Log        :  ./llama_server.log"
        echo "  PID        :  $SERVER_PID"
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # ── UI LOOP — ESC here kills server & goes back to Step 2
        while true; do

            echo "  STEP 4  —  Active: $MODEL_NAME"
            echo "             (ESC to change model)"
            echo ""
            echo "    1)  Web UI      —  llama.cpp built-in  (opens browser)"
            echo "    2)  opencode    —  TUI coding assistant"
            echo "    3)  Skip        —  API only, connect manually"
            echo "    4)  Change model — unload & pick a new one"
            echo "    5)  Quit"
            echo ""
            read_key "  Your choice [1-5]: "
            echo ""

            if [[ "$KEY" == $'\033' ]] || [[ "$KEY" == "4" ]]; then
                echo "  Unloading $MODEL_NAME..."
                kill "$SERVER_PID" 2>/dev/null
                wait "$SERVER_PID" 2>/dev/null
                SERVER_PID=""
                echo "  Server stopped."
                echo ""
                break   # back to model loop → Step 2
            fi

            case $KEY in
                1)
                    echo "  Opening built-in Web UI..."
                    xdg-open "http://$HOST:$PORT" 2>/dev/null || \
                        echo "  ✗  xdg-open not found. Visit: http://$HOST:$PORT"
                    echo ""
                    ;;
                2)
                    if ! command -v opencode-cli &>/dev/null; then
                        echo "  ✗  opencode-cli not found in PATH."
                        echo "     Install it: https://opencode.ai"
                        echo ""
                    else
                        echo "  Launching opencode-cli → http://$HOST:$PORT/v1"
                        echo ""
                        OPENAI_BASE_URL="http://$HOST:$PORT/v1" \
                        OPENAI_API_KEY="local" \
                        opencode-cli
                        echo ""
                    fi
                    ;;
                3)
                    echo "  API is live at http://$HOST:$PORT/v1"
                    echo ""
                    ;;
                5)
                    echo "  GG."
                    exit 0
                    ;;
                *)
                    echo "  ✗  Invalid choice."
                    echo ""
                    ;;
            esac

        done  # UI loop

    done  # model loop

done  # main loop
