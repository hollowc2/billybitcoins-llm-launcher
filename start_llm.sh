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

    # ── STEP 1 — Choose connection mode ──────────────────────
    echo ""
    echo "  ─────────────────────────────────────────────────────"
    echo "  STEP 1  —  How do you want to connect?"
    echo "  ─────────────────────────────────────────────────────"
    echo ""
    echo "    1)  Local           Start a server on this machine  (127.0.0.1)"
    echo "    2)  Tailscale       Start a server, accessible over your VPN"
    echo "    3)  Custom URL      Connect to a server that's already running"
    echo "    4)  Benchmarks      Test all model speeds and save results  (~4 min)"
    echo ""
    echo "  Press ESC to quit"
    echo ""
    read_key "  Your choice [1-4]: "
    echo ""

    [[ "$KEY" == $'\033' ]] && { echo "  GG."; exit 0; }

    CUSTOM_URL_MODE=false
    CONNECT_URL=""
    CONNECT_BASE=""
    CONNECT_ROOT=""

    case $KEY in
        1)
            HOST="127.0.0.1"
            MODE_DESC="Local (127.0.0.1)"
            ;;
        2)
            echo "  Enter your Tailscale IP address  (e.g. 100.x.x.x):"
            printf "  > "
            read -r TAILSCALE_IP
            if [[ -z "$TAILSCALE_IP" ]]; then
                echo "  No IP entered — going back."
                echo ""
                continue
            fi
            HOST="$TAILSCALE_IP"
            MODE_DESC="Tailscale ($TAILSCALE_IP)"
            ;;
        3)
            CUSTOM_URL_MODE=true
            DEFAULT_URL="http://127.0.0.1:${PORT}/v1/chat/completions"
            echo "  Enter the full URL of your already-running LLM server."
            printf "  Press Enter to use the default: %s\n" "$DEFAULT_URL"
            printf "  > "
            read -r input_url
            CONNECT_URL="${input_url:-$DEFAULT_URL}"
            # Strip /chat/completions to get base URL, then strip /v1 for root
            CONNECT_BASE="${CONNECT_URL%/chat/completions}"
            CONNECT_ROOT="${CONNECT_BASE%/v1}"
            MODE_DESC="Custom ($CONNECT_URL)"
            echo ""
            ;;
        4)
            "$SCRIPT_DIR/bench_all.sh"
            echo "  Restarting launcher with fresh results..."
            sleep 2
            exec "$0"
            ;;
        *)
            echo "  Invalid choice — enter 1, 2, 3, or 4."
            continue
            ;;
    esac


    # ── CUSTOM URL MODE — skip model selection & server launch ─
    if $CUSTOM_URL_MODE; then
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Using server  :  $CONNECT_URL"
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        while true; do
            echo "  ─────────────────────────────────────────────────────"
            echo "  Server  :  $CONNECT_URL"
            echo "             (ESC to go back to Step 1)"
            echo "  ─────────────────────────────────────────────────────"
            echo ""
            echo "    1)  Open Web Chat     Built-in chat interface (opens in browser)"
            echo "    2)  Launch opencode   AI coding assistant in your terminal"
            echo "    3)  API info          Show the endpoint URL and an example curl"
            echo "    4)  Go back           Return to Step 1"
            echo "    5)  Quit"
            echo ""
            read_key "  Your choice [1-5]: "
            echo ""

            if [[ "$KEY" == $'\033' ]] || [[ "$KEY" == "4" ]]; then
                break  # back to main loop (Step 1)
            fi

            case $KEY in
                1)
                    echo "  Opening browser at $CONNECT_ROOT ..."
                    xdg-open "$CONNECT_ROOT" 2>/dev/null || \
                        echo "  Could not open browser. Visit manually: $CONNECT_ROOT"
                    echo ""
                    ;;
                2)
                    if ! command -v opencode-cli &>/dev/null; then
                        echo "  opencode-cli not found in PATH."
                        echo "  Install it at: https://opencode.ai"
                        echo ""
                    else
                        echo "  Launching opencode → $CONNECT_BASE"
                        echo ""
                        OPENAI_BASE_URL="$CONNECT_BASE" \
                        OPENAI_API_KEY="local" \
                        opencode-cli
                        echo ""
                    fi
                    ;;
                3)
                    echo "  Chat endpoint  :  $CONNECT_URL"
                    echo "  Base URL       :  $CONNECT_BASE"
                    echo ""
                    echo "  Example — send a message from the terminal:"
                    printf "    curl %s \\\\\n" "$CONNECT_URL"
                    echo "      -H 'Content-Type: application/json' \\"
                    echo "      -d '{\"model\":\"local\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"
                    echo ""
                    ;;
                5)
                    echo "  GG."
                    exit 0
                    ;;
                *)
                    echo "  Invalid choice."
                    echo ""
                    ;;
            esac
        done
        continue  # back to main loop (Step 1)
    fi


    # ── MODEL LOOP — ESC here goes back to Step 1 ────────────
    while true; do

        echo ""
        echo "  ─────────────────────────────────────────────────────"
        echo "  STEP 2  —  Pick a model"
        echo "             Mode: $MODE_DESC   (ESC to go back)"
        echo "  ─────────────────────────────────────────────────────"
        echo ""
        show_model_table
        echo ""
        read_key "  Your choice [1-${#MODELS[@]}]: "
        echo ""

        [[ "$KEY" == $'\033' ]] && break   # back to Step 1

        if ! [[ "$KEY" =~ ^[1-9]$ ]] || (( KEY < 1 || KEY > ${#MODELS[@]} )); then
            echo "  Invalid choice — enter a number between 1 and ${#MODELS[@]}."
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
            echo "  Model file not found: $MODEL_PATH"
            echo "  Check that the file exists and MODELS_DIR in config.sh points to the right folder."
            continue
        fi

        # ── STEP 3 — Launch server ───────────────────────────
        pp="${BENCH_PP[$MODEL_FILE]:-}"
        tg="${BENCH_TG[$MODEL_FILE]:-}"

        echo "  ─────────────────────────────────────────"
        echo "  Starting   :  $MODEL_NAME"
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

        BASE_URL="http://$HOST:$PORT/v1"
        CHAT_URL="$BASE_URL/chat/completions"

        echo ""
        echo ""
        echo "  ✓  Server is ready!"
        echo ""
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Model      :  $MODEL_NAME"
        echo "  Chat URL   :  $CHAT_URL"
        echo "  Base URL   :  $BASE_URL"
        echo "  Log file   :  $LOG_FILE"
        echo "  Server PID :  $SERVER_PID"
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # ── UI LOOP — ESC here kills server & goes back to Step 2
        while true; do

            echo "  ─────────────────────────────────────────────────────"
            echo "  STEP 4  —  Server running: $MODEL_NAME"
            echo "             (ESC to change model)"
            echo "  ─────────────────────────────────────────────────────"
            echo ""
            echo "    1)  Open Web Chat     Built-in chat interface (opens in browser)"
            echo "    2)  Launch opencode   AI coding assistant in your terminal"
            echo "    3)  API info          Show how to connect your own client"
            echo "    4)  Change model      Stop this server and pick a different one"
            echo "    5)  Quit"
            echo ""
            read_key "  Your choice [1-5]: "
            echo ""

            if [[ "$KEY" == $'\033' ]] || [[ "$KEY" == "4" ]]; then
                echo "  Stopping $MODEL_NAME..."
                kill "$SERVER_PID" 2>/dev/null
                wait "$SERVER_PID" 2>/dev/null
                SERVER_PID=""
                echo "  Server stopped."
                echo ""
                break   # back to model loop → Step 2
            fi

            case $KEY in
                1)
                    echo "  Opening browser at http://$HOST:$PORT ..."
                    xdg-open "http://$HOST:$PORT" 2>/dev/null || \
                        echo "  Could not open browser. Visit manually: http://$HOST:$PORT"
                    echo ""
                    ;;
                2)
                    if ! command -v opencode-cli &>/dev/null; then
                        echo "  opencode-cli not found in PATH."
                        echo "  Install it at: https://opencode.ai"
                        echo ""
                    else
                        echo "  Launching opencode → $BASE_URL"
                        echo ""
                        OPENAI_BASE_URL="$BASE_URL" \
                        OPENAI_API_KEY="local" \
                        opencode-cli
                        echo ""
                    fi
                    ;;
                3)
                    echo "  Chat endpoint  :  $CHAT_URL"
                    echo "  Base URL       :  $BASE_URL"
                    echo ""
                    echo "  Example — send a message from the terminal:"
                    printf "    curl %s \\\\\n" "$CHAT_URL"
                    echo "      -H 'Content-Type: application/json' \\"
                    echo "      -d '{\"model\":\"local\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"
                    echo ""
                    ;;
                5)
                    echo "  GG."
                    exit 0
                    ;;
                *)
                    echo "  Invalid choice."
                    echo ""
                    ;;
            esac

        done  # UI loop

    done  # model loop

done  # main loop
