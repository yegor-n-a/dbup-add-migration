function Add-DbUpMigration {
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

    # Assign default settings if requested does not exist
    if ($null -eq $settings) {
        $settings = [Settings]::new()
    }

    # Apply folder and build action values from settings file
    # (only if folder is not specified and build action is 'None')
    Apply-Settings -folder ([ref]$Folder) -buildAction ([ref]$BuildAction) -executionMode ([ref]$ExecutionMode) -settings $settings
    
    # TODO: finish implementation
    $visualStudioVersion = $settings.VisualStudioVersion
    $fullPath = [VisualStudioSolutionExplorer]::getSelectedItemFullPath($visualStudioVersion) | Out-Host

    # Check if the scripts folder is specified
    if ($Folder -ne "") {
        $scriptsDir = Join-Path $scriptsDir $Folder
        
        # Create the scripts directory if it doesn't exist yet
        if (-not (Test-Path $scriptsDir -PathType Container)) {
            New-Item -ItemType Directory -Path $scriptsDir | Out-Null
        }
    }
    # Check if "Migrations" folder exists    
    elseif (Test-Path (Join-Path $scriptsDir $migrationsFolderName) -PathType Container) {
        $scriptsDir = Join-Path $scriptsDir $migrationsFolderName
    }
    # Check if "Scripts" folder exists    
    elseif (Test-Path (Join-Path $scriptsDir $scriptsFolderName) -PathType Container) {
        $scriptsDir = Join-Path $scriptsDir $scriptsFolderName
    }
    else {
        # Search for .sql files in the project
        $sqlFiles = @(Get-ChildItem -Path $projectDir -Filter *.sql -Recurse)

        # If no sql files are found, create a "Migrations" folder,
        # where the new migration file will be stored
        if ($sqlFiles.Count -eq 0) {
            $scriptsDir = Join-Path $scriptsDir $migrationsFolderName
            New-Item -ItemType Directory -Path $scriptsDir | Out-Null
        }
        # Get the first folder with sql files
        else {
            $scriptsDir = $sqlFiles[0].DirectoryName
        }
    }

    # Generate migration file name and path
    $fileName = [File]::buildFullName($Name, $settings.File.PrefixFormat, $settings.File.SegmentSeparator, $ExecutionMode)
    $filePath = Join-Path $scriptsDir $fileName
 
    # Create migration file
    New-Item -Path $scriptsDir -Name $fileName -ItemType File | Out-Null

    # Add the migration file to the project
    $item = $project.ProjectItems.AddFromFile($filePath)
    
    # Set the build action
    if ($BuildAction -ne [BuildActionType]::None) {
        $item.Properties.Item("BuildAction").Value = $BuildAction -as [int]

        # If build action is set to content, then also
        # set 'copy to output directory' to 'copy always'
        if ($BuildAction -eq [BuildActionType]::Content) {
            $item.Properties.Item("CopyToOutputDirectory").Value = [uint32]1
        }
    }

    Write-Host "Created a new migration file - ${fileName}"

    # Open the migration file
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
    # Overwrite $folder value only if it's not already set
    if ($folder.Value -eq "") {
        $folder.Value = $settings.Folder
    }
        
    # Overwrite $buildAction value only if it's set to 'None'
    if ($buildAction.Value -eq [BuildActionType]::None) {
        $buildAction.Value = [BuildActionType] $settings.BuildAction
    }
        
    # Overwrite $executionMode value only if it's set to 'None'
    if ($executionMode.Value -eq [ExecutionMode]::None) {
        $executionMode.Value = [ExecutionMode] $settings.ExecutionMode
    }
}

function Add-MigrationSettings {
    $project = Get-Project
    $projectDir = Split-Path $project.FullName
    $settingsFileName = [File]::getDefaultName()
    $settingsFilePath = Join-Path $projectDir $settingsFileName

    # Create settings file only if it doesn't exist yet
    if (Test-Path $settingsFilePath -PathType Leaf) {
        Write-Host "A settings file for Add-Migration command already exists"
    }
    else {
        # Create the file
        New-Item -Path $projectDir -Name $settingsFileName -ItemType File | Out-Null
        
        # Getting default file settings
        $defaultFileSettings = [File]::new() | Select-Object -Property * -ExcludeProperty Name

        if ([Settings]::getDefaultExecutionMode() -ne [ExecutionMode]::None) {
            $defaultExecutionMode = [Settings]::getDefaultExecutionMode().ToString()
        }
        else {
            $defaultExecutionMode = $null
        }

        $defaultVisualStudioVersion = [Settings]::getDefaultVisualStudioVersion()

        if ([System.String]::IsNullOrWhiteSpace($defaultVisualStudioVersion)) {
            $visualStudioVersion = $null
        }
        else {
            $visualStudioVersion = $defaultVisualStudioVersion
        }
        
        # Composing default settings
        $defaultSettings = [PSCustomObject]@{
            folder              = [Settings]::getDefaultFolder()
            buildAction         = [Settings]::getDefaultBuildAction()
            executionMode       = $defaultExecutionMode
            visualStudioVersion = $visualStudioVersion
            file                = $defaultFileSettings
        }

        # Converting default settings into json-file
        $defaultSettings | Remove-NullOrEmpty | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsFilePath

        # Add settings file to the project
        $item = $project.ProjectItems.AddFromFile($settingsFilePath)

        # Open settings file
        $dte.ItemOperations.OpenFile($settingsFilePath) | Out-Null
    }
}

