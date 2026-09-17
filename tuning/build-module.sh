#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Empacota o módulo de tuning (Magisk / KernelSU / APatch) e roda os testes.
#
# Uso:  sh tuning/build-module.sh
# Saída: tuning/dist/khaje-4gb-tuning-<versao>.zip

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
VER=$(sed -n 's/^version=//p' "$HERE/module/module.prop" | head -1)
OUT="$HERE/dist/khaje-4gb-tuning-${VER}.zip"

echo "== rodando testes =="
sh "$HERE/tests/fake-root-test.sh"

echo
echo "== empacotando $OUT =="
rm -rf "$HERE/dist"
mkdir -p "$HERE/dist/stage"

# O zip do módulo tem os arquivos na raiz
cp "$HERE/module/module.prop" "$HERE/module/customize.sh" \
	"$HERE/module/post-fs-data.sh" "$HERE/module/service.sh" \
	"$HERE/module/uninstall.sh" "$HERE/module/config.example.sh" \
	"$HERE/dist/stage/"
cp "$HERE/khaje-tune.sh" "$HERE/dist/stage/"

( cd "$HERE/dist/stage" && zip -q -r9 "$OUT" . -x '.*' )
rm -rf "$HERE/dist/stage"

echo "ok: $OUT"
unzip -l "$OUT" 2>/dev/null || true
