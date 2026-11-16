[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('Doctor', 'Prepare', 'StartLogs', 'StopLogs', 'Snapshot', 'Finish')]
    [string]$Action,

    [string]$Model = 'SM-S901B',
    [string]$Serial,
    [string]$Session,
    [switch]$SkipBuild,
    [switch]$ContinuousCutover,
    [switch]$Screenshot,
    [switch]$FinalSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PackageName = 'app.bibliolife.reader'
$script:ProjectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:ArtifactRoot = Join-Path $script:ProjectRoot 'build\physical_tests\readium'
$script:CurrentSessionPath = Join-Path $script:ArtifactRoot 'current-session.txt'
$script:ExpectedApkPath = Join-Path $script:ProjectRoot 'build\app\outputs\flutter-apk\app-profile.apk'
$script:AdbPath = $null
$script:FlutterPath = $null
$script:ResolvedSerial = $null

function Get-OptionalProperty {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed with exit code ${exitCode}: $FilePath $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
        Text = $output -join [Environment]::NewLine
    }
}

function Initialize-Tools {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -eq $adb) {
        throw 'adb was not found on PATH.'
    }
    $script:AdbPath = $adb.Source

    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -eq $flutter) {
        throw 'flutter was not found on PATH.'
    }
    $script:FlutterPath = $flutter.Source
}

function Get-ProfileBuildArguments {
    param([bool]$EnableContinuousCutover)

    $arguments = @(
        'build', 'apk', '--profile', '--target=lib/main.dart', '--no-pub'
    )
    if ($EnableContinuousCutover) {
        $arguments += '--android-project-arg=bibliolifeContinuousScrollCutover=true'
    }
    return [string[]]$arguments
}

function Assert-ProjectRoot {
    $required = @(
        (Join-Path $script:ProjectRoot 'pubspec.yaml'),
        (Join-Path $script:ProjectRoot 'lib\main.dart'),
        (Join-Path $script:ProjectRoot 'android\app\src\main\AndroidManifest.xml')
    )
    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Expected BiblioLife project file is missing: $path"
        }
    }

    $gradlePath = Join-Path $script:ProjectRoot 'android\app\build.gradle.kts'
    $manifestPath = Join-Path $script:ProjectRoot 'android\app\src\main\AndroidManifest.xml'
    $gradle = Get-Content -LiteralPath $gradlePath -Raw
    $manifest = Get-Content -LiteralPath $manifestPath -Raw
    if (($gradle -notmatch [regex]::Escape($script:PackageName)) -or
        ($manifest -notmatch 'android.intent.action.MAIN') -or
        ($manifest -notmatch 'android.intent.category.LAUNCHER')) {
        throw 'The expected application package or launcher declaration was not found.'
    }
}

function Normalize-Model {
    param([Parameter(Mandatory = $true)][string]$Value)
    return (($Value.Trim().ToUpperInvariant()) -replace '[-_]', '')
}

function Get-AdbDevices {
    $result = Invoke-NativeCapture -FilePath $script:AdbPath -Arguments @('devices', '-l')
    $devices = @()
    foreach ($line in $result.Output) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^List of devices attached') {
            continue
        }
        if ($line -notmatch '^\s*(\S+)\s+(\S+)(?:\s+(.*))?$') {
            continue
        }

        $deviceSerial = $Matches[1]
        $deviceState = $Matches[2]
        $deviceDetails = $Matches[3]
        $properties = @{}
        if (-not [string]::IsNullOrWhiteSpace($deviceDetails)) {
            foreach ($token in ($deviceDetails -split '\s+')) {
                if ($token -match '^([^:]+):(.*)$') {
                    $properties[$Matches[1]] = $Matches[2]
                }
            }
        }
        $deviceModel = $null
        if ($properties.ContainsKey('model')) {
            $deviceModel = [string]$properties['model']
        }
        $devices += [pscustomobject]@{
            Serial = $deviceSerial
            State = $deviceState
            Model = $deviceModel
            Description = $line.Trim()
        }
    }
    return @($devices)
}

