#!/usr/bin/env -S pwsh -no
#requires -version 5

if (-not ($IsWindows -or $PSVersionTable.PSVersion.Major -eq 5)) {
    Write-Error "Please use Windows."
    exit 1
}

$config = @(
    "title",
    "pwsh",
    "pkgs",
    "uptime",
    "os"
)

# ===== VARIABLES =====
$e = [char]0x1B
$os = Get-CimInstance -ClassName Win32_OperatingSystem -Property Caption,OSArchitecture,LastBootUpTime

function truncate_line {
    param (
        [string]$text,
        [int]$maxLength
    )
    $length = ($text -replace $ansiRegex, "").Length
    if ($length -le $maxLength) {
        return $text
    }

    return $trucatedOutput
}

# ===== TITLE =====
function info_title {
    return @{
        title   = ""
        content = "xFetch - ${e}[1;33m{0}${e}[0m" -f [System.Environment]::UserName
    }
}

# ===== POWERSHELL VERSION =====
function info_pwsh {
    return @{
        title   = "   Shell"
        content = "PowerShell v$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
    }
}

# ===== PACKAGES =====
function info_pkgs {
    $packages = Get-Package -Force
    $numlines = $packages.Count
    return @{
        title   = "   PKGs"
        content = "$numlines, $($env:PROCESSOR_ARCHITECTURE)"
    }
}

# ===== UPTIME =====
function info_uptime {
    $uptime = [System.DateTime]::Now - $os.LastBootUpTime

    $days = $uptime.Days
    $hours = $uptime.Hours
    $minutes = $uptime.Minutes

    $uptimeString = "{0}d {1}h {2}m" -f $days, $hours, $minutes

    return @{
        title   = "   Uptime"
        content = $uptimeString
    }
}

# ===== OS =====
function info_os {
    return @{
        title   = "   Distro"
        content = "$($os.Caption.TrimStart('Microsoft '))"
    }
}

$GAP = 3
$writtenLines = 0
$freeSpace = $Host.UI.RawUI.WindowSize.Width - 1

# print info
foreach ($item in $config) {
        $info = & "info_$item"

    foreach ($line in $info) {
        $output = "$e[1;33m$($line["title"])$e[0m"

        if ($line["title"] -and $line["content"]) {
            $output += " ~ "
        }

        $output += "$($line["content"])"
        Write-Output $output
    }
}
