<#
.SYNOPSIS
    fastfetch-config — one-shot installer for Windows.

.DESCRIPTION
    Installs fastfetch, a Nerd Font, and this repository's config.jsonc.
    Any existing config is backed up, never overwritten silently.
    Nothing here needs administrator rights: the font is installed for the
    current user only.

.EXAMPLE
    irm https://raw.githubusercontent.com/daniloscimone/fastfetch-config/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -FontName Hack
#>

[CmdletBinding()]
param(
    # Nerd Font to install, named as published by ryanoasis/nerd-fonts.
    [string]$FontName = 'JetBrainsMono',

    # Install every weight and variant instead of Regular/Bold/Italic/BoldItalic.
    [switch]$FontFull,

    # Skip the font.
    [switch]$NoFont,

    # Only install the config, not fastfetch itself.
    [switch]$NoFastfetch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoSlug = 'daniloscimone/fastfetch-config'
$RawBase  = "https://raw.githubusercontent.com/$RepoSlug/main"
$FfDl     = 'https://github.com/fastfetch-cli/fastfetch/releases/latest/download'
$NfDl     = 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download'

$script:FontOk = $true

# Windows PowerShell 5.1 still defaults to TLS 1.0 on older builds.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# ---------------------------------------------------------------- output ----

function Write-Step { param([string]$Message) Write-Host "==> " -ForegroundColor Cyan -NoNewline; Write-Host $Message -ForegroundColor White }
function Write-Info { param([string]$Message) Write-Host "    $Message" }
function Write-Dim  { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }
function Write-Ok   { param([string]$Message) Write-Host "    " -NoNewline; Write-Host "OK " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Warn { param([string]$Message) Write-Host "    " -NoNewline; Write-Host "!  " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Err  { param([string]$Message) Write-Host ""; Write-Host "error: " -ForegroundColor Red -NoNewline; Write-Host $Message }

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# Picks up PATH changes made by a package manager in this same session.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Get-Architecture {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'amd64' }
        'ARM64' { 'aarch64' }
        'x86'   { 'amd64' }   # 32-bit shell on a 64-bit machine
        default { 'amd64' }
    }
}

# ------------------------------------------------------------- fastfetch ----

function Install-FastfetchPortable {
    # Last resort: unpack an upstream release under %LOCALAPPDATA%.
    $arch    = Get-Architecture
    $zip     = Join-Path $script:WorkDir "fastfetch-windows-$arch.zip"
    $target  = Join-Path $env:LOCALAPPDATA 'Programs\fastfetch'

    Write-Info "downloading fastfetch-windows-$arch.zip"
    Invoke-WebRequest -Uri "$FfDl/fastfetch-windows-$arch.zip" -OutFile $zip -UseBasicParsing

    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $target -Force

    # The archive may or may not carry a top-level folder.
    $exe = Get-ChildItem -Path $target -Filter 'fastfetch.exe' -Recurse |
           Select-Object -First 1
    if (-not $exe) { throw "fastfetch.exe not found in the release archive" }
    $binDir = $exe.DirectoryName

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$binDir*") {
        [Environment]::SetEnvironmentVariable(
            'Path', (@($userPath, $binDir) | Where-Object { $_ }) -join ';', 'User')
    }
    $env:Path = "$env:Path;$binDir"

    Write-Ok "installed to $binDir"
}

