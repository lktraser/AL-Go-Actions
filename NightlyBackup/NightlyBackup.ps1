Param(
    [Parameter(HelpMessage = "Name for the backup container", Mandatory = $false)]
    [string] $containerName = "nightly-backup",
    
    [Parameter(HelpMessage = "Business Central version to use", Mandatory = $false)]
    [string] $bcVersion = "",
    
    [Parameter(HelpMessage = "JSON array of apps to install", Mandatory = $false)]
    [string] $appList = "",
    
    [Parameter(HelpMessage = "License file URL or path", Mandatory = $false)]
    [string] $licenseFile = "",
    
    [Parameter(HelpMessage = "RapidStart language code", Mandatory = $false)]
    [string] $rapidStartLanguage = "DE",
    
    [Parameter(HelpMessage = "Number of days to keep backups", Mandatory = $false)]
    [int] $retentionDays = 7,
    
    [Parameter(HelpMessage = "Path where backups should be stored", Mandatory = $false)]
    [string] $storageLocation = "",
    
    [Parameter(HelpMessage = "Force recreation of backup even if recent one exists", Mandatory = $false)]
    [bool] $forceRecreate = $false
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# Import required modules
. (Join-Path $PSScriptRoot ".." "AL-Go-Helper.ps1")

function Main {
    Write-Host "Starting Nightly Database Backup Creation"
    Write-Host "Container: $containerName"
    Write-Host "BC Version: $bcVersion"
    Write-Host "Retention Days: $retentionDays"
    
    # Read settings
    $settings = ReadSettings -project '.'
    $prContainerSettings = $settings.prContainers
    $backupSettings = $prContainerSettings.backup
    
    if (-not $prContainerSettings.enabled) {
        Write-Host "PR Containers are not enabled in settings"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "message=PR Containers not enabled"
        return
    }
    
    # Override settings with parameters
    if (-not [string]::IsNullOrEmpty($storageLocation)) {
        $backupSettings.storageLocation = $storageLocation
    }
    if ($retentionDays -gt 0) {
        $backupSettings.retentionDays = $retentionDays
    }
    
    # Parse app list if provided
    $apps = @()
    if (-not [string]::IsNullOrEmpty($appList)) {
        $apps = $appList | ConvertFrom-Json
    } elseif ($backupSettings.apps) {
        $apps = $backupSettings.apps
    }
    
    # Check if backup is needed
    if (-not $forceRecreate) {
        $existingBackup = Get-LatestBackup -backupSettings $backupSettings
        if ($existingBackup -and (Test-BackupAge -backupPath $existingBackup -maxAgeHours 24)) {
            Write-Host "Recent backup exists and is less than 24 hours old: $existingBackup"
            Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "backupPath=$existingBackup"
            Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "message=Using existing recent backup"
            return
        }
    }
    
    try {
        # Create timestamp for backup
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupContainerName = "$containerName-$timestamp"
        
        # Prepare backup target folder
        $bakTargetFolder = Join-Path $backupSettings.storageLocation $backupContainerName
        
        # Remove existing backup container if it exists
        if (Test-BcContainer $backupContainerName) {
            Remove-BcContainer $backupContainerName -force
        }
        
        # Prepare credentials
        $containerCredential = Get-ContainerCredentials
        $sharepointCredential = Get-SharePointCredentials
        
        # Determine artifact URL
        $artifactUrl = ""
        if (-not [string]::IsNullOrEmpty($bcVersion)) {
            $artifactUrl = Get-ALArtifactUrl -root $env:GITHUB_WORKSPACE -version $bcVersion
        } elseif (-not [string]::IsNullOrEmpty($backupSettings.bcVersion)) {
            $artifactUrl = Get-ALArtifactUrl -root $env:GITHUB_WORKSPACE -version $backupSettings.bcVersion
        }
        
        # Create backup container
        Write-Host "Creating backup container: $backupContainerName"
        $containerParams = @{
            containername = $backupContainerName
            credential = $containerCredential
            isolation = 'process'
            updateHosts = $true
            includeAL = $true
            shortcuts = 'None'
        }
        
        if (-not [string]::IsNullOrEmpty($artifactUrl)) {
            $containerParams.artifactUrl = $artifactUrl
        }
        
        if (-not [string]::IsNullOrEmpty($licenseFile)) {
            $containerParams.licenseFile = $licenseFile
        } elseif (-not [string]::IsNullOrEmpty($backupSettings.licenseFile)) {
            $containerParams.licenseFile = $backupSettings.licenseFile
        }
        
        Create-ALContainer @containerParams
        
        # Remove default companies
        Write-Host "Removing default companies..."
        $companyList = Get-CompanyInBcContainer -containerName $backupContainerName
        foreach ($company in $companyList) {
            Remove-CompanyInBcContainer -containerName $backupContainerName -companyName $company.CompanyName
        }
        
        # Install apps
        if ($apps.Count -gt 0) {
            Write-Host "Installing apps..."
            foreach ($app in $apps) {
                Write-Host "Installing app: $($app.name)"
                Install-ALApp -root $env:GITHUB_WORKSPACE `
                    -containername $backupContainerName `
                    -credential $containerCredential `
                    -appName $app.name `
                    -appId $app.id `
                    -appPublisher $app.publisher `
                    -sharepointcredential $sharepointCredential `
                    -downloadDependencies `
                    -releasetype "release" `
                    -apptype "dev" `
                    -importAppData `
                    -rapidStartLanguage $rapidStartLanguage `
                    -useDevEndpoint $true `
                    -useNuGet:$true `
                    -nuGetToken $env:TRASERInternalFeedsToken
            }
        }
        
        # Uninstall TRASER apps (keep only dependencies and test data)
        Write-Host "Removing TRASER apps to keep only base data..."
        $installedApps = Get-BcContainerAppInfo -containerName $backupContainerName -tenantSpecificProperties -sort DependenciesLast |
                        Where-Object { $_.Publisher -ne 'Microsoft' }
        
        foreach ($app in $installedApps) {
            UnInstall-BcContainerApp -containerName $backupContainerName -name $app.Name -publisher $app.Publisher -force
        }
        
        # Create backup
        Write-Host "Creating database backup in: $bakTargetFolder"
        New-Item -ItemType Directory -Path $bakTargetFolder -Force | Out-Null
        Backup-BcContainerDatabases -containerName $backupContainerName -bakFolder $bakTargetFolder
        
        # Stop and remove backup container
        Write-Host "Cleaning up backup container..."
        Stop-BcContainer -containerName $backupContainerName
        Remove-BcContainer -containerName $backupContainerName -force
        
        # Cleanup old backups
        Remove-OldBackups -backupSettings $backupSettings
        
        # Set outputs
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "backupPath=$bakTargetFolder"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "backupTimestamp=$timestamp"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "containerName=$backupContainerName"
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "message=Backup created successfully"
        
        Write-Host "Nightly backup completed successfully"
        Write-Host "Backup location: $bakTargetFolder"
        
    }
    catch {
        $errorMessage = "Nightly backup failed: $($_.Exception.Message)"
        Write-Host "::error::$errorMessage"
        
        # Cleanup on error
        if (Test-BcContainer $backupContainerName) {
            try {
                Remove-BcContainer $backupContainerName -force
            }
            catch {
                Write-Host "::warning::Failed to cleanup backup container: $($_.Exception.Message)"
            }
        }
        
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "message=$errorMessage"
        throw
    }
}

function Get-LatestBackup {
    Param(
        [hashtable] $backupSettings
    )
    
    $backupLocation = $backupSettings.storageLocation
    if ([string]::IsNullOrEmpty($backupLocation) -or -not (Test-Path $backupLocation)) {
        return $null
    }
    
    # Find the most recent backup directory
    $backupDirs = Get-ChildItem $backupLocation -Directory | Where-Object { $_.Name -match "nightly-backup-\d{8}-\d{6}" }
    $latestBackup = $backupDirs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    
    if ($latestBackup) {
        return $latestBackup.FullName
    }
    
    return $null
}

function Test-BackupAge {
    Param(
        [string] $backupPath,
        [int] $maxAgeHours
    )
    
    if (-not (Test-Path $backupPath)) {
        return $false
    }
    
    $backupInfo = Get-Item $backupPath
    $ageHours = (Get-Date) - $backupInfo.LastWriteTime
    
    return $ageHours.TotalHours -lt $maxAgeHours
}

function Remove-OldBackups {
    Param(
        [hashtable] $backupSettings
    )
    
    $backupLocation = $backupSettings.storageLocation
    $retentionDays = $backupSettings.retentionDays
    
    if ([string]::IsNullOrEmpty($backupLocation) -or $retentionDays -le 0) {
        return
    }
    
    if (-not (Test-Path $backupLocation)) {
        return
    }
    
    Write-Host "Cleaning up backups older than $retentionDays days..."
    
    $cutoffDate = (Get-Date).AddDays(-$retentionDays)
    $oldBackups = Get-ChildItem $backupLocation -Directory | 
                  Where-Object { $_.Name -match "nightly-backup-\d{8}-\d{6}" -and $_.LastWriteTime -lt $cutoffDate }
    
    foreach ($oldBackup in $oldBackups) {
        Write-Host "Removing old backup: $($oldBackup.Name)"
        try {
            Remove-Item $oldBackup.FullName -Recurse -Force
        }
        catch {
            Write-Host "::warning::Failed to remove old backup $($oldBackup.Name): $($_.Exception.Message)"
        }
    }
}

function Get-ContainerCredentials {
    if (-not [string]::IsNullOrEmpty($env:containerpassword) -and -not [string]::IsNullOrEmpty($env:containerusername)) {
        $containerPassword = ConvertTo-SecureString $env:containerpassword -AsPlainText -Force
        $containerUsername = $env:containerusername
        return New-Object System.Management.Automation.PSCredential -ArgumentList $containerUsername, $containerPassword
    }
    
    throw "Container credentials not found in environment variables"
}

function Get-SharePointCredentials {
    if (-not [string]::IsNullOrEmpty($env:sppassword) -and -not [string]::IsNullOrEmpty($env:spusername)) {
        $password = ConvertTo-SecureString $env:sppassword -AsPlainText -Force
        $username = $env:spusername
        return New-Object System.Management.Automation.PSCredential -ArgumentList $username, $password
    }
    return $null
}

# Execute main function
Main