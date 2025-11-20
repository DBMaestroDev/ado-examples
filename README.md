# DBmaestro CI/CD Pipeline

Automated deployment pipeline for DBmaestro package management with staged environments (DEV → Release Source → QAS → PRD) and scheduled production deployments.

## Pipeline Overview

The `azure-pipelines.yml` implements a comprehensive deployment orchestration with the following stages:

### Pipeline Stages

1. **ExtractTaskID**: Extracts TaskID from commit message
   - Regex pattern: `TaskID:\s*([A-Za-z0-9_-]+)`
   - Example commit: `Update schema TaskID: ISSUE-75`
   - Creates artifact: `taskid-artifact`

2. **CreatePackage**: Creates DBmaestro package
   - Uses TaskID as package name
   - Runs DBmaestro Build command
   - Environment: DEV_USER

3. **RunPrecheck**: Validates package integrity
   - Executes DBmaestro PreCheck
   - Ensures package is deployable

4. **UpgradeReleaseSource**: Deploys to Release Source
   - Environment: DEV (Release Source)
   - Includes backup and restore behavior
   - First production-like environment test

5. **ApprovalForQAS**: Manual approval gate
   - Requires approval before QAS deployment
   - Notifies: AdoUser@dbmaestro.local
   - Timeout: 24 hours

6. **UpgradeQAS**: Deploys to QAS
   - Environment: QAS
   - Full deployment with backup/restore

7. **SchedulePRDUpgrade**: Schedules production deployment
   - Two jobs: environment approval + automated scheduling
   - Retrieves deployment schedule from work item associated with TaskID
   - Creates dynamic pipeline with calculated cron schedule
   - Registers pipeline in \"Production Deployments\" folder

## Getting Started

### Prerequisites

- Azure DevOps Project with `ado-examples` repository
- Build agent pool: `AdoHosted`
- DBmaestro agent running on `localhost:8017`
- **Git Repository Permissions**: Build service account must have `Contribute` and `Create Branch` permissions

#### Setting Up Build Service Permissions

The pipeline needs permission to commit and push the dynamic production pipeline YAML files:

1. In Azure DevOps, go to **Project Settings** (bottom left)
2. Navigate to **Repositories** → **ado-examples**
3. Click the **Security** tab
4. Search for: `[Project]\Build Service ([Organization])`
   - Example: `poc\Build Service (dbmsc)`
5. Set the following permissions to **Allow**:
   - **Contribute**: Required to commit files
   - **Create Branch**: Required to create main branch if needed
6. Click **Save changes**

Without these permissions, the pipeline will fail at the "Commit Pipeline File to Repository" stage with error:
```
TF401027: You need the Git 'GenericContribute' permission to perform this action
```

### Commit Requirements

All commits must include TaskID (and optionally WorkItemId) in the commit message:

```
git commit -m "Your commit message TaskID: ISSUE-75"
```

or with explicit WorkItemId reference:

```
git commit -m "Your commit message TaskID: ISSUE-75 WorkItemId: 12345"
```

Format: `TaskID: [A-Za-z0-9_-]+` anywhere in the commit message
- TaskID is used as the package name
- If WorkItemId is not explicitly provided, the TaskID is used to look up the corresponding work item
- The work item's description is searched for `TargetDeploymentDate: 'YYYY-MM-DD HH:MM:SS'` to determine deployment schedule

### Variable Groups (Required Setup)

The pipelines require a **Variable Group** named `DBmaestro-Credentials` to store sensitive credentials:

#### Creating the Variable Group

1. In Azure DevOps, go to **Pipelines** → **Library**
2. Click **"+ Variable group"**
3. Enter name: `DBmaestro-Credentials`
4. Add variables:
   - **DBMUsername**: Your DBmaestro service account username
     - Click the **lock icon** to mark as secret
   - **DBMPassword**: Your DBmaestro service account password
     - Click the **lock icon** to mark as secret
   - **ADO_PAT**: Personal Access Token for Azure DevOps API access
     - Click the **lock icon** to mark as secret
     - Required for retrieving work item details and deployment dates
     - Must have permissions to read work items and create pipelines
5. Click **"Save"**

#### Important: Variable Group Access

**The variable group must be accessible to all pipelines in the project**, especially the dynamically generated scheduled pipelines.

To grant access:
1. In **Pipelines** → **Library**, click on `DBmaestro-Credentials`
2. Click the **⋮ (three dots)** menu at the top right
3. Select **"Open access"** to allow all pipelines in the project to use this variable group
4. Confirm the permission change

