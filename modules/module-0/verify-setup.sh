#!/usr/bin/env bash
# Module 0: verify required tools are installed and the workshop cluster is reachable.
# Exits 0 if everything passes, non-zero if anything fails.

set -u

pass=0
fail=0

# check <label> <command...>
# Prints [OK]/[MISS] based on exit code; on success prints a one-line version.
check() {
    local label="$1"; shift
    if out=$("$@" 2>&1); then
        # keep only the first non-empty line
        out=$(printf "%s\n" "$out" | awk 'NF{print; exit}')
        printf "  [OK]   %-10s %s\n" "$label" "$out"
        pass=$((pass + 1))
    else
        printf "  [MISS] %-10s (command: %s)\n" "$label" "$*"
        fail=$((fail + 1))
    fi
}

check_any() {
    local label="$1"; shift
    for cmd in "$@"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            out=$("$cmd" --version 2>&1 | awk 'NF{print; exit}')
            printf "  [OK]   %-10s %s\n" "$label" "$out"
            pass=$((pass + 1))
            return 0
        fi
    done
    printf "  [MISS] %-10s none of: %s\n" "$label" "$*"
    fail=$((fail + 1))
}

echo "==> Checking tool versions"
check_any "python"  python3 python
check_any "pip"     pip3 pip
check     "go"      go version
check     "docker"  docker --version
check     "kubectl" kubectl version --client
check     "kind"    kind version

echo ""
echo "==> Checking Docker daemon"
if docker info >/dev/null 2>&1; then
    echo "  [OK]   Docker daemon reachable"
    pass=$((pass + 1))
else
    echo "  [MISS] Docker daemon not reachable — start Docker Desktop"
    fail=$((fail + 1))
fi

echo ""
echo "==> Checking kind cluster 'mlops-workshop'"
if kind get clusters 2>/dev/null | grep -q '^mlops-workshop$'; then
    echo "  [OK]   kind cluster exists"
    pass=$((pass + 1))
    if kubectl --context kind-mlops-workshop get nodes >/dev/null 2>&1; then
        echo "  [OK]   kubectl can reach the cluster"
        pass=$((pass + 1))
    else
        echo "  [MISS] kubectl context 'kind-mlops-workshop' not reachable"
        fail=$((fail + 1))
    fi
else
    echo "  [WARN] kind cluster 'mlops-workshop' not found"
    echo "         Create it:  kind create cluster --config kind.yaml"
fi

echo ""
echo "==> Summary: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
