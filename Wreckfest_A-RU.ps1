﻿$script:WF_DIR = "C:\Spiele_Server\Wreckfest" # Path to Wreckfest-Dedicated-Server-INstallation
$script:STEAMCMD = "D:\steamcmd_gui\steamcmd" # Path to SteamCMD
$script:restart_time_hour = 8   # time of Restart ( have to rework that one.... got an issue on that one... )
########################################
####### JUST EDIT THE LINES ABOVE ######
########################################
########################################
########################################
########################################
############## SERIOUSLY ###############
########################################
## DON'T TRY TO CHANGE ANYTHING BELOW ##
########################################
function check_ddst ($1) {
        $ddst=Get-ChildItem -Path "$WF_DIR\config\$1\save\dedicated.ddst" -ErrorAction Ignore
        $conf=Get-ChildItem -Path "$WF_DIR\config\$1\server_config.cfg" -ErrorAction Ignore
        if ( "$ddst" -not "$null" -and $($ddst.LastWriteTimeUtc) -lt $($conf.LastWriteTimeUtc) ) {
            Remove-Item -Path "$WF_DIR\config\$1\save\dedicated.ddst" -ErrorAction Ignore
            }
        }
function start_wf () {
    if ( $(Get-Process -Name Wreckfest -ErrorAction Ignore).Count -ge 1) {
        Write-Warning "There are still some servers active. Trying to stop them"
        stop_wf
        }
    $config_dir = $(Get-ChildItem -Directory -Path $WF_DIR\config).Name
    $config_dir | ForEach-Object {
        if ( $(Get-ChildItem -Directory -Path $WF_DIR\config\$_\ -ErrorAction Ignore).Count -eq 0) {
            Write-Warning "No Save-Dir found, creating..."
            New-Item -Path $WF_DIR\config\$_\ -Name "save" -ItemType "directory"
            }
        else { 
            check_ddst $_
            }
        if ( $(Get-ChildItem -Path $WF_DIR\config\$($_)\ -Name server_config.cfg).Count -eq 0) {
            Write-Warning "No server_config.cfg in $WF_DIR\config\$($_)\ found. Skipping Start."
            Sleep -Seconds 1
            }
        else {
            sleep -Milliseconds 200
            $wf_conf = "$WF_DIR\config\$($_)\server_config.cfg"
            $Wf_save = "$WF_DIR\config\$($_)\save\"
            Start-Process -FilePath $WF_DIR\server\Wreckfest.exe -WorkingDirectory $WF_DIR -ArgumentList "-s server_config=$wf_conf","--save-dir=$wf_save"
            }
        }
    Write-Warning "$($(Get-Process -Name Wreckfest).Count) server started. Check for errors on your own."
    $script:last_start = (Get-Date).Date
    }
    
function stop_wf () {
    $wf_pid = $(Get-Process -Name Wreckfest -ErrorAction Ignore).Id
    if ( $($wf_pid.Count) -gt 1 ) {
        Write-Warning "Killing $($wf_pid.Count) server"
        $wf_pid | ForEach-Object {
            Stop-Process -Id $_ -ErrorAction Ignore
            }
        }
    sleep -Milliseconds 300
    if ( $(Get-Process -Name Wreckfest -ErrorAction Ignore).Count -ge 1) {
        Write-Warning "There are still some servers running. Please kill them manually"
        Pause
        Break
        }
    }
function update_wf () {
    stop_wf
    sleep -Seconds 3
    if ( $(Get-Process -Name Wreckfest -ErrorAction Ignore).Count -eq 0) {
        cd $STEAMCMD
        .\steamcmd.exe +login anonymous +force_install_dir $WF_DIR +app_update 361580 validate +quit
        }
    else { 
        Write-Warning "There are still some servers active, please kill them manually and restart the script."
        Pause
        Break
        }
    }
