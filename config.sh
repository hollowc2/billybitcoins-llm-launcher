#!/bin/bash
# ============================================================
#   BillyBitcoins LLM Launcher — Shared Configuration
#   Sourced by start_llm.sh and bench_all.sh. Do not run directly.
# ============================================================

# ---- Hardware — update these per machine -------------------
export ROCM_PATH=/opt/rocm-7.2.0
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH
export HSA_OVERRIDE_GFX_VERSION=11.0.0   # keeps gfx1101 happy (RX 7700 XT)

# ---- Network -----------------------------------------------
TAILSCALE_IP="100.84.150.97"
PORT=8012

# ---- Paths -------------------------------------------------
MODELS_DIR="/mnt/Files/Models"
BUILD_DIR="./build/bin"
BENCH_CACHE="./bench_results.cache"
LOG_FILE="./llama_server.log"

# ---- Server defaults ---------------------------------------
THREADS=8
CTX=32768
ALL_LAYERS=999      # llama-server clamps this to actual layer count
POLL_TIMEOUT=150    # give up waiting for health check after N seconds

# ---- Benchmark defaults ------------------------------------
REPETITIONS=3
PROMPT_TOKENS=512
GEN_TOKENS=128

# ---- Model registry ----------------------------------------
# Format: "display_name|filename.gguf|gpu_layers|notes"
# Use $ALL_LAYERS to offload all layers to GPU.
# Adding/removing a model only requires editing this one array.
MODELS=(
    "Qwen2.5-Coder 14B|Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf|40|Best balance of speed & quality"
    "Qwen2.5-Coder 7B|Qwen2.5-Coder-7B-Instruct-Q8_0.gguf|$ALL_LAYERS|Fastest / lightest  (Q8_0)"
    "Qwen3-Coder 30B-A3B|Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf|29|Strongest  (MoE, partial offload)"
    "Qwen3.5 9B Instruct|Qwen3.5-9B-Q5_K_M.gguf|19|Multimodal — text + vision"
    "DeepSeek-Coder-V2-Lite|DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf|$ALL_LAYERS|16B MoE, 2.4B active  (Q4_K_M)"
)
