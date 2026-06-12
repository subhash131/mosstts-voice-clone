#!/bin/sh
# Render/Railway inject $PORT dynamically. Fall back to 18083 for local runs.
# Resolve port in shell first (conda run can strip env vars on some versions)
APP_PORT="${PORT:-18083}"
exec conda run --no-capture-output -n mosstts \
    env PORT="$APP_PORT" \
    python app.py --host 0.0.0.0 --port "$APP_PORT" --device auto --dtype float16
