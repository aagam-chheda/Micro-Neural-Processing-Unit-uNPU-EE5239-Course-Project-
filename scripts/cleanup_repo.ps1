# One-off cleanup of build output that was committed to the repo.
# Run from the repo root in PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\cleanup_repo.ps1
# Then review with `git status` and commit.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

# 1. DC WORK library files: pure regenerable output -> remove from git AND disk.
$dc = Get-ChildItem -File -Name | Where-Object { $_ -match '-s?verilog\.(pvl|syn)$' -or $_ -match '^UNPU_.*\.mr$' }
if ($dc) { git rm -q -- $dc; Write-Host "Removed $($dc.Count) DC WORK files" }

# 2. Logs at the root -> move into logs/ (kept on disk, no longer tracked).
foreach ($f in @('Synopsys_stack_trace_23694.txt','lm_output.txt','icc2_output.txt')) {
    if (Test-Path $f) { git rm -q --cached -- $f; Move-Item -Force $f logs\ ; Write-Host "Moved $f -> logs\" }
}

# 3. Simulator scratch: stop tracking, keep the files on disk.
git rm -r -q --cached --ignore-unmatch -- `
    sim/compile/run.lnx8664.22.09.d sim/compile/worklib `
    sim/pe/run.lnx8664.22.09.d     sim/pe/worklib `
    gls/top/run.lnx8664.22.09.d    gls/top/worklib `
    logs/compile.history logs/gls_top.history logs/sim_pe.history `
    unpu_pnr_scripts.zip

git status --short
Write-Host "`nReview the list above, then: git commit -m 'Clean up committed build output'"
