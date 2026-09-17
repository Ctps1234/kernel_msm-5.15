# SPDX-License-Identifier: GPL-2.0
#
# Overrides do khaje-tune.sh. Copiado para /data/adb/khaje4gb/config.sh na
# instalação do módulo: tudo que estiver comentado usa o padrão do script.
# Edite, salve e rode:  sh /data/adb/modules/khaje4gb/khaje-tune.sh balanced
#
# ATENÇÃO: valores agressivos aqui podem causar travamentos ou consumo maior.
# Teste um por um e mantenha uma cópia deste arquivo.

# ---------------------------------------------------------------- zram
# 1 = redimensiona/religa o zram; 0 = não mexe
#ZRAM_ENABLE=1
# Tamanho em % da RAM total, por perfil
#ZRAM_PCT_BATTERY=70
#ZRAM_PCT_BALANCED=60
#ZRAM_PCT_SMOOTH=50
# Ordem de preferência do algoritmo (o primeiro disponível é usado)
#ZRAM_ALGO_PREF="lz4kd lz4 zstd lzo-rle lzo"
#ZRAM_SWAP_PRIORITY=100

# ---------------------------------------------------------------- CPU
# Deixe vazio para manter o governor do kernel (schedutil)
#CPU_GOVERNOR=""
# Limite da frequência máxima do cluster grande no perfil battery (%)
#CAP_BIG_BATTERY=85
# Limite da frequência máxima quando o perfil smooth está ativo (raise p/ fps)
#CAP_BIG_SMOOTH=100
# Garantir todos os núcleos ligados
#CORE_ONLINE=1
# EAS ligado
#EAS_ENABLE=1

# ---------------------------------------------------------------- GPU
#GPU_ENABLE=1
# Limite da frequência máxima da GPU no perfil battery (%)
#GPU_PCT_BATTERY=70

# ---------------------------------------------------------------- I/O
#IO_NR_REQUESTS=128
# Desliga o iostat do f2fs (0 = desligado)
#F2FS_IOSTAT=0

# ---------------------------------------------------------------- rede
#TCP_CC_BATTERY=westwood
#TCP_CC_BALANCED=bbr
#TCP_CC_SMOOTH=bbr

# ---------------------------------------------------------------- wakelocks
# Lista extra para o boeffla wakelock blocker (separada por ';').
# O kernel já bloqueia por padrão: qcom_rx_wakelock, IPA_*, DIAG_WS,
# RMNET_DFC, RMNET_SHS, rmnet_ctl, rmnet_ipa%d, hal_bluetooth_lock.
# Bloquear wakelocks de WLAN pode atrasar notificações com a tela apagada.
#WL_BLOCK_EXTRA=""

# ---------------------------------------------------------------- kprofiles
# 1 = espelha o perfil em /sys/kernel/kprofiles/kp_mode (1=bateria,
# 2=balanceado, 3=performance). Só tem efeito se algum módulo do vendor
# consultar o kprofiles (por padrão, não).
#KPROFILES_CONTROL=1
