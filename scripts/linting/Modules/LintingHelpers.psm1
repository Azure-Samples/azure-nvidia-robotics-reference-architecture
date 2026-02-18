# LintingHelpers.psm1
#
# Purpose: Shared helper functions for linting scripts and workflows
# Author: HVE Core Team
# Created: 2025-11-05

function Get-ChangedFilesFromGit {
    <#
    .SYNOPSIS
    Gets changed files from git with intelligent fallback strategies.

    .DESCRIPTION
    Attempts to detect changed files using merge-base, with fallbacks for different scenarios.

    .PARAMETER BaseBranch
    The base branch to compare against (default: origin/main).

    .PARAMETER FileExtensions
    Array of file extensions to filter (e.g., @('*.ps1', '*.md')).

    .OUTPUTS
    Array of changed file paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$BaseBranch = "origin/main",

        [Parameter(Mandatory = $false)]
        [string[]]$FileExtensions = @('*')
    )

    $changedFiles = @()

    try {
        # Try merge-base first (best for PRs)
        $mergeBase = git merge-base HEAD $BaseBranch 2>$null
        if ($LASTEXITCODE -eq 0 -and $mergeBase) {
            $changedFiles = git diff --name-only $mergeBase HEAD 2>$null
        }
        else {
            # Fallback: compare directly with base branch
            $changedFiles = git diff --name-only $BaseBranch HEAD 2>$null
            if ($LASTEXITCODE -ne 0) {
                # Final fallback: get all tracked files
                Write-Warning "Could not determine changed files, analyzing all files"
                $changedFiles = git ls-files 2>$null
            }
        }
    }
    catch {
        Write-Warning "Git operation failed: $_"
        $changedFiles = git ls-files 2>$null
    }

    # Filter by extensions
    if ($FileExtensions -and $FileExtensions[0] -ne '*') {
        $filteredFiles = @()
        foreach ($file in $changedFiles) {
            foreach ($ext in $FileExtensions) {
                $pattern = $ext.TrimStart('*')
                if ($file -like "*$pattern") {
                    $filteredFiles += $file
                    break
                }
            }
        }
        $changedFiles = $filteredFiles
    }

    # Return only existing files
    $existingFiles = @()
    foreach ($file in $changedFiles) {
        if (Test-Path $file) {
            $existingFiles += $file
        }
    }

    return $existingFiles
}

function Get-FilesRecursive {
    <#
    .SYNOPSIS
    Gets files recursively with gitignore pattern support.

    .DESCRIPTION
    Retrieves files matching specified patterns while respecting gitignore rules.

    .PARAMETER Path
    Root path to search from.

    .PARAMETER Include
    Array of file patterns to include (e.g., @('*.ps1', '*.psm1')).

    .PARAMETER GitIgnorePath
    Path to .gitignore file for exclusion patterns.

    .OUTPUTS
    Array of file paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string[]]$Include = @('*'),

        [Parameter(Mandatory = $false)]
        [string]$GitIgnorePath
    )

    $files = @()
    $excludePatterns = @()

    # Load gitignore patterns if provided
    if ($GitIgnorePath -and (Test-Path $GitIgnorePath)) {
        $excludePatterns = Get-GitIgnorePatterns -GitIgnorePath $GitIgnorePath
    }

    # Get all files matching include patterns
    foreach ($pattern in $Include) {
        $matchingFiles = Get-ChildItem -Path $Path -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue
        $basePath = (Resolve-Path -LiteralPath $Path).Path
        foreach ($file in $matchingFiles) {
            $relativePath = [System.IO.Path]::GetRelativePath($basePath, $file.FullName)

            # Check against exclude patterns
            $excluded = $false
            foreach ($excludePattern in $excludePatterns) {
                if ($relativePath -like $excludePattern) {
                    $excluded = $true
                    break
                }
            }

            if (-not $excluded) {
                $files += $file
            }
        }
    }

    return $files | Select-Object -Unique
}

function Get-GitIgnorePatterns {
    <#
    .SYNOPSIS
    Converts gitignore patterns to PowerShell wildcard patterns.

    .PARAMETER GitIgnorePath
    Path to the .gitignore file.

    .OUTPUTS
    Array of PowerShell wildcard patterns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GitIgnorePath
    )

    $patterns = @()

    if (-not (Test-Path $GitIgnorePath)) {
        return $patterns
    }

    $lines = Get-Content $GitIgnorePath -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        $line = $line.Trim()

        # Skip comments and empty lines
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        # Convert to PowerShell pattern
        $pattern = if ($line.StartsWith('/')) {
            $line.Substring(1).Replace('/', '\')
        }
        elseif ($line.Contains('/')) {
            "*\$($line.Replace('/', '\'))*"
        }
        else {
            "*\$line\*"
        }

        $patterns += $pattern
    }

    return $patterns
}

function Write-GitHubAnnotation {
    <#
    .SYNOPSIS
    Writes GitHub Actions annotations for errors, warnings, or notices.

    .PARAMETER Type
    Annotation type: 'error', 'warning', or 'notice'.

    .PARAMETER Message
    The annotation message.

    .PARAMETER File
    Optional file path.

    .PARAMETER Line
    Optional line number.

    .PARAMETER Column
    Optional column number.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('error', 'warning', 'notice')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$File,

        [Parameter(Mandatory = $false)]
        [int]$Line,

        [Parameter(Mandatory = $false)]
        [int]$Column
    )

    if ($env:GITHUB_ACTIONS) {
        $annotation = "::$Type"
        $params = @()

        if ($File) { $params += "file=$File" }
        if ($Line) { $params += "line=$Line" }
        if ($Column) { $params += "col=$Column" }

        if ($params.Count -gt 0) {
            $annotation += " $($params -join ',')"
        }

        $annotation += "::$Message"
        Write-Host $annotation
    }
    else {
        $prefix = switch ($Type) {
            'error' { 'ERROR' }
            'warning' { 'WARN' }
            'notice' { 'INFO' }
        }
        Write-Host "$prefix $Message"
    }
}

function Set-GitHubOutput {
    <#
    .SYNOPSIS
    Sets a GitHub Actions output variable.

    .PARAMETER Name
    Output variable name.

    .PARAMETER Value
    Output variable value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($env:GITHUB_OUTPUT) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    }
    else {
        Write-Verbose "GitHub output: $Name=$Value"
    }
}

function Set-GitHubEnv {
    <#
    .SYNOPSIS
    Sets a GitHub Actions environment variable.

    .PARAMETER Name
    Environment variable name.

    .PARAMETER Value
    Environment variable value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($env:GITHUB_ENV) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
    }
    else {
        Write-Verbose "GitHub env: $Name=$Value"
    }
}

function Write-GitHubStepSummary {
    <#
    .SYNOPSIS
    Appends content to GitHub Actions step summary.

    .PARAMETER Content
    Markdown content to append.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    if ($env:GITHUB_STEP_SUMMARY) {
        $Content | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    }
    else {
        Write-Verbose "Not in GitHub Actions environment - summary content: $Content"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ChangedFilesFromGit',
    'Get-FilesRecursive',
    'Get-GitIgnorePatterns',
    'Write-GitHubAnnotation',
    'Set-GitHubOutput',
    'Set-GitHubEnv',
    'Write-GitHubStepSummary'
)
