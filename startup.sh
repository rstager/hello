#!/bin/bash
# =============================================================================
# startup.sh — Lives in the project repo. Run as `coder` after pod deploy.
# Handles:
#   - Sourcing .env + patching .bashrc
#   - GPU verification
#   - Creating standard directories
#   - Installing project Python dependencies (uv sync)
#   - Downloading data if missing (project-specific — edit the DATA SETUP section)
#   - Starting the main process or keeping alive for interactive use
#
# IDEMPOTENCY REQUIREMENT:
#   Safe to run multiple times (after pause/resume, stop/restart, re-deploy).
#
#   ✓ mkdir -p          — safe, no-ops if dir exists
#   ✓ ln -sfn           — safe, overwrites existing symlinks
#   ✓ uv sync           — safe, idempotent package install
#   ✓ .bashrc patching  — guarded by grep check
#   ✓ DATA SETUP        — MUST use a flag file to skip completed downloads
#   ✗ avoid             — anything that assumes a clean container state
# =============================================================================
set -euo pipefail

REPO_NAME="${REPO_NAME:-hello}"
if [ -z "$REPO_NAME" ]; then
    echo "[startup] ERROR: REPO_NAME env var not set — set it in pod config"
    tail -f /dev/null
    exit 1
fi
REPO_DIR="$HOME/$REPO_NAME"
ENV_FILE="$REPO_DIR/.env"
BASHRC="$HOME/.bashrc"

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
    echo "[startup] Patching $BASHRC"
    cat >> "$BASHRC" << BASHEOF

$BASHRC_MARKER
if [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE"; set +a
fi
BASHEOF
fi

# -----------------------------------------------------------------------------
# 3. GPU check
# -----------------------------------------------------------------------------
echo "[startup] GPU:"
sudo nvidia-smi --query-gpu=name,memory.total --format=csv,noheader \
    || echo "[startup] WARNING: nvidia-smi failed"

# -----------------------------------------------------------------------------
# 4. Standard directories (under home — no root needed)
# -----------------------------------------------------------------------------
mkdir -p ~/data/datasets ~/data/checkpoints ~/data/logs ~/data/wandb ~/data/.cache/huggingface
mkdir -p ~/scratch/tmp ~/scratch/compile

# -----------------------------------------------------------------------------
# 5. Export standard paths
# -----------------------------------------------------------------------------
export HF_HOME="${HF_HOME:-$HOME/data/.cache/huggingface}"
export WANDB_DIR="${WANDD_DIR:-$HOME/data/wandb}"
export TMPDIR="${TMPDIR:-$HOME/scratch/tmp}"
export PYTHONPATH="${PYTHONPATH:-$REPO_DIR}"

# -----------------------------------------------------------------------------
# 6. Install project-specific Python dependencies
# -----------------------------------------------------------------------------
if [ -f "$REPO_DIR/pyproject.toml" ]; then
    echo "[startup] Running uv sync..."
    cd "$REPO_DIR"
    uv sync --frozen --no-install-project 2>&1 | sed 's/^/[startup:uv] /'
    echo "[startup] uv sync complete"
fi

# -----------------------------------------------------------------------------
# 7. DATA SETUP — edit this section per project
#
#    !! IDEMPOTENCY REQUIRED !!
#    Always guard downloads with a flag file so they only run once.
#
# Example (uncomment and adapt):
# DATA_READY_FLAG="$HOME/data/datasets/.ready"
# if [ ! -f "$DATA_READY_FLAG" ]; then
#     echo "[startup] First run — downloading data..."
#     cd "$REPO_DIR"
#     uv run prepare.py
#     touch "$DATA_READY_FLAG"
#     echo "[startup] Data setup complete"
# else
#     echo "[startup] Data already present — skipping download"
# fi

# -----------------------------------------------------------------------------
# 8. Convenience symlinks into repo dir
# -----------------------------------------------------------------------------
ln -sfn ~/data/checkpoints "$REPO_DIR/checkpoints" 2>/dev/null || true
ln -sfn ~/data/datasets    "$REPO_DIR/datasets"    2>/dev/null || true
ln -sfn ~/data/logs        "$REPO_DIR/logs"        2>/dev/null || true

# -----------------------------------------------------------------------------
# 9. Main process — replace tail with your actual entrypoint
#    e.g.: exec uv run train.py
#          exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser
# -----------------------------------------------------------------------------
echo "[startup] Ready — repo at $REPO_DIR"
cd "$REPO_DIR"

# Keep alive for interactive SSH use:
tail -f /dev/null
