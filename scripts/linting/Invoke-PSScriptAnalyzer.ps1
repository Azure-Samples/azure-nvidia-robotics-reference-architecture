#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs PSScriptAnalyzer on PowerShell files in the repository.

.DESCRIPTION
    Wrapper script for PSScriptAnalyzer that provides GitHub Actions integration,
    automatic module installation, and configurable file targeting.

.PARAMETER ChangedFilesOnly
    When specified, only analyze PowerShell files that have changed compared to the base branch.

.PARAMETER BaseBranch
    The base branch to compare against when using ChangedFilesOnly. Defaults to 'origin/main'.

.PARAMETER ConfigPath
    Path to the PSScriptAnalyzer settings file. Defaults to 'scripts/linting/PSScriptAnalyzer.psd1'.

.PARAMETER OutputPath
    Path for JSON results output. When specified, results are exported to this file.

.PARAMETER SoftFail
    When specified, the script exits with code 0 even if violations are found.

.EXAMPLE
    ./Invoke-PSScriptAnalyzer.ps1
    Analyzes all PowerShell files in the repository.

.EXAMPLE
    ./Invoke-PSScriptAnalyzer.ps1 -ChangedFilesOnly -BaseBranch 'origin/main'
    Analyzes only changed PowerShell files compared to origin/main.
#>
[CmdletBinding()]
param(
    [switch]$ChangedFilesOnly,
    [string]$BaseBranch = 'origin/main',
    [string]$ConfigPath = '',
    [string]$OutputPath = '',
    [switch]$SoftFail
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import shared helper functions
$modulePath = Join-Path $PSScriptRoot 'Modules/LintingHelpers.psm1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}

# Determine repository root
$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    $repoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
}

# Set default config path if not specified
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot 'PSScriptAnalyzer.psd1'
}

# Ensure PSScriptAnalyzer module is installed
Write-Host '::group::PSScriptAnalyzer Setup'
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'Installing PSScriptAnalyzer module...'
    Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -Repository PSGallery
}
Import-Module PSScriptAnalyzer -Force
Write-Host "PSScriptAnalyzer version: $((Get-Module PSScriptAnalyzer).Version)"
Write-Host '::endgroup::'

# Collect files to analyze
Write-Host '::group::Collecting Files'
$filesToAnalyze = @()

if ($ChangedFilesOnly) {
    Write-Host "Analyzing changed files only (base: $BaseBranch)"
    if (Get-Command -Name 'Get-ChangedFilesFromGit' -ErrorAction SilentlyContinue) {
        $filesToAnalyze = Get-ChangedFilesFromGit -BaseBranch $BaseBranch -FileExtensions @('*.ps1', '*.psm1', '*.psd1')
    } else {
        # Fallback if module not available
        $mergeBase = git merge-base HEAD $BaseBranch 2>$null
        if (-not $mergeBase) {
            $mergeBase = $BaseBranch
        }
        $changedFiles = git diff --name-only --diff-filter=d $mergeBase HEAD 2>$null
        if ($changedFiles) {
            $filesToAnalyze = $changedFiles | Where-Object { $_ -match '\.(ps1|psm1|psd1)$' } | ForEach-Object {
                Join-Path $repoRoot $_
            } | Where-Object { Test-Path $_ }
        }
    }
} else {
    Write-Host 'Analyzing all PowerShell files in repository'
    $filesToAnalyze = Get-ChildItem -Path $repoRoot -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|vendor)[\\/]' } |
        Select-Object -ExpandProperty FullName
}

Write-Host "Found $($filesToAnalyze.Count) file(s) to analyze"
if ($filesToAnalyze.Count -gt 0) {
    $filesToAnalyze | ForEach-Object { Write-Host "  - $_" }
}
Write-Host '::endgroup::'

# Run analysis
$allResults = @()
$errorCount = 0
$warningCount = 0

if ($filesToAnalyze.Count -gt 0) {
    Write-Host '::group::PSScriptAnalyzer Results'

    foreach ($file in $filesToAnalyze) {
        $relativePath = $file
        if ($file.StartsWith($repoRoot)) {
            $relativePath = $file.Substring($repoRoot.Length).TrimStart('\', '/')
        }

        $analyzerParams = @{
            Path = $file
            Recurse = $false
        }

        if ((Test-Path $ConfigPath)) {
            $analyzerParams['Settings'] = $ConfigPath
        }

        $results = Invoke-ScriptAnalyzer @analyzerParams

        if ($results) {
            $allResults += $results

            foreach ($result in $results) {
                $severity = $result.Severity.ToString().ToLower()
                $message = "$($result.RuleName): $($result.Message)"

                # Map PSScriptAnalyzer severity to GitHub annotation type
                $annotationType = switch ($severity) {
                    'error' { 'error' }
                    'warning' { 'warning' }
                    default { 'notice' }
                }

                if ($severity -eq 'error') { $errorCount++ }
                if ($severity -eq 'warning') { $warningCount++ }

                # Write GitHub Actions annotation
                if (Get-Command -Name 'Write-GitHubAnnotation' -ErrorAction SilentlyContinue) {
                    Write-GitHubAnnotation -Type $annotationType -Message $message -File $relativePath -Line $result.Line -Column $result.Column
                } else {
                    Write-Host "::$annotationType file=$relativePath,line=$($result.Line),col=$($result.Column)::$message"
                }
            }
        }
    }

    Write-Host '::endgroup::'
}

# Export results if OutputPath specified
if ($OutputPath) {
    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $exportData = @{
        timestamp = (Get-Date).ToString('o')
        totalFiles = $filesToAnalyze.Count
        errorCount = $errorCount
        warningCount = $warningCount
        results = $allResults | ForEach-Object {
            @{
                file = $_.ScriptPath
                line = $_.Line
                column = $_.Column
                severity = $_.Severity.ToString()
                rule = $_.RuleName
                message = $_.Message
            }
        }
    }

    $exportData | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Results exported to: $OutputPath"
}

# Summary
Write-Host ''
Write-Host "PSScriptAnalyzer Summary:"
Write-Host "  Files analyzed: $($filesToAnalyze.Count)"
Write-Host "  Errors: $errorCount"
Write-Host "  Warnings: $warningCount"

# Set GitHub outputs if available
if (Get-Command -Name 'Set-GitHubOutput' -ErrorAction SilentlyContinue) {
    Set-GitHubOutput -Name 'error-count' -Value $errorCount
    Set-GitHubOutput -Name 'warning-count' -Value $warningCount
    Set-GitHubOutput -Name 'files-analyzed' -Value $filesToAnalyze.Count
}

# Write step summary if in GitHub Actions
if ($env:GITHUB_STEP_SUMMARY) {
    $summary = @"
## PSScriptAnalyzer Results

| Metric | Count |
|--------|-------|
| Files Analyzed | $($filesToAnalyze.Count) |
| Errors | $errorCount |
| Warnings | $warningCount |

"@
    if (Get-Command -Name 'Write-GitHubStepSummary' -ErrorAction SilentlyContinue) {
        Write-GitHubStepSummary -Content $summary
    } else {
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $summary
    }
}

# Exit with appropriate code
if ($errorCount -gt 0 -and -not $SoftFail) {
    Write-Host ''
    Write-Host "::error::PSScriptAnalyzer found $errorCount error(s). Fix the issues above."
    exit 1
}

exit 0
