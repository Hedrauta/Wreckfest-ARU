﻿$Script:WF_DIR = "D:\testing\server" #Points to Wreckfest-Dedicated-Server-Directory
$Script:STEAMCMD = "D:\testing\steamcmd\SteamCMD\steamcmd.exe" #Points to SteamCMD.exe
$script:restart_time = Get-Date -Hour 8 -Minute 0 -Second 0

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
$script:debug = $false # does write log-files into a subfolder, only for debugging-purposes

$host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: launching"
# All kind of Function to use in the Loop
function check_ddst ($1) {
    $ddst=Get-ChildItem -Path "$WF_DIR\config\$1\save\dedicated.ddst" -ErrorAction Ignore
    $conf=Get-ChildItem -Path "$WF_DIR\config\$1\server_config.cfg" -ErrorAction Ignore
    if ( "$ddst" -ne "$null" -and $($ddst.LastWriteTimeUtc) -lt $($conf.LastWriteTimeUtc) ) {
        Remove-Item -Path "$WF_DIR\config\$1\save\dedicated.ddst" -ErrorAction Ignore
        }
    }
function start_wf () {
    if ( $(Get-Process -Name Wreckfest_x64 -ErrorAction Ignore).Count -ge 1) {
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
            Start-Process -FilePath $WF_DIR\Wreckfest_x64.exe -WorkingDirectory $WF_DIR -WindowStyle Minimized -ArgumentList "-s server_config=$wf_conf","--save-dir=$wf_save"
            }
        }
    Write-Warning "$($(Get-Process -Name Wreckfest_x64).Count) server started. Check for errors on your own."
    $script:last_start = (Get-Date).Date
    }
function stop_wf () {
    $wf_pid = $(Get-Process -Name Wreckfest_x64 -ErrorAction Ignore).Id
    if ( $($wf_pid.Count) -gt 1 ) {
        Write-Warning "Killing $($wf_pid.Count) server"
        $wf_pid | ForEach-Object {
            Stop-Process -Id $_ -ErrorAction Ignore
            }
        }
    sleep -Milliseconds 300
    if ( $(Get-Process -Name Wreckfest_x64 -ErrorAction Ignore).Count -ge 1) {
        Write-Warning "There are still some servers running. Please kill them manually"
        Pause
        Break
        }
    }
Function ConvertFrom-VDF {
    # Source: https://github.com/ChiefIntegrator/Steam-GetOnTop/blob/master/Modules/SteamTools/SteamTools.psm1
    # To Use for the VDF-File as well as getting Infos about an update
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
function update_wf {
    stop_wf
    sleep -Seconds 3
    if ( $(Get-Process -Name Wreckfest_x64 -ErrorAction Ignore).Count -eq 0) {
        .$STEAMCMD +login anonymous +force_install_dir $WF_DIR +app_update 361580 validate +quit
        }
    else { 
        Write-Warning "There are still some servers active, please kill them manually and restart the script."
        Pause
        Break
        }
    }
function LatestAppInfo {
    $script:fetch_app_info = .$STEAMCMD +force_install_dir $WF_DIR +app_info_print 361580 +quit
    $script:cut_app_info = $fetch_app_info[5..($fetch_app_info.Length-4)]
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
    if ((GetLatestBuildID) -eq $null) {
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
            if (((GetLatestBuildID) -ne $null) -and ((GetInstalledBuildID) -eq (GetLatestBuildID))) {
                Write-Host "Update successfull. Starting server!!"
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
function restart_wf () {
    stop_wf
    sleep -Milliseconds 200
    start_wf
    }
if ($debug -eq $true) {
    $script:scrstart = (Get-Date -UFormat %s -Millisecond 0)
    Start-Transcript -Path ".\WF_ARU\$($script:scrstart)_log.txt"
    }

# Script-Start: 
$host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: starting"
"                     _                     _        "
" \    / ._ _   _ | _|_ _   _ _|_    /\ __ |_)__ | | "
"  \/\/  | (/_ (_ |< | (/_ _>  |_   /--\   | \   |_| "
"                                                  "
   "Wreckfest Auto-Run&Update"
   "Because, you don't care anymore"

   "";"";""
   Write-Host "Thanks to github.com/ChiefIntegrator, for his wonderfull ConvertFrom-VDF"
   Sleep -Seconds 3
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
                if ($rh_l -eq 'y'){
                    Pause
                    stop_wf #Just in Case
                    Get-ChildItem -Path $WF_DIR -Exclude "config*" | foreach ($_) {
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
LatestAppInfo
Write-Host "Startup-checks complete. Proceeding to the lazy part"
$host.UI.RawUI.WindowTitle = "Wreckfest Auto-Run&Update: running"
if (((GetLatestBuildID) -ne $null) -and ((GetInstalledBuildID) -eq (GetLatestBuildID))) {
    $script:last_check = Get-Date
    start_wf
    }
else {
    check_version
    }
while (1) {
    $script:start_time = $last_start.AddDays(1)
    if (((Get-Date) -ge $restart_time) -and ((Get-Date) -gt $start_time.Date)) {
        Write-Warning "$(Get-Date) >> Daily Restart!!!"
        ""
        restart_wf
        ""
        }
    if ( (Get-Date) -ge $last_check.AddMinutes(15) ) {
        ""
        check_version
        ""
        }
    Write-Host -NoNewline "."
    sleep -Seconds 10
    }











## Test-Corner
    cls
    # empty file: -ErrorAction Ignore -eq null
    "Fetchin App Info"
    $test = .$Script:STEAMCMD +force_install_dir $Server +app_info_print 361580 +quit
    "Cut App Info"
    $cut1 = $test[5..($test.Length-4)]
    $convert = ConvertFrom-VDF($cut1)
    #BuildID> $($convert.361580).depots.branches.public.buildid
    #LastChangeDate> (Get-Date 01.01.1970).AddSeconds($($convert.361580).depots.branches.public.timeupdated)