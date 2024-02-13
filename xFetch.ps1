#!/usr/bin/env -S pwsh -nop
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
$ansiRegex = '([\u001B\u009B][[\]()#;?]*(?:(?:(?:[a-zA-Z\d]*(?:;[-a-zA-Z\d\/#&.:=?%@~_]*)*)?\u0007)|(?:(?:\d{1,4}(?:;\d{0,4})*)?[\dA-PR-TZcf-ntqry=><~])))'
$cimSession = New-CimSession
$os = Get-CimInstance -ClassName Win32_OperatingSystem -Property Caption,OSArchitecture,LastBootUpTime,TotalVisibleMemorySize,FreePhysicalMemory -CimSession $cimSession
$t = if ($blink) { "5" } else { "1" }
$COLUMNS = $imgwidth

# ===== UTILITY FUNCTIONS =====
function get_percent_bar {
    param ([Parameter(Mandatory)][int]$percent)

    if ($percent -gt 100) { $percent = 100 }
    elseif ($percent -lt 0) { $percent = 0 }

    $x = [char]9632
    $bar = $null

    $bar += "$e[97m[ $e[0m"
    for ($i = 1; $i -le ($barValue = ([math]::round($percent / 10))); $i++) {
        if ($i -le 6) { $bar += "$e[32m$x$e[0m" }
        elseif ($i -le 8) { $bar += "$e[93m$x$e[0m" }
        else { $bar += "$e[91m$x$e[0m" }
    }
    for ($i = 1; $i -le (10 - $barValue); $i++) { $bar += "$e[97m-$e[0m" }
    $bar += "$e[97m ]$e[0m"

    return $bar
}

function get_level_info {
    param (
        [string]$barprefix,
        [string]$style,
        [int]$percentage,
        [string]$text,
        [switch]$altstyle
    )

    switch ($style) {
        'bar' { return "$barprefix$(get_percent_bar $percentage)" }
        'textbar' { return "$text $(get_percent_bar $percentage)" }
        'bartext' { return "$barprefix$(get_percent_bar $percentage) $text" }
        default { if ($altstyle) { return "$percentage% ($text)" } else { return "$text ($percentage%)" }}
    }
}

function truncate_line {
    param (
        [string]$text,
        [int]$maxLength
    )
    $length = ($text -replace $ansiRegex, "").Length
    if ($length -le $maxLength) {
        return $text
    }
    $truncateAmt = $length - $maxLength
    $trucatedOutput = ""
    $parts = $text -split $ansiRegex

    for ($i = $parts.Length - 1; $i -ge 0; $i--) {
        $part = $parts[$i]
        if (-not $part.StartsWith([char]27) -and $truncateAmt -gt 0) {
            $num = if ($truncateAmt -gt $part.Length) {
                $part.Length
            } else {
                $truncateAmt
            }
            $truncateAmt -= $num
            $part = $part.Substring(0, $part.Length - $num)
        }
        $trucatedOutput = "$part$trucatedOutput"
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
    $pkgs = @()

    if ("winget" -in $ShowPkgs -and (Get-Command -Name winget -ErrorAction Ignore)) {
        $wingetpkg = (winget list | Where-Object {$_.Trim("`n`r`t`b-\|/ ").Length -ne 0} | Measure-Object).Count - 1

        if ($wingetpkg) {
            $pkgs += "$wingetpkg (system)"
        }
    }

    if ("choco" -in $ShowPkgs -and (Get-Command -Name choco -ErrorAction Ignore)) {
        $chocopkg = Invoke-Expression $(
            "(& choco list" + $(if([version](& choco --version).Split('-')[0]`
            -lt [version]'2.0.0'){" --local-only"}) + ")[-1].Split(' ')[0] - 1")

        if ($chocopkg) {
            $pkgs += "$chocopkg (choco)"
        }
    }

    if ("scoop" -in $ShowPkgs) {
        $scoopdir = if ($Env:SCOOP) { "$Env:SCOOP\apps" } else { "$Env:UserProfile\scoop\apps" }

        if (Test-Path $scoopdir) {
            $scooppkg = (Get-ChildItem -Path $scoopdir -Directory).Count - 1
        }

        if ($scooppkg) {
            $pkgs += "$scooppkg (scoop)"
        }
    }

    foreach ($pkgitem in $CustomPkgs) {
        if (Test-Path Function:"info_pkg_$pkgitem") {
            $count = & "info_pkg_$pkgitem"
            $pkgs += "$count ($pkgitem)"
        }
    }

    if (-not $pkgs) {
        return @{
            title   = "   Arch"
            content = "$($os.OSArchitecture)"
        }
    }

    return @{
        title   = "   PKGs"
        content = $pkgs -join ', '
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
    if (Test-Path Function:"info_$item") {
        $info = & "info_$item"
    } else {
        $info = @{ title = "$e[31mfunction 'info_$item' not found" }
    }

    if (-not $info) {
        continue
    }

    if ($info -isnot [array]) {
        $info = @($info)
    }

    foreach ($line in $info) {
        $output = "$e[1;33m$($line["title"])$e[0m"

        if ($line["title"] -and $line["content"]) {
            $output += " ~ "
        }

        $output += "$($line["content"])"

        $writtenLines++

        if ($stripansi) {
            $output = $output -replace $ansiRegex, ""
            if ($output.Length -gt $freeSpace) {
                $output = $output.Substring(0, $output.Length - ($output.Length - $freeSpace))
            }
        } else {
            $output = truncate_line $output $freeSpace
        }

        Write-Output $output
    }
}