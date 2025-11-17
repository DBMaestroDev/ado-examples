<#
.SYNOPSIS
    Remove all pipeline executions (builds) from Azure DevOps
.DESCRIPTION
    Deletes all build executions for a specified pipeline or project.
    This script queries the Azure DevOps REST API to retrieve all builds
    and optionally deletes them.
.PARAMETERS
    PipelineId: The pipeline ID to delete builds for (optional - if not provided, deletes all)
    Force: Skip confirmation and delete immediately
.EXAMPLE
    .\remove-pipeline-executions.ps1
    Lists all builds in the project (dry run)
.EXAMPLE
    .\remove-pipeline-executions.ps1 -Force
    Deletes all builds without confirmation
.NOTES
    - Requires ADO_PAT environment variable set with valid Personal Access Token
    - ADO_ORG_URL defaults to "https://dev.azure.com/dbmsc/"
    - ADO_PROJECT defaults to "poc"
#>

param(
    [int]$PipelineId,
    [switch]$Force
)

# Configuration - Get from environment variables or set them
$orgUrl = if ($env:ADO_ORG_URL) { $env:ADO_ORG_URL } else { "https://dev.azure.com/dbmsc/" }
$project = if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { "poc" }
$pat = $env:ADO_PAT

# Validate required parameters
if (-not $pat) {
  Write-Error "ADO_PAT environment variable not set"
  Write-Host ""
  Write-Host "Set environment variables before running this script:"
  Write-Host '  $env:ADO_ORG_URL = "https://dev.azure.com/your-org/"'
  Write-Host '  $env:ADO_PROJECT = "your-project"'
  Write-Host '  $env:ADO_PAT = "your-personal-access-token"'
  Write-Host ""
  exit 1
}

# Create authentication header
$headers = @{
  Authorization = "Bearer $pat"
  "Content-Type" = "application/json"
}

Write-Host "=== Azure DevOps Pipeline Execution Removal ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Organization URL: $orgUrl"
Write-Host "Project: $project"
Write-Host ""

# Step 1: Get all builds
Write-Host "Retrieving all pipeline executions..." -ForegroundColor Yellow

$buildsUri = "$orgUrl$project/_apis/build/builds?api-version=7.0"

try {
  $buildsResponse = Invoke-RestMethod -Uri $buildsUri -Method Get -Headers $headers
  
  $builds = $buildsResponse.value
  
  if ($PipelineId) {
    $builds = $builds | Where-Object { $_.definition.id -eq $PipelineId }
    Write-Host "Found $($builds.Count) builds for pipeline ID $PipelineId"
  } else {
    Write-Host "Found $($builds.Count) builds total" -ForegroundColor Green
  }
  
  if ($builds.Count -eq 0) {
    Write-Host "No builds found to delete"
    exit 0
  }
  
  Write-Host ""
  Write-Host "Builds to be removed:" -ForegroundColor Cyan
  Write-Host "---"
  
  $builds | ForEach-Object {
    $status = $_.status
    $result = if ($_.result) { $_.result } else { "In Progress" }
    Write-Host "  [ID: $($_.id)] Pipeline: $($_.definition.name) | Status: $status | Result: $result | Date: $($_.finishTime)"
  }
  
  Write-Host "---"
  Write-Host ""
  
  # Step 2: Confirm deletion
  if (-not $Force) {
    $confirm = Read-Host "Are you sure you want to delete $($builds.Count) build(s)? (yes/no)"
    if ($confirm -ne "yes") {
      Write-Host "Cancelled. No builds were deleted."
      exit 0
    }
  } else {
    Write-Host "Force flag set - proceeding with deletion without confirmation"
  }
  
  # Step 3: Delete each build
  Write-Host ""
  Write-Host "Deleting builds..." -ForegroundColor Yellow
  
  $successCount = 0
  $failureCount = 0
  
  foreach ($build in $builds) {
    $buildId = $build.id
    $pipelineName = $build.definition.name
    
    try {
      $deleteUri = "$orgUrl$project/_apis/build/builds/$buildId`?api-version=7.0"
      Invoke-RestMethod -Uri $deleteUri -Method Delete -Headers $headers | Out-Null
      
      Write-Host "[+] Deleted build $buildId ($pipelineName)" -ForegroundColor Green
      $successCount++
    } catch {
      Write-Host "[-] Failed to delete build $buildId ($pipelineName): $($_.Exception.Message)" -ForegroundColor Red
      $failureCount++
    }
  }
  
  # Summary
  Write-Host ""
  Write-Host "=== Summary ===" -ForegroundColor Cyan
  Write-Host "Successfully deleted: $successCount builds" -ForegroundColor Green
  Write-Host "Failed to delete: $failureCount builds" -ForegroundColor $(if ($failureCount -gt 0) { "Red" } else { "Green" })
  Write-Host ""
  
} catch {
  Write-Host "=== Error ===" -ForegroundColor Red
  Write-Host "Error Message: $($_.Exception.Message)"
  Write-Host "Status Code: $($_.Exception.Response.StatusCode)"
  
  # Try to parse error response
  try {
    $errorResponse = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $responseBody = $reader.ReadToEnd()
    Write-Host ""
    Write-Host "Response Body:"
    Write-Host $responseBody
  } catch {
    Write-Host "Could not read error response body"
  }
  
  exit 1
}
