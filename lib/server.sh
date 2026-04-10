#!/bin/bash
# ============================================================
#   BillyBitcoins LLM Launcher — Server Management
#   Sourced by start_llm.sh. Do not run directly.
# ============================================================

SERVER_PID=""

cleanup() {
    echo ""
    echo "  Shutting down..."
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM


# ---- launch_server MODEL_PATH HOST -------------------------
# Starts llama-server, polls /health until ready or timeout.
# Reads globals: PORT, LAYERS, CTX, THREADS, LOG_FILE,
#                POLL_TIMEOUT, EXTRA_FLAGS, BUILD_DIR
# Sets global:   SERVER_PID
# Returns:       0 on success, 1 on failure
launch_server() {
    local model_path="$1" host="$2"

    "$BUILD_DIR/llama-server" \
        -m "$model_path" \
        --host "$host" \
        --port "$PORT" \
        --n-gpu-layers "$LAYERS" \
        --ctx-size "$CTX" \
        --flash-attn on \
        --jinja \
        --threads "$THREADS" \
        --no-warmup \
        "${EXTRA_FLAGS[@]}" > "$LOG_FILE" 2>&1 &

    SERVER_PID=$!

    echo "  Loading model into VRAM — this usually takes 30–90 seconds..."
    printf "  "

    local elapsed=0
    until curl -s --fail "http://$host:$PORT/health" | grep -q '{"status":"ok"}'; do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo ""
            echo "  ✗  Server crashed on startup. Last 30 lines of $LOG_FILE:"
            echo ""
            tail -n 30 "$LOG_FILE"
            SERVER_PID=""
            return 1
        fi
        if (( elapsed >= POLL_TIMEOUT )); then
            echo ""
            echo "  ✗  Timed out after ${POLL_TIMEOUT}s. Check $LOG_FILE for details."
            kill "$SERVER_PID" 2>/dev/null
            SERVER_PID=""
            return 1
        fi
        printf "·"
        sleep 2
        (( elapsed += 2 ))
    done
    return 0
}
