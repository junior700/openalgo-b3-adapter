"""gerar_patch.py: estrategia de patches do Desktop_Agent no adapter."""
import importlib.util
import sys
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "gerar_patch", Path(__file__).parents[1] / "gerar_patch.py")
gerar_patch = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(gerar_patch)


def _make_repo(tmp_path):
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "app.py").write_text("print('novo conteudo')\n")
    (tmp_path / "patches").mkdir()
    return tmp_path


def test_generate_patch_creates_versioned_ps1(tmp_path):
    repo = _make_repo(tmp_path)
    import datetime as dt
    ps1 = gerar_patch.generate_patch(
        ["src/app.py"], "fix-exemplo", repo, repo / "patches",
        now=dt.datetime(2026, 9, 26, 15, 30),
    )
    assert ps1.name == "patch_v001_2026-09-26_1530.ps1"
    assert ps1.parent.name == "v001_2026-09-26_1530"
    script = ps1.read_text(encoding="utf-8")

    # conteudo novo embutido na here-string
    assert '"src\\app.py" = @\'' in script
    assert "novo conteudo" in script
    # etapas da estrategia desktop presentes
    for marker in ["anteriores", "registro.csv", "ROLLBACK MANUAL",
                   "AUTODESTRUI", "$Ver"]:
        assert marker in script
    # autodestruicao literal
    assert "Remove-Item -LiteralPath $PSCommandPath -Force" in script


def test_version_number_increments(tmp_path):
    repo = _make_repo(tmp_path)
    import datetime as dt
    gerar_patch.generate_patch(["src/app.py"], "v1", repo, repo / "patches",
                               now=dt.datetime(2026, 9, 26, 15, 0))
    ps1 = gerar_patch.generate_patch(["src/app.py"], "v2", repo, repo / "patches",
                                     now=dt.datetime(2026, 9, 26, 15, 1))
    assert ps1.parent.name == "v002_2026-09-26_1501"


def test_missing_file_aborts(tmp_path):
    repo = _make_repo(tmp_path)
    with pytest.raises(SystemExit, match="nao encontrado"):
        gerar_patch.generate_patch(["nao_existe.py"], "x", repo, repo / "patches")


def test_here_string_breaker_rejected(tmp_path):
    repo = _make_repo(tmp_path)
    (repo / "src" / "app.py").write_text("linha ok\n'@\nviolacao\n")
    with pytest.raises(SystemExit, match="here-string"):
        gerar_patch.generate_patch(["src/app.py"], "x", repo, repo / "patches")


def test_cli_end_to_end(tmp_path):
    repo = _make_repo(tmp_path)
    rc = gerar_patch.main([
        "-m", "fix-de-teste", "src/app.py",
        "--repo", str(repo), "--out", str(repo / "patches"), "--no-gitadd",
    ])
    assert rc == 0
    dirs = [d.name for d in (repo / "patches").iterdir() if d.is_dir()]
    assert len(dirs) == 1 and dirs[0].startswith("v00")