Function ConvertFrom-VDF {
    # Source: https://github.com/ChiefIntegrator/Steam-GetOnTop/blob/master/Modules/SteamTools/SteamTools.psm1
    param
    (
		[Parameter(Position=0, Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
        [System.String[]]$InputObject
	)
    process
    {
        $root = New-Object -TypeName PSObject
        $chain = [ordered]@{}
        $depth = 0
        $parent = $root
        $element = $null
		
        ForEach ($line in $InputObject)
        {
            $quotedElements = (Select-String -Pattern '(?<=")([^\"\t\s]+\s?)+(?=")' -InputObject $line -AllMatches).Matches
    
            if ($quotedElements.Count -eq 1) # Create a new (sub) object
            {
                $element = New-Object -TypeName PSObject
                Add-Member -InputObject $parent -MemberType NoteProperty -Name $quotedElements[0].Value -Value $element
            }
            elseif ($quotedElements.Count -eq 2) # Create a new String hash
            {
                Add-Member -InputObject $element -MemberType NoteProperty -Name $quotedElements[0].Value -Value $quotedElements[1].Value
            }
            elseif ($line -match "{")
            {
                $chain.Add($depth, $element)
                $depth++
                $parent = $chain.($depth - 1) # AKA $element
                
            }
            elseif ($line -match "}")
            {
                $depth--
                $parent = $chain.($depth - 1)
				$element = $parent
                $chain.Remove($depth)
            }
            else # Comments etc
            {
            }
        }

        return $root
    }
    
}

function UpToDateCheck ($a){
    $params = @{
        Uri         = "https://api.steampowered.com/ISteamApps/UpToDateCheck/v1/"
        Body     = @{ 'appid' = "361580";"version" = "$a"}
        Method      = 'GET'
        }
    $script:check = $(Invoke-WebRequest @params).Content | ConvertFrom-Json
}

function check_version () {
    $version = ConvertFrom-VDF (Get-Content $WF_DIR\steamapps\appmanifest_361580.acf)
    UpToDateCheck $version.AppState.buildid
    if ($check.response.up_to_date -eq $true) {
        Write-Host "$(Get-Date) >> Server is Up2Date"
        }
    else {
        Write-Warning "$(Get-Date) >> Server is outdated. Starting Update!"
        Sleep -Seconds 10
        update_wf
        Write-Host "Check Update (because we don't trust steam)"
        $version = ConvertFrom-VDF (Get-Content $WF_DIR\steamapps\appmanifest_361580.acf)
        UpToDateCheck $version.AppState.buildid
        if ($check.response.up_to_date -eq $true) {
            Write-Host "Update successfull. Starting server!!"
            start_wf
            }
        else {
            Write-Warning "Something went wrong. Please update manually and restart the script"
            Sleep -Seconds 15
            Break
            }
        }
    $script:last_check = Get-Date
    }
function restart_wf () {
    stop_wf
    sleep -Milliseconds 200
    start_wf
    }

"                     _                     _      "
" \    / ._ _   _ | _|_ _   _ _|_    /\ __ |_) | | "
"  \/\/  | (/_ (_ |< | (/_ _>  |_   /--\   | \ |_| "
"                                                  "
   "Wreckfest Auto-Run&Update"
   "Because, you don't care anymore"
   "";"";""
Sleep -Seconds 3
if ( $(Get-ChildItem -Directory -Path $WF_DIR\config -ErrorAction Ignore).Count -eq 0) {
    Write-Warning "No Config-Directories found." 
    Write-Warning "Please create a config-folder and for every server a subfolder, which contains the server_config.cfg"
    Write-Warning "example: $WF_DIR\config\server1\server_config.cfg"
    Pause
    Break
    }
$version = ConvertFrom-VDF (Get-Content $WF_DIR\steamapps\appmanifest_361580.acf)
if ( $version.AppState.appid -ne 361580 ) {
    Write-Warning "Server is not installed as dedicated Server. Please reinstall with AppID 361580"
    Pause
    Break
    }
check_version
Write-Host "Startup-checks complete. Proceeding to the lazy part"
if ( $check.response.up_to_date -eq $false) {
    check_version
    }
else {
    start_wf
    }
while (1) {
    $script:current_time = Get-Date
    $script:restart_time = Get-Date -Hour $restart_time_hour -Minute 0
    $script:start_time = $last_start.AddDays(1)
    if ( $current_time -ge $restart_time -and $current_time -gt $start_time.Date ) {
        Write-Warning "$(Get-Date) >> Daily Restart!!!"
        ""
        restart_wf
        ""
        }
    if ( $current_time -ge $last_check.AddMinutes(15) ) {
        ""
        check_version
        ""
        }
    Write-Host -NoNewline "."
    sleep -Seconds 10

    }