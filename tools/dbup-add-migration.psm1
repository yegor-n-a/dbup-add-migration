﻿function Add-DbUpMigration {
    param
    (
        [string] $Name,
        [string] $Folder = "",
        [BuildActionType] $BuildAction = [BuildActionType]::None,
        [ExecutionMode] $ExecutionMode = [ExecutionMode]::None
    )

    $migrationsFolderName = "Migrations"
    $scriptsFolderName = "Scripts"

    $project = Get-Project
    $projectDir = Split-Path $project.FullName
    $scriptsDir = $projectDir    

    $defaultFileName = [File]::getDefaultName()
    $filePath = Join-Path $projectDir $defaultFileName
    
    $settings = [Settings]::readFromFile($filePath)

    #assign default settings if requested does not exist
    if ($null -eq $settings) {
        $settings = [Settings]::new()
    }

    #apply folder and build action values from settings file
    #(only if folder is not specified and build action is 'None')
    Apply-Settings -folder ([ref]$Folder) -buildAction ([ref]$BuildAction) -executionMode ([ref]$ExecutionMode) -settings $settings

    #check if the scripts folder is specified
    if ($Folder -ne "") {
        $scriptsDir = Join-Path $scriptsDir $Folder
        
        #create the scripts directory if it doesn't exist yet
        if (-not (Test-Path $scriptsDir -PathType Container)) {
            New-Item -ItemType Directory -Path $scriptsDir | Out-Null
        }
    }
    #check if "Migrations" folder exists    
    elseif (Test-Path (Join-Path $scriptsDir $migrationsFolderName) -PathType Container) {
        $scriptsDir = Join-Path $scriptsDir $migrationsFolderName
    }
    #check if "Scripts" folder exists    
    elseif (Test-Path (Join-Path $scriptsDir $scriptsFolderName) -PathType Container) {
        $scriptsDir = Join-Path $scriptsDir $scriptsFolderName
    }
    else {
        #search for .sql files in the project
        $sqlFiles = @(Get-ChildItem -Path $projectDir -Filter *.sql -Recurse)

        #if no sql files are found, create a "Migrations" folder,
        #where the new migration file will be stored
        if ($sqlFiles.Count -eq 0) {
            $scriptsDir = Join-Path $scriptsDir $migrationsFolderName
            New-Item -ItemType Directory -Path $scriptsDir | Out-Null
        }
        #get the first folder with sql files
        else {
            $scriptsDir = $sqlFiles[0].DirectoryName
        }
    }

    #generate migration file name and path
    $fileName = [File]::buildFullName($Name, $settings.File.PrefixFormat, $settings.File.SegmentSeparator, $ExecutionMode)
    $filePath = Join-Path $scriptsDir $fileName
 
    #create migration file
    New-Item -Path $scriptsDir -Name $fileName -ItemType File | Out-Null

    #add the migration file to the project
    $item = $project.ProjectItems.AddFromFile($filePath)
    
    #set the build action
    if ($BuildAction -ne [BuildActionType]::None) {
        $item.Properties.Item("BuildAction").Value = $BuildAction -as [int]

        #if build action is set to content, then also
        #set 'copy to output directory' to 'copy always'
        if ($BuildAction -eq [BuildActionType]::Content) {
            $item.Properties.Item("CopyToOutputDirectory").Value = [uint32]1
        }
    }

    Write-Host "Created a new migration file - ${fileName}"

    #open the migration file
    $dte.ItemOperations.OpenFile($filePath) | Out-Null
}

function Add-Migration {
    param
    (
        [string] $Name,
        [string] $Folder = "",
        [BuildActionType] $BuildAction = [BuildActionType]::None,
        [ExecutionMode] $ExecutionMode = [ExecutionMode]::None
    )

    Add-DbUpMigration -Name $Name -Folder $Folder -BuildAction $BuildAction -ExecutionMode $ExecutionMode
}

function Apply-Settings([ref]$folder, [ref]$buildAction, [ref]$executionMode, [Settings]$settings) {    
    #overwrite $folder value only if it's not already set
    if ($folder.Value -eq "") {
        $folder.Value = $settings.Folder
    }
        
    #overwrite $buildAction value only if it's set to 'None'
    if ($buildAction.Value -eq [BuildActionType]::None) {
        $buildAction.Value = [BuildActionType] $settings.BuildAction
    }
        
    #overwrite $executionMode value only if it's set to 'None'
    if ($executionMode.Value -eq [ExecutionMode]::None) {
        $executionMode.Value = [ExecutionMode] $settings.ExecutionMode
    }
}

