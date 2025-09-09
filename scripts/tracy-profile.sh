#!/bin/bash
# Tracy Profiler Script for JamZig
# 
# This script automates Tracy profiling capture for JamZig benchmarks.
# It builds JamZig with Tracy enabled, starts tracy-capture, runs benchmarks,
# and cleanly stops capture to generate .tracy files for analysis.
#
# Now supports Tracy tracing integration to route structured trace output
# to Tracy for unified timeline visualization.

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROFILES_DIR="$PROJECT_ROOT/profiles/captures"
TRACY_PORT=8086
DEFAULT_ITERATIONS=100

# Default options
ENABLE_TRACING=true
ITERATIONS=$DEFAULT_ITERATIONS
TRACE_FILTER=""

# Help function
show_help() {
    cat << EOF
🔧 JamZig Tracy Profiling Script

USAGE:
    $0 [OPTIONS] [iterations] [trace_name]

ARGUMENTS:
    iterations          Number of benchmark iterations (default: $DEFAULT_ITERATIONS)
    trace_name         Specific trace to run (e.g., safrole, fallback)

OPTIONS:
    --disable-tracing   Disable Tracy tracing integration (performance zones only)
    --help             Show this help message

EXAMPLES:
    # Default: Performance profiling + tracing integration
    $0 100 safrole

    # Sampling only
    $0 --disable-tracing 50 safrole

    # All traces with comprehensive profiling + tracing (default)
    $0 25

OUTPUT:
    Tracy files are saved to: profiles/captures/
    Open with: tracy-profiler path/to/file.tracy

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --disable-tracing)
            ENABLE_TRACING=false
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Positional arguments
            if [[ -z "$ITERATIONS_SET" ]]; then
                ITERATIONS="$1"
                ITERATIONS_SET=true
            elif [[ -z "$TRACE_FILTER" ]]; then
                TRACE_FILTER="$1"
            else
                echo "Too many arguments: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate iterations is a number
if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "Error: Iterations must be a number, got: $ITERATIONS"
    echo "Use --help for usage information"
    exit 1
fi

# No additional validation needed for tracing (it's now automatic)

# Create profiles directory
mkdir -p "$PROFILES_DIR"

# Generate timestamp-based filename
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROFILE_TYPE="profiling"
if [[ "$ENABLE_TRACING" == true ]]; then
    PROFILE_TYPE="profiling+tracing"
fi

if [ -n "$TRACE_FILTER" ]; then
    TRACY_FILE="$PROFILES_DIR/jamzig-${TRACE_FILTER}-${PROFILE_TYPE}-${TIMESTAMP}.tracy"
    BENCHMARK_ARGS="$ITERATIONS $TRACE_FILTER"
else
    TRACY_FILE="$PROFILES_DIR/jamzig-all-traces-${PROFILE_TYPE}-${TIMESTAMP}.tracy"
    BENCHMARK_ARGS="$ITERATIONS"
fi

echo "🔧 JamZig Tracy Profiling Script"
echo "=================================="
echo "Mode: Performance profiling$(if [[ "$ENABLE_TRACING" == true ]]; then echo " + trace routing"; fi)"
echo "Iterations: $ITERATIONS"

echo "Output file: $(basename "$TRACY_FILE")"
echo "Tracy port: $TRACY_PORT"
echo ""

# Change to project root
cd "$PROJECT_ROOT"

# Step 1: Build JamZig with Tracy enabled
BUILD_FLAGS="-Denable-tracy=true"
if [[ "$ENABLE_TRACING" == true ]]; then
    BUILD_FLAGS="$BUILD_FLAGS -Dtracing-mode=tracy"
    echo "📦 Building JamZig with Tracy profiling + tracing enabled..."
    echo "   Build flags: $BUILD_FLAGS"
else
    echo "📦 Building JamZig with Tracy profiling enabled..."
    echo "   Build flags: $BUILD_FLAGS"
fi

if ! zig build $BUILD_FLAGS > build.log 2>&1; then
    echo "❌ Build failed! Check build.log for details."
    exit 1
fi
echo "✅ Build successful"

# Cleanup function for proper signal handling
cleanup() {
    echo ""
    echo "🛑 Stopping Tracy capture..."
    
    if [ -n "$TRACY_PID" ]; then
        # Send SIGTERM to tracy-capture and wait for it to finish
        kill -TERM "$TRACY_PID" 2>/dev/null || true
        wait "$TRACY_PID" 2>/dev/null || true
    fi
    
    if [ -f "$TRACY_FILE" ]; then
        local file_size=$(du -h "$TRACY_FILE" | cut -f1)
        echo "✅ Tracy capture complete: $(basename "$TRACY_FILE") ($file_size)"
        echo ""
        echo "🔍 To analyze the capture:"
        echo "   tracy-profiler \"$TRACY_FILE\""
    else
        echo "⚠️  No Tracy file generated"
    fi
    
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM EXIT

# Step 2: Start tracy-capture in background
echo "🎯 Starting Tracy capture..."
echo "   Output: $(basename "$TRACY_FILE")"

tracy-capture -o "$TRACY_FILE" -p "$TRACY_PORT" &
TRACY_PID=$!

# Give tracy-capture a moment to start listening
sleep 2

# Verify tracy-capture started successfully
if ! kill -0 "$TRACY_PID" 2>/dev/null; then
    echo "❌ Failed to start tracy-capture"
    exit 1
fi

echo "✅ Tracy capture started (PID: $TRACY_PID)"

# Step 3: Run the benchmark
echo ""
if [[ "$ENABLE_TRACING" == true ]]; then
    echo "🚀 Running benchmark with Tracy profiling + tracing..."
    echo "   Build flags: $BUILD_FLAGS"
else
    echo "🚀 Running benchmark with Tracy profiling..."
fi
echo "   Benchmark: zig build bench-block-import -- $BENCHMARK_ARGS"
echo ""
echo "⏱️  Benchmark in progress... (Press Ctrl+C to stop)"

# Run the benchmark and capture its exit code
set +e  # Don't exit on benchmark failure, we still want to save the tracy file
./zig-out/bin/bench-block-import $BENCHMARK_ARGS
BENCHMARK_EXIT_CODE=$?
set -e

# Give tracy-capture a moment to finish writing data
echo ""
echo "⏳ Finalizing Tracy capture..."
sleep 2

# The cleanup function will handle stopping tracy-capture and reporting results
if [ $BENCHMARK_EXIT_CODE -eq 0 ]; then
    echo "✅ Benchmark completed successfully"
else
    echo "⚠️  Benchmark completed with warnings/errors (exit code: $BENCHMARK_EXIT_CODE)"
    echo "   Tracy capture may still contain useful data"
fi
