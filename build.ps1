<#
.SYNOPSIS
    Compila o fix-easybuilding com javac + jar (sem Gradle, sem Loom).

.DESCRIPTION
    Gera um jar por loader:
        build\fix-easybuilding-fabric-2.0.0.jar
        build\fix-easybuilding-neoforge-2.0.0.jar

    Os jars usados so na compilacao sao procurados em:
        ..\easy-building-minecraft-mod\...   (Easy Building ja buildado, preferido)
        libs\                                (copia local / download do Modrinth)
        cache do Gradle/Loom                 (Minecraft mapeado + sponge-mixin)

    O Minecraft mapeado (minecraft-clientonly-deobf) vem do cache do Loom. Para
    apologise-lo, faca uma build do Easy Building uma vez:
        ..\easy-building-minecraft-mod\easy-building-fabric-26.3\gradlew.bat build

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Loader fabric
    .\build.ps1 -ModVersion 2.0.1
#>
[CmdletBinding()]
param(
    [ValidateSet('fabric', 'neoforge', 'all')]
    [string] $Loader = 'all',
    [string] $McVersion = '26.3',
    [string] $ModVersion = '2.0.0'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$libsDir = Join-Path $root 'libs'
$buildDir = Join-Path $root 'build'
$gradleCache = Join-Path $env:USERPROFILE '.gradle\caches'
$easyBuildingRepoDir = Join-Path (Split-Path -Parent $root) 'easy-building-minecraft-mod'

# --------------------------------------------------------------------------- helpers

# Achata (recursivamente) o resultado de pipelines aninhados em uma lista de strings.
# Nao use $Input como nome de parametro: e uma variavel automatica do PowerShell.
# Um pipeline dentro de um array literal pode virar um array dentro do array, por isso
# a funcao desce ate o nivel de string.
function Expand-Candidates {
    param([object] $Items)

    $result = New-Object System.Collections.ArrayList
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }

        if ($item -is [string]) {
            if ($item) { [void] $result.Add($item) }
        }
        elseif ($item -is [System.Collections.IEnumerable]) {
            foreach ($flattened in (Expand-Candidates $item)) { [void] $result.Add($flattened) }
        }
        else {
            [void] $result.Add([string] $item)
        }
    }

    return $result.ToArray()
}

function Get-Toolchain {
    $javacExe = $null
    $jarExe = $null

    if ($env:JAVA_HOME) {
        $javacExe = Join-Path $env:JAVA_HOME 'bin\javac.exe'
        $jarExe = Join-Path $env:JAVA_HOME 'bin\jar.exe'
    }

    if (-not (Test-Path $javacExe)) {
        $onPath = Get-Command javac -ErrorAction SilentlyContinue
        if ($onPath) {
            $javacExe = $onPath.Source
            $jarExe = Join-Path (Split-Path -Parent $onPath.Source) 'jar.exe'
        }
    }

    if (-not (Test-Path $javacExe)) {
        throw 'javac nao encontrado. Defina JAVA_HOME apontando para um JDK 25+ ou adicione o javac no PATH.'
    }

    $version = (& $javacExe -version 2>&1) -join ' '
    if ($version -notmatch 'javac (\d+)') { throw "Nao foi possivel ler a versao do javac: $version" }
    if ([int]$Matches[1] -lt 25) {
        throw "Minecraft 26.x exige Java 25 ou superior, mas o javac em uso e o $($Matches[1]). Configure JAVA_HOME para um JDK 25+."
    }

    Write-Host "Toolchain: $version" -ForegroundColor DarkGray
    return @{ Javac = $javacExe; Jar = $jarExe }
}

function Test-JarContains {
    param([string] $Path, [string] $Entry)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            return [bool]($zip.Entries | Where-Object { $_.FullName -eq $Entry } | Select-Object -First 1)
        }
        finally {
            $zip.Dispose()
        }
    }
    catch {
        return $false
    }
}

function Resolve-FirstExisting {
    param([string[]] $Candidates, [string] $What)

    foreach ($candidate in (Expand-Candidates $Candidates)) {
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }

    $tried = (Expand-Candidates $Candidates | ForEach-Object { Split-Path -Leaf $_ } | Select-Object -First 4) -join ', '
    throw "$What nao encontrado. Procurado: $tried"
}