function Add-MigrationSettings {
    $project = Get-Project
    $projectDir = Split-Path $project.FullName
    $settingsFileName = [File]::getDefaultName()
    $settingsFilePath = Join-Path $projectDir $settingsFileName

    #create settings file only if it doesn't exist yet
    if (Test-Path $settingsFilePath -PathType Leaf) {
        Write-Host "A settings file for Add-Migration command already exists"
    }
    else {
        #create the file
        New-Item -Path $projectDir -Name $settingsFileName -ItemType File | Out-Null
        
        #getting default file settings
        $defaultFileSettings = [File]::new() | Select-Object -Property * -ExcludeProperty Name

        if ([Settings]::getDefaultExecutionMode() -ne [ExecutionMode]::None) {
            $defaultExecutionMode = [Settings]::getDefaultExecutionMode().ToString()
        }
        else {
            $defaultExecutionMode = $null
        }
        
        #composing default settings
        $defaultSettings = [PSCustomObject]@{
            folder        = [Settings]::getDefaultFolder()
            buildAction   = [Settings]::getDefaultBuildAction()
            executionMode = $defaultExecutionMode
            file          = $defaultFileSettings
        }

        #converting default settings into json-file
        $defaultSettings | Remove-NullOrEmpty | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsFilePath

        #add settings file to the project
        $item = $project.ProjectItems.AddFromFile($settingsFilePath)

        #open settings file
        $dte.ItemOperations.OpenFile($settingsFilePath) | Out-Null
    }
}

function Remove-NullOrEmpty {
    [cmdletbinding()]
    param(
        #object to remove null values from
        [parameter(ValueFromPipeline, Mandatory)]
        [object[]]$InputObject,
        #by default, remove empty strings (""); specify -LeaveEmptyStrings to leave them
        [switch]$LeaveEmptyStrings
    )
    process {
        foreach ($obj in $InputObject) {
            $AllProperties = $obj.psobject.properties.Name
            $NonNulls = $AllProperties |
            where-object { $null -ne $obj.$PSItem } |
            where-object { $LeaveEmptyStrings.IsPresent -or -not [string]::IsNullOrEmpty($obj.$PSItem) }
            $obj | Select-Object -Property $NonNulls
        }
    }
}

class Settings {
    [string] $Folder
    [string] $BuildAction
    [File] $File
    [ExecutionMode] $ExecutionMode

    hidden static [string] $defaultFolder = "Migrations"
    hidden static [string] $defaultBuildAction = "EmbeddedResource"
    hidden static [ExecutionMode] $defaultExecutionMode = [ExecutionMode]::None

    static [string] getDefaultFolder() {
        return [Settings]::defaultFolder
    }

    static [string] getDefaultBuildAction() {
        return [Settings]::defaultBuildAction
    }
    
    static [ExecutionMode] getDefaultExecutionMode() {
        return [Settings]::defaultExecutionMode
    }

    static [Settings] readFromFile([string]$FilePath) {    
        #check if settings file exists
        if (Test-Path $FilePath -PathType Leaf) {
            return [Settings](Get-Content -Raw -Path $FilePath | ConvertFrom-Json)
        }
        else {
            return $null
        }
    }
    
    Settings() {
        $this.Folder = [Settings]::getDefaultFolder()
        $this.BuildAction = [Settings]::getDefaultBuildAction()
        $this.File = [File]::new()
        $this.ExecutionMode = [Settings]::getDefaultExecutionMode()
    }

    Settings([string] $Folder, [string] $BuildAction, [File] $File, [ExecutionMode] $ExecutionMode) {
        $this.Folder = $Folder
        $this.BuildAction = $BuildAction
        $this.File = $File
        $this.ExecutionMode = $ExecutionMode
    }
}

class File {
    [string] $Name
    [string] $SegmentSeparator
    [string] $PrefixFormat

    hidden static [string] $defaultName = "dbup-add-migration.json"
    hidden static [string] $defaultSegmentSeparator = "_"
    hidden static [string] $defaultPrefixFormat = "yyyyMMddHHmmss"

    static [string] getDefaultName() {
        return [File]::defaultName
    }

    static [string] getDefaultSegmentSeparator() {
        return [File]::defaultSegmentSeparator
    }

    static [string] getDefaultPrefixFormat() {
        return [File]::defaultPrefixFormat
    }

    static [string] buildFullName([string]$MainSegment, [string]$Format, [string]$Separator, [ExecutionMode]$ExecutionMode) {
        $fullName = Get-Date([System.DateTime]::UtcNow) -Format $Format
        
        if ($ExecutionMode -ne [ExecutionMode]::None) {
            $fullName += $Separator + $ExecutionMode.ToString()
        }
    
        if ($MainSegment -ne "") {
            $fullName += $Separator + $MainSegment
        }
    
        return $fullName + ".sql"
    }

    File() {
        $this.Name = [File]::getDefaultName()
        $this.SegmentSeparator = [File]::getDefaultSegmentSeparator()
        $this.PrefixFormat = [File]::getDefaultPrefixFormat()
    }

    File([string] $Name, [string] $SegmentSeparator, [string] $PrefixFormat) {
        $this.Name = $Name
        $this.SegmentSeparator = $SegmentSeparator
        $this.PrefixFormat = $PrefixFormat
    }
}

enum BuildActionType {
    None = 0
    Compile = 1
    Content = 2
    EmbeddedResource = 3
}

enum ExecutionMode {
    None = 0
    RunOnce = 1
    RunAlways = 2
    RunOnChange = 3
}

Export-ModuleMember -Function Add-DbUpMigration, Add-Migration, Add-MigrationSettings