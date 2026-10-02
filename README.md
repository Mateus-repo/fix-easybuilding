# fix-easybuilding

Corrige o crash de `NullPointerException` do mod [Easy Building](https://modrinth.com/mod/easy-building)
quando o cliente fica sem jogador (desconectar, "Save and Quit to Title", voltar ao menu principal).

## O problema

O Easy Building guarda o estado do "plane mode" em campos estáticos (`PlaneMode.active`). Quando o
cliente sai de um mundo, `Minecraft.player` vira `null`, mas `PlaneMode.active` continua `true`. O
handler de tick do mod chama `getProjectedBlock()`, que faz `player.getEyePosition()` → NPE.

## A correção

Um mixin roda no `HEAD` de `Minecraft.tick()`, antes de qualquer handler de tick dos loaders, e
limpa o estado que sobrou quando não há jogador:

```java
if (minecraft.player == null && PlaneMode.active) {
    PlaneMode.clear();
}
```

Além de evitar o crash, isso resolve o estado corrompido: ao entrar em outro mundo o Easy Building
não começa mais com o modo ligado.

O mixin é ancorado no `Minecraft` (e não em métodos internos do Easy Building) de propósito, para
continuar funcionando se o mod trocar a forma de registrar o tick — evento no NeoForge, lambda do
`ClientTickEvents` no Fabric, etc. Como o Minecraft 26.x roda com os nomes oficiais da Mojang, o jar
não precisa de remapeamento.

## Versões

| | |
|---|---|
| Minecraft | 26.3 |
| Java | 25+ |
| Loaders | Fabric e NeoForge (jars separados) |
| Easy Building | `marum.easybuilding.client.PlaneMode` (Fabric) / `marum.easybuilding.PlaneMode` (NeoForge) |

## Build

Sem Gradle: `javac` + `jar`.

```powershell
$env:JAVA_HOME = "C:\Program Files\Java\jdk-25"
.\build.ps1                    # fabric + neoforge
.\build.ps1 -Loader fabric
.\build.ps1 -ModVersion 2.0.1
```

Saída:

```
build\fix-easybuilding-fabric-2.0.0.jar
build\fix-easybuilding-neoforge-2.0.0.jar
```

O `build.ps1` procura sozinho os jars necessários para compilar:

| Jar | Onde |
|---|---|
| `minecraft-clientonly-deobf` / `minecraft-common-deobf` | cache do Loom (`%USERPROFILE%\.gradle\caches\fabric-loom\...`) ou `libs\` |
| `sponge-mixin` | cache do Gradle ou `libs\` |
| Easy Building (Fabric) | `..\easy-building-minecraft-mod\easy-building-fabric-26.3\build\libs` ou `libs\` |
| Easy Building (NeoForge) | `libs\` (baixado do Modrinth se não existir) |

Se o Minecraft mapeado não estiver no cache, faça uma build do Easy Building uma vez — o Loom
materializa o `minecraft-clientonly-deobf-26.3.jar` no cache:

```powershell
cd ..\easy-building-minecraft-mod\easy-building-fabric-26.3
.\gradlew.bat build
```

Para instalar, basta colocar o jar do seu loader em `.minecraft\mods` (ou `mods` do cliente).
