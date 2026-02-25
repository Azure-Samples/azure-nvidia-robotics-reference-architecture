# deploy-to-osmo.ps1 - Transfer files, build image, and submit training on OSMO
# -------------------------------------------------------------------------
# Transfers all training files + rosbag data to the OSMO instance via SCP,
# builds the Docker image on the remote host, and submits the workflow.
#
# Usage (from the train/ directory):
#   .\osmo\deploy-to-osmo.ps1                          # base single-GPU workflow
#   .\osmo\deploy-to-osmo.ps1 -Workflow wandb          # wandb-enabled
#   .\osmo\deploy-to-osmo.ps1 -Workflow ddp             # multi-GPU DDP
#   .\osmo\deploy-to-osmo.ps1 -Workflow sweep           # hyperparameter sweep
#   .\osmo\deploy-to-osmo.ps1 -SkipBuild                # skip Docker build
#   .\osmo\deploy-to-osmo.ps1 -SkipData                 # skip rosbag data transfer
#   .\osmo\deploy-to-osmo.ps1 -Pool my-gpu-pool         # target a specific pool
# -------------------------------------------------------------------------

param(
    [string]$OsmoHost   = "192.168.1.100",
    [string]$OsmoUser   = "workstation2",
    [string]$RemoteDir  = "~/ur10e-act-train",
    [string]$Registry   = "192.168.1.100:5000",
    [string]$ImageName  = "ur10e-act-train",
    [string]$ImageTag   = "latest",
    [string]$Pool       = "",
    [string]$Workflow   = "base",
    [switch]$SkipBuild,
    [switch]$SkipData
)

$ErrorActionPreference = "Stop"

# --------------- Resolve paths ---------------
$TrainDir = $PSScriptRoot | Split-Path   # train/
Push-Location $TrainDir

$WorkflowMap = @{
    "base"       = "osmo/osmo-workflow.yaml"
    "wandb"      = "osmo/osmo-workflow-wandb.yaml"
    "ddp"        = "osmo/osmo-workflow-ddp.yaml"
    "sweep"      = "osmo/osmo-workflow-sweep.yaml"
    "blob"       = "osmo/osmo-workflow-blob.yaml"
    "train-eval" = "osmo/osmo-workflow-train-eval.yaml"
}

if (-not $WorkflowMap.ContainsKey($Workflow)) {
    Write-Error "Unknown workflow '$Workflow'. Options: $($WorkflowMap.Keys -join ', ')"
    Pop-Location
    exit 1
}

$WorkflowFile = $WorkflowMap[$Workflow]
$Remote = "${OsmoUser}@${OsmoHost}"

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " UR10e ACT - OSMO Training Deploy"     -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  OSMO Host     : $Remote"
Write-Host "  Remote Dir    : $RemoteDir"
Write-Host "  Registry      : $Registry"
Write-Host "  Workflow      : $Workflow ($WorkflowFile)"
if ($Pool) { Write-Host "  Pool          : $Pool" }
Write-Host ""

# --------------- Step 1: Create remote directory structure ---------------
Write-Host "[1/5] Creating remote directories ..." -ForegroundColor Yellow
ssh $Remote "mkdir -p $RemoteDir/osmo $RemoteDir/local_bags"
if ($LASTEXITCODE -ne 0) {
    Write-Error "SSH failed. Verify connectivity and credentials for $Remote."
    Pop-Location
    exit 1
}
Write-Host "  -> OK" -ForegroundColor Green

# --------------- Step 2: Transfer training files ---------------
Write-Host "[2/5] Transferring training files ..." -ForegroundColor Yellow

$TrainingFiles = @(
    "train.py",
    "act_model.py",
    "config.yaml",
    "pyproject.toml"
)

foreach ($f in $TrainingFiles) {
    if (Test-Path $f) {
        Write-Host "  -> $f" -ForegroundColor DarkGray
        scp $f "${Remote}:${RemoteDir}/$f"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "SCP failed for $f"
            Pop-Location
            exit 1
        }
    }
}

# Transfer osmo/ directory contents
$OsmoFiles = Get-ChildItem -Path "osmo" -File
foreach ($f in $OsmoFiles) {
    Write-Host "  -> osmo/$($f.Name)" -ForegroundColor DarkGray
    scp "osmo/$($f.Name)" "${Remote}:${RemoteDir}/osmo/$($f.Name)"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "SCP failed for osmo/$($f.Name)"
        Pop-Location
        exit 1
    }
}

Write-Host "  -> All training files transferred" -ForegroundColor Green

