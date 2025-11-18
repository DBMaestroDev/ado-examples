# Get Schedule from Azure DevOps Work Item Description
# This script retrieves work item details and extracts schedule info from the description

param(
    [string]$OrgUrl = "https://dev.azure.com/dbmsc/",
    [string]$Project = "poc",
    [int]$WorkItemId = 51  # Work item ID to retrieve
)

function Get-Headers {
    param([string]$Pat)
    
    return @{
        Authorization = "Bearer $Pat"
        "Content-Type" = "application/json"
    }
}

function Get-WorkItemSchedule {
    param(
        [string]$OrgUrl,
        [string]$Project,
        [int]$WorkItemId,
        [hashtable]$Headers
    )
    
    Write-Host "=== Retrieving Work Item Schedule ===" -ForegroundColor Cyan
    Write-Host "Organization: $OrgUrl"
    Write-Host "Project: $Project"
    Write-Host "Work Item ID: $WorkItemId`n"
    
    try {
        # API call to get work item details
        $wiUri = "$($OrgUrl)_apis/wit/workitems/$WorkItemId" + "?api-version=7.0&`$expand=relations"
        Write-Host "URI: $wiUri`n"
        
        $workItem = Invoke-RestMethod -Uri $wiUri -Method Get -Headers $Headers -ErrorAction Stop
        
        Write-Host "Work Item Details:" -ForegroundColor Yellow
        Write-Host "  ID: $($workItem.id)"
        Write-Host "  Title: $($workItem.fields.'System.Title')"
        Write-Host "  Type: $($workItem.fields.'System.WorkItemType')"
        Write-Host "  State: $($workItem.fields.'System.State')"
        Write-Host "  Assigned To: $($workItem.fields.'System.AssignedTo'.displayName)"
        Write-Host ""
        
        # Get description
        $description = $workItem.fields.'System.Description'
        if ($description) {
            Write-Host "Description:" -ForegroundColor Yellow
            Write-Host $description
            Write-Host ""
            
            # Look for schedule patterns in the description
            $schedule = Extract-ScheduleFromText -Text $description
            
            if ($schedule) {
                Write-Host "Schedule Found:" -ForegroundColor Green
                Write-Host "  $schedule"
            } else {
                Write-Host "No schedule pattern found in description" -ForegroundColor Yellow
            }
        } else {
            Write-Host "No description found in work item" -ForegroundColor Yellow
        }
        
        # Check for custom fields that might contain schedule
        Write-Host "`nChecking for custom schedule fields..." -ForegroundColor Cyan
        $customScheduleFields = $workItem.fields | Where-Object {
            $_.PSObject.Properties.Name -match 'schedule|date|time|cron'
        }
        
        if ($customScheduleFields) {
            Write-Host "Custom fields found:"
            foreach ($field in $customScheduleFields.PSObject.Properties) {
                if ($field.Value) {
                    Write-Host "  $($field.Name): $($field.Value)"
                }
            }
        }
        
        return $workItem
        
    } catch {
        Write-Host "ERROR: Failed to retrieve work item: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            Write-Host "Status Code: $($_.Exception.Response.StatusCode)" -ForegroundColor Yellow
        }
        return $null
    }
}

function Extract-ScheduleFromText {
    param(
        [string]$Text
    )
    
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    
    # Remove HTML tags if present
    $cleanText = $Text -replace '<[^>]+>', ''
    
    # Patterns to look for schedule information
    $patterns = @(
        @{
            Name = "TargetDeploymentDate"
            Pattern = "TargetDeploymentDate\s*:\s*'([^']+)'"
        },
        @{
            Name = "Scheduled at Pattern"
            Pattern = 'scheduled\s+(?:at|for|on)[\s:]+([^\n]+)'
        },
        @{
            Name = "Deployment Date Pattern"
            Pattern = 'deployment\s+(?:date|time)[\s:]+([^\n]+)'
        },
        @{
            Name = "Schedule Pattern"
            Pattern = 'schedule[\s:]+([^\n]+)'
        },
        @{
            Name = "Cron Expression"
            Pattern = '(\d{1,2}\s+\d{1,2}\s+\d{1,2}\s+\d{1,2}\s+[0-6*])'
        },
        @{
            Name = "ISO DateTime"
            Pattern = '\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}'
        },
        @{
            Name = "Cron Pattern"
            Pattern = 'cron[\s:]+([^\n]+)'
        }
    )
    
    foreach ($patternObj in $patterns) {
        if ($cleanText -match $patternObj.Pattern) {
            $match = if ($matches.Count -gt 1) { $matches[1] } else { $matches[0] }
            Write-Host "    (Matched: $($patternObj.Name))" -ForegroundColor Cyan
            return $match.Trim()
        }
    }
    
    return $null
}

# Main execution
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "  Get Schedule from Work Item" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host ""

$pat = $env:ADO_PAT
if ([string]::IsNullOrWhiteSpace($pat)) {
    Write-Host "ERROR: ADO_PAT environment variable not set" -ForegroundColor Red
    Write-Host "Please set: `$env:ADO_PAT = 'your-personal-access-token'" -ForegroundColor Yellow
    exit 1
}

$headers = Get-Headers -Pat $pat

# Get work item details and schedule
$workItem = Get-WorkItemSchedule -OrgUrl $OrgUrl -Project $Project -WorkItemId $WorkItemId -Headers $headers

Write-Host ""
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "  Schedule Pattern Examples" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "The script looks for these patterns in the work item description:" -ForegroundColor Cyan
Write-Host "  - ISO DateTime: '2025-11-18 14:30:00'"
Write-Host "  - Cron Expression: '30 14 18 11 *'"
Write-Host "  - 'Scheduled at: 2025-11-18 14:30:00'"
Write-Host "  - 'Deployment date: 2025-11-18 14:30:00'"
Write-Host "  - 'Schedule: 2025-11-18 14:30:00'"
Write-Host "  - 'Cron: 30 14 18 11 *'"
Write-Host ""
Write-Host "Work Item URL:" -ForegroundColor Cyan
Write-Host "$($OrgUrl)$Project/_workitems/edit/$WorkItemId"
Write-Host ""
