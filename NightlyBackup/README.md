# Nightly Database Backup

This action creates nightly database backups that contain test data for use with PR containers.

## Features

- Creates Business Central containers with specified BC version
- Installs configured apps with dependencies
- Imports test data and configuration
- Creates database backups for PR container use
- Manages backup retention and cleanup
- Supports multiple BC versions

## Usage

### Basic Usage

```yaml
- name: Create Nightly Backup
  uses: ./Actions/NightlyBackup
  with:
    containerName: 'nightly-backup'
```

### Advanced Usage

```yaml
- name: Create Nightly Backup
  uses: ./Actions/NightlyBackup
  with:
    containerName: 'nightly-backup-v23'
    bcVersion: '23.0'
    appList: '[{"id":"guid1","name":"App1","publisher":"TRASER Software GmbH"}]'
    licenseFile: 'https://example.com/license.flf'
    rapidStartLanguage: 'DE'
    retentionDays: 14
    storageLocation: '\\server\backups'
    forceRecreate: 'false'
```

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `containerName` | Name for the backup container | No | nightly-backup |
| `bcVersion` | Business Central version to use | No | From settings |
| `appList` | JSON array of apps to install | No | From settings |
| `licenseFile` | License file URL or path | No | From settings |
| `rapidStartLanguage` | RapidStart language code | No | DE |
| `retentionDays` | Number of days to keep backups | No | 7 |
| `storageLocation` | Path where backups should be stored | No | From settings |
| `forceRecreate` | Force recreation even if recent backup exists | No | false |

## Outputs

| Name | Description |
|------|-------------|
| `backupPath` | Path to the created backup |
| `backupTimestamp` | Timestamp of the backup creation |
| `containerName` | Name of the backup container used |
| `message` | Backup operation result message |

## App List Format

The `appList` input should be a JSON array of objects with these properties:

```json
[
  {
    "id": "app-guid-here",
    "name": "App Name",
    "publisher": "TRASER Software GmbH"
  }
]
```

## Configuration

Configure nightly backups in your AL-Go settings:

```json
{
  "prContainers": {
    "enabled": true,
    "backup": {
      "schedule": "0 2 * * *",
      "storageLocation": "\\\\server\\backups",
      "retentionDays": 7,
      "bcVersion": "23.0",
      "licenseFile": "https://example.com/license.flf",
      "apps": [
        {
          "id": "app-guid",
          "name": "App Name",
          "publisher": "TRASER Software GmbH"
        }
      ],
      "testDataLanguage": "DE",
      "includeRapidStart": true
    }
  }
}
```

## Workflow Examples

### Scheduled Nightly Backup

```yaml
name: Nightly Database Backup

on:
  schedule:
    - cron: '0 2 * * *'  # 2 AM daily
  workflow_dispatch:

jobs:
  create-backup:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      
      - name: Create Nightly Backup
        uses: ./Actions/NightlyBackup
        with:
          retentionDays: 14
        env:
          containerusername: ${{ secrets.CONTAINER_USERNAME }}
          containerpassword: ${{ secrets.CONTAINER_PASSWORD }}
          spusername: ${{ secrets.SP_USERNAME }}
          sppassword: ${{ secrets.SP_PASSWORD }}
          TRASERInternalFeedsToken: ${{ secrets.NUGET_TOKEN }}
```

### Multiple Version Backups

```yaml
name: Multi-Version Nightly Backup

on:
  schedule:
    - cron: '0 2 * * *'

jobs:
  create-backups:
    runs-on: self-hosted
    strategy:
      matrix:
        version: ['22.0', '23.0', '24.0']
    steps:
      - uses: actions/checkout@v4
      
      - name: Create Backup for BC ${{ matrix.version }}
        uses: ./Actions/NightlyBackup
        with:
          containerName: 'nightly-backup-v${{ matrix.version }}'
          bcVersion: ${{ matrix.version }}
        env:
          containerusername: ${{ secrets.CONTAINER_USERNAME }}
          containerpassword: ${{ secrets.CONTAINER_PASSWORD }}
```

## Environment Variables

The action requires these environment variables:

- `containerusername` - Container admin username
- `containerpassword` - Container admin password
- `spusername` - SharePoint username (optional)
- `sppassword` - SharePoint password (optional)
- `TRASERInternalFeedsToken` - NuGet feed token (optional)

## Backup Process

1. **Check for existing recent backup** (if not forcing recreation)
2. **Create temporary backup container** with specified BC version
3. **Remove default companies** to start with clean slate
4. **Install specified apps** with dependencies and test data
5. **Remove TRASER apps** (keeping only dependencies and data)
6. **Create database backup** in timestamped folder
7. **Cleanup backup container** and remove temporary resources
8. **Remove old backups** based on retention policy

## Storage Structure

Backups are stored in the following structure:

```
\\server\backups\
├── nightly-backup-20241219-020000\
│   ├── tenant.bak
│   └── application.bak
├── nightly-backup-20241218-020000\
│   ├── tenant.bak
│   └── application.bak
└── ...
```

## Troubleshooting

### Backup Creation Fails
- Check if Docker is running and configured for Windows containers
- Verify storage location is accessible and has sufficient space
- Check if BC artifacts are available for specified version
- Ensure required PowerShell modules are installed

### App Installation Fails
- Verify SharePoint credentials are correct
- Check NuGet token permissions
- Ensure app dependencies are available
- Review container logs for specific errors

### Storage Issues
- Check network connectivity to storage location
- Verify write permissions on storage location
- Ensure sufficient disk space is available
- Check if antivirus is blocking file operations

### Retention Policy Not Working
- Verify retention days is set to positive number
- Check if backup naming pattern matches expected format
- Ensure process has delete permissions on storage location
- Review logs for cleanup operation errors