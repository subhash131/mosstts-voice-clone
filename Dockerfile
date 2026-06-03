# ── Base image ────────────────────────────────────────────────────────────────
FROM continuumio/miniconda3:24.7.1-0

WORKDIR /app

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ffmpeg libsndfile1 \
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

# ── (Optional) Pre-download HF model weights into the image ──────────────────
# Uncomment the block below to bake models into the image (~2 GB larger image
# but zero download delay on cold start). Leave commented to download on first run.
#
# RUN conda run -n mosstts python -c "\
#     from moss_tts_nano_runtime import NanoTTSService; \
#     svc = NanoTTSService(); svc.get_model()"

# ── Port ──────────────────────────────────────────────────────────────────────
EXPOSE 18083

# ── Healthcheck ───────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:18083/api/warmup-status || exit 1

# ── Start the server ──────────────────────────────────────────────────────────
# Switch "app.py" → "app_onnx.py" for the lighter ONNX CPU version (no PyTorch at inference)
CMD ["conda", "run", "--no-capture-output", "-n", "mosstts", \
     "python", "app.py", "--host", "0.0.0.0", "--port", "18083"]
