[CmdletBinding()]
param(
    [string]$DeviceId,
    [switch]$InstallProfile,
    [switch]$SkipFlutterTests,
    [switch]$SkipReleaseBuild
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$AuditDir = Join-Path $ProjectRoot 'audit/device-build'
New-Item -ItemType Directory -Force -Path $AuditDir | Out-Null
Set-Location $ProjectRoot

function Invoke-Logged {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $log = Join-Path $AuditDir ($Name + '.log')
    Write-Host "`n== $Name ==" -ForegroundColor Cyan
    & $Executable @Arguments 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE. See $log"
    }
}

foreach ($tool in @('flutter', 'dart', 'java')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' is not on PATH. Install/configure Flutter 3.44.7, Dart 3.12.2, JDK 17+ and Android SDK platform-tools first."
    }
}

$flutterMachine = (& flutter --version --machine | ConvertFrom-Json)
if ($flutterMachine.frameworkVersion -ne '3.44.7') {
    throw "Expected Flutter 3.44.7, found $($flutterMachine.frameworkVersion). Use the pinned toolchain before validating this candidate."
}
if ($flutterMachine.dartSdkVersion -ne '3.12.2') {
    throw "Expected Dart 3.12.2, found $($flutterMachine.dartSdkVersion)."
}

if ($InstallProfile -and -not (Get-Command 'adb' -ErrorAction SilentlyContinue)) {
    throw "ADB is required when -InstallProfile is specified. Install Android SDK platform-tools first."
}

$doctorLog = Join-Path $AuditDir 'flutter-doctor.log'
& flutter doctor -v 2>&1 | Tee-Object -FilePath $doctorLog
if ($LASTEXITCODE -ne 0) { throw "flutter doctor failed. See $doctorLog" }