Without this setting, dynamically created scheduled pipelines will fail with a permission error when trying to access the variable group.

#### Why Variable Groups?

- **Security**: Credentials stored securely in Azure DevOps (not in YAML files)
- **Reusability**: Automatically available to all pipelines that reference the group
- **Dynamic Pipelines**: Scheduled production pipelines inherit credentials from the group without manual setup

### Agent Pool Access (Required for Scheduled Pipelines)

The dynamically created production deployment scheduled pipelines require permission to access the agent pool.

#### Configuring Agent Pool Permissions

**Option 1: Authorize Individual Pipelines (Recommended for security)**

1. In Azure DevOps, go to **Project Settings** → **Agent pools** (under Pipelines section)
2. Click on **AdoHosted** pool
3. Click the **Security** tab
4. Click the **+** button to add a new pipeline
5. Search for and select the **newly created production deployment pipeline** (e.g., "Deploy-PRD-ISSUE-93")
6. Click **Save**

This grants permission to that specific pipeline to use the agent pool.

**Option 2: Allow All Pipelines (Easier for less restricted projects)**

If you have project-level permissions:

1. In Azure DevOps, go to **Project Settings** → **Agent pools** (under Pipelines section)
2. Click on **AdoHosted** pool
3. Click the **Security** tab
4. Look for a **"Make open"** or **"Allow all pipelines"** option (depending on your Azure DevOps version)
5. Enable it to allow all pipelines in the project to use this agent pool

This eliminates the need to authorize each new production deployment pipeline individually.

**Without agent pool access**, newly created production deployment pipelines will fail with error:
```
This pipeline needs permission to access a resource before this run can continue to Deploy to Production
```

### Pipeline Variables

#### From Variable Group (Secure)
- `DBMUsername`: DBmaestro service account username (from `DBmaestro-Credentials`)
- `DBMPassword`: DBmaestro service account password (from `DBmaestro-Credentials`)
- `ADO_PAT`: Personal Access Token for Azure DevOps API access (from `DBmaestro-Credentials`)

#### Automatically Retrieved
- `TargetDeploymentDate`: Extracted from work item description (parsed from `TargetDeploymentDate: 'YYYY-MM-DD HH:MM:SS'` format)
  - Retrieved via the TaskID and WorkItemId embedded in the commit message
  - If not found, defaults to 5 minutes from approval time
  - Used to calculate cron expression for scheduled pipeline

## Scheduling Production Deployment

### Automatic Scheduling (via Work Item)

When the TaskID is extracted from the commit message, the pipeline automatically:

1. **Retrieves the WorkItemId** from the commit message (TaskID used to link to work item)
2. **Looks up the work item** in Azure DevOps via REST API
3. **Searches the description** for: `TargetDeploymentDate: 'YYYY-MM-DD HH:MM:SS'`
4. **Extracts the deployment date** from the work item description
5. **Creates a scheduled pipeline** with the calculated cron expression
6. **Registers and executes** the pipeline at the scheduled time

### Example Work Item Description Format

Add this to your Azure DevOps work item description:

```
Deployment Details:
TargetDeploymentDate: '2025-11-17 14:30:00'
Version: 1.0.0
Approver: John Doe
```

The pipeline will parse and extract `2025-11-17 14:30:00` as the deployment time.

### Default Behavior (No TargetDeploymentDate)

If the work item doesn't contain `TargetDeploymentDate` in the description:
- Pipeline proceeds to **ApprovalForDeployment** stage (environment-based approval)
- After approval, defaults to **5 minutes from approval time**
- Creates scheduled pipeline with this default timing

## Pipeline Details

### Configuration Variables

```yaml
dbmaestroVersion: '2024.1.0'
DBM_JAR_PATH: 'C:\Program Files (x86)\DBmaestro\DOP Server\Agent\DBmaestroAgent.jar'
DBM_AGENT_ENDPOINT: 'localhost:8017'
DBM_PROJECT_NAME: 'Demo-MSSQL'
DBM_ENV_NAME_DEV: 'DEV_USER'
DBM_ENV_NAME_RS: 'DEV'        # Release Source
DBM_ENV_NAME_QA: 'QAS'
DBM_ENV_NAME_PROD: 'PRD'
```

### Generated Production Pipeline

For each package, a dynamic production pipeline is created:
- **File**: `deploy-prd-[PACKAGE_NAME].yml`
- **Location**: Repository root
- **Schedule**: Calculated cron expression
- **Folder**: "Production Deployments" in Azure DevOps
- **Trigger**: Scheduled (not manual)

