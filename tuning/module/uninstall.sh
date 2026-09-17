#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Nada precisa ser restaurado: todo o tuning é volátil (sysfs/sysctl).
# Um reboot devolve o kernel ao estado padrão.

echo "[khaje4gb] modulo removido; reinicie para voltar ao padrao" >> /data/adb/khaje4gb/tune.log 2>/dev/null
exit 0
