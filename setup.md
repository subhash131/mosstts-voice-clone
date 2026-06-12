# ☁️ MOSS-TTS-Nano — Cloud Deployment Guide

> **Why this doc exists:** The project depends on `pynini` / `WeTextProcessing`, which can be a pain to install without conda. Docker is the cleanest fix, and it works on every major cloud platform.

---

## 📋 Table of Contents

1. [Quick-fix: install pynini without Conda](#1-quick-fix-install-pynini-without-conda)
2. [Docker (recommended base for any cloud)](#2-docker-recommended-base-for-any-cloud)
3. [Railway (easiest one-click PaaS)](#3-railway-easiest-one-click-paas)
4. [Render](#4-render)
5. [Google Cloud Run](#5-google-cloud-run)
6. [Hugging Face Spaces](#6-hugging-face-spaces)
7. [RunPod / GPU VMs](#7-runpod--gpu-vms)
8. [Environment Variables Reference](#8-environment-variables-reference)

---

## 1. Quick-fix: install pynini without Conda

If you really want to avoid Docker, install a pre-built `pynini` wheel first. The community-maintained wheels live at:

```
https://github.com/kylebgorman/pynini/releases
```

Pick the `.whl` that matches your Python version + OS, then:

```bash
pip install pynini‑<version>‑<pyver>‑<os>.whl
pip install git+https://github.com/WhizZest/WeTextProcessing.git
pip install -r requirements.txt
pip install -e .
```

> **This is only for VMs where you control the OS.**  
> For PaaS services (Railway, Render, HF Spaces) — use Docker (section 2).

---

## 2. Docker (recommended base for any cloud)

Docker solves the `pynini` issue by using a pre-built `conda` environment inside the image.

### 2.1 Create `Dockerfile`

Create a file called `Dockerfile` in the root of the project:

```dockerfile
# ── Base image ────────────────────────────────────────────────────────────────
FROM continuumio/miniconda3:24.7.1-0

WORKDIR /app

# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# ── Conda environment ─────────────────────────────────────────────────────────
RUN conda create -n mosstts python=3.12 -y && \
    conda run -n mosstts conda install -c conda-forge pynini=2.1.6.post1 -y

# ── Copy source ───────────────────────────────────────────────────────────────
COPY . .

# ── Python dependencies ───────────────────────────────────────────────────────
RUN conda run -n mosstts pip install --no-cache-dir \
    git+https://github.com/WhizZest/WeTextProcessing.git && \
    conda run -n mosstts pip install --no-cache-dir -r requirements.txt && \
    conda run -n mosstts pip install --no-cache-dir -e .

# ── Pre-download HF models (optional but speeds up first request) ─────────────
# Uncomment if you want models baked into the image (~2 GB extra):
# RUN conda run -n mosstts python -c "\
#     from moss_tts_nano_runtime import NanoTTSService; \
#     NanoTTSService().get_model()"

# ── Expose port ───────────────────────────────────────────────────────────────
EXPOSE 18083

# ── Entrypoint ────────────────────────────────────────────────────────────────
CMD ["conda", "run", "--no-capture-output", "-n", "mosstts", \
     "python", "app.py", "--host", "0.0.0.0", "--port", "18083"]
```

### 2.2 Create `.dockerignore`

```
.git
__pycache__
*.pyc
.cache
generated_audio
.app_prompt_uploads
*.egg-info
```

### 2.3 Build & run locally

```bash
# Build (takes ~5 min first time)
docker build -t mosstts .

# Run
docker run -p 18083:18083 mosstts

# Open http://localhost:18083
```

### 2.4 Push to Docker Hub / GHCR

```bash
# Docker Hub
docker tag mosstts YOUR_DOCKERHUB_USERNAME/mosstts:latest
docker push YOUR_DOCKERHUB_USERNAME/mosstts:latest

# GitHub Container Registry
docker tag mosstts ghcr.io/YOUR_GITHUB_USERNAME/mosstts:latest
docker push ghcr.io/YOUR_GITHUB_USERNAME/mosstts:latest
```

---

## 3. Railway (easiest one-click PaaS)

Railway detects your `Dockerfile` automatically — no YAML needed.

### Steps

1. Push your repo (with the `Dockerfile`) to GitHub.
2. Go to [railway.app](https://railway.app) → **New Project** → **Deploy from GitHub repo**.
3. Select your repository. Railway will auto-detect the `Dockerfile`.
4. In **Settings → Networking**, set **Internal Port** to `18083` and enable **Public URL**.
5. Click **Deploy**.

### Important Railway settings

| Setting           | Value                     |
| ----------------- | ------------------------- |
| Internal Port     | `18083`                   |
| Health Check Path | `/api/warmup-status`      |
| Root Directory    | `/` (default)             |
| RAM               | ≥ 2 GB (4 GB recommended) |

> **Cost tip:** Railway's free hobby tier gives 500 CPU hours/month — enough for a demo.

---

## 4. Render

### Steps

1. Push your repo (with the `Dockerfile`) to GitHub.
2. Go to [render.com](https://render.com) → **New** → **Web Service**.
3. Connect your GitHub repo.
4. Set:
   - **Environment**: `Docker`
   - **Port**: `18083`
5. Under **Advanced → Health Check Path**: `/api/warmup-status`
6. Click **Create Web Service**.

### Free tier note

Render's free tier spins down after 15 minutes of inactivity (cold start ~30 s). Upgrade to **Starter ($7/mo)** to keep it always-on.

---

## 5. Google Cloud Run

Cloud Run is fully managed, auto-scales to zero, and supports Docker images natively.

### 5.1 Prerequisites

```bash
# Install gcloud CLI: https://cloud.google.com/sdk/docs/install
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud services enable run.googleapis.com artifactregistry.googleapis.com
```

### 5.2 Build & push to Artifact Registry

```bash
# Create a repository
gcloud artifacts repositories create mosstts \
  --repository-format=docker \
  --location=us-central1

# Configure Docker auth
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build with Cloud Build (avoids slow local upload)
gcloud builds submit --tag us-central1-docker.pkg.dev/YOUR_PROJECT_ID/mosstts/app:latest
```

### 5.3 Deploy

```bash
gcloud run deploy mosstts-app \
  --image us-central1-docker.pkg.dev/YOUR_PROJECT_ID/mosstts/app:latest \
  --platform managed \
  --region us-central1 \
  --port 18083 \
  --memory 4Gi \
  --cpu 2 \
  --timeout 300 \
  --allow-unauthenticated
```

> **Startup timeout:** The model warmup takes ~60-90 s. Cloud Run's default startup is 240 s, which is enough, but you can pass `--startup-cpu-boost` to speed up the initial load.

### 5.4 Check deployment

```bash
gcloud run services describe mosstts-app --region us-central1 --format="value(status.url)"
```

---

## 6. Hugging Face Spaces

HF Spaces supports Docker deployments and has free CPU allocations.

### Steps

1. Create a new Space at [huggingface.co/new-space](https://huggingface.co/new-space).
2. Choose **Docker** as the SDK.
3. Clone the Space repo, copy your project files in, and push.

### `README.md` front-matter (required by HF Spaces)

Add this block to the **top** of your `README.md` (or create a separate one in the Space repo):

```yaml
---
title: MOSS TTS Nano
emoji: 🔊
colorFrom: purple
colorTo: indigo
sdk: docker
app_port: 18083
pinned: false
---
```

### HF-specific `Dockerfile` tweak

HF Spaces runs as a non-root user. Add this line before `CMD`:

```dockerfile
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user PATH=/home/user/.local/bin:$PATH
```

> **Free tier:** CPU Basic (2 vCPU, 16 GB RAM) is free. GPU tiers are available for a fee.

---

## 7. RunPod / GPU VMs

Use this route if you need a real GPU for lower latency.

### 7.1 RunPod (serverless GPU)

1. Go to [runpod.io](https://runpod.io) → **Serverless** → **New Endpoint**.
2. Use your Docker image URL (from section 2.4).
3. Set **Container Disk** to at least **20 GB** (models cache here).
4. Set **GPU**: RTX 3090 or A4000 is enough for this 0.1B model.
5. Set **Environment Variables** (see section 8).

### 7.2 RunPod Pod (persistent GPU VM)

```bash
# SSH in, then:
git clone https://github.com/OpenMOSS/MOSS-TTS-Nano.git
cd MOSS-TTS-Nano

conda create -n mosstts python=3.12 -y
conda activate mosstts
conda install -c conda-forge pynini=2.1.6.post1 -y
pip install git+https://github.com/WhizZest/WeTextProcessing.git
pip install -r requirements.txt
pip install -e .

# Run with GPU
python app.py --host 0.0.0.0 --port 18083 --device cuda
```

Expose port **18083** in the pod's **HTTP Port** settings to get a public URL.

---

## 8. Environment Variables Reference

These can be set in any cloud provider's dashboard under "Environment Variables":

| Variable             | Default                | Description                     |
| -------------------- | ---------------------- | ------------------------------- |
| `HF_HOME`            | `~/.cache/huggingface` | Where HF model files are cached |
| `TRANSFORMERS_CACHE` | same as `HF_HOME`      | Legacy cache path               |
| `MOSS_TTS_DEVICE`    | `cpu`                  | Set to `cuda` for GPU inference |
| `MOSS_TTS_PORT`      | `18083`                | Server port                     |
| `MOSS_TTS_HOST`      | `127.0.0.1`            | Set to `0.0.0.0` for cloud      |

### Persistent model cache (avoid re-downloading on restart)

Mount a persistent volume at `/root/.cache/huggingface` (or wherever `HF_HOME` points).  
On Railway/Render this is a **Disk** add-on. On Cloud Run, use a **Cloud Storage FUSE** mount.

---

## 9. Minimum Resource Requirements

| Mode                | RAM                  | vCPU | Storage |
| ------------------- | -------------------- | ---- | ------- |
| CPU (PyTorch)       | 3 GB                 | 2    | 6 GB    |
| CPU (ONNX)          | 2 GB                 | 2    | 6 GB    |
| GPU (PyTorch, cuda) | 4 GB VRAM + 2 GB RAM | 2    | 6 GB    |

The **ONNX version** (`app_onnx.py`) is the best choice for cloud CPU deployments:

- No PyTorch dependency at inference time
- ~2x faster than the PyTorch version on CPU
- Same voice cloning workflow

To use ONNX in your Dockerfile, replace the `CMD` line with:

```dockerfile
CMD ["conda", "run", "--no-capture-output", "-n", "mosstts", \
     "python", "app_onnx.py", "--host", "0.0.0.0", "--port", "18083"]
```

---

## 10. Quick Comparison

| Platform      | Free tier     | GPU support | Docker | Effort        |
| ------------- | ------------- | ----------- | ------ | ------------- |
| **Railway**   | 500 CPU-hr/mo | ❌          | ✅     | ⭐ Easiest    |
| **Render**    | Yes (sleeps)  | ❌          | ✅     | ⭐⭐ Easy     |
| **HF Spaces** | CPU Basic     | Paid        | ✅     | ⭐⭐ Easy     |
| **Cloud Run** | 2M req/mo     | ❌          | ✅     | ⭐⭐⭐ Medium |
| **RunPod**    | Pay-per-use   | ✅          | ✅     | ⭐⭐⭐ Medium |

---

> 💡 **Tip:** Start with **Railway** or **HF Spaces** — just push your code and they handle everything. Migrate to **Cloud Run** or **RunPod GPU** once you need production scale or GPU acceleration.