function Resolve-Device {
    param(
        [string]$RequestedSerial,
        [Parameter(Mandatory = $true)][string]$RequestedModel
    )

    $devices = @(Get-AdbDevices)
    if (-not [string]::IsNullOrWhiteSpace($RequestedSerial)) {
        $matches = @($devices | Where-Object { $_.Serial -eq $RequestedSerial })
        if ($matches.Count -ne 1) {
            throw "Serial '$RequestedSerial' was not found exactly once in adb devices -l."
        }
        if ($matches[0].State -ne 'device') {
            throw "Serial '$RequestedSerial' is not authorized and ready (state: $($matches[0].State))."
        }
        $selected = $matches[0]
    }
    else {
        $normalizedModel = Normalize-Model -Value $RequestedModel
        $matches = @($devices | Where-Object {
            $_.State -eq 'device' -and
            -not [string]::IsNullOrWhiteSpace($_.Model) -and
            (Normalize-Model -Value $_.Model) -eq $normalizedModel
        })
        if ($matches.Count -eq 0) {
            $seen = if ($devices.Count -eq 0) { '<none>' } else { ($devices.Description -join '; ') }
            throw "No authorized '$RequestedModel' device was found. Connected entries: $seen"
        }
        if ($matches.Count -gt 1) {
            throw "Multiple authorized '$RequestedModel' devices were found. Pass -Serial explicitly."
        }
        $selected = $matches[0]
    }

    $script:ResolvedSerial = $selected.Serial
    return $selected
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    if ([string]::IsNullOrWhiteSpace($script:ResolvedSerial)) {
        throw 'A device must be resolved before issuing a device command.'
    }
    return Invoke-NativeCapture -FilePath $script:AdbPath -Arguments (@('-s', $script:ResolvedSerial) + $Arguments) -AllowFailure:$AllowFailure
}

function Assert-PackageInstalled {
    $packagePath = Invoke-Adb -Arguments @('shell', 'pm', 'path', $script:PackageName) -AllowFailure
    if (($packagePath.ExitCode -ne 0) -or ($packagePath.Text -notmatch '(?m)^package:')) {
        throw "The expected package '$($script:PackageName)' is not installed on '$($script:ResolvedSerial)'."
    }
    return $packagePath.Text.Trim()
}

function Resolve-LauncherActivity {
    $result = Invoke-Adb -Arguments @(
        'shell', 'cmd', 'package', 'resolve-activity', '--brief',
        '-a', 'android.intent.action.MAIN',
        '-c', 'android.intent.category.LAUNCHER',
        $script:PackageName
    )
    $activity = @($result.Output | Where-Object {
        $_ -match '^[A-Za-z0-9._]+/[A-Za-z0-9._$]+$'
    } | Select-Object -Last 1)
    if (($activity.Count -ne 1) -or (-not $activity[0].StartsWith("$($script:PackageName)/"))) {
        throw "Could not resolve the launcher activity for '$($script:PackageName)'."
    }
    return [string]$activity[0]
}

function Get-DevicePid {
    $result = Invoke-Adb -Arguments @('shell', 'pidof', '-s', $script:PackageName) -AllowFailure
    if (($result.ExitCode -ne 0) -or [string]::IsNullOrWhiteSpace($result.Text)) {
        return $null
    }
    $pidText = $result.Text.Trim()
    if ($pidText -notmatch '^\d+$') {
        throw "Unexpected PID output for '$($script:PackageName)': $pidText"
    }
    return $pidText
}

