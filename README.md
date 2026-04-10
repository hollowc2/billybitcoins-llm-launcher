# BillyBitcoins LLM Launcher

Interactive TUI launcher for [llama.cpp](https://github.com/ggerganov/llama.cpp) on AMD GPUs via ROCm. Pick a connection mode, pick a model, and get an OpenAI-compatible REST endpoint running in seconds. Includes a benchmark suite that caches results and displays PP/TG speeds alongside each model.

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

## Project Structure

```
billybitcoins-llm-launcher/
├── config.sh        # All shared config: hardware constants, paths, model registry
├── start_llm.sh     # Interactive TUI: mode → model → server → active menu
├── bench_all.sh     # Benchmark suite: runs llama-bench on all registered models
└── lib/
    ├── ui.sh        # TUI helpers: print_banner, read_key, show_model_table
    └── server.sh    # Server helpers: cleanup trap, launch_server()
```

## Prerequisites

1. **llama.cpp** built with ROCm support. Set `BUILD_DIR` in `config.sh` to your build output path:
   ```bash
   cmake -B build -DGGML_HIPBLAS=ON
   cmake --build build --config Release -j$(nproc)
   ```

2. **Models** in GGUF format at `MODELS_DIR` (default: `/mnt/Files/Models`). The repo expects a `./models` symlink:
   ```bash
   mkdir -p /mnt/Files/Models
   ln -s /mnt/Files/Models ./models
   ```

3. **ROCm** installed at `ROCM_PATH` (default: `/opt/rocm-7.2.0`).

## Usage

**Launch the server:**
```bash
./start_llm.sh
```

The TUI walks through four steps:

| Step | What happens |
|------|-------------|
| 1 | Choose how to connect — see options below |
| 2 | Pick a model from the registry (PP/TG speeds shown if cache exists) |
| 3 | Server launches; health-check loop polls `/health` until ready |
| 4 | Active menu: open Web Chat, launch opencode, view API info, change model, or quit |

**Navigation:** ESC at Step 1 exits. ESC at Step 2 returns to Step 1. ESC or choice 4 at Step 4 stops the server and returns to Step 2.

### Step 1 — Connection modes

| Option | What it does |
|--------|-------------|
| **1 — Local** | Starts a server on `127.0.0.1` (only accessible from this machine) |
| **2 — Tailscale** | Starts a server bound to your Tailscale IP (accessible over your VPN) |
| **3 — Custom URL** | Skips server launch — connects to a server that's already running at a URL you enter. Defaults to `http://127.0.0.1:8012/v1/chat/completions` |
| **4 — Benchmarks** | Runs `llama-bench` across all models and saves results to cache (~4 min) |

**Run benchmarks separately:**
```bash
./bench_all.sh
```

Runs `llama-bench` across all registered models and saves results to `bench_results.cache`. The launcher reads this cache on startup and shows PP/TG token speeds in the model table. You can also trigger this from Step 1 (choice 4).

## Configuration

All machine-specific values live in `config.sh`:

| Variable | Default | How to find yours |
|---|---|---|
| `HSA_OVERRIDE_GFX_VERSION` | `11.0.0` (RX 7700 XT / gfx1101) | `rocminfo \| grep gfx` |
| `ROCM_PATH` | `/opt/rocm-7.2.0` | `ls /opt/ \| grep rocm` |
| `BUILD_DIR` | `/home/corey/Desktop/llama.cpp/build/bin` | path to your llama.cpp build |
| `PORT` | `8012` | change to any free port |

## Model Registry

The `MODELS` array is defined **once** in `config.sh` and picked up automatically by both scripts. Format:

```bash
# "display_name|filename.gguf|gpu_layers|notes"
MODELS=(
    "My Model|my-model-Q4_K_M.gguf|32|Some notes"
)
```

- `gpu_layers` is passed to `--n-gpu-layers`; use `999` (or the `$ALL_LAYERS` constant) to offload everything to GPU
- Adding or removing a model only requires editing this array — no other files need to change

Current models:

| Name | File | GPU Layers | Notes |
|------|------|-----------|-------|
| Qwen2.5-Coder 14B | `Qwen2.5-Coder-14B-Instruct-Q5_K_M.gguf` | 40 | Best balance of speed & quality |
| Qwen2.5-Coder 7B | `Qwen2.5-Coder-7B-Instruct-Q8_0.gguf` | all | Fastest / lightest (Q8_0) |
| Qwen3-Coder 30B-A3B | `Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf` | 29 | Strongest (MoE, partial offload) |
| Qwen3.5 9B Instruct | `Qwen3.5-9B-Q5_K_M.gguf` | 19 | Multimodal — text + vision |
| DeepSeek-Coder-V2-Lite | `DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf` | all | 16B MoE, 2.4B active (Q4_K_M) |

## Benchmark Cache

After running `bench_all.sh`, results are saved to `bench_results.cache`:

```
# last run: YYYY-MM-DD HH:MM
filename.gguf|PP_value|TG_value
```

- **PP** — prompt-processing speed (tokens/sec): how fast the GPU reads your input
- **TG** — token-generation speed (tokens/sec): how fast tokens stream back to you

The cache is machine-specific and excluded from version control.

## Connecting Your Own Client

When a server is running, the API endpoint is OpenAI-compatible. You can point any OpenAI client at it:

```bash
# Quick test from the terminal
curl http://127.0.0.1:8012/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"local","messages":[{"role":"user","content":"Hello!"}]}'
```

Set these environment variables in any app that supports OpenAI-compatible APIs:
```
OPENAI_BASE_URL=http://127.0.0.1:8012/v1
OPENAI_API_KEY=local
```

## opencode Integration

Step 4 option 2 launches [opencode](https://opencode.ai) pointed at the running server:

```bash
OPENAI_BASE_URL="http://$HOST:$PORT/v1" OPENAI_API_KEY="local" opencode-cli
```

Requires `opencode-cli` in `PATH`.
