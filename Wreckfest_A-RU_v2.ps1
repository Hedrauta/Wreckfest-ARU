$WF_DIR = "C:\Spiele_Server\Wreckfest" #Points to Wreckfest-Dedicated-Server-Directory
$STEAMCMD = "D:\steamcmd_gui\steamcmd\steamcmd.exe" #Points to SteamCMD.exe
$restart_time = Get-Date -Hour 8 -Minute 0 -Second 0 # Daily Restart time

########################################
####### JUST EDIT THE LINES ABOVE ######
########################################
########################################
############## SERIOUSLY ###############
########################################
## DON'T TRY TO CHANGE ANYTHING BELOW ##
########################################
####### YOU MAY BREAK THE SCRIPT #######
########################################
$debug = $false # does write log-files into a subfolder, only for debugging-purposes

$host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: launching"
# All kind of Function to use in the Loop
Function ConvertFrom-VDF {
    # Source: https://github.com/ChiefIntegrator/Steam-GetOnTop/blob/master/Modules/SteamTools/SteamTools.psm1
    # To Use for the VDF-File as well as getting Infos about an update
    param
    (
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]$InputObject
    )
    process {
        $root = New-Object -TypeName PSObject
        $chain = [ordered]@{}
        $depth = 0
        $parent = $root
        $element = $null
		
        ForEach ($line in $InputObject) {
            $quotedElements = (Select-String -Pattern '(?<=")([^\"\t\s]+\s?)+(?=")' -InputObject $line -AllMatches).Matches
    
            if ($quotedElements.Count -eq 1) { # Create a new (sub) object
                $element = New-Object -TypeName PSObject
                Add-Member -InputObject $parent -MemberType NoteProperty -Name $quotedElements[0].Value -Value $element
            }
            elseif ($quotedElements.Count -eq 2) { # Create a new String hash
                Add-Member -InputObject $element -MemberType NoteProperty -Name $quotedElements[0].Value -Value $quotedElements[1].Value
            }
            elseif ($line -match "{") {
                $chain.Add($depth, $element)
                $depth++
                $parent = $chain.($depth - 1) # AKA $element
                
            }
            elseif ($line -match "}") {
                $depth--
                $parent = $chain.($depth - 1)
                $element = $parent
                $chain.Remove($depth)
            }
            else { # Comments etc
            }
        }

        return $root
    }
    
}
function update_wf {
    stop_wf
    Start-Sleep -Seconds 3
    if ( $(Get-Process -Name Wreckfest_x64 -ErrorAction Ignore).Count -eq 0) {
        .$STEAMCMD +force_install_dir $WF_DIR +login anonymous +app_update 361580 validate +quit
    }
    else { 
        Write-Warning "There are still some servers active, please kill them manually and restart the script."
        Pause
        Break
    }
} 
function LatestAppInfo {
    #NEW: Grab Build-Infos directly from Steam
    $script:fetch_app_info = .$STEAMCMD +force_install_dir $WF_DIR +app_info_print 361580 +quit
    $script:cut_app_info = $fetch_app_info[5..($fetch_app_info.Length - 4)]
    $script:ConvertedAppInfo = ConvertFrom-VDF($cut_app_info)
}
function GetLatestBuildID {
    
    return $($ConvertedAppInfo.361580).depots.branches.public.buildid
}
function GetLatestBuildTime {
    return (Get-Date 01.01.1970).AddSeconds($($ConvertedAppInfo.361580).depots.branches.public.timeupdated)
}
function GetInstalledBuildID {
    return $(ConvertFrom-VDF (Get-Content $WF_DIR\steamapps\appmanifest_361580.acf)).AppState.buildid
}
function GetInstalledAppID {
    return $(ConvertFrom-VDF (Get-Content $WF_DIR\steamapps\appmanifest_361580.acf)).AppState.appid
}
function check_version {
    LatestAppInfo
    if ($null -eq (GetLatestBuildID)) {
        Write-Warning "Wasn't able to fetch the latest buildid. Function check_version stopped."
        Write-Warning "Is Steam offline?"
    }
    else {
        if ((GetInstalledBuildID) -eq (GetLatestBuildID) ) {
            Write-Host "$(Get-Date) >> Server is Up2Date"
        }
        else {
            Write-Warning "$(Get-Date) >> BuildID doesnt match. Better we will do an Update!"
            update_wf
            Write-Host "Check Update (because we don't trust anyone)"
            LatestAppInfo
            if (($null -ne (GetLatestBuildID)) -and ((GetInstalledBuildID) -eq (GetLatestBuildID))) {
                Write-Host "Update successfull. Starting server!!"
                Start-Sleep -Milliseconds 200
                start_wf
            }
            else {
                Write-Warning "Something went wrong during updating. Did Steam gone in maintenance?"
                Write-Warning "Please Check if Steam is online and restart the script"
                Pause
                Break
            }
        }
        $script:last_check = Get-Date
    }
}
function start_wf {
    #NEW: Support for single instance
    param(
        [System.String]$local:WorkingDIR
    )
    
    function start_process {
        # to prevent write it multiple times
        param(
            [System.String]$local:ConfigDIR
        )
        $local:Status = Get-Content $WF_DIR\config\$local:ConfigDIR\save\PID.json -Force -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $local:Status) {
            $running = $(Get-Process -Id $Status.PID -ErrorAction SilentlyContinue).HasExited
            "Found and loaded JSON for $($local:ConfigDIR)"
        }
        if (($local:running -eq $true) -or ($null -eq $local:running)) {
            Write-Warning "Server for $($local:ConfigDIR) not started. Starting..."
            $local:started = Start-Process -FilePath $WF_DIR\Wreckfest_x64.exe -WorkingDirectory $WF_DIR -WindowStyle Minimized -PassThru -ArgumentList "-s server_config=$WF_DIR\config\$local:ConfigDIR\server_config.cfg", "--save-dir=$WF_DIR\config\$local:ConfigDIR\save\"
            $local:LastConfigChange = $(Get-Item -Path $WF_DIR\config\$local:ConfigDIR\server_config.cfg).LastWriteTimeUtc
            Remove-Item $WF_DIR\config\$local:ConfigDIR\save\pid.json -Force -ErrorAction SilentlyContinue
            @{  PID              = [int]$($local:started.Id)
                LastConfigChange = [DateTime]$($local:LastConfigChange)
            } | ConvertTo-Json | Out-File $WF_DIR\config\$local:ConfigDIR\save\pid.json -Force
            $(Get-Item -Path "$WF_DIR\config\$local:ConfigDIR\save\pid.json").Attributes = "Hidden"
            Write-Warning "Started server for config-folder $($local:ConfigDIR)"
        }
        else { "Server for config at $($local:ConfigDIR) already running. Skipping..." }
    }
    if ($WorkingDIR -ne "") {
        # has an argument
        start_process($local:WorkingDIR)
    }
    else {
        # no argument > start all config_dirs
        $(Get-ChildItem -Path $WF_DIR\config\ -Directory).BaseName | ForEach-Object ($_) {
            start_process($_)
        }
    }
}
function stop_wf {
    #NEW: Support for single instance
    param(
        [System.String]$local:WorkingDIR
    )
    function stop_process {
        param(
            [System.String]$local:ConfigDIR
        )
        $local:Status = Get-Content $WF_DIR\config\$local:ConfigDIR\save\PID.json -Force -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $local:Status) {
            $local:running = Get-Process -Id $Status.PID -ErrorAction SilentlyContinue
            if ($local:running.HasExited -eq $false -and $local:running.Name -eq "Wreckfest_x64") {
                Stop-Process -Id $Status.PID
                "Instance for config $local:ConfigDIR stopped"
            }
            else {
                "Instance already stopped or a different process claimed the PID. Skipping..."
            }
        }
    }
    if ($local:WorkingDIR -ne "") {
        stop_process($local:WorkingDIR)
    }
    else { 
        $(Get-ChildItem -Path $WF_DIR\config -Directory).BaseName | ForEach-Object ($_) {
            stop_process($_)
        }
    }
}
function Config_check {
    #NEW: will restart specific instance, if config changes
    $(Get-ChildItem $WF_DIR\config -Directory).BaseName | ForEach-Object ($_) {
        $local:Status = Get-Content $WF_DIR\config\$_\save\PID.json -Force -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        $local:config_file = Get-Item $WF_DIR\config\$_\server_config.cfg
        if ($local:config_file.LastWriteTimeUtc.AddSeconds(-2) -gt $local:Status.LastConfigChange) {
            ""; "Config-Change for $_ detected. Restarting instance..."
            stop_wf($_)
            Remove-Item $WF_DIR\config\$_\save\dedicated.ddst -Force
            start_wf($_)
            ""
        }
    }
}

