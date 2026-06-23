#!/bin/bash
# Environment setup script for AutoResearchClaw.
#
# Creates a Python virtualenv, installs project dependencies (including the
# [all] extras: crawl4ai, playwright, scholarly, tavily, PyMuPDF), and
# provisions the Playwright Chromium browser binary required by the web
# crawling subsystem (Stage 4 — LITERATURE_COLLECT).
#
# Usage:
#   ./scripts/env_setup.sh                # uv + .venv (default)
#   ./scripts/env_setup.sh --pip          # force pip + venv instead of uv
#   ./scripts/env_setup.sh --skip-browsers  # skip Playwright browser install
#
# Requirements:
#   - Python 3.11+ on PATH
#   - (optional) uv: https://docs.astral.sh/uv/  — faster, uses uv.lock

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"
USE_UV=1
SKIP_BROWSERS=0

for arg in "$@"; do
    case "$arg" in
        --pip) USE_UV=0 ;;
        --skip-browsers) SKIP_BROWSERS=1 ;;
        -h|--help)
            sed -n '2,16p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

cd "$PROJECT_ROOT"

echo "============================================================"
echo "  AutoResearchClaw — Environment Setup"
echo "  Project: $PROJECT_ROOT"
echo "  $(date)"
echo "============================================================"
echo ""

# ── 1. Python version check ────────────────────────────────────
PY_BIN="${PYTHON:-python3}"
if ! command -v "$PY_BIN" >/dev/null 2>&1; then
    echo "ERROR: Python 3.11+ required but '$PY_BIN' not found on PATH." >&2
    echo "Install Python: https://www.python.org/downloads/" >&2
    exit 1
fi
PY_VERSION="$("$PY_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
PY_MAJOR_MINOR="$PY_VERSION"
if "$PY_BIN" -c "import sys; exit(0 if sys.version_info >= (3, 11) else 1)"; then
    echo "  [OK] Python $PY_VERSION found"
else
    echo "ERROR: Python 3.11+ required, found $PY_VERSION" >&2
    exit 1
fi
echo ""

# ── 2. Create / reuse virtualenv ───────────────────────────────
if [ "$USE_UV" -eq 1 ] && command -v uv >/dev/null 2>&1; then
    echo "  [uv] Using uv (lockfile-resolved install)"
    if [ ! -d "$VENV_DIR" ]; then
        uv venv "$VENV_DIR" --python "$PY_MAJOR_MINOR"
    fi
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    echo "  [uv] Syncing dependencies from uv.lock…"
    uv sync --extra all
    UV_PIP=1
else
    if [ "$USE_UV" -eq 1 ]; then
        echo "  [note] uv not found — falling back to pip + venv"
        echo "         (install uv for faster, reproducible installs: https://docs.astral.sh/uv/)"
    else
        echo "  [pip] Using pip + venv (--pip flag)"
    fi
    if [ ! -d "$VENV_DIR" ]; then
        "$PY_BIN" -m venv "$VENV_DIR"
    fi
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    python -m pip install --upgrade pip
    echo "  [pip] Installing project with [all] extras…"
    pip install -e ".[all]"
    UV_PIP=0
fi
echo ""
echo "  [OK] Dependencies installed into $VENV_DIR"
echo ""

# ── 3. Playwright browser binaries (the missing step) ─────────
# crawl4ai drives Playwright's Chromium under the hood. `pip install` pulls
# the Python bindings but NOT the ~170 MB browser binary — that must be
# fetched separately, or Stage 4 crawling fails with:
#   BrowserType.launch: Executable doesn't exist at .../chromium-1223/...
if [ "$SKIP_BROWSERS" -eq 1 ]; then
    echo "  [--] Skipping Playwright browser install (--skip-browsers)"
else
    echo "  [web] Provisioning Playwright Chromium browser…"
    if command -v crawl4ai-setup >/dev/null 2>&1; then
        crawl4ai-setup
    elif python -m playwright install chromium; then
        :
    else
        echo "  [WARN] Playwright browser install failed." >&2
        echo "         Web crawling (Stage 4) will fall back to urllib only." >&2
        echo "         Retry manually: playwright install chromium" >&2
    fi
    echo ""

    echo "  [web] Verifying Chromium launches…"
    if python -c "
from playwright.sync_api import sync_playwright
p = sync_playwright().start()
b = p.chromium.launch()
b.close()
p.stop()
print('  [OK] Chromium launches successfully')
" 2>/dev/null; then
        :
    else
        echo "  [WARN] Chromium verification failed — crawling may not work." >&2
        echo "         Check PLAYWRIGHT_BROWSERS_PATH if on a shared system." >&2
    fi
fi
echo ""

# ── 4. Summary ────────────────────────────────────────────────
echo "============================================================"
echo "  Setup complete."
echo ""
echo "  Next steps:"
echo "    source .venv/bin/activate"
echo "    researchclaw setup        # optional: check OpenCode/Docker/LaTeX"
echo "    researchclaw init         # create config.arc.yaml"
echo "    export OPENAI_API_KEY=\"…\""
echo "    researchclaw run --config config.arc.yaml --topic \"…\" --auto-approve"
echo "============================================================"
