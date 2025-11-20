#!/usr/bin/env python3
"""Benchmark visualization script with weighted scoring system"""

import json
import os
import sys
import math
from datetime import datetime
from pathlib import Path

BENCH_DIR = "bench"

# Weighted scoring system weights
SCORING_WEIGHTS = {
    'median': 0.35,    # P50 - Typical performance
    'p90': 0.25,       # P90 - Consistency
    'mean': 0.20,      # Mean - Average
    'p99': 0.10,       # P99 - Worst case
    'consistency': 0.10 # Lower variance (1 - coefficient of variation)
}

def ns_to_ms(ns_value):
    """Convert nanoseconds to milliseconds"""
    try:
        return float(ns_value) / 1_000_000
    except (ValueError, TypeError):
        return 0.0

def extract_trace_data(data, trace_name, metric):
    """Extract trace data from JSON"""
    for result in data.get('results', []):
        if result.get('trace_name') == trace_name:
            return result.get(metric, 0)
    return 0

def calculate_percentiles(min_ns, max_ns, median_ns, mean_ns, stddev_ns):
    """
    Estimate P90 and P99 from available statistics.
    This uses normal distribution approximation for percentiles.
    """
    if stddev_ns <= 0:
        # No variance, all values are the same
        return median_ns, median_ns

    # Z-scores for P90 and P99
    z_90 = 1.282  # 90th percentile
    z_99 = 2.326  # 99th percentile

    # Estimate percentiles using mean + z_score * stddev
    p90_est = mean_ns + (z_90 * stddev_ns)
    p99_est = mean_ns + (z_99 * stddev_ns)

    # Clamp to reasonable bounds (can't exceed max)
    p90_est = min(p90_est, max_ns)
    p99_est = min(p99_est, max_ns)

    # Ensure ordering: median <= p90 <= p99 <= max
    p90_est = max(p90_est, median_ns)
    p99_est = max(p99_est, p90_est)

    return p90_est, p99_est

def calculate_consistency_score(mean_ns, stddev_ns):
    """
    Calculate consistency score as (1 - coefficient of variation).
    Higher values indicate more consistent performance.
    """
    if mean_ns <= 0:
        return 1.0

    cv = stddev_ns / mean_ns  # Coefficient of variation
    consistency = max(0.0, 1.0 - cv)  # Ensure non-negative
    return consistency

def calculate_weighted_score(metrics):
    """
    Calculate weighted score from performance metrics.
    Lower scores are better (faster performance).
    """
    median_ms = metrics['median_ms']
    p90_ms = metrics['p90_ms']
    mean_ms = metrics['mean_ms']
    p99_ms = metrics['p99_ms']
    consistency = metrics['consistency']

    # Weighted score calculation
    score = (
        SCORING_WEIGHTS['median'] * median_ms +
        SCORING_WEIGHTS['p90'] * p90_ms +
        SCORING_WEIGHTS['mean'] * mean_ms +
        SCORING_WEIGHTS['p99'] * p99_ms +
        SCORING_WEIGHTS['consistency'] * (1.0 - consistency) * mean_ms  # Penalty for inconsistency
    )

    return score

def extract_trace_metrics(data, trace_name):
    """Extract and calculate all metrics for a trace"""
    result = None
    for r in data.get('results', []):
        if r.get('trace_name') == trace_name:
            result = r
            break

    if not result:
        return None

    min_ns = result.get('min_ns', 0)
    max_ns = result.get('max_ns', 0)
    median_ns = result.get('median_ns', 0)
    mean_ns = result.get('mean_ns', 0)
    stddev_ns = result.get('stddev_ns', 0)

    # Convert to milliseconds
    min_ms = ns_to_ms(min_ns)
    max_ms = ns_to_ms(max_ns)
    median_ms = ns_to_ms(median_ns)
    mean_ms = ns_to_ms(mean_ns)
    stddev_ms = ns_to_ms(stddev_ns)

    # Calculate estimated percentiles
    p90_ns, p99_ns = calculate_percentiles(min_ns, max_ns, median_ns, mean_ns, stddev_ns)
    p90_ms = ns_to_ms(p90_ns)
    p99_ms = ns_to_ms(p99_ns)

    # Calculate consistency score
    consistency = calculate_consistency_score(mean_ns, stddev_ns)

    metrics = {
        'min_ms': min_ms,
        'max_ms': max_ms,
        'median_ms': median_ms,
        'mean_ms': mean_ms,
        'stddev_ms': stddev_ms,
        'p90_ms': p90_ms,
        'p99_ms': p99_ms,
        'consistency': consistency,
        'iterations': result.get('iterations', 0)
    }

    # Calculate weighted score
    metrics['weighted_score'] = calculate_weighted_score(metrics)

    return metrics