if ($debug -eq $true) {
    $script:scrstart = (Get-Date -UFormat %s -Millisecond 0)
    Start-Transcript -Path ".\WF_ARU\$($script:scrstart)_log.txt"
}


Start-Sleep -Milliseconds 300
# Script-Start:
$host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: starting"
"                     _                     _        "
" \    / ._ _   _ | _|_ _   _ _|_    /\ __ |_)__ | | "
"  \/\/  | (/_ (_ |< | (/_ _>  |_   /--\   | \   |_| "
""
"Wreckfest Auto-Run&Update"
"Because, you don't care anymore"

""; ""; ""
"Thanks to github.com/ChiefIntegrator, for his wonderfull ConvertFrom-VDF"
Start-Sleep -Seconds 3
$host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: checking dirs and game"
if (!(Test-Path -Path $SteamCMD -PathType Leaf)) {
    Write-Warning "Looks like you don't have SteamCMD. Did you set up the two lines on top of this script?"
    Pause; Break
}
if ( $(Get-ChildItem -Directory -Path $WF_DIR\config -ErrorAction Ignore).Count -eq 0) {
    Write-Warning "No Config-Directories found." 
    Write-Warning "Please create a config-folder and for every server a subfolder, which contains the server_config.cfg"
    Write-Warning "example: $WF_DIR \config\server1\server_config.cfg < "
    Pause
    Break
}
if ((GetInstalledAppID) -ne 361580 ) {
    Write-Warning "Downloaded Server is not installed as dedicated Server. Do you wish to install it correctly?"
    Write-Warning "This will remove every content in the Server-Directory, except the Configs."
    do {
        $rh_l = Read-Host -Prompt "Install 'Wreckfest Dedicated Server' (AppID 361580) correctly? [y/n]"
        if ($rh_l -eq 'y') {
            Pause
            stop_wf #Just in Case
            Get-ChildItem -Path $WF_DIR -Exclude "config*" | ForEach-Object ($_) {
                "CLEANING :" + $_.fullname
                Remove-Item $_.fullname -Force -Recurse
                "CLEANED... :" + $_.fullname
            }
            Pause
            "Remove Succesful. Installing correct Software. This may take some time."
            Start-Sleep -Seconds 2
            .$STEAMCMD +login anonymous +force_install_dir $WF_DIR +app_update 361580 validate +quit
        }
        elseif ( $rh_l -eq 'n') {
            Write-Warning "This Script doesnt work with anything else than AppID 361580. Killing Script"
            Pause
            Break(9)
        }
    } until ($rh_l -eq 'y' -or $rh_l -eq 'n')
}
Write-Host "Startup-checks complete. Proceeding to the lazy part"
$host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: running"
if (($null -ne (GetLatestBuildID)) -and ((GetInstalledBuildID) -eq (GetLatestBuildID))) {
    $script:last_check = Get-Date
    start_wf
}
else {
    check_version
}
if ($(Get-Date) -gt $restart_time) {
    $restart_time = $restart_time.AddDays(1)
    "______________________________________"
    "Skipping a possible restart"
    "Next Restart: $restart_time"
    "______________________________________"
    }

while (1) {
    $host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: Checking Changes"
    if (((Get-Date) -ge $restart_time)) {
        ""
        Write-Warning "$(Get-Date) >> Daily Restart!!!"
        ""
        stop_wf
        start_wf
        $restart_time = $restart_time.AddDays(1)
        "Next Restart: $restart_time"
    }
    if ( (Get-Date) -ge $last_check.AddMinutes(5) ) {
        ""
        check_version
        ""
    }
    Config_check
    Write-Host -NoNewline "."
    $script:timer = 10
    while ($script:timer -ne 0) {
        $host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: Idle for $timer seconds"
        Start-Sleep -Seconds 1
        $timer = $timer - 1
    }
}
