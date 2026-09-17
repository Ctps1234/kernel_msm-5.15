#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""
Validador de defconfig usando kconfiglib (mesmo parser do Kconfig do kernel).

Uso:
    python3 scripts/local/kconfig_check.py <defconfig> <lista_de_simbolos>

- Carrega o Kconfig da raiz do kernel, aplica o defconfig informado exatamente
  como o "make <defconfig>" faria e imprime o valor final de cada CONFIG_
  listado no arquivo de simbolos (um por linha; '#' inicia comentario).
- Avisa tambem sobre simbolos inexistentes no Kconfig (typo / opcao removida).

Detalhes:
- Usa o compilador do host apenas para os testes de $(cc-option) do Kconfig;
  o objetivo e validar simbolos, nao capacidades de toolchain.
- Aplica automaticamente um patch em uma copia do kconfiglib instalado para
  aceitar a propriedade "modules" (Linux 5.16+), que a versao do PyPI ainda
  nao entende. Nada e alterado no repositorio do kernel.
"""
import os
import shutil
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# O Kconfig do kernel usa $(srctree), $(CC) e $(LD) para checar o compilador.
os.environ.setdefault("ARCH", "arm64")
os.environ.setdefault("SRCARCH", os.environ["ARCH"])
os.environ.setdefault("srctree", REPO)
os.environ.setdefault("CC", "gcc")
os.environ.setdefault("LD", "ld")
os.environ.setdefault("CLANG_FLAGS", "")


def _import_patched_kconfiglib():
    """Importa kconfiglib ensinando-o a aceitar a propriedade 'modules'."""
    import kconfiglib as original

    src = original.__file__
    with open(src) as f:
        code = f.read()

    marker = "            elif t0 is _T_MODULES:\n                pass\n"
    if "elif t0 is _T_MODULES" not in code.split("_parse_props")[1][:6000]:
        anchor = "            elif t0 is _T_DEPENDS:\n"
        if anchor not in code:
            print("aviso: nao foi possivel aplicar o patch do 'modules'")
            return original
        patch = (
            "            elif t0 is _T_MODULES:\n"
            "                # Propriedade 'modules' avulsa (Linux 5.16+). Só\n"
            "                # afeta se tristate pode ser 'm' com MODULES=n;\n"
            "                # irrelevante para validar defconfig. Ignorada.\n"
            "                pass\n"
        )
        code = code.replace(anchor, patch + anchor, 1)

    path = os.path.join(tempfile.mkdtemp(prefix="klib-"), "kconfiglib.py")
    with open(path, "w") as f:
        f.write(code)

    sys.path.insert(0, os.path.dirname(path))
    import importlib

    importlib.invalidate_caches()
    sys.modules.pop("kconfiglib", None)
    return importlib.import_module("kconfiglib")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1

    defconfig, syms_file = sys.argv[1], sys.argv[2]
    kconfiglib = _import_patched_kconfiglib()

    with open(syms_file) as f:
        wanted = [l.strip() for l in f if l.strip() and not l.startswith("#")]

    kconf = kconfiglib.Kconfig(os.path.join(REPO, "Kconfig"), warn=False)
    kconf.load_config(os.path.join(REPO, defconfig))

    missing, out = [], []
    for sym in wanted:
        base = sym[7:] if sym.startswith("CONFIG_") else sym
        node = kconf.syms.get(base)
        if node is None:
            missing.append(base)
            continue
        val = node.str_value
        out.append(f"{base}={val if val else 'n'}")

    print(f"# defconfig: {defconfig}  ({len(wanted)} simbolos)")
    for line in out:
        print(line)
    if missing:
        print("# SIMBOLOS INEXISTENTES NO KCONFIG:")
        for m in missing:
            print(f"#   {m}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
