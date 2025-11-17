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
   - Notifies: nicolast@dbmaestro.com
   - Timeout: 24 hours

6. **UpgradeQAS**: Deploys to QAS
   - Environment: QAS
   - Full deployment with backup/restore

7. **SchedulePRDUpgrade**: Schedules production deployment
   - Two jobs: manual approval + automated scheduling
   - Creates dynamic pipeline with custom cron schedule
   - Registers pipeline in "Production Deployments" folder

## Getting Started

### Prerequisites

- Azure DevOps Project with `ado-examples` repository
- Build agent pool: `NicolasHosted`
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

All commits must include TaskID in the commit message:

```
git commit -m "Your commit message TaskID: ISSUE-75"
```

Format: `TaskID: [A-Za-z0-9_-]+` anywhere in the commit message

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

### Pipeline Variables

#### From Variable Group (Secure)
- `DBMUsername`: DBmaestro service account username (from `DBmaestro-Credentials`)
- `DBMPassword`: DBmaestro service account password (from `DBmaestro-Credentials`)

#### Optional (Set during approval stages)
- `TargetDeploymentDate`: Custom production deployment time (format: `YYYY-MM-DD HH:MM:SS`)
  - Example: `2025-11-17 14:30:00`
  - Default if not specified: 5 minutes from approval

## Scheduling Production Deployment

### Automatic Scheduling (Default)

When the "Set Production Deployment Time" approval stage appears:
- Approve without setting variables → uses default schedule (tomorrow at 2 AM)
- Pipeline automatically creates a scheduled pipeline YAML file
- New pipeline registers and executes at scheduled time

### Manual Scheduling (Custom Date/Time)

When the "Set Production Deployment Time" approval stage appears:

1. **Click the approval notification** in Azure DevOps
2. **Click the three dots menu (⋮)** at the top right
3. **Select "Set variables"**
4. **Add variable:**
   - Variable name: `TargetDeploymentDate`
   - Value: `2025-11-17 14:30:00` (YYYY-MM-DD HH:MM:SS format)
5. **Click "Save"**
6. **Click "Approve"**

The pipeline will use your custom date/time instead of the default (5 minutes from approval).

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
| SetDeploymentTime | Confirm schedule for PRD | 24 hours | Approve (set time first) |

## Artifact Passing

Package name (TaskID) is passed between stages via artifact:
- **Published by**: ExtractTaskID stage
- **Artifact name**: `taskid-artifact`
- **File**: `taskid.txt`
- **Used by**: All subsequent stages

## Troubleshooting

### Pipeline fails at "Commit Pipeline File to Repository"

**Error**: `error: src refspec main does not match any`

**Solution**: Ensure `main` branch exists in repository. The pipeline handles detached HEAD state by running:
```powershell
git fetch origin
git checkout -B main origin/main
```

### Custom deployment date not recognized

**Solution**: Verify date format is exactly: `YYYY-MM-DD HH:MM:SS`
- Correct: `2025-11-17 14:30:00`
- Incorrect: `11/17/2025 2:30 PM`

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