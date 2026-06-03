# ── Base image ────────────────────────────────────────────────────────────────
FROM continuumio/miniconda3:24.7.1-0

WORKDIR /app

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ffmpeg libsndfile1 curl \
    && rm -rf /var/lib/apt/lists/*

# ── Create conda env and install pynini (the conda-only dep) ─────────────────
RUN conda create -n mosstts python=3.12 -y && \
    conda run -n mosstts conda install -c conda-forge pynini=2.1.6.post1 -y

# ── Copy source code ──────────────────────────────────────────────────────────
COPY . .

# ── Install Python dependencies ───────────────────────────────────────────────
RUN conda run -n mosstts pip install --no-cache-dir \
        git+https://github.com/WhizZest/WeTextProcessing.git && \
    conda run -n mosstts pip install --no-cache-dir -r requirements.txt && \
    conda run -n mosstts pip install --no-cache-dir -e .

# ── Make startup script executable ───────────────────────────────────────────
RUN chmod +x start.sh

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
