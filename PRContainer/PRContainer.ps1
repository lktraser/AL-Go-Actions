Param(
    [Parameter(HelpMessage = "Operation to perform: create, update, remove", Mandatory = $true)]
    [ValidateSet('create', 'update', 'remove')]
    [string] $operation,
    
    [Parameter(HelpMessage = "Pull Request ID", Mandatory = $true)]
    [string] $prId,
    
    [Parameter(HelpMessage = "Override container name (defaults to pr{prId})", Mandatory = $false)]
    [string] $containerName = "",
    
    [Parameter(HelpMessage = "Path to backup file for restore", Mandatory = $false)]
    [string] $backupPath = "",
    
    [Parameter(HelpMessage = "Domain name for container access", Mandatory = $false)]
    [string] $domainName = "",
    
    [Parameter(HelpMessage = "Use Traefik for reverse proxy", Mandatory = $false)]
    [bool] $useTraefik = $true,
    
    [Parameter(HelpMessage = "JSON object with CPU and memory limits", Mandatory = $false)]
    [string] $resourceLimits = "",
    
    [Parameter(HelpMessage = "Force cleanup of existing container", Mandatory = $false)]
    [bool] $forceCleanup = $false,
    
    [Parameter(HelpMessage = "Post container URL as PR comment", Mandatory = $false)]
    [bool] $postComment = $true
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# Import required modules
. (Join-Path $PSScriptRoot ".." "AL-Go-Helper.ps1")
. (Join-Path $PSScriptRoot "PRContainerHelper.psm1")

function Main {
    Write-Host "Starting PR Container Management - Operation: $operation, PR ID: $prId"
    
    # Set default container name if not provided
    if ([string]::IsNullOrEmpty($containerName)) {
        $containerName = "pr$prId"
    }
    
    # Read settings
    $settings = ReadSettings -project '.'
    $prContainerSettings = $settings.prContainers
    
    if (-not $prContainerSettings.enabled) {
        Write-Host "PR Containers are not enabled in settings"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "message=PR Containers not enabled"
        return
    }
    
    # Parse resource limits if provided
    $limits = @{}
    if (-not [string]::IsNullOrEmpty($resourceLimits)) {
        $limits = $resourceLimits | ConvertFrom-Json -AsHashtable
    }
    
    # Execute operation
    $result = @{
        containerName = $containerName
        containerUrl = ""
        message = ""
    }
    
    try {
        switch ($operation) {
            'create' {
                $result = Invoke-PRContainerCreate -containerName $containerName -prId $prId -settings $prContainerSettings -backupPath $backupPath -limits $limits
            }
            'update' {
                $result = Invoke-PRContainerUpdate -containerName $containerName -prId $prId -settings $prContainerSettings -limits $limits
            }
            'remove' {
                $result = Invoke-PRContainerRemove -containerName $containerName -forceCleanup $forceCleanup
            }
        }
        
        # Set outputs
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "containerName=$($result.containerName)"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "containerUrl=$($result.containerUrl)"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "message=$($result.message)"
        
        Write-Host "PR Container operation '$operation' completed successfully"
        Write-Host "Container: $($result.containerName)"
        if (-not [string]::IsNullOrEmpty($result.containerUrl)) {
            Write-Host "URL: $($result.containerUrl)"
        }
        
    }
    catch {
        $errorMessage = "PR Container operation '$operation' failed: $($_.Exception.Message)"
        Write-Host "::error::$errorMessage"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "message=$errorMessage"
        throw
    }
}

# Execute main function
Main