function New-SessionDirectory {
    if (-not (Test-Path -LiteralPath $script:ArtifactRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $script:ArtifactRoot -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $sessionPath = Join-Path $script:ArtifactRoot $stamp
    if (Test-Path -LiteralPath $sessionPath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $sessionPath = Join-Path $script:ArtifactRoot $stamp
    }
    New-Item -ItemType Directory -Path $sessionPath | Out-Null
    Set-Content -LiteralPath $script:CurrentSessionPath -Value $sessionPath -Encoding UTF8
    return $sessionPath
}

function Resolve-SessionDirectory {
    param([string]$RequestedSession)

    if ([string]::IsNullOrWhiteSpace($RequestedSession)) {
        if (-not (Test-Path -LiteralPath $script:CurrentSessionPath -PathType Leaf)) {
            throw 'No active physical session was found. Run Prepare first or pass -Session.'
        }
        $candidate = (Get-Content -LiteralPath $script:CurrentSessionPath -Raw).Trim()
    }
    elseif ([System.IO.Path]::IsPathRooted($RequestedSession)) {
        $candidate = $RequestedSession
    }
    else {
        $candidate = Join-Path $script:ArtifactRoot $RequestedSession
    }

    $resolvedRoot = [System.IO.Path]::GetFullPath($script:ArtifactRoot).TrimEnd('\')
    $resolvedCandidate = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\')
    if (-not $resolvedCandidate.StartsWith("$resolvedRoot\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Session must be inside '$resolvedRoot'."
    }
    if (-not (Test-Path -LiteralPath $resolvedCandidate -PathType Container)) {
        throw "Session directory does not exist: $resolvedCandidate"
    }
    return $resolvedCandidate
}

function Read-SessionState {
    param([Parameter(Mandatory = $true)][string]$SessionPath)
    $statePath = Join-Path $SessionPath 'state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Session state is missing: $statePath"
    }
    return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}

function Save-SessionState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$SessionPath
    )
    Write-JsonFile -Value $State -Path (Join-Path $SessionPath 'state.json')
}

function Resolve-SessionDevice {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$RequestedSerial,
        [Parameter(Mandatory = $true)][string]$RequestedModel
    )
    $stateSerial = [string](Get-OptionalProperty -InputObject $State -Name 'serial')
    if ([string]::IsNullOrWhiteSpace($stateSerial)) {
        throw 'The session does not contain a resolved serial.'
    }
    if ((-not [string]::IsNullOrWhiteSpace($RequestedSerial)) -and ($RequestedSerial -ne $stateSerial)) {
        throw "The requested serial does not match the session serial '$stateSerial'."
    }
    return Resolve-Device -RequestedSerial $stateSerial -RequestedModel $RequestedModel
}

function Get-PackageMetadata {
    $dump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $script:PackageName)
    $values = [ordered]@{}
    foreach ($field in @('versionName', 'versionCode', 'firstInstallTime', 'lastUpdateTime')) {
        $match = [regex]::Match($dump.Text, "(?m)^\s*$field=([^\r\n]+)")
        if ($match.Success) {
            $values[$field] = $match.Groups[1].Value.Trim()
        }
    }
    return [pscustomobject]$values
}

function Get-DeviceMetadata {
    param([Parameter(Mandatory = $true)]$ResolvedDevice)
    return [pscustomobject][ordered]@{
        serial = $ResolvedDevice.Serial
        adbModel = $ResolvedDevice.Model
        productModel = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.model')).Text.Trim()
        manufacturer = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.product.manufacturer')).Text.Trim()
        androidRelease = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.release')).Text.Trim()
        apiLevel = (Invoke-Adb -Arguments @('shell', 'getprop', 'ro.build.version.sdk')).Text.Trim()
    }
}

function Invoke-Doctor {
    Assert-ProjectRoot
    Initialize-Tools
    Invoke-NativeCapture -FilePath $script:AdbPath -Arguments @('version') | Out-Null
    $device = Resolve-Device -RequestedSerial $Serial -RequestedModel $Model
    $packagePath = Assert-PackageInstalled
    $launcher = Resolve-LauncherActivity

    Write-Host 'Doctor PASS (read-only)'
    Write-Host "Project: $($script:ProjectRoot)"
    Write-Host 'Entrypoint: lib/main.dart'
    Write-Host "Device: $($device.Serial) ($($device.Model))"
    Write-Host "Package: $($script:PackageName)"
    Write-Host "Launcher: $launcher"
    Write-Host "Installed path: $packagePath"
}

