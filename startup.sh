#!/bin/bash
# =============================================================================
# startup.sh — Lives in the project repo at /workspace/REPO_NAME/startup.sh
# Called by entrypoint.sh after clone/pull. Handles:
#   - Sourcing .env + patching .bashrc
#   - GPU + volume verification
#   - Creating standard directories
#   - Installing project Python dependencies (uv sync)
#   - Downloading data if missing (project-specific — edit the DATA SETUP section)
#   - Starting the main process or keeping alive for interactive use
#
# IDEMPOTENCY REQUIREMENT:
#   This script is called every time a pod starts, including after pause/resume
#   and stop/restart. Every step MUST be safe to run multiple times:
#
#   ✓ mkdir -p          — safe, no-ops if dir exists
#   ✓ ln -sfn           — safe, overwrites existing symlinks
#   ✓ uv sync           — safe, idempotent package install
#   ✓ .bashrc patching  — guarded by grep check
#   ✓ DATA SETUP        — MUST use a flag file to skip completed downloads
#                         (see section 8 below — the flag-file pattern is
#                          REQUIRED, not optional)
#   ✗ avoid             — anything that assumes a clean container state,
#                         binds a port without checking, or writes without
#                         checking if the output already exists
# =============================================================================
set -euo pipefail

REPO_NAME="${REPO_NAME:-hello}"
REPO_DIR="/workspace/$REPO_NAME"
ENV_FILE="$REPO_DIR/.env"
BASHRC="/root/.bashrc"

echo "[startup] $(date)"

# -----------------------------------------------------------------------------
# 1. Source .env for this session
# -----------------------------------------------------------------------------
if [ -f "$ENV_FILE" ]; then
    echo "[startup] Sourcing $ENV_FILE"
    set -a; source "$ENV_FILE"; set +a
else
    echo "[startup] NOTE: $ENV_FILE not found — create it with HF_TOKEN, WANDB_KEY, etc."
fi

# -----------------------------------------------------------------------------
# 2. Patch .bashrc so .env is sourced in every interactive shell
# -----------------------------------------------------------------------------
BASHRC_MARKER="# cloud: auto-source project .env"
if ! grep -qF "$BASHRC_MARKER" "$BASHRC" 2>/dev/null; then
    echo "[startup] Patching $BASHRC to auto-source $ENV_FILE and set UV_PROJECT_ENVIRONMENT"
    cat >> "$BASHRC" << BASHEOF

$BASHRC_MARKER
export UV_PROJECT_ENVIRONMENT=/opt/venv
if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE"; set +a
fi
BASHEOF
fi

# -----------------------------------------------------------------------------
# 3. GPU check
# -----------------------------------------------------------------------------
echo "[startup] GPU:"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader \
    || echo "[startup] WARNING: nvidia-smi failed"

# -----------------------------------------------------------------------------
# 4. Volume check
# -----------------------------------------------------------------------------
for vol in /workspace /data /scratch; do
    if [ -d "$vol" ]; then
        echo "[startup] $vol: $(df -h "$vol" | tail -1 | awk '{print $4}') free"
    else
        echo "[startup] WARNING: $vol not available"
    fi
done

# -----------------------------------------------------------------------------
# 5. Standard directories
# -----------------------------------------------------------------------------
mkdir -p /data/datasets /data/checkpoints /data/logs /data/wandb /data/.cache/huggingface
mkdir -p /scratch/tmp /scratch/compile

# -----------------------------------------------------------------------------
# 6. Export standard paths
# -----------------------------------------------------------------------------
export HF_HOME="${HF_HOME:-/data/.cache/huggingface}"
export WANDB_DIR="${WANDB_DIR:-/data/wandb}"
export TMPDIR="${TMPDIR:-/scratch/tmp}"
export PYTHONPATH="${PYTHONPATH:-$REPO_DIR}"

# -----------------------------------------------------------------------------
# 7. Install project-specific Python dependencies
# -----------------------------------------------------------------------------
if [ -f "$REPO_DIR/pyproject.toml" ]; then
    echo "[startup] Running uv sync..."
    export UV_CACHE_DIR="${UV_CACHE_DIR:-/workspace/.uv-cache}"
    mkdir -p "$UV_CACHE_DIR"
    cd "$REPO_DIR"
    uv sync --frozen --no-install-project 2>&1 | sed 's/^/[startup:uv] /'
    echo "[startup] uv sync complete"
fi

# -----------------------------------------------------------------------------
# 8. DATA SETUP — no persistent data needed for this project
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 9. Convenience symlinks into repo dir
# -----------------------------------------------------------------------------
ln -sfn /data/checkpoints "$REPO_DIR/checkpoints" 2>/dev/null || true
ln -sfn /data/datasets    "$REPO_DIR/datasets"    2>/dev/null || true
ln -sfn /data/logs        "$REPO_DIR/logs"        2>/dev/null || true

# -----------------------------------------------------------------------------
# 10. Main process
# -----------------------------------------------------------------------------
echo "[startup] Ready — repo at $REPO_DIR"
cd "$REPO_DIR"

# Run hello.py then keep alive for interactive SSH use
python hello.py

tail -f /dev/null
