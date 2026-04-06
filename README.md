# BillyBitcoins LLM Launcher

Interactive TUI launcher for [llama.cpp](https://github.com/ggerganov/llama.cpp) on AMD GPUs via ROCm. Pick a model, pick a network mode, and get an OpenAI-compatible REST endpoint running in seconds. Includes a benchmark suite that caches results and displays them alongside your model list.

```
  ██████╗ ██╗██╗     ██╗  ██╗   ██╗
  ██╔══██╗██║██║     ██║  ╚██╗ ██╔╝
  ██████╔╝██║██║     ██║   ╚████╔╝
  ██╔══██╗██║██║     ██║    ╚██╔╝
  ██████╔╝██║███████╗███████╗██║
  ╚═════╝ ╚═╝╚══════╝╚══════╝╚═╝
```

## Hardware

Developed and tested on:
- GPU: RX 7700 XT (12 GB VRAM)
- Backend: ROCm 7.2 + llama.cpp

## Prerequisites

1. **llama.cpp** built with ROCm support:
   ```bash
   cmake -B build -DGGML_HIPBLAS=ON
   cmake --build build --config Release -j$(nproc)
   ```

2. **Models** placed in a `models/` directory next to the scripts (GGUF format):
   ```
   LLMLauncher/
   ├── models/
   │   ├── Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf
   │   └── ...
   ├── start_llm.sh
   └── bench_all.sh
   ```

3. **llama-server** and **llama-bench** binaries available at `./build/bin/`

## Usage

**Launch the server:**
```bash
./start_llm.sh
```
- Step 1: Choose network mode (local or Tailscale)
- Step 2: Pick a model from the registry
- The server starts and waits for a health check before confirming it's ready

**Run benchmarks:**
```bash
./bench_all.sh
```
Runs `llama-bench` across all registered models and saves results to `bench_results.cache`. The launcher reads this cache and shows PP/TG token speeds alongside each model in the selection table.

## Model Registry

Both scripts share a `MODELS` array. To add or remove models, edit this block near the top of each file:

```bash
# Format: "display_name|file|layers|notes"
MODELS=(
    "Qwen2.5-Coder 14B|Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf|40|Best balance of speed & quality"
    "My New Model|my-model-Q4_K_M.gguf|32|Some notes"
)
```

- `layers` controls `--n-gpu-layers` (use `999` to offload everything)
- Both scripts must be kept in sync

## Configuration

Two values are hardcoded and **must be updated** to match your system:

### `HSA_OVERRIDE_GFX_VERSION=11.0.0`
Set near the top of both scripts. This is the GFX version string for the RX 7700 XT (gfx1101). Other AMD GPUs require a different value. Find yours with:
```bash
rocminfo | grep gfx
```
Then set the override accordingly, e.g. `10.3.0` for an RX 6000-series card.

### `ROCM_PATH=/opt/rocm-7.2.0`
Also set near the top of both scripts. Update this to your actual ROCm installation path. Check with:
```bash
ls /opt/ | grep rocm
```

## Benchmark Cache

After running `bench_all.sh`, results are saved to `bench_results.cache`. The launcher reads this on startup and shows prompt-processing (PP) and token-generation (TG) speeds in the model selection table.

- **PP** — how fast the GPU ingests your prompt (tokens/sec)
- **TG** — how fast tokens stream back to you (tokens/sec)

The cache is machine-specific and excluded from version control.
