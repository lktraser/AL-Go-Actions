function Invoke-PRContainerCreate {
    Param(
        [string] $containerName,
        [string] $prId,
        [hashtable] $settings,
        [string] $backupPath,
        [hashtable] $limits
    )
    
    Write-Host "Creating PR container: $containerName"
    
    # Check if container already exists - if so, remove it first
    if (Test-BcContainer $containerName) {
        Write-Host "Container $containerName already exists. Removing first..."
        Remove-BcContainer $containerName -force
    }
    
    # Find latest backup if not specified
    if ([string]::IsNullOrEmpty($backupPath)) {
        $backupPath = Get-LatestBackup -settings $settings
        if ([string]::IsNullOrEmpty($backupPath)) {
            throw "No backup found and no backup path specified"
        }
    }
    
    # Prepare container credentials
    $containerCredential = Get-ContainerCredentials
    
    # Prepare SharePoint credentials if needed
    $sharepointCredential = Get-SharePointCredentials
    
    # Create container parameters
    $containerParams = @{
        containername = $containerName
        credential = $containerCredential
        bakFolder = $backupPath
        isolation = 'process'
        updateHosts = $true
        includeAL = $true
        shortcuts = 'None'
    }
    
    # Add resource limits if specified
    if ($limits.Count -gt 0) {
        if ($limits.ContainsKey('memory')) {
            $containerParams.memoryLimit = $limits.memory
        }
        if ($limits.ContainsKey('cpu')) {
            $containerParams.additionalParameters = @("--cpus=$($limits.cpu)")
        }
    }
    
    # Add Traefik configuration if enabled
    if ($settings.useTraefik -and -not [string]::IsNullOrEmpty($settings.domainName)) {
        $containerParams.useTraefik = $true
        $containerParams.PublicDnsName = $settings.domainName
    }
    
    # Create the container
    Write-Host "Creating container with backup: $backupPath"
    New-BcContainer @containerParams
    
    # Deploy PR branch apps
    Deploy-PRApps -containerName $containerName -prId $prId -credential $containerCredential -sharepointCredential $sharepointCredential
    
    # Generate container URL
    $containerUrl = Get-ContainerUrl -containerName $containerName -settings $settings
    
    return @{
        containerName = $containerName
        containerUrl = $containerUrl
        message = "Container created successfully"
    }
}

function Invoke-PRContainerUpdate {
    Param(
        [string] $containerName,
        [string] $prId,
        [hashtable] $settings,
        [hashtable] $limits
    )
    
    Write-Host "Updating PR container: $containerName"
    
    # Simple approach: Remove and recreate container
    if (Test-BcContainer $containerName) {
        Write-Host "Removing existing container for update..."
        Remove-BcContainer $containerName -force
    }
    
    # Get latest backup for recreation
    $backupPath = Get-LatestBackup -settings $settings
    if ([string]::IsNullOrEmpty($backupPath)) {
        throw "No backup found for container update"
    }
    
    # Recreate container with latest backup and PR apps
    return Invoke-PRContainerCreate -containerName $containerName -prId $prId -settings $settings -backupPath $backupPath -limits $limits
}


function Invoke-PRContainerRemove {
    Param(
        [string] $containerName,
        [bool] $forceCleanup
    )
    
    Write-Host "Removing PR container: $containerName"
    
    if (-not (Test-BcContainer $containerName)) {
        Write-Host "Container $containerName does not exist"
        return @{
            containerName = $containerName
            containerUrl = ""
            containerStatus = "NotFound"
            message = "Container does not exist"
        }
    }
    
    # Remove container
    if ($forceCleanup) {
        Remove-BcContainer $containerName -force
    } else {
        Remove-BcContainer $containerName
    }
    
    return @{
        containerName = $containerName
        containerUrl = ""
        message = "Container removed successfully"
    }
}


function Deploy-PRApps {
    Param(
        [string] $containerName,
        [string] $prId,
        [PSCredential] $credential,
        [PSCredential] $sharepointCredential
    )
    
    Write-Host "Deploying PR apps to container: $containerName"
    
    # Set high app version for PR builds
    Set-ALAppVersion -root $env:GITHUB_WORKSPACE -Build 2147483647
    
    # Use Deploy-ToALContainer from TraserBCHelper (similar to your pr.yml)
    $deployParams = @{
        containername = $containerName
        credential = $credential
        root = $env:GITHUB_WORKSPACE
        sharepointcredential = $sharepointCredential
        downloaddependencies = $true
        usetraefik = $true
        pubdnsname = $settings.domainName
        releasetype = "master"  # Could be made configurable
        runContainerUpgrade = $true
        includeRelatedApps = $true
        useNuGet = $true
        nuGetToken = $env:TRASERInternalFeedsToken
    }
    
    Deploy-ToALContainer @deployParams
}

function Get-LatestBackup {
    Param(
        [hashtable] $settings
    )
    
    $backupLocation = $settings.backup.storageLocation
    if ([string]::IsNullOrEmpty($backupLocation)) {
        return ""
    }
    
    # Find the most recent backup
    $backupPattern = Join-Path $backupLocation "*"
    $latestBackup = Get-ChildItem $backupPattern -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    
    if ($latestBackup) {
        return $latestBackup.FullName
    }
    
    return ""
}

function Get-ContainerCredentials {
    # Use credentials from environment
    $containerPassword = ConvertTo-SecureString $env:containerpassword -AsPlainText -Force
    $containerUsername = $env:containerusername
    return New-Object System.Management.Automation.PSCredential -ArgumentList $containerUsername, $containerPassword
}

function Get-SharePointCredentials {
    if (-not [string]::IsNullOrEmpty($env:sppassword) -and -not [string]::IsNullOrEmpty($env:spusername)) {
        $password = ConvertTo-SecureString $env:sppassword -AsPlainText -Force
        $username = $env:spusername
        return New-Object System.Management.Automation.PSCredential -ArgumentList $username, $password
    }
    return $null
}

function Get-ContainerUrl {
    Param(
        [string] $containerName,
        [hashtable] $settings
    )
    
    if ($settings.useTraefik -and -not [string]::IsNullOrEmpty($settings.domainName)) {
        return "https://$containerName.$($settings.domainName)"
    }
    
    # Fallback to IP-based access
    $containerInfo = Get-BcContainerInfo $containerName
    if ($containerInfo -and $containerInfo.IpAddress) {
        return "http://$($containerInfo.IpAddress):7048/BC"
    }
    
    return ""
}

Export-ModuleMember -Function @(
    'Invoke-PRContainerCreate',
    'Invoke-PRContainerUpdate', 
    'Invoke-PRContainerRemove'
)