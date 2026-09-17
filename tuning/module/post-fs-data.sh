#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Roda antes do zygote: é a única janela segura para redimensionar o zram
# (sem apps usando swap ainda). Só o zram é tocado aqui; o resto do tuning
# é aplicado pelo service.sh depois do boot.

MODDIR=${0%/*}
DATA=/data/adb/khaje4gb
LOG="$DATA/tune.log"
mkdir -p "$DATA" 2>/dev/null

# O init cria o zram0; espera o driver aparecer (até 90 s)
_i=0
while [ ! -e /sys/block/zram0/disksize ] && [ "$_i" -lt 90 ]; do
	sleep 1
	_i=$((_i + 1))
done

# Dá um tempo para o init terminar o swapon inicial antes de mexer
sleep 5

echo "[post-fs-data] $(date) aplicando zram" >> "$LOG" 2>/dev/null
sh "$MODDIR/khaje-tune.sh" zram >> "$LOG" 2>&1
exit 0