Example: `deploy-prd-ISSUE-75.yml` scheduled for 2025-11-17 at 14:30:00

### Git Integration

The scheduling job performs these operations:
- Generates custom pipeline YAML from template
- Commits to `main` branch with message: `"Add scheduled production deployment for [PACKAGE] [skip ci]"`
- Pushes to origin
- Registers pipeline via Azure DevOps REST API v7.1

## Approvals

| Stage | Purpose | Timeout | Action |
|-------|---------|---------|--------|
| ApprovalForQAS | Review Release Source deployment | 24 hours | Approve/Reject |
| ApprovalForDeployment | Environment-based approval for PRD | 24 hours | Approve (environment checks enforce this) |

The SetDeploymentTime stage automatically retrieves the deployment date from the work item description - no manual variable setting required.

## Artifact Passing

Package name and deployment information is passed between stages via artifacts:

### TaskID Artifact
- **Published by**: ExtractTaskID stage
- **Artifact name**: `taskid-artifact`
- **File**: `taskid.txt`
- **Used by**: CreatePackage, RunPrecheck, UpgradeINTEGRACION, UpgradeQAS, ScheduleUpgrade stages

### WorkItemId Artifact
- **Published by**: ExtractTaskID stage
- **Artifact name**: `workitemid-artifact`
- **File**: `workitemid.txt`
- **Used by**: SetDeploymentTime stage to retrieve deployment schedule from work item description

### DeploymentDate Artifact
- **Published by**: SetDeploymentTime stage
- **Artifact name**: `deploymentdate-artifact`
- **File**: `deploymentdate.txt`
- **Used by**: ScheduleUpgrade stage to apply the extracted deployment date to cron schedule

## Troubleshooting

### Pipeline fails at "Commit Pipeline File to Repository"

**Error**: `error: src refspec main does not match any`

**Solution**: Ensure `main` branch exists in repository. The pipeline handles detached HEAD state by running:
```powershell
git fetch origin
git checkout -B main origin/main
```

### Custom deployment date not recognized

**Solution**: Verify the work item description contains the date in exactly this format: `TargetDeploymentDate: 'YYYY-MM-DD HH:MM:SS'`
- Correct: `TargetDeploymentDate: '2025-11-17 14:30:00'`
- Incorrect: `TargetDeploymentDate: 11/17/2025 2:30 PM`
- Check that the format is surrounded by single quotes

### Work item deployment date not being extracted

**Error**: Pipeline defaults to 5 minutes instead of using work item date

**Solution**: 
1. Verify `ADO_PAT` is defined in the `DBmaestro-Credentials` variable group
2. Ensure the work item description contains: `TargetDeploymentDate: 'YYYY-MM-DD HH:MM:SS'`
3. Check that the Personal Access Token has permissions to read work items
4. Verify the work item exists and is linked to the TaskID

### Missing ADO_PAT variable

**Error**: Pipeline skips work item lookup and uses default scheduling

**Solution**: Add `ADO_PAT` to the `DBmaestro-Credentials` variable group:
1. Go to **Pipelines** → **Library** → `DBmaestro-Credentials`
2. Add variable: `ADO_PAT`
3. Set value to your Personal Access Token with work item read permissions
4. Mark as secret (click lock icon)

### Scheduled pipeline not executing

**Solution**: Check if "Production Deployments" folder exists in Azure DevOps pipelines. If not, create it manually or the REST API will create it automatically on first run.

## Build and Test

Run the pipeline with a test commit:

```
git commit --allow-empty -m "Test pipeline TaskID: TEST-001"
git push origin main
```

Monitor the pipeline run in Azure DevOps. All stages should complete successfully through SchedulePRDUpgrade.

## Maintenance

### Cleanup

Old production deployment pipeline files can be safely deleted from the repository after execution if desired. The scheduled pipeline will have already executed before cleanup.

### Updating Pipeline

Edit `azure-pipelines.yml` directly. Changes apply to all future runs.

### Updating Production Template

Edit `deploy-prd-template.yml` to change production deployment behavior. Placeholders:
- `CRON_SCHEDULE_PLACEHOLDER`: Replaced with calculated cron expression
- `PACKAGE_NAME_PLACEHOLDER`: Replaced with package name

## Integration Points

- **DBmaestro Agent**: `localhost:8017` (configurable)
- **Azure DevOps REST API**: Used for pipeline registration
- **Git Repository**: Source of pipeline files and commit triggers
- **Azure DevOps Build Agents**: Executes all pipeline jobs