function Install-Fastfetch {
    Write-Step 'fastfetch'

    if (Test-Command 'fastfetch') {
        $version = @(fastfetch --version)[0]
        Write-Ok "already installed ($version)"
        return
    }

    $installed = $false

    if (Test-Command 'winget') {
        Write-Info 'installing with winget'
        try {
            winget install --id Fastfetch-cli.Fastfetch --exact --silent `
                --accept-source-agreements --accept-package-agreements | Out-Null
            Update-SessionPath
            $installed = Test-Command 'fastfetch'
        } catch { $installed = $false }
    }

    if (-not $installed -and (Test-Command 'scoop')) {
        Write-Info 'installing with scoop'
        try {
            scoop install fastfetch | Out-Null
            Update-SessionPath
            $installed = Test-Command 'fastfetch'
        } catch { $installed = $false }
    }

    if (-not $installed -and (Test-Command 'choco')) {
        Write-Info 'installing with chocolatey'
        try {
            choco install fastfetch -y --no-progress | Out-Null
            Update-SessionPath
            $installed = Test-Command 'fastfetch'
        } catch { $installed = $false }
    }

    if (-not $installed) {
        if (-not (Test-Command 'winget')) { Write-Warn 'winget not available' }
        Install-FastfetchPortable
        $installed = Test-Command 'fastfetch'
    }

    if (-not $installed) { throw 'fastfetch installation failed' }
    Write-Ok (@(fastfetch --version)[0])
}

# ------------------------------------------------------------------ font ----

function Test-FontInstalled {
    param([string]$Name)

    $userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    foreach ($dir in @($userFonts, "$env:WINDIR\Fonts")) {
        if (Test-Path $dir) {
            $hit = Get-ChildItem -Path $dir -Filter "$Name*NerdFont*" -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($hit) { return $true }
        }
    }
    return $false
}

function Install-NerdFont {
    Write-Step "Nerd Font - $FontName"

    if (Test-FontInstalled -Name $FontName) {
        Write-Ok "$FontName Nerd Font is already installed"
        return
    }

    $extract = Join-Path $script:WorkDir 'font'
    New-Item -ItemType Directory -Path $extract -Force | Out-Null

    # The .zip is well over a hundred megabytes; the .tar.xz is a few. Windows
    # 10 1803+ ships bsdtar, which usually handles xz - try it first.
    $unpacked = $false
    if (Test-Command 'tar') {
        $archive = Join-Path $script:WorkDir "$FontName.tar.xz"
        Write-Info "downloading $FontName.tar.xz"
        try {
            Invoke-WebRequest -Uri "$NfDl/$FontName.tar.xz" -OutFile $archive -UseBasicParsing
        } catch {
            Write-Warn "no Nerd Font named '$FontName' - see https://www.nerdfonts.com/font-downloads"
            $script:FontOk = $false
            return
        }
        # Native stderr must not become a terminating error here: a tar build
        # without xz support is an expected outcome, not a failure.
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & tar -xf $archive -C $extract *>$null } catch { }
        $ErrorActionPreference = $previous

        $unpacked = (Get-ChildItem -Path $extract -Recurse -Include '*.ttf', '*.otf' |
                     Measure-Object).Count -gt 0
    }

    if (-not $unpacked) {
        Write-Warn 'falling back to the .zip archive (large download)'
        $archive = Join-Path $script:WorkDir "$FontName.zip"
        try {
            Invoke-WebRequest -Uri "$NfDl/$FontName.zip" -OutFile $archive -UseBasicParsing
            Expand-Archive -Path $archive -DestinationPath $extract -Force
        } catch {
            Write-Warn "could not download or unpack $FontName"
            $script:FontOk = $false
            return
        }
    }

    $files = Get-ChildItem -Path $extract -Recurse -Include '*.ttf', '*.otf'
    if (-not $FontFull) {
        # Regular/Bold/Italic/BoldItalic of the standard and Mono variants is
        # what a terminal actually needs; the archives ship ~100 files.
        $pattern  = "^$([regex]::Escape($FontName))NerdFont(Mono)?-(Regular|Bold|Italic|BoldItalic)\.(ttf|otf)$"
        $filtered = $files | Where-Object { $_.Name -match $pattern }
        if ($filtered) { $files = $filtered }
    }

    if (-not $files) {
        Write-Warn 'no font files found in the archive'
        $script:FontOk = $false
        return
    }

    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
    $regKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }

    $copied = 0
    foreach ($file in $files) {
        $dest = Join-Path $fontDir $file.Name
        Copy-Item -Path $file.FullName -Destination $dest -Force

        $type  = if ($file.Extension -eq '.otf') { '(OpenType)' } else { '(TrueType)' }
        $entry = "$([IO.Path]::GetFileNameWithoutExtension($file.Name)) $type"
        New-ItemProperty -Path $regKey -Name $entry -Value $dest -PropertyType String -Force | Out-Null
        $copied++
    }

    Write-Ok "installed $copied font file(s) to $fontDir"
    Write-Dim 'Already-running terminals may need a restart to see the new font.'
}

# ---------------------------------------------------------------- config ----

function Get-ConfigDirectory {
    # fastfetch itself knows where it looks for config files; the first entry
    # is the preferred one.
    if (Test-Command 'fastfetch') {
        try {
            $first = (fastfetch --list-config-paths) -split "`r?`n" |
                     Where-Object { $_.Trim() } | Select-Object -First 1
            if ($first) {
                return ($first -replace '\s*\(\*\)\s*$', '').TrimEnd('/', '\')
            }
        } catch { }
    }
    Join-Path $env:USERPROFILE '.config\fastfetch'
}

function Get-SourceConfig {
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot 'config.jsonc'
        if (Test-Path $local) { return $local }
    }

    $tmp = Join-Path $script:WorkDir 'config.jsonc'
    Invoke-WebRequest -Uri "$RawBase/config.jsonc" -OutFile $tmp -UseBasicParsing
    return $tmp
}

function Install-Config {
    Write-Step 'configuration'

    $src     = Get-SourceConfig
    $destDir = Get-ConfigDirectory
    $dest    = Join-Path $destDir 'config.jsonc'

    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    if (Test-Path $dest) {
        $same = (Get-FileHash $src).Hash -eq (Get-FileHash $dest).Hash
        if ($same) {
            Write-Ok 'config.jsonc is already up to date'
            return
        }
        $backup = "$dest.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -Path $dest -Destination $backup -Force
        Write-Info "existing config saved as $(Split-Path $backup -Leaf)"
    }

    Copy-Item -Path $src -Destination $dest -Force
    Write-Ok "installed to $dest"
}

# ------------------------------------------------------------------ main ----

$script:WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("fastfetch-config-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

try {
    Write-Host ''
    Write-Host 'fastfetch-config' -ForegroundColor Cyan -NoNewline
    Write-Host "  github.com/$RepoSlug" -ForegroundColor DarkGray
    Write-Host ''

    if (-not $NoFastfetch) { Install-Fastfetch }
    if (-not $NoFont)      { Install-NerdFont }
    Install-Config

    Write-Step 'done'
    if (Test-Command 'fastfetch') {
        Write-Host ''
        fastfetch
        Write-Host ''
    }
    if ($script:FontOk -and -not $NoFont) {
        Write-Dim "Set your terminal font to `"$FontName Nerd Font`" so the icons render."
    } else {
        Write-Dim 'Install a Nerd Font and set it as your terminal font so the icons render.'
    }
    Write-Dim "Run 'fastfetch' to print it again."
    Write-Host ''
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
finally {
    if (Test-Path $script:WorkDir) {
        Remove-Item $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