$localProperties = Join-Path $ProjectRoot 'android/local.properties'
if (-not (Test-Path $localProperties)) {
    $flutterCommand = Get-Command 'flutter'
    $flutterRoot = Split-Path (Split-Path $flutterCommand.Source -Parent) -Parent
    $sdkRoot = $env:ANDROID_SDK_ROOT
    if ([string]::IsNullOrWhiteSpace($sdkRoot)) { $sdkRoot = $env:ANDROID_HOME }
    if ([string]::IsNullOrWhiteSpace($sdkRoot)) {
        $doctorText = Get-Content -Raw $doctorLog
        if ($doctorText -match 'Android SDK at ([^
]+)') { $sdkRoot = $Matches[1].Trim() }
    }
    if ([string]::IsNullOrWhiteSpace($sdkRoot) -or -not (Test-Path $sdkRoot)) {
        throw 'Android SDK path was not found. Set ANDROID_SDK_ROOT or ANDROID_HOME, then rerun.'
    }
    $flutterRoot = (Resolve-Path $flutterRoot).Path.Replace('\', '/')
    $sdkRoot = (Resolve-Path $sdkRoot).Path.Replace('\', '/')
    @("flutter.sdk=$flutterRoot", "sdk.dir=$sdkRoot") | Set-Content -Encoding ASCII $localProperties
    Write-Host 'Created ignored android/local.properties from the selected Flutter and Android SDK paths.' -ForegroundColor Yellow
}

# The lockfile was prepared for file_picker 11.0.3. This command must validate its
# archive hash and all package constraints before any Gradle or APK build proceeds.
Invoke-Logged -Name 'pub-get-enforce-lockfile' -Executable 'flutter' -Arguments @('pub', 'get', '--enforce-lockfile')
Invoke-Logged -Name 'pub-dependency-graph' -Executable 'flutter' -Arguments @('pub', 'deps', '--json')

if (-not $SkipFlutterTests) {
    Invoke-Logged -Name 'flutter-analyze' -Executable 'flutter' -Arguments @('analyze')
    Invoke-Logged -Name 'flutter-test' -Executable 'flutter' -Arguments @('test', '--reporter', 'expanded')
}

Push-Location (Join-Path $ProjectRoot 'android')
try {
    $gradle = Join-Path (Get-Location) 'gradlew.bat'
    if (-not (Test-Path $gradle)) { throw 'Gradle wrapper is missing.' }
    Invoke-Logged -Name 'gradle-file-picker-kotlin-compile' -Executable $gradle -Arguments @(':file_picker:compileReleaseKotlin')
    Invoke-Logged -Name 'gradle-release-runtime-dependencies' -Executable $gradle -Arguments @(':app:dependencies', '--configuration', 'releaseRuntimeClasspath')
    Invoke-Logged -Name 'gradle-junrar-insight' -Executable $gradle -Arguments @(':app:dependencyInsight', '--dependency', 'junrar', '--configuration', 'releaseRuntimeClasspath')
    Invoke-Logged -Name 'gradle-slf4j-insight' -Executable $gradle -Arguments @(':app:dependencyInsight', '--dependency', 'slf4j-api', '--configuration', 'releaseRuntimeClasspath')
    Invoke-Logged -Name 'gradle-nio-desugar-insight' -Executable $gradle -Arguments @(':app:dependencyInsight', '--dependency', 'desugar_jdk_libs_nio', '--configuration', 'coreLibraryDesugaring')
    Invoke-Logged -Name 'gradle-tika-insight' -Executable $gradle -Arguments @(':app:dependencyInsight', '--dependency', 'tika-core', '--configuration', 'releaseRuntimeClasspath')
} finally {
    Pop-Location
}

$dartDefines = @()
if (-not [string]::IsNullOrWhiteSpace($env:GOOGLE_BOOKS_API_KEY)) {
    $dartDefines += "--dart-define=GOOGLE_BOOKS_API_KEY=$($env:GOOGLE_BOOKS_API_KEY)"
} else {
    Write-Warning 'GOOGLE_BOOKS_API_KEY is not set. The APK will build, but Google Books search will report a missing compile-time key.'
}

Invoke-Logged -Name 'build-profile-apk' -Executable 'flutter' -Arguments (@('build', 'apk', '--profile', '--no-pub', '-t', 'lib/main.dart') + $dartDefines)
$profileApk = Join-Path $ProjectRoot 'build/app/outputs/flutter-apk/app-profile.apk'
if (-not (Test-Path $profileApk)) { throw "Profile APK not found at $profileApk" }
Get-FileHash -Algorithm SHA256 $profileApk | Format-List | Out-File (Join-Path $AuditDir 'app-profile.sha256.txt')

if (-not $SkipReleaseBuild) {
    Invoke-Logged -Name 'build-release-apk' -Executable 'flutter' -Arguments (@('build', 'apk', '--release', '--no-pub', '-t', 'lib/main.dart') + $dartDefines)
    $releaseApk = Join-Path $ProjectRoot 'build/app/outputs/flutter-apk/app-release.apk'
    if (-not (Test-Path $releaseApk)) { throw "Release APK not found at $releaseApk" }
    Get-FileHash -Algorithm SHA256 $releaseApk | Format-List | Out-File (Join-Path $AuditDir 'app-release.sha256.txt')

    if (-not (Test-Path (Join-Path $ProjectRoot 'android/key.properties'))) {
        Write-Warning 'android/key.properties is absent. The release APK is expected to be unsigned and cannot be installed as a normal release build. Do not use a debug key for production.'
    }

    $sdkRoot = $env:ANDROID_SDK_ROOT
    if ([string]::IsNullOrWhiteSpace($sdkRoot)) { $sdkRoot = $env:ANDROID_HOME }
    if (-not [string]::IsNullOrWhiteSpace($sdkRoot) -and (Test-Path $sdkRoot)) {
        $analyzer = Get-ChildItem (Join-Path $sdkRoot 'cmdline-tools') -Filter 'apkanalyzer.bat' -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($null -ne $analyzer) {
            foreach ($entry in @(
                @{ Name = 'application-id'; Args = @('manifest', 'application-id', $releaseApk) },
                @{ Name = 'min-sdk'; Args = @('manifest', 'min-sdk', $releaseApk) },
                @{ Name = 'target-sdk'; Args = @('manifest', 'target-sdk', $releaseApk) },
                @{ Name = 'version-code'; Args = @('manifest', 'version-code', $releaseApk) },
                @{ Name = 'version-name'; Args = @('manifest', 'version-name', $releaseApk) }
            )) {
                $analyzerArgs = @($entry.Args)
                & $analyzer.FullName @analyzerArgs 2>&1 | Set-Content (Join-Path $AuditDir ("apk-" + $entry.Name + '.txt'))
                if ($LASTEXITCODE -ne 0) { throw "apkanalyzer failed for $($entry.Name)." }
            }
            $applicationId = (Get-Content -Raw (Join-Path $AuditDir 'apk-application-id.txt')).Trim()
            if ($applicationId -ne 'app.bibliolife.reader') {
                throw "Unexpected APK application ID '$applicationId'; expected app.bibliolife.reader."
            }
            $minSdk = (Get-Content -Raw (Join-Path $AuditDir 'apk-min-sdk.txt')).Trim()
            if ($minSdk -ne '24') {
                throw "Unexpected APK minSdk '$minSdk'; expected 24. Review the supported Android API floor before continuing."
            }
        } else {
            Write-Warning 'apkanalyzer.bat was not found; APK manifest metadata inspection is deferred.'
        }

        $signer = Get-ChildItem (Join-Path $sdkRoot 'build-tools') -Filter 'apksigner.bat' -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($null -ne $signer) {
            & $signer.FullName verify --print-certs $releaseApk 2>&1 | Set-Content (Join-Path $AuditDir 'apk-signature.txt')
            if ($LASTEXITCODE -ne 0) {
                Write-Warning 'APK signature verification failed; this is expected for an unsigned release APK. Review apk-signature.txt.'
            }
        } else {
            Write-Warning 'apksigner.bat was not found; APK signature inspection is deferred.'
        }
    } else {
        Write-Warning 'ANDROID_SDK_ROOT/ANDROID_HOME is not set; apkanalyzer/apksigner inspection is deferred.'
    }
}

if ($InstallProfile) {
    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        $devices = & adb devices
        $connected = @($devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' })
        if ($connected.Count -ne 1) {
            throw 'Pass -DeviceId explicitly when zero or multiple ADB devices are connected.'
        }
        $DeviceId = ($connected[0] -split '\s+')[0]
    }
    $model = (& adb -s $DeviceId shell getprop ro.product.model).Trim()
    $device = (& adb -s $DeviceId shell getprop ro.product.device).Trim()
    "DeviceId=$DeviceId`nModel=$model`nDevice=$device" | Set-Content (Join-Path $AuditDir 'device-info.txt')
    Write-Host "Installing profile APK on $model ($device). This is a debug-key-signed profile build, not the production release signature." -ForegroundColor Yellow
    Invoke-Logged -Name 'adb-install-profile' -Executable 'adb' -Arguments @('-s', $DeviceId, 'install', '-r', $profileApk)
}

Write-Host "`nBuild preparation completed. Logs and hashes: $AuditDir" -ForegroundColor Green
Write-Host 'Do not publish until the resolved dependency graph, release notices, signing, APK inspection and device acceptance are reviewed.' -ForegroundColor Yellow
