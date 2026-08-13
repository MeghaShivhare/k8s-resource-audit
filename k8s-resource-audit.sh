#!/usr/bin/env bash

set -euo pipefail

# Default option values
NAMESPACE=""
ONLY_MISSING=false
INPUT_FILE=""
FORMAT="table"

# Helper for printing usage
show_help() {
  cat << EOF
Kubernetes Resource Audit Tool

Scan Kubernetes Deployments and audit containers for missing CPU and memory requests or limits.

Usage:
  $(basename "$0") [options]

Options:
  -n, --namespace <ns>      Scan a specific namespace (defaults to all namespaces)
  --only-missing            Only show containers with resource issues (missing request/limit)
  -f, --file <path>         Read Kubernetes deployment JSON from a file (use "-" for stdin)
  --format <format>         Output format: table, csv, tsv, json (default: table)
  -h, --help                Show this help message and exit

Examples:
  # Scan all deployments in the active cluster context
  ./$(basename "$0")

  # Scan only the "backend" namespace and print CSV
  ./$(basename "$0") -n backend --format csv

  # Scan a pre-saved deployments JSON file, displaying only issues
  ./$(basename "$0") -f deployments.json --only-missing
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      if [[ -z "${2:-}" ]]; then
        echo "Error: Option $1 requires an argument" >&2
        exit 1
      fi
      NAMESPACE="$2"
      shift 2
      ;;
    --namespace=*)
      NAMESPACE="${1#*=}"
      shift 1
      ;;
    --only-missing)
      ONLY_MISSING=true
      shift 1
      ;;
    -f|--file)
      if [[ -z "${2:-}" ]]; then
        echo "Error: Option $1 requires an argument" >&2
        exit 1
      fi
      INPUT_FILE="$2"
      shift 2
      ;;
    --file=*)
      INPUT_FILE="${1#*=}"
      shift 1
      ;;
    --format)
      if [[ -z "${2:-}" ]]; then
        echo "Error: Option $1 requires an argument" >&2
        exit 1
      fi
      FORMAT="$2"
      shift 2
      ;;
    --format=*)
      FORMAT="${1#*=}"
      shift 1
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Error: Unknown option $1" >&2
      show_help >&2
      exit 1
      ;;
  esac
done

# Validate format choice
if [[ "$FORMAT" != "table" && "$FORMAT" != "csv" && "$FORMAT" != "tsv" && "$FORMAT" != "json" ]]; then
  echo "Error: Invalid format: '$FORMAT'. Supported formats: table, csv, tsv, json" >&2
  exit 1
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first." >&2
  exit 1
fi

# Create a temporary directory for audit processing
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

INPUT_JSON="$TMP_DIR/input.json"
REPORT_JSON="$TMP_DIR/report.json"

# Retrieve JSON source input
if [[ "$INPUT_FILE" == "-" ]]; then
  cat > "$INPUT_JSON"
elif [[ -n "$INPUT_FILE" ]]; then
  if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: File not found: $INPUT_FILE" >&2
    exit 1
  fi
  cat "$INPUT_FILE" > "$INPUT_JSON"
elif [[ ! -t 0 ]]; then
  # Stdin is redirected (piped input)
  cat > "$INPUT_JSON"
else
  # Live cluster query
  if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is required to scan a live cluster context." >&2
    echo "Install kubectl or pass a JSON file with -f/--file." >&2
    exit 1
  fi
  
  if [[ -n "$NAMESPACE" ]]; then
    if ! kubectl get deployments -n "$NAMESPACE" -o json > "$INPUT_JSON" 2>/dev/null; then
      echo "Error: Failed to fetch deployments from cluster. Check connection or namespace '$NAMESPACE'." >&2
      exit 1
    fi
  else
    if ! kubectl get deployments -A -o json > "$INPUT_JSON" 2>/dev/null; then
      echo "Error: Failed to fetch deployments from cluster. Check connection." >&2
      exit 1
    fi
  fi
fi

# Validate input is valid JSON
if ! jq empty "$INPUT_JSON" &>/dev/null; then
  echo "Error: Input is not a valid JSON document." >&2
  exit 1
fi