function Get-MinecraftJars {
    $mavenRoot = Join-Path $gradleCache 'fabric-loom\minecraftMaven\net\minecraft'

    $client = Resolve-FirstExisting -What 'minecraft-clientonly-deobf' -Candidates @(
        (Join-Path $libsDir "minecraft-clientonly-deobf-$McVersion.jar"),
        (Get-ChildItem -Path (Join-Path $mavenRoot "minecraft-clientonly-deobf\$McVersion") -Filter '*.jar' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'sources' } |
            ForEach-Object { $_.FullName })
    )

    $common = Resolve-FirstExisting -What 'minecraft-common-deobf' -Candidates @(
        (Join-Path $libsDir "minecraft-common-deobf-$McVersion.jar"),
        (Get-ChildItem -Path (Join-Path $mavenRoot "minecraft-common-deobf\$McVersion") -Filter '*.jar' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'sources' } |
            ForEach-Object { $_.FullName })
    )

    return @($client, $common)
}

function Get-MixinJar {
    return Resolve-FirstExisting -What 'sponge-mixin' -Candidates @(
        (Join-Path $libsDir 'sponge-mixin.jar'),
        (Get-ChildItem -Path (Join-Path $gradleCache 'modules-2\files-2.1\net.fabricmc\sponge-mixin') -Recurse -Filter 'sponge-mixin-*.jar' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'sources' } |
            Sort-Object FullName -Descending |
            ForEach-Object { $_.FullName })
    )
}

function Install-EasyBuildingFromModrinth {
    param([ValidateSet('fabric', 'neoforge')] $Target)

    $projectId = 't3wlJuW5' # Easy Building no Modrinth

    Write-Host "    baixando Easy Building ($Target) do Modrinth..." -ForegroundColor DarkGray

    # A API do Modrinth ignora os filtros de loaders/game_versions, entao filtramos aqui.
    # O ForEach-Object e necessario porque no PS 5.1 o ConvertFrom-Json devolve o array
    # JSON embrulhado em um unico objeto.
    $raw = (Invoke-WebRequest -UseBasicParsing "https://api.modrinth.com/v2/project/$projectId/version").Content
    $all = @(($raw | ConvertFrom-Json) | ForEach-Object { $_ })

    $matching = @($all | Where-Object { $_.loaders -contains $Target })
    if ($matching.Count -eq 0) { throw "Nao encontrei nenhuma versao do Easy Building para o loader $Target no Modrinth." }

    $major = ($McVersion -split '\.')[0]

    $ranked = @($matching | ForEach-Object {
        $score = 0
        if ($_.game_versions -contains $McVersion) { $score = 2 }
        elseif (@($_.game_versions | Where-Object { $_ -like "$major.*" }).Count -gt 0) { $score = 1 }
        [PSCustomObject]@{ Version = $_; Score = $score; Published = [datetime] $_.date_published }
    } | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Published'; Descending = $true })

    $file = ($ranked | Select-Object -First 1).Version.files |
        Where-Object { $_.primary } | Select-Object -First 1
    if (-not $file) { throw "Nao encontrei um jar do Easy Building ($Target) no Modrinth." }

    if (-not (Test-Path $libsDir)) { New-Item -ItemType Directory -Path $libsDir | Out-Null }
    $destination = Join-Path $libsDir "easybuilding-$Target.jar"
    Invoke-WebRequest $file.url -OutFile $destination

    Write-Host "    -> $(Split-Path -Leaf $destination) ($($file.filename))" -ForegroundColor DarkGray
    return $destination
}

function Get-EasyBuildingJar {
    param([ValidateSet('fabric', 'neoforge')] $Target)

    $expectedEntry = if ($Target -eq 'fabric') { 'marum/easybuilding/client/PlaneMode.class' } else { 'marum/easybuilding/PlaneMode.class' }

    if ($Target -eq 'fabric') {
        $candidates = @(
            # build da pasta da versao-alvo tem prioridade
            (Get-ChildItem -Path (Join-Path $easyBuildingRepoDir "easy-building-fabric-$McVersion\build\libs") -Filter '*.jar' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'sources' } | ForEach-Object { $_.FullName }),
            (Get-ChildItem -Path (Join-Path $easyBuildingRepoDir 'easy-building-fabric-*') -Recurse -Filter 'easy-building*.jar' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'sources' } | ForEach-Object { $_.FullName }),
            (Join-Path $libsDir 'easy-building-fabric.jar'),
            (Get-ChildItem -Path $libsDir -Filter 'easy-building*.jar' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'sources' } | ForEach-Object { $_.FullName })
        )
    }
    else {
        $candidates = @(
            (Get-ChildItem -Path (Join-Path $easyBuildingRepoDir 'easy-building-neoforge-*') -Recurse -Filter '*.jar' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'sources' -and $_.FullName -match 'build\\libs' } | ForEach-Object { $_.FullName }),
            (Join-Path $libsDir 'easybuilding-neoforge.jar'),
            (Get-ChildItem -Path $libsDir -Filter 'easybuilding-neoforge*.jar' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'sources' } | ForEach-Object { $_.FullName })
        )
    }

    foreach ($candidate in (Expand-Candidates $candidates)) {
        if (Test-JarContains -Path $candidate -Entry $expectedEntry) { return $candidate }
    }

    return Install-EasyBuildingFromModrinth -Target $Target
}

