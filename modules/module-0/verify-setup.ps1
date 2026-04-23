# Module 0: verify required tools are installed and the workshop cluster is reachable.
# Exits 0 if everything passes, non-zero if anything fails.

$pass = 0
$fail = 0

function Check-Tool {
    param([string]$Label, [string]$Command, [string[]]$Args)
    try {
        $out = & $Command @Args 2>&1
        if ($LASTEXITCODE -ne 0) { throw }
        $firstLine = ($out | Where-Object { $_ -match '\S' } | Select-Object -First 1)
        Write-Host ("  [OK]   {0,-10} {1}" -f $Label, $firstLine)
        $script:pass++
    } catch {
        Write-Host ("  [MISS] {0,-10} (command: {1} {2})" -f $Label, $Command, ($Args -join ' '))
        $script:fail++
    }
}

function Check-Any {
    param([string]$Label, [string[]]$Commands)
    foreach ($cmd in $Commands) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            $out = & $cmd --version 2>&1 | Where-Object { $_ -match '\S' } | Select-Object -First 1
            Write-Host ("  [OK]   {0,-10} {1}" -f $Label, $out)
            $script:pass++
            return
        }
    }
    Write-Host ("  [MISS] {0,-10} none of: {1}" -f $Label, ($Commands -join ', '))
    $script:fail++
}

Write-Host "==> Checking tool versions"
Check-Any "python"  @("python", "python3")
Check-Any "pip"     @("pip", "pip3")
Check-Tool "go"      "go"      @("version")
Check-Tool "docker"  "docker"  @("--version")
Check-Tool "kubectl" "kubectl" @("version", "--client")
Check-Tool "kind"    "kind"    @("version")

Write-Host ""
Write-Host "==> Checking Docker daemon"
$dockerInfo = docker info 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK]   Docker daemon reachable"
    $pass++
} else {
    Write-Host "  [MISS] Docker daemon not reachable -- start Docker Desktop"
    $fail++
}

Write-Host ""
Write-Host "==> Checking kind cluster 'mlops-workshop'"
$clusters = kind get clusters 2>$null
if ($clusters -match '^mlops-workshop$') {
    Write-Host "  [OK]   kind cluster exists"
    $pass++
    kubectl --context kind-mlops-workshop get nodes 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK]   kubectl can reach the cluster"
        $pass++
    } else {
        Write-Host "  [MISS] kubectl context 'kind-mlops-workshop' not reachable"
        $fail++
    }
} else {
    Write-Host "  [WARN] kind cluster 'mlops-workshop' not found"
    Write-Host "         Create it:  kind create cluster --config kind.yaml"
}

Write-Host ""
Write-Host "==> Summary: $pass passed, $fail failed"
exit $fail
