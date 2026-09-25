# Bonsai 2 27B (ternary GGUF) — Dokploy Docker Compose

Serves `prism-ml/Ternary-Bonsai-2-27B-gguf` behind an OpenAI-compatible API
(`llama-server`), using PrismML's own llama.cpp fork — required because the
ternary PQ2_0/PTQ1_0 packing needs a Hadamard-transform kernel that isn't in
stock llama.cpp yet. Using an unpatched image will either refuse to load the
file or silently output garbage.

## Files

- `Dockerfile` — builds an image around the PrismML llama.cpp fork's prebuilt binaries
- `entrypoint.sh` — downloads the GGUF into `/models` on first boot (cached after that), then starts `llama-server`
- `docker-compose.yml` — CPU-only deployment (works on any Dokploy VPS, no GPU needed)
- `docker-compose.gpu.yml` — NVIDIA GPU deployment (needs `nvidia-container-toolkit` on the host)

## Deploying on Dokploy

1. Push this folder to a git repo Dokploy can access (or paste the compose file directly).
2. In Dokploy: **Create Service → Docker Compose**, point it at the repo.
3. If you want the GPU variant, set the compose file path to `docker-compose.gpu.yml` in the service's Advanced settings (default is `docker-compose.yml`, the CPU build).
4. Set environment variables in Dokploy's UI if you want to override the defaults below.
5. Expose port `8080` via a Dokploy domain/proxy, or leave it internal and call it from other services on the same network.
6. Deploy. First boot downloads the ~7.2 GB model into the `bonsai_models` volume — watch the logs; this can take a few minutes. Subsequent redeploys reuse the cached file.

Once running, it's an OpenAI-compatible endpoint:

```bash
curl http://your-domain-or-ip:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "bonsai2",
    "messages": [{"role": "user", "content": "Explain quantum computing simply."}]
  }'
```

## Environment variables

| Variable         | Default   | Notes                                                                 |
| ---------------- | --------- | ---------------------------------------------------------------------|
| `BONSAI_PACKING` | `PQ2_0`   | `PQ2_0` (7.21GB, faster prefill, best on H100/A100/Blackwell) or `PTQ1_0` (5.95GB, best on Ada-gen/L4 GPUs or when RAM is tight) |
| `BONSAI_NGL`     | `0` (CPU) / `99` (GPU compose) | GPU layers to offload; `0` = CPU-only |
| `BONSAI_CTX`     | `8192`    | Context length, up to `262144`. Costs real memory — see sizing below |
| `BONSAI_VISION`  | `0`       | Set to `1` to also fetch the ~0.6GB vision projector for image input |
| `BONSAI_TEMP`, `BONSAI_TOP_P`, `BONSAI_TOP_K`, `BONSAI_MIN_P` | `1.0`/`0.95`/`20`/`0.05` | Prism ML's recommended thinking-mode sampling defaults |
| `BONSAI_EXTRA_ARGS` | (empty) | Any extra flags passed straight to `llama-server` |

## Sizing / hardware notes

- Model weights alone: ~7.2 GB (PQ2_0) or ~6.0 GB (PTQ1_0).
- Add roughly the FP16 KV-cache cost on top: ~0.5 GiB at 4K context, ~6.3 GiB at 100K context (halves with 4-bit KV cache, not wired up in this compose but a `BONSAI_EXTRA_ARGS` flag away if you build it in).
- **CPU-only**: works, but this model's published throughput numbers are all on Apple Silicon (Metal) — 18-47 tok/s depending on chip. No official x86 CPU numbers are published, so expect it to be noticeably slower on a generic VPS; test before relying on it for latency-sensitive use.
- **GPU**: on a single consumer/entry-level GPU (e.g. RTX 4090, L4), expect roughly 30-90 tok/s decode depending on card and packing choice, per Prism ML's published benchmarks.
- Give the container at minimum ~10 GB RAM (CPU build) for the model + a modest context window; more if you raise `BONSAI_CTX`.

## Source of truth

Prism ML explicitly says their [Bonsai-demo repo](https://github.com/PrismML-Eng/Bonsai-demo) is
the source of truth for running these models and is kept current as the kernels move — worth a
glance if something here stops matching upstream (e.g. a new fork release breaking the asset
naming this Dockerfile assumes).