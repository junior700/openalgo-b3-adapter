# Estratégia de patches (herdada do Desktop_Agent_BASE44)

Correções neste projeto seguem a mesma estratégia de patches versionados
e autodestrutivos do Desktop_Agent:

## Ciclo de vida de uma correção

1. **Correção é feita no repositório** (código já corrigido no disco) e
   commitada normalmente — o GitHub é sempre a fonte da verdade.

2. **Um patch é gerado** com o gerador:

   ```bash
   python gerar_patch.py -m "descricao-da-correcao" caminho/arquivo1 ...
   ```

   Isso cria `patches/vNNN_AAAA-MM-DD_HHMM/patch_vNNN_AAAA-MM-DD_HHMM.ps1`
   — um script PowerShell **self-contained** que embute os novos conteúdos
   dos arquivos. O patch é commitado: histórico permanente no git.

3. **Em qualquer instalação replicada** (feita pelo `replicar_github.ps1`),
   o patch é copiado para a raiz e executado:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\patch_vNNN_....ps1
   ```

## O que o patch faz ao ser executado

| Etapa | Ação |
|---|---|
| 0 | Recusa re-aplicação: checa `patches/registro.csv` |
| — | Pede confirmação antes de tocar em qualquer arquivo |
| 1 | Cria `patches/vNNN_data/` |
| 2 | **Backup da versão ANTIGA** de cada arquivo em `<ver>/anteriores/` |
| 3 | Grava os conteúdos novos (UTF-8 sem BOM; arquivo novo = inclusão) |
| 4 | Guarda cópia versionada dos arquivos novos em `<ver>/` |
| 5 | Guarda cópia versionada **de si mesmo** em `<ver>/` |
| 6 | Anexa linha em `patches/registro.csv` (versão; data; arquivos; descrição) |
| 7 | Mostra resumo, espera ENTER e **SE AUTODESTRÓI** |

A cópia versionada permanece em `patches/<ver>/` para rastreio.
**Rollback manual:** copie de volta de `patches/<ver>/anteriores/`.

## Arquivos da estratégia

| Arquivo | Papel |
|---|---|
| `replicar_github.ps1` / `.bat` | Coloque numa pasta raiz genérica: clona (ou atualiza) o projeto do GitHub |
| `gerar_patch.py` | Gera o patch ps1 embutindo os arquivos já corrigidos |
| `patches/registro.csv` | Registro das correções aplicadas (versão; data; arquivos; descrição) |
| `patches/vNNN_.../` | Patch versionado + backups + cópia de si mesmo |

## Regras do projeto (herdadas)

- ASCII puro nos scripts, pausa antes de qualquer saída
- Confirmação antes de tocar em qualquer arquivo
- Token do GitHub **nunca gravado** no `.git/config` (só em memória)
- Nunca `--force` no push
