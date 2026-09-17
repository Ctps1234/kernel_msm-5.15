#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Instalador do módulo (Magisk / KernelSU / APatch).

SKIPUNZIP=0

ui_print "- Khaje 4GB Tuning"
ui_print "- Perfis: battery | balanced (padrao) | smooth"
ui_print "- Ajustes em /data/adb/khaje4gb/config.sh"

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in khaje-tune.sh service.sh post-fs-data.sh uninstall.sh; do
	[ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
[ -f "$MODPATH/config.example.sh" ] && set_perm "$MODPATH/config.example.sh" 0 0 0755

DATA=/data/adb/khaje4gb
mkdir -p "$DATA" 2>/dev/null
if [ ! -f "$DATA/config.sh" ] && [ -f "$MODPATH/config.example.sh" ]; then
	cp -f "$MODPATH/config.example.sh" "$DATA/config.sh" 2>/dev/null
	ui_print "- Criado $DATA/config.sh (tudo comentado = padroes)"
fi
if [ ! -f "$DATA/profile" ]; then
	echo balanced > "$DATA/profile" 2>/dev/null
	ui_print "- Perfil inicial: balanced"
fi

ui_print "- Instale o kernel com o defconfig otimizado (khaje_4gb_tuning)"
ui_print "- Reinicie para aplicar"
