[![NuGet](https://img.shields.io/nuget/dt/dbup-add-migration.svg)](https://www.nuget.org/packages/dbup-add-migration/)
[![NuGet](https://img.shields.io/nuget/v/dbup-add-migration.svg)](https://www.nuget.org/packages/dbup-add-migration/)

# Add-Migration command for DbUp
**Add-Migration** Package Manager Console command intended for use with [DbUp](http://dbup.github.io/) (but not depending on it)

## Requirements

- Powershell 5

## About
This package adds a new command **"Add-Migration"** (and **"Add-DbUpMigration"** alias) to the Package Manager Console. Running the command results in generating an empty sql file with the specified name, which is prefixed by a timestamp in UTC (by default, in a format `_yyyyMMddHHmmss_`). The auto-generated file (e.g. `20170730185349_MyFirstMigration.sql`) will be added to the project, which you can set by selecting respective item from the dropdown list "Default project" on the top of your package manager console window.

Create a file using default behavior (the command will decide where to put it, build action will not be set):

    Add-Migration "MyFirstMigration"

Create a file in specific folder:

    Add-Migration "MyFirstMigration" -Folder "Migrations"    

Set build action when creating a file (use tab for -BuildAction value hints):

    Add-Migration "MyFirstMigration" -BuildAction EmbeddedResource

Include script execution mode into the file name to support building of `ScriptOptions` and improve integration of script types available for DbUp 4.2 and higher:

    Add-Migration "MyFirstMigration" -ExecutionMode RunAlways

**If you experience issues with `Add-Migration` command being overwritten by the EF migrations' command (which has the same name), please use the alias `Add-DbUpMigration` or prefix the command with package name: `dbup-add-migration\Add-Migration`**

---

The sql files are generated in either of these locations in your project:
- _Specified folder_ - when `-Folder` parameter is added, the script will be generated in the given directory. If the directory does not exist, it will be created.
- _"Migrations" folder_ - when `-Folder` parameter is omitted, but a folder named "Migrations" already exists in the project.
- _"Scripts" folder_ - when `-Folder` parameter is omitted, but a folder named "Scripts" already exists in the project.
- _First folder with .sql files_ - when `-Folder` parameter is omitted and neither "Migrations" nor "Scripts" folder exists, the command will add the new migration in the first folder in the project that contains .sql files. If no such folder is found, then "Migrations" folder will be created and used by default.

---

When `-BuildAction` parameter is set to _Content_, the command will also set **Copy to output directory** to _Copy always_

---

When `-ExecutionMode` parameter is not set or equal to `None`, it is ignored and will not be included into the file name

---

## Optional settings file
If you don't want to specify the `-BuildAction`, `-Folder` or `-ExecutionMode` parameter every time you add a new migration, you can add an optional settings file to your project by executing the following command:

    Add-MigrationSettings

This command will add `dbup-add-migration.json` file to your project (if it doesn't exist yet) with default configuration for the Add-Migration command:

```
{
    "folder": "Migrations",
    "buildAction": "EmbeddedResource",
    "file": {
        "SegmentSeparator":  "_",
        "PrefixFormat":  "yyyyMMddHHmmss"
    }
}
```

Please, note, that `executionMode` is optional and can be added if required (e.g. `"executionMode": "RunOnce"`)

---
The "buildAction" field should contain one of the following values:

- None
- Compile
- Content
- EmbeddedResource
---

The "executionMode" field should contain one of the following values:

- RunOnce
- RunAlways
- RunOnChange
---

However, if you have the settings file in your project and specify the `-BuildAction`, `-Folder` or `-ExecutionMode` parameters anyway when generating a new migration, they will take precedence over the values in `dbup-add-migration.json`

## How to install
You can install this package from [NuGet](https://www.nuget.org/packages/dbup-add-migration/)
    
    Install-Package dbup-add-migration
