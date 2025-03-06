Function Initialize-RunnerEnvironment {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Name of the script, including extension.  Example: MyScript.ps1")]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('\.ps1$')]
        [string]$ScriptName,
        
        [Parameter(Mandatory = $false, Position = 1, HelpMessage = "Path to the functions folder")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$FunctionsPath,

        [Parameter(Mandatory = $false, Position = 2, HelpMessage = "Do you wish to run the script?")]
        [switch]$RunScript
    )
    BEGIN {
        try {
            # Create global variables based on script parameters above
            # Script name is required for logging and file name transformations
            $Global:ScriptName = $ScriptName
            # All ps1 files in the functions folder are dot loaded
            $Global:FunctionsPath = $FunctionsPath
            $ErrorCount = 0
            #region Workspace
            # The Workspace folder is the root of the git repository, set as an environment variable sent from the github actions workflow

            ## Uncomment below for VERY verbose logging
            #$PSDefaultParameterValues['Write-Verbose:Verbose'] = $true
            
            ## Uncomment below for debug logging
            #$PSDefaultParameterValues['Write-Debug:Debug'] = $true
            

            #Debug preference continue so it doesn't stop to ask for input
            $DebugPreference = 'Continue'
            
            #Error preference stop so that the script will stop on errors, needed for try/catch/throw logic
            $ErrorActionPreference = 'Stop'

            #region FolderStructure
            # The template has some very specific folder structure requirements, but the initializer will use fake data for testing if the environment variables are not set.
            
            ## Lines below set the script name and job name
            Write-Host "Initializing Script Environment"
            
            # This simply gets the environment variables and outputs them to the console
            Get-ChildItem Env:\ | Out-String
            
            ## Job name is the script name plus the date, used for logging and artifact naming
            $Global:JobName = "$($ScriptName)_$(Get-Date -Format yyyy-M-d)"

            ## Below creates global variables for github environment. Most of these are set by the github actions workflow, except the artifacts folder which is a concat.
            If ($Env:GITHUB_WORKSPACE) {
                # Workspace is the root of the git repository
                $Global:Workspace = $Env:GITHUB_WORKSPACE
                # Runner name is the name of the runner server
                $Global:RunnerName = $ENV:RUNNER_NAME
                # Run number is the number of the workflow run, used for logging and troubleshooting
                $Global:RunNumber = $ENV:GITHUB_RUN_NUMBER
                # Ref name is the branch or tag name that the workflow is running on
                $Global:RefName = $ENV:GITHUB_REF_NAME
                # Artifacts folder is the workspace folder plus the artifacts folder, for logs and output files
                $Global:Artifacts = "$Workspace\artifacts"
                # Server URL is the github URL, used for troubleshooting the workflow run
                $Global:ServerURL = $env:GITHUB_SERVER_URL
                # Repository is the name of the repository, used for troubleshooting the workflow run
                $Global:Repository = $env:GITHUB_REPOSITORY
                # Run ID is the unique ID of the workflow run, used for troubleshooting the workflow run
                $Global:RunID = $env:GITHUB_RUN_ID
            }
            ## If not running in github, set variables for local testing, these are fake values and can be changed to any value for testing.
            Else {
                # Workspace here is set to the profile folder path for the user, but can be set to any folder for testing
                $Global:Workspace = $(Get-Location)
                # Runner name is the testing computer name
                $Global:RunnerName = "$env:COMPUTERNAME"
                # Run number is the date of the run, this would otherwise be a simple integer sent from gha
                $Global:RunNumber = "$(Get-Date -Format yyyy.M.d)"
                # For testing, the ref name is set to local, but would otherwise be the branch or tag name from gha
                $Global:RefName = "Local"
                # Artifacts folder is set to the artifacts folder in the profile folder, but can be set to any folder for testing
                $Global:Artifacts = "$($Workspace)\artifacts"
                # Server URL is set to localhost, but would otherwise be the github server URL
                $Global:ServerURL = "https://localhost"
                # Repository is set to local, but would otherwise be the repository name from gha
                $Global:Repository = "Local"
                # Run ID is set to local, but would otherwise be the run ID from gha
                $Global:RunID = "Local"
            }
            
            ## Github folder structure for this template should have the script in a src folder
            # If the src folder exists, set the location to the src folder
            If (Test-Path -Path "$Workspace\src" -ErrorAction SilentlyContinue) {
                Set-Location -Path "$Workspace\src"
            }
            # Otherwise set it to the root of the workspace
            Else {
                Set-Location -Path "$Workspace"
            }
            #endregion FolderStructure

            #region Logging
            # The logging section sets up logging for the script, including a CSV log file in the artifacts folder, and PSFramework logging to the console.
            Write-Host "Setting up Logging"
            ## Next section Saves a CSV logfile to the artifacts folder.
            If ($Workspace) {
                If (-NOT (Test-Path -Path $Artifacts)) {
                    $null = New-Item -Path $Artifacts -ItemType Directory -ErrorAction SilentlyContinue
                }
                ## Next section enables psframework logging provider "console".  This forces all logging to appear on screen in github actions display, unless specifically suppressed.
                ## Note log display on github actions at time of writing is limited to 1500 lines.

                # Start a transcript of the script run, this will show all output to the console in the transcript.log file in the artifacts folder.
                Start-Transcript -Path "$Artifacts\transcript.log" -Append -ErrorAction SilentlyContinue
                
                # Set the PSFramework logging style to include the time, function name, line number, and message.
                $PSFStyle = "[%Time%] [%FunctionName%] [%Line%] %Message%"
                # Enable Console logging provider with the PSFramework style
                Set-PSFLoggingProvider -Name Console -Enabled $true -Style $PSFStyle
                
                ## Next section redirects standard powershell messages to PSFramework logging
                If (get-module psframework -ListAvailable) {
                    # Set-Alias lets us redirect the standard powershell message commands to the PSFramework logging provider.
                    Set-Alias Write-Verbose Write-PSFMessageProxy -Scope Global
                    Set-Alias Write-Warning Write-PSFMessageProxy -Scope Global
                    Set-Alias Write-Host Write-PSFMessageProxy -Scope Global
                    Set-Alias Write-Debug Write-PSFMessageProxy -Scope Global
                }
                # Create a log file name based on the runner name, ref name, and run number.
                $LogName = "{0}_{1}_{2}_{3}" -f $RunnerName, $RefName, 'RunNumber', $RunNumber
                $setPSFLoggingProviderSplat = @{
                    Name        = 'logfile'
                    filepath    = "$($Artifacts)\%logname%.csv"
                    logname     = $LogName
                    Enabled     = $true
                    ErrorAction = 'Stop'

                }
                # Enable the logfile logging provider with the logname and filepath
                Set-PSFLoggingProvider @setPSFLoggingProviderSplat
            }

            ## Next section displays script information to the console
            Write-Debug -Message "Started processing at [$([DateTime]::Now)]."
            Write-Debug -Message "Jobname is [$JobName]"
            Write-Debug -Message "Scriptname is [$ScriptName]"
            Write-Debug -Message "ScriptPath is [$Workspace]"
            Write-Debug -Message "InvocationName is [$($MyInvocation.MyCommand.Name)]"
            Write-Debug -Message "Log path is $($Artifacts)\$($LogName).csv"

            #endregion Logging

            #region Config
            Write-Host "Loading Config"
            ## Next section imports the script config file.  Config can only have static values.
            ## The config path is generated dynamically based on the script name.  Requires src folder structure.
            
            # Check if the src folder exists in the workspace, create a config path based on the script name
            If (Test-Path -Path $PSScriptRoot\src -ErrorAction SilentlyContinue) {
                $Global:ConfigPath = Join-Path -Path "$Workspace\src" -ChildPath $ScriptName.Replace('.ps1', '.Config.psd1')
            }
            # If the src folder does not exist, create a config path based on the script name
            Else {
                $Global:ConfigPath = Join-Path -Path "$Workspace" -ChildPath $ScriptName.Replace('.ps1', '.Config.psd1')
            }
            ## If the config file exists, import it.
            If (Test-Path -Path $ConfigPath -ErrorAction SilentlyContinue) {
                $Global:Config = Import-PowershellDataFile -Path $ConfigPath -ErrorAction Stop
                Write-Debug -Message "Config Loaded."
            }
            ## If the config file does not exist, throw an error.
            Else {
                Throw "Config file not found at $ConfigPath"
            }

            #endregion Config

            #region Credentials
            Write-Host "Creating Logon Secrets"
            ## Next section creates global credential variables depending on access to the github secrets.
            #   Write-Debug -Message "Creating logon secrets"

            # If AD Service Account secrets availble use them, else use config file credentials (remove secrets from config file after testing)
            If ($Env:AD_SERVICE_ACCOUNT_USERNAME -and $Env:AD_SERVICE_ACCOUNT_PASSWORD) {
                $Global:ADCredential = New-Object System.Management.Automation.PSCredential ($Env:AD_SERVICE_ACCOUNT_USERNAME, (ConvertTo-SecureString $Env:AD_SERVICE_ACCOUNT_PASSWORD -AsPlainText -Force))
            }
            ElseIf ($Config.ADUsername -and $Config.ADPassword) {
                $Global:ADCredential = New-Object System.Management.Automation.PSCredential ("$Config.ADUsername", (ConvertTo-SecureString "$Config.ADPassword" -AsPlainText -Force))
            }
            # If Office 365 secrets availble use them, else use config file credentials (remove secrets from config file after testing)
            If ($Env:OFFICE365_CREDS_USR -and $Env:OFFICE365_CREDS_PSW) {
                $Global:Credential = New-Object System.Management.Automation.PSCredential ($Env:OFFICE365_CREDS_USR, (ConvertTo-SecureString $Env:OFFICE365_CREDS_PSW -AsPlainText -Force))
            }
            ElseIf ($Config.OfficeUsername -and $Config.OfficePassword) {
                $Global:Credential = New-Object System.Management.Automation.PSCredential ("$Config.OfficeUsername", (ConvertTo-SecureString "$Config.OfficePassword" -AsPlainText -Force))
            }
            Write-Debug -Message "Logon secrets created"
            #endregion Credentials

            #region Functions
            Write-Host "Loading Functions"
            # Check if functions path exists in global scope
            If (-not [string]::IsNullOrWhiteSpace($FunctionsPath)) {
                # Check if the functions path exists and has PS1 files
                If (Test-Path -Path $FunctionsPath -Filter *.ps* -ErrorAction SilentlyContinue) {
                    $FunctionFiles = Get-ChildItem -Path $FunctionsPath -Filter *.ps* -Recurse -ErrorAction 'Stop' | Where-Object { $_.name -NotLike '*.Tests.ps1' }
                    # Check all imported functions in the function: powershell drive
                    $ImportedFunctions = Get-Item -Path function:
                    # If there are functions not imported, import them
                    ForEach ($Function in $FunctionFiles) {
                        if ($ImportedFunctions -notcontains $Function.BaseName) {
                            Import-Module $Function.FullName
                            $PSFMessage = "Loaded function:  {0}." -f $Function.FullName
                            Write-Debug -Message $PSFMessage
                        }
                    }
                    Write-Debug -Message "Functions Loaded."
                }
                # If the functions path does not exist, throw an error
                Else {
                    Write-PSFMessage -Level Warning "No functions found at $FunctionsPath"
                }
            }
            # If the functions path is empty or not initialized, skip loading functions and log a warning
            Else {
                Write-Warning -Message "No functions path provided, skipping function loading."
            }
            
            #endregion Functions
        
            #endregion Workspace
        }
        catch {
            #### Log failure
            Write-Warning -Message "ERROR:`t$($PSItem.Exception.Message)"
            $ErrorCount ++
        }
    }
    PROCESS {
        try {
            #region Dependencies
            Write-Host "Checking Dependencies"
            # Check if the user is an administrator
            If ([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544') {
                Write-Debug -Message "User is an administrator, checking dependencies."
                If (Test-Path -Path "$Env:ProgramData\InitDate_$($ScriptName).xml" -ErrorAction SilentlyContinue) {
                    #Get the date of the last module updates, used to check if the dependencies are up to date.
                    $InitDate = Import-CliXML -Path "$Env:ProgramData\InitDate_$($ScriptName).xml"
                    #Get the current date to compare to the last update date
                    $Now = Get-Date
                    #Check if the last update was more than 30 days ago
                    If ($Now - $InitDate -gt (New-TimeSpan -Days 30)) {
                        #region LongPathSupport
                        ## Next section looks for long path/filename support on runner and enables it if needed. (requires that network authority or system is granted local administrator access to the runner)
                        # Write-Debug -Message "Checking Long Path support for Windows"
                        # Regkey location values
                        $Reg = @{
                            Path  = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
                            Name  = "LongPathsEnabled"
                            Value = "1"
                            #ErrorAction = "SilentlyContinue"
                        }
                        # Checking if the registry key exists
                        $Key = Get-ItemProperty -Path $Reg.Path -Name $Reg.Name -ErrorAction SilentlyContinue
                
                        # If the key does not exist, create it
                        if ($null -eq $Key) {
                            Write-Debug -Message "Creating Registry Key"
                            New-ItemProperty @Reg -Type String
                        }
                        # If the key exists but is not set to 1, set it to 1
                        if (($null -ne $Key) -and ($Key.LongPathsEnabled -ne "1")) {
                            #   Write-Debug -Message "Updating Registry Value"
                            Set-ItemProperty @Reg
                        }
                        #endregion LongPathSupport

                        #region TLS12
                        ## Next section checks for TLS 1.2 support and enables it if needed.
                        #   Write-Debug -Message "Forcing TLS 1.2"
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        #endregion TLS12

                        #region Nuget
                        ## Next section checks for Nuget/PowershellGet is installed, using -bootstrap will re-install if needed.
                        Get-PackageProvider -Name Nuget -ForceBootstrap -ErrorAction Ignore | Out-Null
                        #   Write-Debug -Message "NuGet version is $([string]$Nuget.Version)"
                        #endregion Nuget

                        #region PSGallery
                        ## Next section checks for the PSGallery and custom repositories are setup correctly.
                        #   Write-Debug -Message "Powershell Galleries Check"
                        $PSGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
                        If ($null -eq $PSGallery) {
                            Write-Debug -Message "WARN:`tPSGallery Missing, registering Powershell Gallery"
                            Register-PSRepository -Name PSGallery -SourceLocation "https://www.powershellgallery.com/api/v2/" -InstallationPolicy Trusted -ErrorAction Ignore
                        }
                        ## PSGallery is typically already set on Windows powershell, below checks that it is set to trusted.
                        ElseIf ($PSGallery.InstallationPolicy -ne "Trusted") {
                            Write-Debug -Message "WARN:`tPSGallery configuration incomplete, updating Powershell Gallery"
                            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Ignore
                        }
                        
                        #TODO How to handle internal repositories without hardcoding?

                        #Export the date of this run so that the dependencies are not checked again for 30 days.
                        Write-Debug -Message "Exporting the date of this run"
                        $Now | Export-Clixml -Path "$Env:ProgramData\InitDate_$($ScriptName).xml"
                    }
                }
                Else {
                    #If the initfile does not exist, create a new one set 31 days in the past, this will force the dependencies to be updated on the next run.
                    (get-date).adddays(-31) | Export-CliXML -Path "$Env:ProgramData\InitDate_$($ScriptName).xml"
                }
            }
            Else {
                Write-Debug -Message "User is not an administrator, skipping dependencies."
            }

            #endregion Dependencies
        }
        catch {
            #### Log failure
            Write-Warning -Message "ERROR:`t$($PSItem.Exception.Message)"
            $ErrorCount ++
        }
    }
    END {
        If ($RunScript -eq $True) {
            #region Run
            ## Next section verifies script is available in src folder
            #   Write-Debug -Message "Getting the Script Path"
            $BuildFolder = "{0}" -f "$($Workspace)\\src"
            $ScriptNamePath = Join-Path $BuildFolder $ScriptName
            #   Write-Debug -Message "Testing the path"
            if ((Test-Path -Path $ScriptNamePath) -eq $False) {
                
                $BuildFolder = "{0}" -f "$($Workspace)"
                $ScriptNamePath = Join-Path $BuildFolder $ScriptName
                if ((Test-Path -Path $ScriptNamePath) -eq $False) {
                    Throw "Script not found in $BuildFolder."
                }
            }

            #region DynamicParameters
            Write-Host "Setting Dynamic Parameters"
            ## These parameters are set by environment variables in the github actions workflow
            ## This section is used for workflows that take interactive input from the user.
            ## If the environment variables are blank or null, the parameters are not set.
            ## The parameters are then added to the splat for the script being run.

            ##### Use the splat below to customize run parameters #####
            Write-PSFHostColor -String "Use Environment variables to change parameters of the run script" -DefaultColor Green
            Write-PSFHostColor -String "Var1-7 and Value1-7 environment variables are passed to the script as parameters" -DefaultColor Green
            
            ## Use Environment variables to change parameters of the run script ##
            ## Var1-7 and Value1-7 environment variables are passed to the script as parameters ##
            
            $Global:ScriptNameSplat = @{}
            #Get the environment variables "parameters" that match the pattern "var[1-7]"
            $Parameters = get-childitem env: | Where-Object { $_.name -match "var[1-7]" }

            ForEach ($Parameter in $Parameters) {
                # Loop through the parameters
                Write-Host "Processing parameter $($Parameter.Name) - $($Parameter.Value)"
                # Find the corresponding value for the parameter by replacing "var" with "value"
                $ValueEnv = $Parameter.Name -replace "Var", "Value"
                Write-Host "Checking for value in $($ValueEnv)"
                # Check values in the environment variables
                If (($ValueEnv -match "value[1-7]") -and (Test-Path -Path "env:\$ValueEnv")) {
                    # Get the parameter name from the environment Var[i] variable "value" property (ie if Var1 value is "Path")
                    $Key = $Parameter.Value

                    # Get the parameter value from the envirronment Value[i] variable "value" property (ie Value1 value should be a path like "C:\Temp")
                    $Value = Get-ChildItem "env:\$ValueEnv"
                    Write-Host "Value Variable found $($Value.Name) - $($Value.Value)"

                    # If the parameter key/value pair is not null or empty, add it to the splat
                    If ( -not ( ([string]::IsNullOrWhiteSpace($Value.Value)) -and [string]::IsNullOrWhiteSpace($Key) )) {
                        Write-Host -Message "Adding parameter $Key with argument $($Value.Value) to the splat"
                        If ($Value.Value -match "(true|false)") {
                            Write-Host "Parameter $Key is a boolean $($value.value)"
                            $Global:ScriptNameSplat.Add($Key, $([bool]$Value.Value))
                        }
                        Else {
                        $Global:ScriptNameSplat.Add($Key, $($Value.Value))
                        }
                    }
                    Else {
                        Write-Host -Message "Parameter key or value [$Key / $($Value.Value)] is null or empty, skipping."
                    }
                }
            }
            #endregion DynamicParameters

            # Display the splat
            Write-Host -Message "Finalized Splat is $($ScriptNameSplat | Out-String)"
            # Run the script
            Write-Debug -Message "Running the script $ScriptNamePath"
            & $ScriptNamePath @ScriptNameSplat
            #endregion Run
        }
        
        # Collect errors and send notifications
        If ($ErrorCount -gt 0) {
            $ThrowMessage = "A total of [{0}] errors were logged.  Please view logs for details." -f $ErrorCount
            Throw $ThrowMessage
        }
    }
}
