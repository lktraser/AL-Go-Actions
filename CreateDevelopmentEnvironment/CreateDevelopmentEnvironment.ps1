[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'GitHub Secrets are transferred as plain text')]
Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Name of the online environment", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Project name if the repository is setup for multiple projects", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "Admin center API credentials", Mandatory = $false)]
    [string] $adminCenterApiCredentials,
    [Parameter(HelpMessage = "Reuse environment if it exists?", Mandatory = $false)]
    [bool] $reUseExistingEnvironment,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $updateBranch,
    [Parameter(HelpMessage = "Direct Commit?", Mandatory = $false)]
    [bool] $directCommit
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
$serverUrl, $branch = CloneIntoNewFolder -actor $actor -token $token -updateBranch $updateBranch -DirectCommit $directCommit -newBranchPrefix 'create-development-environment'
$baseFolder = (Get-Location).Path
DownloadAndImportBcContainerHelper -baseFolder $baseFolder

$adminCenterApiCredentials = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($adminCenterApiCredentials))
CreateDevEnv `
    -kind cloud `
    -caller GitHubActions `
    -environmentName $environmentName `
    -reUseExistingEnvironment:$reUseExistingEnvironment `
    -baseFolder $baseFolder `
    -project $project `
    -adminCenterApiCredentials ($adminCenterApiCredentials | ConvertFrom-Json | ConvertTo-HashTable)

CommitFromNewFolder -serverUrl $serverUrl -commitMessage "Create a development environment $environmentName" -branch $branch | Out-Null