def print_detailed_metrics(trace_metrics, trace_name):
    """Print detailed metrics for a single trace"""
    print(f"\n--- {trace_name.upper()} Trace Detailed Metrics ---")
    print(f"Iterations: {trace_metrics['iterations']}")
    print(f"Min:        {trace_metrics['min_ms']:>8.2f} ms")
    print(f"Median:     {trace_metrics['median_ms']:>8.2f} ms  (Weight: 35%)")
    print(f"Mean:       {trace_metrics['mean_ms']:>8.2f} ms  (Weight: 20%)")
    print(f"P90:        {trace_metrics['p90_ms']:>8.2f} ms  (Weight: 25%)")
    print(f"P99:        {trace_metrics['p99_ms']:>8.2f} ms  (Weight: 10%)")
    print(f"Max:        {trace_metrics['max_ms']:>8.2f} ms")
    print(f"StdDev:     {trace_metrics['stddev_ms']:>8.2f} ms")
    print(f"Consistency: {trace_metrics['consistency']:>7.3f}    (Weight: 10%)")
    print(f"Weighted Score: {trace_metrics['weighted_score']:>6.2f} ms")

def calculate_overall_score(trace_metrics_dict):
    """Calculate overall score using geometric mean of individual trace scores"""
    if not trace_metrics_dict:
        return 0.0

    scores = [metrics['weighted_score'] for metrics in trace_metrics_dict.values()]

    # Calculate geometric mean
    product = 1.0
    for score in scores:
        if score > 0:
            product *= score

    geometric_mean = product ** (1.0 / len(scores))
    return geometric_mean