# Audit processing inside jq
# Map namespace filter and calculate statistics and issue messages
jq --arg namespace "$NAMESPACE" '
  .items // [] |
  map(
    select($namespace == "" or .metadata.namespace == $namespace)
  ) as $filtered_items |
  [
    $filtered_items[] |
    .metadata.namespace as $ns |
    .metadata.name as $deployment |
    if .spec.template.spec.containers == null then empty
    else
      .spec.template.spec.containers[] |
      .name as $container_name |
      .resources.requests.cpu as $req_cpu |
      .resources.requests.memory as $req_mem |
      .resources.limits.cpu as $lim_cpu |
      .resources.limits.memory as $lim_mem |
      ($req_cpu == null) as $no_req_cpu |
      ($req_mem == null) as $no_req_mem |
      ($lim_cpu == null) as $no_lim_cpu |
      ($lim_mem == null) as $no_lim_mem |
      (
        if $no_req_cpu and $no_req_mem and $no_lim_cpu and $no_lim_mem then "Requests & limits missing"
        elif $no_req_cpu and $no_req_mem then "Requests missing"
        elif $no_lim_cpu and $no_lim_mem then "Limits missing"
        else
          [
            (if $no_req_cpu then "CPU request" else empty end),
            (if $no_req_mem then "Memory request" else empty end),
            (if $no_lim_cpu then "CPU limit" else empty end),
            (if $no_lim_mem then "Memory limit" else empty end)
          ] | join(" & ") + (if length > 0 then " missing" else "" end)
        end
      ) as $issue |
      {
        namespace: $ns,
        deployment: $deployment,
        container: $container_name,
        issue: $issue
      }
    end
  ] as $all_containers |
  ($filtered_items | map({namespace: .metadata.namespace, name: .metadata.name}) | unique | length) as $scanned_count |
  ($all_containers | map(select(.issue != "")) | map({namespace: .namespace, deployment: .deployment}) | unique | length) as $problematic_count |
  {
    scanned_deployments_count: $scanned_count,
    problematic_deployments_count: $problematic_count,
    results: $all_containers
  }
' "$INPUT_JSON" > "$REPORT_JSON"

# Output formatting
case "$FORMAT" in
  json)
    jq --argjson only_missing "$ONLY_MISSING" '
      if $only_missing then
        .results |= map(select(.issue != ""))
      else
        .
      end
    ' "$REPORT_JSON"
    ;;
  
  csv)
    echo "Namespace,Deployment,Container,Issue"
    jq -r --argjson only_missing "$ONLY_MISSING" '
      .results[] |
      select($only_missing == false or .issue != "") |
      [
        .namespace,
        .deployment,
        .container,
        (if .issue == "" then "OK" else .issue end)
      ] |
      @csv
    ' "$REPORT_JSON"
    ;;

  tsv)
    echo -e "Namespace\tDeployment\tContainer\tIssue"
    jq -r --argjson only_missing "$ONLY_MISSING" '
      .results[] |
      select($only_missing == false or .issue != "") |
      [
        .namespace,
        .deployment,
        .container,
        (if .issue == "" then "OK" else .issue end)
      ] |
      @tsv
    ' "$REPORT_JSON"
    ;;

  table)
    # Print clean header
    echo "Kubernetes Resource Audit"
    echo "────────────────────────────────────────────────────────────────────────────────"
    echo

    # Align columns using column
    (
      echo -e "NAMESPACE\tDEPLOYMENT\tCONTAINER\tISSUE"
      jq -r --argjson only_missing "$ONLY_MISSING" '
        .results[] |
        select($only_missing == false or .issue != "") |
        [
          .namespace,
          .deployment,
          .container,
          (if .issue == "" then "OK" else .issue end)
        ] |
        @tsv
      ' "$REPORT_JSON"
    ) | column -t -s $'\t'

    echo
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    # Print metrics footer
    scanned_count=$(jq -r '.scanned_deployments_count' "$REPORT_JSON")
    problematic_count=$(jq -r '.problematic_deployments_count' "$REPORT_JSON")
    echo "Deployments scanned: $scanned_count"
    echo "Deployments with issues: $problematic_count"
    ;;
esac
