#!/usr/bin/env python3
"""gerar_patch.py - gerador de patches self-contained (estrategia Desktop_Agent).

Estrategia (herdada do Desktop_Agent_BASE44):
  - cada correcao vira uma pasta patches/vNNN_AAAA-MM-DD_HHMM/ com um
    script patch_vNNN_....ps1 que EMBUTE os novos conteudos dos arquivos;
  - ao ser executado na raiz de qualquer instalacao replicada, o ps1:
      0. recusa re-aplicacao (checa patches/registro.csv) e pede confirmacao
      1. cria patches/vNNN_AAAA-MM-DD_HHMM/ (aqui e no destino)
      2. backup dos arquivos ATUAIS em <ver>/anteriores/ (arquivo novo = sem backup)
      3. grava os conteudos corrigidos nos destinos (UTF-8 sem BOM)
      4. guarda copia versionada dos novos em <ver>/
      5. guarda copia versionada DE SI MESMO em <ver>/
      6. anexa uma linha em patches/registro.csv
      7. mostra resumo, espera ENTER e SE AUTODESTRUI (a copia versionada
         em <ver>/ permanece para rastreio/rollback)
  - o ps1 e versionado no git: qualquer outra instalacao replica o projeto
    (replicar_github.ps1) e roda os mesmos patches para ficar identica.

Uso (na raiz do repo, com os arquivos JA CORRIGIDOS no disco):

    python gerar_patch.py -m "descricao-da-correcao" arquivo1 arquivo2 ...

    --repo DIR     raiz do projeto (padrao: pasta deste script)
    --out DIR      onde ficam os patches (padrao: <repo>/patches)
    --no-gitadd    nao executa 'git add' no patch gerado

Saida: patches/vNNN_AAAA-MM-DD_HHMM/patch_vNNN_AAAA-MM-DD_HHMM.ps1

O patch e aplicado na maquina alvo com:

    powershell -ExecutionPolicy Bypass -File .\\patch_vNNN_....ps1
"""
from __future__ import annotations

import argparse
import datetime as _dt
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple

HERE_STRING = "@'"
PS1_TEMPLATE = r"""# ============================================================
# patch.ps1 - aplicador automatico de correcoes
# Projeto: openalgo-b3-adapter
# Versao:  __VER__  |  Arquivos: __N__
# Descricao: __DESC__
#
# COMO USAR (na raiz da instalacao replicada):
#   powershell -ExecutionPolicy Bypass -File .\__PS1__
#
# O QUE ELE FAZ (nesta ordem):
#   0. recusa re-aplicacao (patches\registro.csv) e pede confirmacao
#   1. cria a pasta patches\__VER__\
#   2. backup dos arquivos ATUAIS em __VER__\anteriores\
#      (arquivo novo = inclusao, sem backup)
#   3. grava os arquivos corrigidos nos lugares devidos
#      (UTF-8 sem BOM; cria subpastas se faltar)
#   4. guarda copia versionada dos novos em __VER__\
#   5. guarda copia versionada DE SI MESMO em __VER__\
#   6. anexa uma linha no patches\registro.csv
#   7. mostra o resumo, espera ENTER e SE AUTODESTRUI
#
# RASTREIO: patches\registro.csv guarda versao, data, arquivos e
# resultado. ROLLBACK MANUAL: copie de __VER__\anteriores\.
#
# REGRAS DO PROJETO: pausa antes de qualquer saida, confirmacao
# antes de tocar em qualquer arquivo, token nunca gravado.
# ============================================================

$ErrorActionPreference = "Stop"
$Raiz = $PSScriptRoot
if (-not $Raiz) { $Raiz = (Get-Location).Path }

$Ver  = "__VER__"
$Desc = "__DESC__"

Write-Host ""
Write-Host "=== PATCH AUTOMATICO - openalgo-b3-adapter ===" -ForegroundColor Cyan
Write-Host "Versao: $Ver"
Write-Host "Descricao: $Desc"
Write-Host "Raiz do projeto: $Raiz"
Write-Host ""

# --- 0. recusa re-aplicacao ---
$Registro = Join-Path $Raiz "patches\registro.csv"
if (Test-Path $Registro) {
    $ja = Get-Content $Registro -ErrorAction SilentlyContinue |
          Where-Object { $_ -match "^$Ver;" }
    if ($ja) {
        Write-Host "Patch $Ver JA aplicado (registro.csv). Nada a fazer." -ForegroundColor Yellow
        Read-Host "Pressione ENTER para sair"
        exit 0
    }
}

# --- confirmacao antes de tocar em qualquer arquivo ---
$r = Read-Host "Aplicar este patch? [S/N]"
if ($r -ne "S" -and $r -ne "s") {
    Write-Host "Cancelado. Nenhum arquivo foi tocado."
    Read-Host "Pressione ENTER para sair"
    exit 0
}

# --- pasta da versao ---
$DirVer = Join-Path $Raiz "patches\$Ver"
$DirAnt = Join-Path $DirVer "anteriores"
New-Item -ItemType Directory -Force -Path $DirVer | Out-Null
New-Item -ItemType Directory -Force -Path $DirAnt | Out-Null

# --- arquivos embutidos: destino relativo -> conteudo novo ---
$Arquivos = @{

__PAYLOAD__

}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Alterados = @()
$Incluidos = @()

foreach ($dest in $Arquivos.Keys) {
    $alvo = Join-Path $Raiz $dest
    $dirAlvo = Split-Path $alvo -Parent
    if (-not (Test-Path $dirAlvo)) {
        New-Item -ItemType Directory -Force -Path $dirAlvo | Out-Null
    }
    if (Test-Path $alvo) {
        # 2. backup da versao ATUAL (antiga) antes de sobrescrever
        $bk = Join-Path $DirAnt ($dest -replace "[\\/]", "__")
        Copy-Item -LiteralPath $alvo -Destination $bk -Force
        $Alterados += $dest
    } else {
        $Incluidos += $dest
    }
    # 3. grava o conteudo corrigido (UTF-8 sem BOM)
    [System.IO.File]::WriteAllText($alvo, $Arquivos[$dest], $Utf8NoBom)
    # 4. copia versionada do arquivo novo
    $cp = Join-Path $DirVer ($dest -replace "[\\/]", "__")
    Copy-Item -LiteralPath $alvo -Destination $cp -Force
}

# --- 5. copia versionada de si mesmo ---
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $DirVer "__PS1__") -Force

# --- 6. registro ---
$linha = "$Ver;__DATAHORA__;__ARQUIVOSCSV__;__DESC__`n"
[System.IO.File]::AppendAllText($Registro, $linha, $Utf8NoBom)

# --- 7. resumo + autodestruicao ---
Write-Host ""
Write-Host "========================================"
Write-Host "Patch $Ver aplicado:"
foreach ($a in $Alterados) { Write-Host "  alterado : $a" }
foreach ($a in $Incluidos) { Write-Host "  incluido : $a" }
Write-Host "Backup (versao antiga): patches\$Ver\anteriores\"
Write-Host "Copias versionadas    : patches\$Ver\"
Write-Host "Registro atualizado   : patches\registro.csv"
Write-Host "========================================"
Read-Host "Pressione ENTER para concluir e remover o script"

Remove-Item -LiteralPath $PSCommandPath -Force
Write-Host "Script de patch removido (autodestruicao). Ate logo."
"""


