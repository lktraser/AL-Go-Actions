# PR Container Management

This action manages persistent pull request containers for Business Central development and testing.

## Features

- Creates persistent containers for each pull request
- Restores containers from nightly database backups
- Deploys PR branch changes to containers
- Provides web access via Traefik reverse proxy
- Manages container lifecycle (start/stop/remove)
- Posts container URLs as PR comments

## Usage

### Basic Usage

```yaml
- name: Create PR Container
  uses: ./Actions/PRContainer
  with:
    operation: 'create'
    prId: '${{ github.event.number }}'
```

### Advanced Usage

```yaml
- name: Manage PR Container
  uses: ./Actions/PRContainer
  with:
    operation: 'create'
    prId: '${{ github.event.number }}'
    containerName: 'custom-pr-${{ github.event.number }}'
    domainName: 'dev.company.com'
    useTraefik: 'true'
    resourceLimits: '{"cpu": "2", "memory": "8GB"}'
    postComment: 'true'
    testCredentials: '{"username": "testuser", "password": "testpass"}'
```

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `operation` | Operation to perform: create, update, start, stop, remove, status | Yes | |
| `prId` | Pull Request ID | Yes | |
| `containerName` | Override container name | No | pr{prId} |
| `backupPath` | Path to backup file for restore | No | Latest available |
| `domainName` | Domain name for container access | No | From settings |
| `useTraefik` | Use Traefik for reverse proxy | No | true |
| `resourceLimits` | JSON object with CPU and memory limits | No | |
| `forceCleanup` | Force cleanup of existing container | No | false |
| `postComment` | Post container URL as PR comment | No | true |
| `testCredentials` | JSON object with test user credentials | No | From env |

## Outputs

| Name | Description |
|------|-------------|
| `containerName` | Name of the container |
| `containerUrl` | URL to access the container |
| `containerStatus` | Current status of the container |
| `message` | Operation result message |

## Operations

### create
Creates a new PR container from the latest backup and deploys PR changes.

### update
Updates an existing PR container with latest PR changes.

### start
Starts a stopped PR container.

### stop
Stops a running PR container.

### remove
Removes a PR container completely.

### status
Gets the current status of a PR container.

## Configuration

Configure PR containers in your AL-Go settings:

```json
{
  "prContainers": {
    "enabled": true,
    "domainName": "dev.company.com",
    "useTraefik": true,
    "resourceLimits": {
      "cpu": "2",
      "memory": "8GB"
    },
    "retention": {
      "gracePeriodHours": 24,
      "maxAgeDays": 30,
      "idleTimeoutHours": 72
    },
    "backup": {
      "storageLocation": "\\\\server\\backups",
      "retentionDays": 7
    }
  }
}
```

## Environment Variables

The action expects these environment variables to be available:

- `containerusername` - Default container admin username
- `containerpassword` - Default container admin password
- `spusername` - SharePoint username (optional)
- `sppassword` - SharePoint password (optional)
- `TRASERInternalFeedsToken` - NuGet feed token (optional)

## Examples

### Workflow Integration

```yaml
name: PR Container Management

on:
  pull_request:
    types: [opened, synchronize]
  issue_comment:
    types: [created]

jobs:
  manage-pr-container:
    runs-on: self-hosted
    if: github.event.action == 'opened' || github.event.action == 'synchronize'
    steps:
      - uses: actions/checkout@v4
      - name: Create/Update PR Container
        uses: ./Actions/PRContainer
        with:
          operation: ${{ github.event.action == 'opened' && 'create' || 'update' }}
          prId: '${{ github.event.number }}'

  handle-commands:
    runs-on: self-hosted
    if: github.event.issue.pull_request && contains(github.event.comment.body, '/container')
    steps:
      - uses: actions/checkout@v4
      - name: Parse Command
        id: command
        run: |
          comment="${{ github.event.comment.body }}"
          if [[ $comment == *"/container start"* ]]; then
            echo "operation=start" >> $GITHUB_OUTPUT
          elif [[ $comment == *"/container stop"* ]]; then
            echo "operation=stop" >> $GITHUB_OUTPUT
          elif [[ $comment == *"/container restart"* ]]; then
            echo "operation=update" >> $GITHUB_OUTPUT
          fi
      - name: Execute Command
        if: steps.command.outputs.operation
        uses: ./Actions/PRContainer
        with:
          operation: ${{ steps.command.outputs.operation }}
          prId: '${{ github.event.issue.number }}'
```

### Manual Dispatch

```yaml
name: Manual PR Container Management

on:
  workflow_dispatch:
    inputs:
      operation:
        description: 'Operation to perform'
        required: true
        type: choice
        options:
          - create
          - update
          - start
          - stop
          - remove
          - status
      prId:
        description: 'Pull Request ID'
        required: true
        type: string

jobs:
  manage-container:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Manage PR Container
        uses: ./Actions/PRContainer
        with:
          operation: ${{ github.event.inputs.operation }}
          prId: ${{ github.event.inputs.prId }}
```

## Dependencies

This action requires:
- BcContainerHelper PowerShell module
- TraserBCHelper PowerShell module (your custom module)
- Docker with Windows containers
- Traefik (if using reverse proxy)
- Access to backup storage location

## Troubleshooting

### Container Creation Fails
- Check if Docker is running and configured for Windows containers
- Verify backup path is accessible
- Check resource limits are valid
- Ensure required PowerShell modules are installed

### Container Not Accessible
- Verify Traefik configuration
- Check DNS resolution for domain
- Confirm firewall rules allow access
- Check container logs for errors

### App Deployment Fails
- Verify SharePoint credentials are correct
- Check NuGet token permissions
- Ensure app dependencies are available
- Review container logs for specific errors