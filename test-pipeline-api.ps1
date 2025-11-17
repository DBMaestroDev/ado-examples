# Test script for Azure DevOps Pipeline REST API
# This script tests creating a pipeline via the REST API

# Configuration - Get from environment variables or set them
$orgUrl = if ($env:ADO_ORG_URL) { $env:ADO_ORG_URL } else { "https://dev.azure.com/dbmsc/" }
$project = if ($env:ADO_PROJECT) { $env:ADO_PROJECT } else { "poc" }
$pat = $env:ADO_PAT
$repoId = $env:ADO_REPO_ID
$yamlPath = if ($env:ADO_YAML_PATH) { $env:ADO_YAML_PATH } else { "/deploy-prd-ISSUE-79.yml" }

# Validate required parameters
if (-not $pat) {
  Write-Error "ADO_PAT environment variable not set"
  Write-Host ""
  Write-Host "Set environment variables before running this script:"
  Write-Host '  $env:ADO_ORG_URL = "https://dev.azure.com/your-org/"'
  Write-Host '  $env:ADO_PROJECT = "your-project"'
  Write-Host '  $env:ADO_PAT = "your-personal-access-token"'
  Write-Host '  $env:ADO_REPO_ID = "your-repository-id"'
  Write-Host ""
  exit 1
}

if (-not $repoId) {
  Write-Error "ADO_REPO_ID environment variable not set"
  exit 1
}

# Create authentication header
$headers = @{
  Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
  "Content-Type" = "application/json"
}

# Create request body
$pipelineName = "Deploy-PRD-ISSUE-79-TEST"
$body = @{
  configuration = @{
    type = "yaml"
    path = $yamlPath
    repository = @{
      id = $repoId
      type = "azureReposGit"
    }
  }
  folder = "Production Deployments"
} | ConvertTo-Json -Depth 10

Write-Host "=== Azure DevOps Pipeline API Test ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Organization URL: $orgUrl"
Write-Host "Project: $project"
Write-Host "Pipeline Name: $pipelineName"
Write-Host "YAML Path: $yamlPath"
Write-Host "Repository ID: $repoId"
Write-Host ""
Write-Host "Request Body:"
Write-Host $body
Write-Host ""

# Make the API call
$uri = "$orgUrl$project/_apis/pipelines?api-version=7.1-preview.1"

Write-Host "API URI: $uri"
Write-Host ""
Write-Host "Sending request..."
Write-Host ""

try {
  $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -Verbose
  
  Write-Host "=== Success ===" -ForegroundColor Green
  Write-Host "Pipeline ID: $($response.id)"
  Write-Host "Pipeline Name: $($response.name)"
  Write-Host "Pipeline URL: $($response._links.web.href)"
  Write-Host ""
  Write-Host "Full Response:"
  Write-Host ($response | ConvertTo-Json -Depth 10)
  
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
}
