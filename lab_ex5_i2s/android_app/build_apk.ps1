param([string]$PythonExe = 'python', [string]$GradleExe = '', [switch]$Offline)
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$bundledJdk=Join-Path $workspace 'android_toolchain\jdk\jdk-17.0.20.1+1'
if (-not $env:JAVA_HOME -and (Test-Path -LiteralPath $bundledJdk)) { $env:JAVA_HOME=$bundledJdk }
if (-not $env:ANDROID_HOME -and (Test-Path -LiteralPath (Join-Path $workspace 'android_toolchain\sdk'))) {
    $env:ANDROID_HOME=Join-Path $workspace 'android_toolchain\sdk'
}
if (-not $GradleExe) {
    $bundledGradle=Join-Path $workspace 'android_toolchain\gradle\gradle-8.7\bin\gradle.bat'
    if (Test-Path -LiteralPath $bundledGradle) { $GradleExe=$bundledGradle } else { $GradleExe='gradle' }
}
$env:GRADLE_USER_HOME=Join-Path $workspace '.android_gradle'
$env:ANDROID_USER_HOME=Join-Path $workspace '.android_profile'
$env:JAVA_TOOL_OPTIONS="-Duser.home=`"$workspace`""
& $PythonExe (Join-Path $PSScriptRoot 'sync_controller.py')
if($LASTEXITCODE -ne 0){throw 'UI asset generation failed'}
$gradleArgs=@('-p', $PSScriptRoot, '--no-daemon', 'assembleDebug')
if ($Offline) { $gradleArgs += '--offline' }
& $GradleExe @gradleArgs
if($LASTEXITCODE -ne 0){throw 'APK build failed'}
$output=Join-Path $PSScriptRoot 'app\build\outputs\apk\debug\app-debug.apk'
Copy-Item -LiteralPath $output -Destination (Join-Path $workspace 'lab_ex5_i2s-work\W02_Controller_Android.apk')
