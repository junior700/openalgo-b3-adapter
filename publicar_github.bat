@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM publicar_github.bat - Git Add/Commit/Push Automatico
REM Convencao herdada do Desktop_Agent_BASE44 (v2):
REM   1) TOKEN NUNCA gravado no .git/config: push usa a URL com
REM      token so em memoria; remote origin fica limpo
REM   2) baixa novidades ANTES de empurrar (evita push rejeitado)
REM   3) NUNCA usa --force
REM   4) identidade git local configurada se faltar
REM   5) distingue "nada a commitar" de erro real de commit
REM ============================================================

set "REPO_LIMPO=https://github.com/junior700/openalgo-b3-adapter.git"
set "TOKENFILE=token_github.txt"

cd /d "%~dp0"
echo ========================================
echo   Git Add/Commit/Push Automatico
echo   (openalgo-b3-adapter)
echo ========================================
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo ERRO: git nao encontrado. Instale em https://git-scm.com
    pause
    exit /b 1
)

REM identidade local se faltar
git config user.name  >nul 2>&1 || git config user.name "junior700"
git config user.email >nul 2>&1 || git config user.email "hrdfjmaris@gmail.com"

REM token (arquivo local NUNCA versionado; usado apenas em memoria)
set "TOKEN="
if exist "%TOKENFILE%" (
    set /p TOKEN=<"%TOKENFILE%"
)
if "%TOKEN%"=="" (
    echo AVISO: %TOKENFILE% ausente - push usara credenciais do git.
    set "PUSHURL=%REPO_LIMPO%"
) else (
    set "PUSHURL=https://%TOKEN%@github.com/junior700/openalgo-b3-adapter.git"
)

set /p MSG="Mensagem de commit: "

git add -A
git diff --cached --quiet >nul 2>&1
if not errorlevel 1 (
    echo Nada a commitar. Apenas sincronizando com o GitHub...
    goto sync
)

git commit -m "%MSG%"
if errorlevel 1 (
    echo ERRO no commit. Revertendo staged...
    git reset >nul 2>&1
    pause
    exit /b 1
)

:sync
git fetch %REPO_LIMPO% main 2>nul
if exist .git\refs\remotes\origin\main git merge origin/main -m "merge: sincronizacao automatica" 2>nul
git push "%PUSHURL%" main --tags
if errorlevel 1 (
    echo.
    echo ERRO no push. Verifique token/rede e rode de novo.
    pause
    exit /b 1
)
echo.
echo Pronto. Repositorio atualizado.
pause