function Build-Loader {
    param(
        [ValidateSet('fabric', 'neoforge')] $Target,
        [hashtable] $Tools,
        [string[]] $MinecraftJars
    )

    $srcJava = Join-Path $root "src\$Target\java"
    $srcResources = Join-Path $root "src\$Target\resources"
    $classesDir = Join-Path $buildDir "classes\$Target"
    $outJar = Join-Path $buildDir "fix-easybuilding-$Target-$ModVersion.jar"

    Write-Host ""
    Write-Host "==> $Target" -ForegroundColor Cyan

    $classpath = @($MinecraftJars) + @((Get-MixinJar), (Get-EasyBuildingJar -Target $Target))
    $classpath | ForEach-Object { Write-Host "    cp: $(Split-Path -Leaf $_)" -ForegroundColor DarkGray }

    if (Test-Path $classesDir) { Remove-Item $classesDir -Recurse -Force }
    New-Item -ItemType Directory -Path $classesDir -Force | Out-Null

    $sources = @(Get-ChildItem -Path $srcJava -Recurse -Filter '*.java' | ForEach-Object { $_.FullName })
    & $Tools.Javac --release 25 -nowarn -encoding UTF-8 -classpath ($classpath -join ';') -d $classesDir $sources
    if ($LASTEXITCODE -ne 0) { throw "javac falhou para o loader $Target." }

    if (Test-Path $srcResources) {
        Get-ChildItem -Path $srcResources -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($srcResources.Length).TrimStart('\')
            $destination = Join-Path $classesDir $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null

            if ($_.Extension -in '.json', '.toml') {
                (Get-Content $_.FullName -Raw).Replace('${version}', $ModVersion) |
                    Set-Content -Path $destination -NoNewline -Encoding UTF8
            }
            else {
                Copy-Item $_.FullName $destination -Force
            }
        }
    }

    if (Test-Path $outJar) { Remove-Item $outJar -Force }

    # O jar do NeoForge precisa do MixinConfigs no manifest, e o jar doFabric nao tem
    # manifest proprio: passamos o arquivo explicitamente quando existir.
    $manifest = Join-Path $classesDir 'META-INF\MANIFEST.MF'
    $manifestArgs = @()
    if (Test-Path $manifest) { $manifestArgs = @('--manifest', $manifest) }

    & $Tools.Jar --create --file $outJar @manifestArgs -C $classesDir .
    if ($LASTEXITCODE -ne 0) { throw "jar falhou para o loader $Target." }

    $size = [math]::Round((Get-Item $outJar).Length / 1KB, 1)
    Write-Host "    OK -> build\$(Split-Path -Leaf $outJar) ($size KB)" -ForegroundColor Green
}

# --------------------------------------------------------------------------- main
$tools = Get-Toolchain
$targets = if ($Loader -eq 'all') { @('fabric', 'neoforge') } else { @($Loader) }

$minecraftJars = Get-MinecraftJars
foreach ($target in $targets) {
    Build-Loader -Target $target -Tools $tools -MinecraftJars $minecraftJars
}

Write-Host ""
Write-Host "Build concluido: $ModVersion para $($targets -join ', ')" -ForegroundColor Cyan