function Invoke-Prepare {
    if ($ContinuousCutover -and $SkipBuild) {
        throw '-ContinuousCutover requires a fresh profile build and cannot be combined with -SkipBuild.'
    }

    Assert-ProjectRoot
    Initialize-Tools
    $device = Resolve-Device -RequestedSerial $Serial -RequestedModel $Model
    $packageBeforePath = Assert-PackageInstalled
    $packageBefore = Get-PackageMetadata
    $sessionPath = New-SessionDirectory
    $state = [pscustomobject][ordered]@{
        schemaVersion = 1
        status = 'preparing'
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        sessionPath = $sessionPath
        projectRoot = $script:ProjectRoot
        packageName = $script:PackageName
        requestedModel = $Model
        serial = $device.Serial
        adbModel = $device.Model
        apkPath = $script:ExpectedApkPath
        packagePathBefore = $packageBeforePath
        continuousCutover = [bool]$ContinuousCutover
    }
    Save-SessionState -State $state -SessionPath $sessionPath

    $continuousCutoverStatus = if ($ContinuousCutover) { 'ENABLED' } else { 'DISABLED' }
    Write-Host "ContinuousCutover: $continuousCutoverStatus"
    $buildStarted = [DateTime]::UtcNow
    $profileBuildArguments = @(Get-ProfileBuildArguments -EnableContinuousCutover ([bool]$ContinuousCutover))
    $buildCommand = 'flutter ' + ($profileBuildArguments -join ' ')
    if ($SkipBuild) {
        if (-not (Test-Path -LiteralPath $script:ExpectedApkPath -PathType Leaf)) {
            throw "-SkipBuild requires the expected APK: $($script:ExpectedApkPath)"
        }
        $buildMode = 'skipped-existing-apk-confirmed'
    }
    else {
        Push-Location $script:ProjectRoot
        try {
            $buildResult = Invoke-NativeCapture -FilePath $script:FlutterPath `
                -Arguments $profileBuildArguments -AllowFailure
        }
        finally {
            Pop-Location
        }
        $buildResult.Output | Set-Content -LiteralPath (Join-Path $sessionPath 'build.log') -Encoding UTF8
        if ($buildResult.ExitCode -ne 0) {
            Set-ObjectProperty -InputObject $state -Name 'status' -Value 'build-failed'
            Save-SessionState -State $state -SessionPath $sessionPath
            throw "Profile build failed. See $(Join-Path $sessionPath 'build.log')"
        }
        $buildMode = 'built'
    }
    if (-not (Test-Path -LiteralPath $script:ExpectedApkPath -PathType Leaf)) {
        throw "Expected profile APK was not produced: $($script:ExpectedApkPath)"
    }

    $apk = Get-Item -LiteralPath $script:ExpectedApkPath
    $apkHash = Get-FileHash -LiteralPath $script:ExpectedApkPath -Algorithm SHA256
    $installResult = Invoke-Adb -Arguments @('install', '-r', $script:ExpectedApkPath) -AllowFailure
    $installResult.Output | Set-Content -LiteralPath (Join-Path $sessionPath 'install.log') -Encoding UTF8
    if ($installResult.Text -match '(?i)INSTALL_FAILED_UPDATE_INCOMPATIBLE|INSTALL_FAILED_VERSION_DOWNGRADE|INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES|signatures do not match|incompatible') {
        Set-ObjectProperty -InputObject $state -Name 'status' -Value 'install-incompatible'
        Save-SessionState -State $state -SessionPath $sessionPath
        throw "APK compatibility check failed. No recovery action was attempted. See $(Join-Path $sessionPath 'install.log')"
    }
    if ($installResult.ExitCode -ne 0) {
        Set-ObjectProperty -InputObject $state -Name 'status' -Value 'install-failed'
        Save-SessionState -State $state -SessionPath $sessionPath
        throw "APK replacement failed. See $(Join-Path $sessionPath 'install.log')"
    }

    $launcher = Resolve-LauncherActivity
    $launchResult = Invoke-Adb -Arguments @(
        'shell', 'am', 'start', '-W',
        '-a', 'android.intent.action.MAIN',
        '-c', 'android.intent.category.LAUNCHER',
        '-n', $launcher
    )
    $launchResult.Output | Set-Content -LiteralPath (Join-Path $sessionPath 'launch.log') -Encoding UTF8

    $metadata = [pscustomobject][ordered]@{
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        device = Get-DeviceMetadata -ResolvedDevice $device
        build = [pscustomobject][ordered]@{
            mode = $buildMode
            command = $buildCommand
            continuousCutover = [bool]$ContinuousCutover
            startedAtUtc = $buildStarted.ToString('o')
            finishedAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        apk = [pscustomobject][ordered]@{
            path = $apk.FullName
            lengthBytes = $apk.Length
            lastWriteTimeUtc = $apk.LastWriteTimeUtc.ToString('o')
            sha256 = $apkHash.Hash
        }
        packageBefore = $packageBefore
        packageAfter = Get-PackageMetadata
        launcherActivity = $launcher
    }
    Write-JsonFile -Value $metadata -Path (Join-Path $sessionPath 'metadata.json')

    Set-ObjectProperty -InputObject $state -Name 'status' -Value 'prepared'
    Set-ObjectProperty -InputObject $state -Name 'preparedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Set-ObjectProperty -InputObject $state -Name 'launcherActivity' -Value $launcher
    Save-SessionState -State $state -SessionPath $sessionPath

    @(
        "Session: $sessionPath"
        "Device: $($device.Serial) ($($device.Model))"
        "APK: $($script:ExpectedApkPath)"
        "Launcher: $launcher"
        "ContinuousCutover: $continuousCutoverStatus"
    ) | Set-Content -LiteralPath (Join-Path $sessionPath 'summary.txt') -Encoding UTF8

    Write-Host "Prepare complete: $sessionPath"
}

function Test-TrackedProcess {
    param([Parameter(Mandatory = $true)]$Capture)
    $hostPid = [int](Get-OptionalProperty -InputObject $Capture -Name 'hostPid')
    $startedTicks = [int64](Get-OptionalProperty -InputObject $Capture -Name 'hostStartedUtcTicks')
    $process = Get-Process -Id $hostPid -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return $null
    }
    if ($process.StartTime.ToUniversalTime().Ticks -ne $startedTicks) {
        return $null
    }
    $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($script:AdbPath)
    if ($process.ProcessName -ne $expectedName) {
        return $null
    }
    return $process
}

function Stop-TrackedLogs {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$SessionPath
    )

    $capture = Get-OptionalProperty -InputObject $State -Name 'logCapture'
    if ($null -eq $capture) {
        Write-Host 'No script-owned log capture is recorded for this session.'
        return
    }
    $captureStatus = [string](Get-OptionalProperty -InputObject $capture -Name 'status')
    if ($captureStatus -ne 'running') {
        Write-Host "Log capture is already $captureStatus."
        return
    }

    $process = Test-TrackedProcess -Capture $capture
    if ($null -ne $process) {
        Stop-Process -Id $process.Id
        Wait-Process -Id $process.Id -ErrorAction SilentlyContinue
        Set-ObjectProperty -InputObject $capture -Name 'status' -Value 'stopped'
    }
    else {
        Set-ObjectProperty -InputObject $capture -Name 'status' -Value 'exited-or-identity-mismatch'
    }
    Set-ObjectProperty -InputObject $capture -Name 'stoppedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Set-ObjectProperty -InputObject $State -Name 'logCapture' -Value $capture
    Save-SessionState -State $State -SessionPath $SessionPath
}

function Invoke-StartLogs {
    Assert-ProjectRoot
    Initialize-Tools
    $sessionPath = Resolve-SessionDirectory -RequestedSession $Session
    $state = Read-SessionState -SessionPath $sessionPath
    $device = Resolve-SessionDevice -State $state -RequestedSerial $Serial -RequestedModel $Model

    $existing = Get-OptionalProperty -InputObject $state -Name 'logCapture'
    if ($null -ne $existing) {
        $existingProcess = Test-TrackedProcess -Capture $existing
        if ($null -ne $existingProcess) {
            throw "A script-owned log capture is already running with host PID $($existingProcess.Id)."
        }
    }

    $devicePid = Get-DevicePid
    if ([string]::IsNullOrWhiteSpace($devicePid)) {
        throw "The package '$($script:PackageName)' is not running. Run Prepare before StartLogs."
    }
    $logPath = Join-Path $sessionPath 'logcat.txt'
    $errorPath = Join-Path $sessionPath 'logcat.stderr.txt'
    $arguments = @('-s', $script:ResolvedSerial, 'logcat', "--pid=$devicePid", '-v', 'threadtime')
    $process = Start-Process -FilePath $script:AdbPath -ArgumentList $arguments `
        -RedirectStandardOutput $logPath -RedirectStandardError $errorPath `
        -WindowStyle Hidden -PassThru

    $capture = [pscustomobject][ordered]@{
        status = 'running'
        startedAtUtc = [DateTime]::UtcNow.ToString('o')
        hostPid = $process.Id
        hostStartedUtcTicks = $process.StartTime.ToUniversalTime().Ticks
        devicePid = $devicePid
        serial = $device.Serial
        packageName = $script:PackageName
        logPath = $logPath
        errorPath = $errorPath
        arguments = $arguments
    }
    Set-ObjectProperty -InputObject $state -Name 'logCapture' -Value $capture
    Save-SessionState -State $state -SessionPath $sessionPath
    Write-Host "PID-filtered log capture started: $logPath"
}

function Invoke-StopLogs {
    Assert-ProjectRoot
    Initialize-Tools
    $sessionPath = Resolve-SessionDirectory -RequestedSession $Session
    $state = Read-SessionState -SessionPath $sessionPath
    Stop-TrackedLogs -State $state -SessionPath $sessionPath
    Write-Host "Log capture state updated: $(Join-Path $sessionPath 'state.json')"
}

function ConvertTo-NativeQuotedArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Save-AdbScreenshot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $arguments = @('-s', $script:ResolvedSerial, 'exec-out', 'screencap', '-p')
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $script:AdbPath
    $startInfo.Arguments = (($arguments | ForEach-Object { ConvertTo-NativeQuotedArgument -Value $_ }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Could not start the screenshot command.'
    }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $process.StandardOutput.BaseStream.CopyTo($stream)
    }
    finally {
        $stream.Dispose()
    }
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Screenshot command failed with exit code $($process.ExitCode): $errorText"
    }
}

function New-PhysicalSnapshot {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$SessionPath,
        [Parameter(Mandatory = $true)]$Device,
        [switch]$CaptureScreenshot
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $snapshotRoot = Join-Path $SessionPath 'snapshots'
    if (-not (Test-Path -LiteralPath $snapshotRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null
    }
    $snapshotPath = Join-Path $snapshotRoot $stamp
    if (Test-Path -LiteralPath $snapshotPath) {
        $snapshotPath = Join-Path $snapshotRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    }
    New-Item -ItemType Directory -Path $snapshotPath | Out-Null

    $devicePid = Get-DevicePid
    $logPath = Join-Path $SessionPath 'logcat.txt'
    $tailPath = Join-Path $snapshotPath 'logcat-tail.txt'
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        @(Get-Content -LiteralPath $logPath -Tail 200) |
            Set-Content -LiteralPath $tailPath -Encoding UTF8
    }
    else {
        Set-Content -LiteralPath $tailPath -Value '<no captured log is available>' -Encoding UTF8
    }

    $screenshotPath = $null
    if ($CaptureScreenshot) {
        $screenshotPath = Join-Path $snapshotPath 'screen.png'
        Save-AdbScreenshot -Path $screenshotPath
    }
    $snapshotMetadata = [pscustomobject][ordered]@{
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        serial = $Device.Serial
        adbModel = $Device.Model
        packageName = $script:PackageName
        devicePid = $devicePid
        logTailPath = $tailPath
        screenshotPath = $screenshotPath
    }
    Write-JsonFile -Value $snapshotMetadata -Path (Join-Path $snapshotPath 'snapshot.json')
    return $snapshotPath
}

function Invoke-Snapshot {
    Assert-ProjectRoot
    Initialize-Tools
    $sessionPath = Resolve-SessionDirectory -RequestedSession $Session
    $state = Read-SessionState -SessionPath $sessionPath
    $device = Resolve-SessionDevice -State $state -RequestedSerial $Serial -RequestedModel $Model
    $snapshotPath = New-PhysicalSnapshot -State $state -SessionPath $sessionPath -Device $device -CaptureScreenshot:$Screenshot
    Write-Host "Snapshot: $snapshotPath"
}

function Invoke-Finish {
    Assert-ProjectRoot
    Initialize-Tools
    $sessionPath = Resolve-SessionDirectory -RequestedSession $Session
    $state = Read-SessionState -SessionPath $sessionPath
    Stop-TrackedLogs -State $state -SessionPath $sessionPath
    $state = Read-SessionState -SessionPath $sessionPath

    $finalSnapshotPath = $null
    if ($FinalSnapshot -or $Screenshot) {
        $device = Resolve-SessionDevice -State $state -RequestedSerial $Serial -RequestedModel $Model
        $finalSnapshotPath = New-PhysicalSnapshot -State $state -SessionPath $sessionPath -Device $device -CaptureScreenshot:$Screenshot
    }

    Set-ObjectProperty -InputObject $state -Name 'status' -Value 'finished-awaiting-manual-result'
    Set-ObjectProperty -InputObject $state -Name 'finishedAtUtc' -Value ([DateTime]::UtcNow.ToString('o'))
    Set-ObjectProperty -InputObject $state -Name 'finalSnapshotPath' -Value $finalSnapshotPath
    Save-SessionState -State $state -SessionPath $sessionPath

    $summaryPath = Join-Path $sessionPath 'summary.txt'
    @(
        ''
        "Finished at (UTC): $([DateTime]::UtcNow.ToString('o'))"
        "Metadata: $(Join-Path $sessionPath 'metadata.json')"
        "Log: $(Join-Path $sessionPath 'logcat.txt')"
        "Final snapshot: $(if ($null -eq $finalSnapshotPath) { '<not requested>' } else { $finalSnapshotPath })"
        'Manual visual acceptance: [ ] PASS  [ ] FAIL'
        'Manual notes:'
    ) | Add-Content -LiteralPath $summaryPath -Encoding UTF8

    Write-Host "Session: $sessionPath"
    Write-Host "Summary: $summaryPath"
    Write-Host 'Manual visual acceptance: [ ] PASS  [ ] FAIL'
}

switch ($Action) {
    'Doctor' { Invoke-Doctor }
    'Prepare' { Invoke-Prepare }
    'StartLogs' { Invoke-StartLogs }
    'StopLogs' { Invoke-StopLogs }
    'Snapshot' { Invoke-Snapshot }
    'Finish' { Invoke-Finish }
}