def find_repo_root(start: Path) -> Path:
    """Sobe ate a pasta com .git ou pyproject.toml."""
    cur = start.resolve()
    for cand in [cur, *cur.parents]:
        if (cand / ".git").exists() or (cand / "pyproject.toml").exists():
            return cand
    return start.resolve()


def next_version(patches_dir: Path) -> int:
    """Proximo numero de versao (vNNN) olhando as pastas existentes."""
    mx = 0
    if patches_dir.exists():
        for child in patches_dir.iterdir():
            m = re.match(r"v(\d{3})_", child.name)
            if child.is_dir() and m:
                mx = max(mx, int(m.group(1)))
    return mx + 1


def build_payload(entries: List[Tuple[str, str]]) -> str:
    """Monta a hashtable PS destino -> here-string com o conteudo novo."""
    blocks: List[str] = []
    for dest, content in entries:
        if re.search(r"^'@", content, flags=re.MULTILINE):
            raise SystemExit(
                f"ERRO: '{dest}' contem linha iniciada com '@, que quebra a "
                "here-string do PowerShell. Reescreva esse trecho."
            )
        body = content.rstrip("\n")
        blocks.append(f'    "{dest}" = {HERE_STRING}\n{body}\n\'@')
    return "\n\n".join(blocks)


def generate_patch(
    files: List[str],
    message: str,
    repo_root: Path,
    patches_dir: Path,
    now: _dt.datetime | None = None,
) -> Path:
    """Gera patches/vNNN_data/patch_vNNN_data.ps1 embutindo os arquivos."""
    now = now or _dt.datetime.now()
    num = next_version(patches_dir)
    ver = f"v{num:03d}_{now:%Y-%m-%d_%H%M}"
    ver_dir = patches_dir / ver
    ver_dir.mkdir(parents=True, exist_ok=True)

    entries: List[Tuple[str, str]] = []
    for rel in files:
        p = Path(rel)
        src = p if p.is_absolute() else repo_root / p
        if not src.is_file():
            raise SystemExit(f"ERRO: arquivo nao encontrado: {src}")
        dest = src.resolve().relative_to(repo_root.resolve()).as_posix()
        content = src.read_text(encoding="utf-8")
        entries.append((dest.replace("/", "\\"), content))

    ps1_name = f"patch_{ver}.ps1"
    payload = build_payload(entries)
    script = PS1_TEMPLATE
    for token, value in [
        ("__VER__", ver),
        ("__N__", str(len(entries))),
        ("__DESC__", message),
        ("__PS1__", ps1_name),
        ("__PAYLOAD__", payload),
        ("__DATAHORA__", now.strftime("%Y-%m-%d %H:%M")),
        ("__ARQUIVOSCSV__", "|".join(d for d, _ in entries)),
    ]:
        script = script.replace(token, value)

    ps1_path = ver_dir / ps1_name
    ps1_path.write_text(script, encoding="utf-8")
    return ps1_path


def main(argv: List[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-m", "--message", required=True, help="descricao da correcao")
    ap.add_argument("files", nargs="+", help="arquivos corrigidos (caminhos relativos)")
    ap.add_argument("--repo", default=None, help="raiz do projeto")
    ap.add_argument("--out", default=None, help="pasta de patches")
    ap.add_argument("--no-gitadd", action="store_true", help="nao executa git add")
    args = ap.parse_args(argv)

    repo = Path(args.repo) if args.repo else find_repo_root(Path(__file__).parent)
    patches = Path(args.out) if args.out else repo / "patches"
    ps1 = generate_patch(args.files, args.message, repo, patches)

    print(f"patch gerado: {ps1.relative_to(repo)}")
    print("proximos passos:")
    print("  1. copie o .ps1 para a raiz da instalacao alvo e rode:")
    print(f"     powershell -ExecutionPolicy Bypass -File .\\{ps1.name}")
    print("  2. commite o patch no git (rastreio permanente)")
    if not args.no_gitadd:
        subprocess.run(["git", "add", str(ps1)], cwd=repo, check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
