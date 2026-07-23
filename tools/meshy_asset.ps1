[CmdletBinding(DefaultParameterSetName = "Generate")]
param(
    [Parameter(Mandatory, ParameterSetName = "Generate")]
    [ValidatePattern("^[a-zA-Z0-9][a-zA-Z0-9_-]*$")]
    [string]$Name,

    [Parameter(Mandatory, ParameterSetName = "Generate")]
    [ValidateLength(1, 600)]
    [string]$Prompt,

    [Parameter(ParameterSetName = "Generate")]
    [ValidateLength(0, 600)]
    [string]$TexturePrompt = "",

    [Parameter(ParameterSetName = "Generate")]
    [ValidateSet("standard", "lowpoly")]
    [string]$ModelType = "lowpoly",

    [Parameter(ParameterSetName = "Generate")]
    [ValidateRange(100, 300000)]
    [int]$TargetPolycount = 12000,

    [Parameter(ParameterSetName = "Generate")]
    [ValidateSet("", "a-pose", "t-pose")]
    [string]$PoseMode = "",

    [Parameter(ParameterSetName = "Generate")]
    [switch]$PreviewOnly,

    [Parameter(ParameterSetName = "Generate")]
    [switch]$HdTexture,

    [Parameter(ParameterSetName = "Generate")]
    [switch]$NoAutoSize,

    [Parameter(ParameterSetName = "Generate")]
    [switch]$DryRun,

    [Parameter(Mandatory, ParameterSetName = "Status")]
    [string]$TaskId,

    [ValidateRange(2, 120)]
    [int]$PollSeconds = 10,

    [ValidateRange(30, 7200)]
    [int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"
$apiRoot = "https://api.meshy.ai/openapi/v2/text-to-3d"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Get-MeshyApiKey {
    if (-not $env:MESHY_API_KEY) {
        throw "MESHY_API_KEY is not set. Add it to your user environment or current terminal session."
    }
    return $env:MESHY_API_KEY.Trim()
}

function Invoke-MeshyApi {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Get", "Post")]
        [string]$Method,
        [Parameter(Mandatory)]
        [string]$Uri,
        [hashtable]$Body
    )

    $headers = @{ Authorization = "Bearer $(Get-MeshyApiKey)" }
    try {
        if ($Method -eq "Post") {
            return Invoke-RestMethod -Method Post -Uri $Uri -Headers $headers -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 8) -TimeoutSec 60
        }
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers -TimeoutSec 60
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $details = $_.ErrorDetails.Message
        throw "Meshy API request failed$(if ($statusCode) { " with HTTP $statusCode" }): $details"
    }
}

function New-MeshyTask {
    param([hashtable]$Body)
    $response = Invoke-MeshyApi -Method Post -Uri $apiRoot -Body $Body
    if (-not $response.result) {
        throw "Meshy did not return a task ID."
    }
    return [string]$response.result
}

function Wait-MeshyTask {
    param([string]$Id)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastProgress = -1
    while ([DateTime]::UtcNow -lt $deadline) {
        $task = Invoke-MeshyApi -Method Get -Uri "$apiRoot/$Id"
        $progress = [int]$task.progress
        $status = [string]$task.status
        if ($progress -ne $lastProgress -or $status -in @("SUCCEEDED", "FAILED", "CANCELED")) {
            Write-Output "$Id`: $status ($progress%)"
            $lastProgress = $progress
        }
        if ($status -eq "SUCCEEDED") {
            return $task
        }
        if ($status -in @("FAILED", "CANCELED")) {
            throw "Meshy task $Id ended with $status`: $($task.task_error.message)"
        }
        [System.Threading.Thread]::Sleep($PollSeconds * 1000)
    }
    throw "Meshy task $Id did not finish within $TimeoutSeconds seconds."
}

function Save-MeshyAsset {
    param(
        [object]$Task,
        [hashtable]$RequestMetadata
    )

    $modelUrl = $Task.model_urls.glb
    if (-not $modelUrl) {
        throw "Completed Meshy task has no GLB download URL."
    }

    $assetName = $Name.ToLowerInvariant()
    $outputDirectory = Join-Path $projectRoot "assets\generated\$assetName"
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $modelPath = Join-Path $outputDirectory "$assetName.glb"
    Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath -UseBasicParsing -TimeoutSec 120

    if ($Task.thumbnail_url) {
        Invoke-WebRequest -Uri $Task.thumbnail_url -OutFile (Join-Path $outputDirectory "${assetName}_preview.png") -UseBasicParsing -TimeoutSec 120
    }

    $manifest = [ordered]@{
        generator = "Meshy Text to 3D API v2"
        task_id = $Task.id
        task_type = $Task.type
        status = $Task.status
        consumed_credits = $Task.consumed_credits
        request = $RequestMetadata
        source_prompt = $Task.prompt
        texture_prompt = $Task.texture_prompt
        license_review_required = $true
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputDirectory "$assetName.meshy.json") -Encoding UTF8
    Write-Output "Downloaded Godot-ready asset to assets/generated/$assetName/$assetName.glb"
}

if ($PSCmdlet.ParameterSetName -eq "Status") {
    Invoke-MeshyApi -Method Get -Uri "$apiRoot/$TaskId" | ConvertTo-Json -Depth 10
    return
}

$previewRequest = [ordered]@{
    mode = "preview"
    prompt = $Prompt
    model_type = $ModelType
    target_formats = @("glb")
    moderation = $true
    auto_size = -not $NoAutoSize
    origin_at = "bottom"
}
if ($ModelType -eq "standard") {
    $previewRequest.ai_model = "latest"
    $previewRequest.should_remesh = $true
    $previewRequest.topology = "triangle"
    $previewRequest.target_polycount = $TargetPolycount
}
if ($PoseMode) {
    $previewRequest.pose_mode = $PoseMode
}

if ($DryRun) {
    [ordered]@{
        preview = $previewRequest
        output = "assets/generated/$($Name.ToLowerInvariant())"
    } | ConvertTo-Json -Depth 8
    return
}

Write-Output "Creating Meshy preview task..."
$previewId = New-MeshyTask -Body $previewRequest
$previewTask = Wait-MeshyTask -Id $previewId
$finalTask = $previewTask
$requestMetadata = [ordered]@{ preview = $previewRequest }

if (-not $PreviewOnly) {
    $refineRequest = [ordered]@{
        mode = "refine"
        preview_task_id = $previewId
        ai_model = "latest"
        enable_pbr = $true
        hd_texture = [bool]$HdTexture
        remove_lighting = $true
        moderation = $true
        target_formats = @("glb")
        auto_size = -not $NoAutoSize
        origin_at = "bottom"
    }
    if ($TexturePrompt) {
        $refineRequest.texture_prompt = $TexturePrompt
    }
    $requestMetadata.refine = $refineRequest
    Write-Output "Creating Meshy refine task with PBR textures..."
    $refineId = New-MeshyTask -Body $refineRequest
    $finalTask = Wait-MeshyTask -Id $refineId
}

Save-MeshyAsset -Task $finalTask -RequestMetadata $requestMetadata
Write-Output "Run tools/validate_godot.ps1 to import and verify the new GLB."
