#!/bin/bash
# ============================================================
#   BillyBitcoins LLM Launcher
#   RX 7700 XT (12 GB VRAM)  |  ROCm 7.2  |  llama.cpp
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/server.sh"


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

print_banner "BillyBitcoins LLM Launcher" "Endpoint  :  OpenAI-compatible REST API"


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
            "$SCRIPT_DIR/bench_all.sh"
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

        if ! launch_server "$MODEL_PATH" "$HOST"; then
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
        echo "  Log        :  $LOG_FILE"
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
