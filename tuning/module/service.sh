#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Aplica o perfil de tuning depois que o Android terminou de subir.
# Duas passadas: uma assim que o boot completa e outra 60 s depois, porque
# o init/thermal/HAL costumam reescrever alguns valores durante o boot.

MODDIR=${0%/*}
DATA=/data/adb/khaje4gb
LOG="$DATA/tune.log"
mkdir -p "$DATA" 2>/dev/null

# espera o boot completar (até 5 min)
_i=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$_i" -lt 300 ]; do
	sleep 5
	_i=$((_i + 5))
done
sleep 25

echo "[service] $(date) aplicando perfil completo" >> "$LOG" 2>/dev/null
sh "$MODDIR/khaje-tune.sh" >> "$LOG" 2>&1

sleep 60
echo "[service] $(date) reaplicando (pos-boot)" >> "$LOG" 2>/dev/null
sh "$MODDIR/khaje-tune.sh" >> "$LOG" 2>&1
exit 0
