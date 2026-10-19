$ErrorActionPreference = 'Stop'
$desktop = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $desktop
$python = if (Test-Path '.venv/Scripts/python.exe') { '.venv/Scripts/python.exe' } else { 'python' }
if (-not (Test-Path '.venv/Scripts/python.exe')) {
    & python -m venv .venv
    $python = '.venv/Scripts/python.exe'
}
& $python -m pip install --upgrade pip
& $python -m pip install -r requirements.txt -r requirements-packaging.txt 'devar-engine>=0.1.1,<0.2.0'
& $python -c 'import sounddevice, pywhispercpp.model, devar_engine; print("Windows speech dependencies are ready")'

$dist = Join-Path $desktop 'dist'
$app = Join-Path $dist 'Devar'
$helperDist = Join-Path $dist 'speech-build'
Remove-Item $app, $helperDist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $dist | Out-Null
& $python -m PyInstaller --noconfirm --clean --onedir --console `
    --name desktop_bridge --distpath $helperDist --workpath (Join-Path $desktop '.build/win-work') `
    --specpath (Join-Path $desktop '.build') --collect-all pywhispercpp `
    --collect-all devar_engine --collect-all sounddevice --hidden-import _pywhispercpp `
    (Join-Path $desktop 'Sources/DevarDesktop/Resources/desktop_bridge.py')
if ($LASTEXITCODE -ne 0) { throw 'Failed to package the local Devar speech service.' }

dotnet publish (Join-Path $PSScriptRoot 'Devar.Windows/Devar.Windows.csproj') `
    -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -o $app
if ($LASTEXITCODE -ne 0) { throw 'Failed to publish the Devar Windows app.' }
New-Item -ItemType Directory -Path (Join-Path $app 'Speech') -Force | Out-Null
Copy-Item (Join-Path $helperDist 'desktop_bridge') (Join-Path $app 'Speech') -Recurse -Force
$zipPath = Join-Path $dist 'Devar-Windows-x64.zip'
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $app '*') -DestinationPath $zipPath
Write-Host "Created $zipPath"