function Remove-NullOrEmpty {
    [cmdletbinding()]
    param(
        # Object to remove null values from
        [parameter(ValueFromPipeline, Mandatory)]
        [object[]]$InputObject,
        # By default, remove empty strings (""); specify -LeaveEmptyStrings to leave them
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
    [string] $VisualStudioVersion

    hidden static [string] $defaultFolder = "Migrations"
    hidden static [string] $defaultBuildAction = "EmbeddedResource"
    hidden static [ExecutionMode] $defaultExecutionMode = [ExecutionMode]::None
    hidden static [string] $defaultVisualStudioVersion = "VisualStudio.DTE.15.0"

    static [string] getDefaultFolder() {
        return [Settings]::defaultFolder
    }

    static [string] getDefaultBuildAction() {
        return [Settings]::defaultBuildAction
    }
    
    static [ExecutionMode] getDefaultExecutionMode() {
        return [Settings]::defaultExecutionMode
    }
    
    static [string] getDefaultVisualStudioVersion() {
        return [Settings]::defaultVisualStudioVersion
    }

    static [Settings] readFromFile([string]$FilePath) {    
        # Check if settings file exists
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
        $this.VisualStudioVersion = [Settings]::getDefaultVisualStudioVersion()
    }

    Settings([string] $Folder, [string] $BuildAction, [File] $File, [ExecutionMode] $ExecutionMode, [string] $VisualStudioVersion) {
        $this.Folder = $Folder
        $this.BuildAction = $BuildAction
        $this.File = $File
        $this.ExecutionMode = $ExecutionMode
        $this.VisualStudioVersion = $VisualStudioVersion
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

class Folder {
    [string] $RelativeToProjectInPkgMgmtConsole
    [bool] $TakeSelectedInSolutionExplorer

    hidden static [string] $defaultRelativeToProjectInPkgMgmtConsole = "Migrations"
    hidden static [bool] $defaultTakeSelectedInSolutionExplorer = $false

    static [string] getDefaultRelativeToProjectInPkgMgmtConsole() {
        return [Folder]::defaultRelativeToProjectInPkgMgmtConsole
    }

    static [bool] getDefaultTakeSelectedInSolutionExplorer() {
        return [Folder]::defaultTakeSelectedInSolutionExplorer
    }

    Folder() {
        $this.RelativeToProjectInPkgMgmtConsole = [Folder]::defaultRelativeToProjectInPkgMgmtConsole
        $this.TakeSelectedInSolutionExplorer = [Folder]::defaultTakeSelectedInSolutionExplorer
    }

    Folder([string] $relativeToProjectInPkgMgmtConsole, [bool] $takeSelectedInSolutionExplorer) {
        $this.RelativeToProjectInPkgMgmtConsole = $relativeToProjectInPkgMgmtConsole
        $this.TakeSelectedInSolutionExplorer = $takeSelectedInSolutionExplorer
    }
}

class VisualStudioSolutionExplorer {
    # Refers to "reserved" GUID, which is defined in Visual Studio SDK as a part of "system" constants
    # please, see details: https://docs.microsoft.com/en-us/visualstudio/extensibility/ide-guids?view=vs-2017
    hidden static [guid] $physicalFolderIdConst = "6bb5f8ef-4483-11d3-8bcf-00c04f8ec28c"

    static [guid] getPhysicalFolderIdConst() {
        return [VisualStudioSolutionExplorer]::physicalFolderIdConst
    }

    static [string] getSelectedItemFullPath([string] $visualStudioDteVersion) {
        $dteObject = [System.Runtime.InteropServices.Marshal]::GetActiveObject($visualStudioDteVersion)

        $multipleItemsSelected = $dteObject.SelectedItems.MultiSelect
    
        # Exit if multiple items have been selected
        if ($multipleItemsSelected) {
            return $null
        }
    
        $projectItem = $dteObject.SelectedItems.Item(1).ProjectItem
    
        # Exit if selected item is solution/virtual folder/project
        if ($null -eq $projectItem) {
            return $null
        }
    
        [guid] $projectItemId = $projectItem.Kind
        [guid] $physicalFolderId = [VisualStudioSolutionExplorer]::getPhysicalFolderIdConst()
    
        if ($projectItemId -ne $physicalFolderId) {
            return $null   
        }
    
        return $projectItem.Properties.Item("FullPath").Value.ToString()
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