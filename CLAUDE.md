# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Bash TUI launcher for [llama.cpp](https://github.com/ggerganov/llama.cpp) on AMD GPUs via ROCm. `start_llm.sh` is the interactive launcher; `bench_all.sh` is the benchmark suite.

## Project structure

```
billybitcoins-llm-launcher/
├── config.sh        # All shared config: hardware constants, paths, model registry
├── start_llm.sh     # Interactive TUI: mode → model → server → active menu
├── bench_all.sh     # Benchmark suite: runs llama-bench on all models
└── lib/
    ├── ui.sh        # TUI helpers: print_banner, read_key, show_model_table
    └── server.sh    # Server helpers: cleanup trap, launch_server()
```

Both `start_llm.sh` and `bench_all.sh` source `config.sh` and the relevant `lib/` files at startup.

## Running

```bash
./start_llm.sh      # Interactive TUI: pick network mode → pick model → server starts
./bench_all.sh      # Benchmark all registered models; saves results to bench_results.cache
```

## System dependencies (not in this repo)

- `./build/bin/llama-server` and `./build/bin/llama-bench` — llama.cpp built with ROCm (`-DGGML_HIPBLAS=ON`)
- `/mnt/Files/Models/*.gguf` — GGUF model files (symlinked as `./models`)
- ROCm installation at `ROCM_PATH` (default: `/opt/rocm-7.2.0`)

### Model storage

Model files live at `/mnt/Files/Models/` (outside the repo). The project has a `./models` symlink pointing there. Both paths are gitignored.

To set up on a new machine:
```bash
mkdir -p /mnt/Files/Models
ln -s /mnt/Files/Models ./models
```

## Hardware-specific constants (must be updated per machine)

All machine-specific values are in `config.sh`:

| Variable | Default | How to find yours |
|---|---|---|
| `HSA_OVERRIDE_GFX_VERSION` | `11.0.0` (RX 7700 XT / gfx1101) | `rocminfo \| grep gfx` |
| `ROCM_PATH` | `/opt/rocm-7.2.0` | `ls /opt/ \| grep rocm` |
| `TAILSCALE_IP` | `100.84.150.97` | `tailscale ip` |
| `PORT` | `8012` | — |

## Model registry

The `MODELS` array is defined **once** in `config.sh`. Format:

```bash
"display_name|filename.gguf|gpu_layers|notes"
```

- `gpu_layers`: passed to `--n-gpu-layers`; use `$ALL_LAYERS` (999) to offload everything
- Adding/removing a model requires editing this array in `config.sh` only — both scripts pick it up automatically

## Benchmark cache

`bench_results.cache` is written by `bench_all.sh` and read by `start_llm.sh` on startup. Format:

```
# last run: YYYY-MM-DD HH:MM
filename.gguf|PP_value|TG_value
```

The cache is machine-specific and excluded from version control (`.gitignore`).

## Key implementation details

- **Health check loop** (`lib/server.sh` → `launch_server()`): polls `http://$HOST:$PORT/health` every 2 seconds with a `POLL_TIMEOUT=150s` ceiling; crashes are detected via `kill -0 $SERVER_PID`
- **Cleanup trap** (`lib/server.sh`): `SIGINT`/`SIGTERM` always kills `$SERVER_PID` on exit
- **Navigation**: ESC at Step 1 exits; ESC at Step 2 goes back to Step 1; ESC/choice 4 at Step 4 stops the server and returns to Step 2
- **Server log**: stdout/stderr from `llama-server` goes to `$LOG_FILE` (`./llama_server.log`); last 30 lines shown on crash
- **opencode integration**: Step 4 option 2 launches `opencode-cli` with `OPENAI_BASE_URL` and `OPENAI_API_KEY=local` pointed at the running server
