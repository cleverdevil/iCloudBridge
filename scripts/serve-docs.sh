#!/bin/bash
#
# serve-docs.sh - Build and serve iCloud Bridge documentation locally
#
# Usage:
#   ./scripts/serve-docs.sh [command]
#
# Commands:
#   build    Build documentation only (no server)
#   serve    Build and serve documentation (default)
#   api      Serve only API docs (no build)
#   python   Serve only Python docs (no build)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
API_DOCS_DIR="$PROJECT_DIR/docs/api"
PYTHON_DOCS_DIR="$PROJECT_DIR/python/docs"
PYTHON_DOCS_BUILD="$PYTHON_DOCS_DIR/_build/html"
VENV_DIR="$PROJECT_DIR/python/.venv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}==>${NC} $1"
}

log_success() {
    echo -e "${GREEN}==>${NC} $1"
}

log_error() {
    echo -e "${RED}Error:${NC} $1" >&2
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Set up virtual environment for Python docs
setup_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        log_info "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
    fi

    # Activate virtual environment
    source "$VENV_DIR/bin/activate"

    # Install dependencies if needed
    if ! python3 -c "import sphinx" 2>/dev/null; then
        log_info "Installing Sphinx and dependencies..."
        cd "$PROJECT_DIR/python"
        pip install -e ".[dev]" --quiet
    fi
}

# Build Python documentation with Sphinx
build_python_docs() {
    log_info "Building Python documentation..."

    # Set up and activate venv
    setup_venv

    # Build the docs
    cd "$PYTHON_DOCS_DIR"
    python3 -m sphinx -b html . _build/html

    log_success "Python documentation built at: $PYTHON_DOCS_BUILD"
}

# Serve documentation using Python's built-in HTTP server
serve_docs() {
    local port="${1:-8000}"
    local docs_dir="$2"

    log_info "Starting documentation server on http://localhost:$port"
    log_info "Press Ctrl+C to stop the server"
    echo ""

    cd "$docs_dir"
    python3 -m http.server "$port"
}

# Create a combined docs landing page
create_landing_page() {
    local landing_dir="$PROJECT_DIR/docs/_serve"
    mkdir -p "$landing_dir"

    cat > "$landing_dir/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>iCloud Bridge Documentation</title>
    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            max-width: 800px;
            width: 100%;
        }
        h1 {
            color: white;
            text-align: center;
            margin-bottom: 40px;
            font-size: 2.5rem;
            text-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }
        .cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        .card {
            background: white;
            border-radius: 12px;
            padding: 30px;
            text-decoration: none;
            color: inherit;
            transition: transform 0.2s, box-shadow 0.2s;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .card:hover {
            transform: translateY(-4px);
            box-shadow: 0 12px 24px rgba(0,0,0,0.15);
        }
        .card h2 {
            color: #333;
            margin-bottom: 10px;
            font-size: 1.5rem;
        }
        .card p {
            color: #666;
            line-height: 1.6;
        }
        .card .icon {
            font-size: 2rem;
            margin-bottom: 15px;
        }
        .api-card .icon { color: #10B981; }
        .python-card .icon { color: #3B82F6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>iCloud Bridge Documentation</h1>
        <div class="cards">
            <a href="/api/" class="card api-card">
                <div class="icon">&#128640;</div>
                <h2>REST API Reference</h2>
                <p>Interactive API documentation with Swagger UI. Explore endpoints, try requests, and see response schemas.</p>
            </a>
            <a href="/python/" class="card python-card">
                <div class="icon">&#128013;</div>
                <h2>Python Client</h2>
                <p>Python client library documentation with guides, examples, and complete API reference.</p>
            </a>
        </div>
    </div>
</body>
</html>
EOF

    echo "$landing_dir"
}

# Serve combined documentation
serve_combined() {
    local port="${1:-8000}"
    local landing_dir
    landing_dir=$(create_landing_page)

    # Create symlinks for the docs
    ln -sf "$API_DOCS_DIR" "$landing_dir/api"
    ln -sf "$PYTHON_DOCS_BUILD" "$landing_dir/python"

    log_success "Documentation available at:"
    echo "  - Landing page:  http://localhost:$port/"
    echo "  - API docs:      http://localhost:$port/api/"
    echo "  - Python docs:   http://localhost:$port/python/"
    echo ""

    # Open in browser (macOS)
    if command_exists open; then
        open "http://localhost:$port/"
    fi

    serve_docs "$port" "$landing_dir"
}

# Main script
main() {
    local command="${1:-serve}"
    local port="${2:-8000}"

    case "$command" in
        build)
            build_python_docs
            log_success "Documentation build complete!"
            ;;
        serve)
            build_python_docs
            serve_combined "$port"
            ;;
        api)
            log_info "Serving API documentation only..."
            if command_exists open; then
                open "http://localhost:$port/"
            fi
            serve_docs "$port" "$API_DOCS_DIR"
            ;;
        python)
            if [ ! -d "$PYTHON_DOCS_BUILD" ]; then
                log_error "Python docs not built. Run './scripts/serve-docs.sh build' first."
                exit 1
            fi
            log_info "Serving Python documentation only..."
            if command_exists open; then
                open "http://localhost:$port/"
            fi
            serve_docs "$port" "$PYTHON_DOCS_BUILD"
            ;;
        -h|--help|help)
            echo "Usage: $0 [command] [port]"
            echo ""
            echo "Commands:"
            echo "  build    Build documentation only (no server)"
            echo "  serve    Build and serve documentation (default)"
            echo "  api      Serve only API docs (no build)"
            echo "  python   Serve only Python docs (no build)"
            echo ""
            echo "Options:"
            echo "  port     Port number for the server (default: 8000)"
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Run '$0 --help' for usage information."
            exit 1
            ;;
    esac
}

main "$@"
