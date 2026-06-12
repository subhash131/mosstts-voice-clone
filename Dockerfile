# ── Base image ────────────────────────────────────────────────────────────────
FROM nvidia/cuda:12.6.3-runtime-ubuntu22.04

WORKDIR /app  

# ── NVIDIA Container Runtime — expose GPUs inside the container ───────────────
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ffmpeg libsndfile1 curl \
    && rm -rf /var/lib/apt/lists/*

# ── Install Miniconda ─────────────────────────────────────────────────────────
ENV CONDA_DIR=/opt/conda
ENV CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes
RUN curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o miniconda.sh && \
    bash miniconda.sh -b -p $CONDA_DIR && \
    rm miniconda.sh
ENV PATH=$CONDA_DIR/bin:$PATH

# ── Create conda env and install pynini (the conda-only dep) ─────────────────
RUN conda create -n mosstts python=3.12 -y && \
    conda run -n mosstts conda install -c conda-forge pynini=2.1.6.post1 -y && \
    conda clean -afy

# ── Install PyTorch with CUDA support (before COPY to leverage cache) ─────────
# Pinned to match requirements.txt versions but from the cu126 index for GPU.
RUN conda run -n mosstts pip install --no-cache-dir \
    torch==2.7.0 torchaudio==2.7.0 \
    --index-url https://download.pytorch.org/whl/cu126

# ── Copy requirements file first to cache dependency installation ───────────
COPY requirements.txt .

# ── Install Python dependencies ───────────────────────────────────────────────
# IMPORTANT: --no-deps on torch/torchaudio to prevent requirements.txt from
# overwriting the CUDA build with CPU-only wheels from PyPI.
RUN conda run -n mosstts pip install --no-cache-dir -r requirements.txt \
        --no-deps torch torchaudio && \
    conda run -n mosstts pip install --no-cache-dir \
        git+https://github.com/WhizZest/WeTextProcessing.git

# ── Copy the rest of the source code ──────────────────────────────────────────
COPY . .

# ── Install editable package ──────────────────────────────────────────────────
RUN conda run -n mosstts pip install --no-cache-dir -e .

# ── Pre-download model weights to avoid slow cold starts ─────────────────────
RUN conda run -n mosstts python -c "\
from huggingface_hub import snapshot_download; \
snapshot_download('OpenMOSS-Team/MOSS-TTS-Nano'); \
snapshot_download('OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano')"

# ── Make startup script executable ───────────────────────────────────────────
RUN sed -i 's/\r$//' start.sh && chmod +x start.sh

# ── Port (Render/Railway override this via $PORT env var at runtime) ──────────
# The app reads $PORT at startup and binds to it; 18083 is the local fallback.
EXPOSE 18083

# ── Healthcheck ───────────────────────────────────────────────────────────────
# Uses $PORT so it works on Railway too
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD curl -f http://localhost:${PORT:-18083}/api/warmup-status || exit 1

# ── Start ─────────────────────────────────────────────────────────────────────
# start.sh reads $PORT (injected by Railway) and falls back to 18083 locally
CMD ["/bin/sh", "start.sh"]