# --------------- Step 3: Transfer rosbag data ---------------
if (-not $SkipData) {
    $BagDir = "../rosbag-to-lerobot/local_bags"
    if (Test-Path $BagDir) {
        $Recordings = Get-ChildItem -Path $BagDir -Directory
        $RecCount = $Recordings.Count
        Write-Host "[3/5] Transferring rosbag data - $RecCount recordings ..." -ForegroundColor Yellow

        foreach ($rec in $Recordings) {
            Write-Host "  -> $($rec.Name)" -ForegroundColor DarkGray
            ssh $Remote "mkdir -p $RemoteDir/local_bags/$($rec.Name)"
            scp -r "$($rec.FullName)/*" "${Remote}:${RemoteDir}/local_bags/$($rec.Name)/"
            if ($LASTEXITCODE -ne 0) {
                Write-Error "SCP failed for recording $($rec.Name)"
                Pop-Location
                exit 1
            }
        }
        Write-Host "  -> Rosbag data transferred" -ForegroundColor Green
    } else {
        Write-Host "[3/5] No rosbag data at $BagDir - skipping" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "[3/5] Skipping rosbag data transfer (--SkipData)" -ForegroundColor DarkGray
}

# --------------- Step 4: Build Docker image on remote ---------------
if (-not $SkipBuild) {
    Write-Host "[4/5] Building Docker image on $OsmoHost ..." -ForegroundColor Yellow

    $BuildCmd = "cd $RemoteDir && docker build -t ${ImageName}:${ImageTag} -f osmo/Dockerfile ."
    ssh $Remote $BuildCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker build failed on $OsmoHost."
        Pop-Location
        exit 1
    }
    Write-Host "  -> Build OK" -ForegroundColor Green

    # Tag for local registry if available
    Write-Host "[4/5] Tagging image for registry ..." -ForegroundColor Yellow
    $TagCmd = "docker tag ${ImageName}:${ImageTag} ${Registry}/${ImageName}:${ImageTag} && docker push ${Registry}/${ImageName}:${ImageTag} 2>/dev/null || echo 'Registry push skipped (registry may not be running)'"
    ssh $Remote $TagCmd
    Write-Host "  -> Tag/push complete" -ForegroundColor Green

    # Build eval image if train-eval workflow
    if ($Workflow -eq "train-eval") {
        Write-Host "[4/5] Building eval image ..." -ForegroundColor Yellow
        $EvalBuildCmd = "cd $RemoteDir && docker build -t ur10e-act-eval:${ImageTag} -f osmo/Dockerfile.eval ."
        ssh $Remote $EvalBuildCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Eval image build failed on $OsmoHost."
            Pop-Location
            exit 1
        }
        Write-Host "  -> Eval image OK" -ForegroundColor Green
    }
} else {
    Write-Host "[4/5] Skipping Docker build (--SkipBuild)" -ForegroundColor DarkGray
}

# --------------- Step 5: Submit workflow ---------------
Write-Host "[5/5] Submitting workflow on $OsmoHost ..." -ForegroundColor Yellow

$PoolArg = ""
if ($Pool) { $PoolArg = "--pool $Pool" }

$SubmitCmd = "cd $RemoteDir && osmo workflow submit $WorkflowFile $PoolArg"
Write-Host "  -> $SubmitCmd" -ForegroundColor DarkGray
ssh $Remote $SubmitCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  Workflow submission returned non-zero. This may be expected if" -ForegroundColor DarkYellow
    Write-Host "  the OSMO CLI is not yet configured on $OsmoHost." -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "  To submit manually, SSH into the instance and run:" -ForegroundColor Yellow
    Write-Host "    ssh $Remote" -ForegroundColor White
    Write-Host "    cd $RemoteDir" -ForegroundColor White
    Write-Host "    osmo workflow submit $WorkflowFile $PoolArg" -ForegroundColor White
    Write-Host ""
    Pop-Location
    exit 0
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host " Workflow submitted successfully!"      -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
Write-Host "Monitor with:"
Write-Host "  ssh $Remote 'osmo workflow list'"
Write-Host "  ssh $Remote 'osmo workflow logs <id> --task train-act --follow'"
Write-Host ""
Write-Host "Download checkpoint after completion:"
Write-Host "  ssh $Remote 'osmo dataset download ur10e-act-checkpoint --output $RemoteDir/checkpoint'"
Write-Host "  scp -r ${Remote}:${RemoteDir}/checkpoint ./checkpoint"
Write-Host ""

Pop-Location