def generate_report():
    """Generate benchmark report with weighted scoring"""
    print("=== JamZig Benchmark Performance Report ===")
    print("Weighted Scoring System:")
    print("• Median (P50): 35% - Typical performance")
    print("• P90: 25% - Consistency")
    print("• Mean: 20% - Average")
    print("• P99: 10% - Worst case")
    print("• Consistency: 10% - Lower variance")
    print()

    bench_path = Path(BENCH_DIR)
    if not bench_path.exists():
        print(f"Error: {BENCH_DIR} directory not found")
        print("Run benchmarks first with: zig build bench-block-import")
        return

    json_files = sorted(bench_path.glob("*.json"))

    if not json_files:
        print(f"No JSON files found in {BENCH_DIR}/")
        return

    print(f"Found {len(json_files)} benchmark file(s)")
    print()

    file_data = []

    # Process each file
    for file_path in json_files:
        print(f"Processing: {file_path.name}", file=sys.stderr)

        try:
            with open(file_path) as f:
                data = json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Error reading {file_path}: {e}", file=sys.stderr)
            continue

        # Extract metadata
        timestamp = data.get('timestamp', 0)
        git_commit = data.get('git_commit', 'unknown')
        params = data.get('params', 'unknown')

        # Convert timestamp to date
        date_str = "unknown"
        if timestamp and timestamp != "null":
            try:
                date_str = datetime.fromtimestamp(int(timestamp)).strftime('%Y-%m-%d %H:%M:%S')
            except (ValueError, OSError):
                date_str = "unknown"

        print(f"Benchmark: {file_path.name}")
        print(f"  Date: {date_str}")
        print(f"  Git Commit: {git_commit}")
        print(f"  Parameters: {params}")
        print()

        # Extract unique trace names
        trace_names = sorted(set(result.get('trace_name', '') for result in data.get('results', [])))

        # Calculate metrics for all traces
        trace_metrics_dict = {}
        for trace in trace_names:
            if trace:
                metrics = extract_trace_metrics(data, trace)
                if metrics:
                    trace_metrics_dict[trace] = metrics

        # Display summary table
        print("  Performance Summary:")
        print(f"  {'Trace':<15} {'Median':>8} {'P90':>8} {'Mean':>8} {'P99':>8} {'Consist':>8} {'Score':>8}")
        print("  " + "-" * 75)

        for trace in trace_names:
            if not trace or trace not in trace_metrics_dict:
                continue

            metrics = trace_metrics_dict[trace]
            print(f"  {trace:<15} {metrics['median_ms']:>8.2f} {metrics['p90_ms']:>8.2f} "
                  f"{metrics['mean_ms']:>8.2f} {metrics['p99_ms']:>8.2f} "
                  f"{metrics['consistency']:>8.3f} {metrics['weighted_score']:>8.2f}")

        # Calculate and display overall score
        overall_score = calculate_overall_score(trace_metrics_dict)
        print("  " + "-" * 75)
        print(f"  Overall Score (Geometric Mean): {overall_score:8.2f} ms")
        print()

        # Show detailed metrics for each trace
        for trace in trace_names:
            if trace and trace in trace_metrics_dict:
                print_detailed_metrics(trace_metrics_dict[trace], trace)

        print()
        print()

        file_data.append((file_path, data, trace_metrics_dict))
    
    # Generate summary comparison if multiple files
    if len(file_data) > 1:
        print("=== Performance Trends ===")
        print()

        first_file, first_data, first_metrics = file_data[0]
        last_file, last_data, last_metrics = file_data[-1]

        first_timestamp = first_data.get('timestamp', 0)
        last_timestamp = last_data.get('timestamp', 0)

        first_date = "unknown"
        last_date = "unknown"

        try:
            if first_timestamp:
                first_date = datetime.fromtimestamp(int(first_timestamp)).strftime('%Y-%m-%d')
            if last_timestamp:
                last_date = datetime.fromtimestamp(int(last_timestamp)).strftime('%Y-%m-%d')
        except (ValueError, OSError):
            pass

        print(f"Comparison between {first_date} and {last_date}:")
        print()

        # Calculate overall scores for comparison
        first_overall_score = calculate_overall_score(first_metrics)
        last_overall_score = calculate_overall_score(last_metrics)

        print("Overall Performance Comparison:")
        print(f"  First:  {first_overall_score:8.2f} ms")
        print(f"  Latest: {last_overall_score:8.2f} ms")

        if first_overall_score > 0:
            overall_change_pct = ((last_overall_score - first_overall_score) / first_overall_score) * 100
            direction = "improvement" if overall_change_pct < 0 else "regression"
            print(f"  Change: {overall_change_pct:+.1f}% ({direction})")
        print()

        # Detailed trace comparison
        print("Individual Trace Comparison (Weighted Scores):")
        print(f"{'Trace':<15} {'First':>8} {'Latest':>8} {'Change%':>10} {'Status':>12}")
        print("-" * 60)

        # Get common trace names
        common_traces = set(first_metrics.keys()) & set(last_metrics.keys())

        for trace in sorted(common_traces):
            first_score = first_metrics[trace]['weighted_score']
            last_score = last_metrics[trace]['weighted_score']

            if first_score > 0:
                change_pct = ((last_score - first_score) / first_score) * 100
                change_str = f"{change_pct:+.1f}%"

                if change_pct < -5:
                    status = "IMPROVED"
                elif change_pct > 5:
                    status = "REGRESSED"
                else:
                    status = "STABLE"
            else:
                change_str = "N/A"
                status = "N/A"

            print(f"{trace:<15} {first_score:>8.2f} {last_score:>8.2f} {change_str:>10} {status:>12}")

        print()

        # Show optimization insights
        print("=== Optimization Insights ===")
        print("Individual metric breakdown for latest benchmark:")
        print()

        for trace in sorted(last_metrics.keys()):
            metrics = last_metrics[trace]
            print(f"{trace.upper()} - Areas for optimization:")

            # Calculate contribution of each component to weighted score
            median_contrib = SCORING_WEIGHTS['median'] * metrics['median_ms']
            p90_contrib = SCORING_WEIGHTS['p90'] * metrics['p90_ms']
            mean_contrib = SCORING_WEIGHTS['mean'] * metrics['mean_ms']
            p99_contrib = SCORING_WEIGHTS['p99'] * metrics['p99_ms']
            consistency_contrib = SCORING_WEIGHTS['consistency'] * (1.0 - metrics['consistency']) * metrics['mean_ms']

            contributions = [
                ("Median (P50)", median_contrib, 0.35),
                ("P90", p90_contrib, 0.25),
                ("Mean", mean_contrib, 0.20),
                ("P99", p99_contrib, 0.10),
                ("Inconsistency", consistency_contrib, 0.10)
            ]

            # Sort by contribution (highest first)
            contributions.sort(key=lambda x: x[1], reverse=True)

            for name, contrib, weight in contributions:
                print(f"  • {name:<15}: {contrib:6.2f} ms ({weight*100:2.0f}% weight)")

            print(f"  Total Score: {metrics['weighted_score']:6.2f} ms")
            print()

        print()

if __name__ == "__main__":
    generate_report()