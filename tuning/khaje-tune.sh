#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# khaje-tune.sh — tuning de runtime para os aparelhos da plataforma khaje
# (SM6225): Redmi Note 12 4G, Note 13 4G NFC e Redmi Pad SE, com 4 GB de RAM.
# Objetivo: fluidez (menos travadas, menos mortes de app) + bateria.
#
# Uso:
#   khaje-tune.sh                    aplica o perfil salvo (default: balanced)
#   khaje-tune.sh smooth             aplica um perfil: battery|balanced|smooth
#   khaje-tune.sh zram [perfil]      ajusta somente o zram (usado no boot)
#   khaje-tune.sh status             mostra os valores atuais
#   khaje-tune.sh reset              volta os valores voláteis ao padrão
#
# Ajustes persistentes ficam em /data/adb/khaje4gb/config.sh (opcional) e o
# perfil escolhido em /data/adb/khaje4gb/profile.
#
# Tudo aqui é volátil: reiniciar o aparelho devolve o estado padrão do kernel
# (o que também torna a reversão trivial).
#
# Variável de ambiente KHAJE_SYS_ROOT permite apontar para uma árvore falsa de
# /sys e /proc (usado pelos testes automatizados; no aparelho fica vazia).

VERSION="1.0.0"

MODDIR=${0%/*}
SYS=${KHAJE_SYS_ROOT:-}
DATA_DIR=${KHAJE_DATA_DIR:-/data/adb/khaje4gb}
CONFIG="$DATA_DIR/config.sh"
PROFILE_FILE="$DATA_DIR/profile"
LOG="$DATA_DIR/tune.log"
LOG_MAX_BYTES=262144

# ---------------------------------------------------------------------------
# Valores padrão (podem ser sobrescritos pelo $CONFIG)
# ---------------------------------------------------------------------------
ZRAM_ENABLE=1                 # 1 = redimensiona e liga o zram
ZRAM_PCT_BATTERY=70
ZRAM_PCT_BALANCED=60
ZRAM_PCT_SMOOTH=50
ZRAM_ALGO_PREF="lz4kd lz4 zstd lzo-rle lzo"
ZRAM_SWAP_PRIORITY=100
ZRAM_MIN_DISKSIZE_MB=512

CPU_GOVERNOR=""               # vazio = mantém o governor atual (schedutil)
CORE_ONLINE=1                 # garante todos os núcleos ligados
EAS_ENABLE=1                  # /proc/sys/kernel/sched_energy_aware

CAP_LITTLE_BATTERY=100        # % da freq máxima do cluster pequeno (battery)
CAP_BIG_BATTERY=85            # % da freq máxima do cluster grande (battery)
CAP_BIG_SMOOTH=100            # % da freq máxima do cluster grande (smooth)

TCP_CC_BATTERY=westwood
TCP_CC_BALANCED=bbr
TCP_CC_SMOOTH=bbr

GPU_ENABLE=1
GPU_PCT_BATTERY=70
GPU_PCT_BALANCED=100
GPU_PCT_SMOOTH=100

IO_SCHED_PREF_BATTERY="mq-deadline kyber bfq none"
IO_SCHED_PREF_BALANCED="ssg mq-deadline kyber bfq none"
IO_SCHED_PREF_SMOOTH="ssg mq-deadline kyber bfq none"
IO_NR_REQUESTS=128

F2FS_IOSTAT=0
WL_BLOCK_EXTRA=""             # ex.: "wlan_wow_wl;qcom_icmpv6" (ver README)
KPROFILES_CONTROL=1           # espelha o perfil em /sys/kernel/kprofiles/kp_mode

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ANDROID_LOG=/system/bin/log
log() {
	_msg="[$(date '+%H:%M:%S')] $*"
	echo "$_msg" >&2
	[ -d "$DATA_DIR" ] && echo "$_msg" >> "$LOG" 2>/dev/null
	# logcat (caminho absoluto de propósito: 'log' é o nome desta função)
	[ -x "$ANDROID_LOG" ] && "$ANDROID_LOG" -t khaje-tune "$*" 2>/dev/null
	return 0
}

trim_log() {
	[ -f "$LOG" ] || return 0
	_size=$(wc -c < "$LOG" 2>/dev/null)
	if [ "${_size:-0}" -gt "$LOG_MAX_BYTES" ] 2>/dev/null; then
		tail -n 400 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
	fi
	return 0
}

# Escreve em um caminho (sysfs/procfs), se ele existir.
wp() {
	_path=$SYS$1; shift
	[ -e "$_path" ] || return 0
	echo "$*" > "$_path" 2>/dev/null || { log "  ! falhou: $1 <- $*"; return 0; }
	return 1
}

# Escreve apenas se o valor atual for diferente (evita locks desnecessários).
wpc() {
	_path=$SYS$1; _want=$2
	[ -e "$_path" ] || return 0
	_cur=$(cat "$_path" 2>/dev/null)
	[ "$_cur" = "$_want" ] && return 0
	echo "$_want" > "$_path" 2>/dev/null || return 0
	return 1
}

# Leitura simples
rp() { cat "$SYS$1" 2>/dev/null; }

sysctl_set() {
	_key=$1; _val=$2
	_path="/proc/sys/$(echo "$_key" | tr '.' '/')"
	[ -e "$SYS$_path" ] || return 0
	wpc "$_path" "$_val"
}

contains_word() { echo " $1 " | grep -q " $2 "; }

ram_kb() { awk '/^MemTotal:/ {print $2}' "$SYS/proc/meminfo" 2>/dev/null; }
ram_mb() { _kb=$(ram_kb); echo $(( ${_kb:-4096} / 1024 )); }

# Primeiro item de $_pref que estiver disponível em $_avail
pick_first() {
	_pref=$1; _avail=$2
	for _s in $_pref; do
		contains_word "$_avail" "$_s" && { echo "$_s"; return 0; }
	done
	return 1
}

# ---------------------------------------------------------------------------
# zram
# ---------------------------------------------------------------------------
apply_zram() {
	[ "$ZRAM_ENABLE" = "1" ] || { log "zram: desabilitado por config"; return 0; }

	_name=""
	for _d in zram0 zram1; do
		[ -e "$SYS/sys/block/$_d/disksize" ] && { _name=$_d; break; }
	done
	[ -n "$_name" ] || { log "zram: dispositivo não encontrado"; return 0; }

	_sys=/sys/block/$_name
	_node=/dev/block/$_name
	[ -e "$SYS$_node" ] || _node=/dev/$_name

	_ram=$(ram_mb)
	_want_mb=$(( _ram * ZRAM_PCT / 100 ))
	[ "$_want_mb" -lt "$ZRAM_MIN_DISKSIZE_MB" ] && _want_mb=$ZRAM_MIN_DISKSIZE_MB

	_avail=$(rp "$_sys/comp_algorithm" | tr -d '[]')
	_algo=$(pick_first "$ZRAM_ALGO_PREF" "$_avail")
	[ -n "$_algo" ] || { _algo=zstd; log "zram: nenhum algoritmo preferido em [$_avail], usando zstd"; }

	_cur_size=$(rp "$_sys/disksize")
	_cur_algo=$(rp "$_sys/comp_algorithm" | tr -d '[] ')
	_want_size=$(( _want_mb * 1024 * 1024 ))

	if [ "${_cur_size:-0}" = "$_want_size" ] && [ "${_cur_algo:-}" = "$_algo" ]; then
		log "zram: já configurado (${_want_mb}M $_algo)"
		_swapped=$(awk -v n="$_node" '$1 == n {print "1"}' "$SYS/proc/swaps" 2>/dev/null)
		[ "$_swapped" = "1" ] || swapon -p "$ZRAM_SWAP_PRIORITY" "$_node" 2>/dev/null
		return 0
	fi

	log "zram: aplicando ${_want_mb}M de ${_ram}M de RAM com $_algo"
	swapoff "$_node" 2>/dev/null
	sleep 0.3
	echo 1 > "$SYS$_sys/reset" 2>/dev/null
	wpc "$_sys/comp_algorithm" "$_algo"
	wpc "$_sys/disksize" "${_want_mb}M"
	if ! swapon -p "$ZRAM_SWAP_PRIORITY" "$_node" 2>/dev/null; then
		log "  ! swapon falhou em $_node"
	fi
	return 0
}

# ---------------------------------------------------------------------------
# VM / memória
# ---------------------------------------------------------------------------
apply_vm() {
	log "vm: swappiness=$VM_SWAPPINESS page-cluster=$VM_PAGE_CLUSTER vfs_cache_pressure=$VM_VFS_CACHE_PRESSURE watermark=$VM_WATERMARK_SCALE"
	sysctl_set vm.swappiness "$VM_SWAPPINESS"
	sysctl_set vm.page-cluster "$VM_PAGE_CLUSTER"
	sysctl_set vm.vfs_cache_pressure "$VM_VFS_CACHE_PRESSURE"
	sysctl_set vm.watermark_scale_factor "$VM_WATERMARK_SCALE"
	sysctl_set vm.min_free_kbytes "$VM_MIN_FREE_KB"
	sysctl_set vm.dirty_background_ratio "$VM_DIRTY_BG_RATIO"
	sysctl_set vm.dirty_ratio "$VM_DIRTY_RATIO"
	sysctl_set vm.stat_interval 1
	sysctl_set vm.panic_on_oom 0        # deixa o lmkd (PSI) decidir
	sysctl_set vm.overcommit_memory 0
	sysctl_set kernel.sched_schedstats 0
}

apply_mglru() {
	[ -e "$SYS/sys/kernel/mm/lru_gen/enabled" ] || { log "mglru: não disponível neste kernel"; return 0; }
	wpc /sys/kernel/mm/lru_gen/enabled y
	wpc /sys/kernel/mm/lru_gen/min_ttl_ms "$MGLRU_MIN_TTL_MS"
	log "mglru: enabled=$(rp /sys/kernel/mm/lru_gen/enabled) min_ttl_ms=$(rp /sys/kernel/mm/lru_gen/min_ttl_ms)"
}

# ---------------------------------------------------------------------------
# CPU: núcleos, EAS, governor, rate limits, clamp e limites de frequência
# ---------------------------------------------------------------------------
apply_cpu() {
	if [ "$CORE_ONLINE" = "1" ]; then
		for _c in "$SYS"/sys/devices/system/cpu/cpu[0-9]*/online; do
			[ -e "$_c" ] || continue
			wpc "${_c#$SYS}" 1
		done
	fi

	[ "$EAS_ENABLE" = "1" ] && wpc /proc/sys/kernel/sched_energy_aware 1

	[ -n "$SCHED_WAKEUP_GRANULARITY_NS" ] && sysctl_set kernel.sched_wakeup_granularity_ns "$SCHED_WAKEUP_GRANULARITY_NS"
	[ -n "$SCHED_MIGRATION_COST_NS" ] && sysctl_set kernel.sched_migration_cost_ns "$SCHED_MIGRATION_COST_NS"
	[ -n "$CLAMP_MIN" ] && sysctl_set kernel.sched_util_clamp_min "$CLAMP_MIN"
	[ -n "$CLAMP_MAX" ] && sysctl_set kernel.sched_util_clamp_max "$CLAMP_MAX"

	# Cluster "grande" = policy com a maior frequência máxima
	_big_pol=""; _big_max=0
	for _p in "$SYS"/sys/devices/system/cpu/cpufreq/policy[0-9]*; do
		[ -e "$_p/cpuinfo_max_freq" ] || continue
		_m=$(cat "$_p/cpuinfo_max_freq" 2>/dev/null)
		if [ "${_m:-0}" -gt "$_big_max" ]; then _big_max=$_m; _big_pol=${_p#$SYS}; fi
	done

	for _p_pref in "$SYS"/sys/devices/system/cpu/cpufreq/policy[0-9]*; do
		[ -e "$_p_pref/scaling_governor" ] || continue
		_p=${_p_pref#$SYS}
		_pol=${_p##*/}

		if [ -n "$CPU_GOVERNOR" ]; then
			_gov=$(rp "$_p/scaling_governor")
			if [ "$_gov" != "$CPU_GOVERNOR" ] && contains_word "$(rp "$_p/scaling_available_governors")" "$CPU_GOVERNOR"; then
				wpc "$_p/scaling_governor" "$CPU_GOVERNOR"
				log "cpu/$_pol: governor -> $CPU_GOVERNOR"
			fi
		fi
		_gov=$(rp "$_p/scaling_governor")

		case "$_gov" in
		schedutil)
			[ -n "$RATE_LIMIT_US" ] && wpc "$_p/schedutil/rate_limit_us" "$RATE_LIMIT_US"
			;;
		schedhorizon)
			[ -n "$UP_RATE_LIMIT_US" ] && wpc "$_p/schedhorizon/up_rate_limit_us" "$UP_RATE_LIMIT_US"
			[ -n "$DOWN_RATE_LIMIT_US" ] && wpc "$_p/schedhorizon/down_rate_limit_us" "$DOWN_RATE_LIMIT_US"
			;;
		esac

		_max=$(rp "$_p/cpuinfo_max_freq")
		[ -n "$_max" ] || continue
		[ "$_p" = "$_big_pol" ] && _pct=$CAP_BIG_PCT || _pct=$CAP_LITTLE_PCT

		if [ -z "$_pct" ] || [ "$_pct" = "100" ]; then
			_want=$_max
		else
			_target=$(( _max * _pct / 100 ))
			_want=$(rp "$_p/scaling_available_frequencies" | tr ' ' '\n' |
				awk -v t="$_target" '$1 <= t {v=$1} END {print v}')
			[ -n "$_want" ] || _want=$_max
		fi
		wpc "$_p/scaling_max_freq" "$_want"
		log "cpu/$_pol: gov=$_gov max=$_want min=$(rp "$_p/scaling_min_freq")"
	done
	return 0
}

apply_cpuidle() {
	[ -n "$CPUIDLE_GOV" ] || return 0
	[ -e "$SYS/sys/devices/system/cpu/cpuidle/current_governor" ] || return 0
	_avail=$(rp /sys/devices/system/cpu/cpuidle/available_governors)
	contains_word "$_avail" "$CPUIDLE_GOV" && wpc /sys/devices/system/cpu/cpuidle/current_governor "$CPUIDLE_GOV"
	return 0
}

# ---------------------------------------------------------------------------
# GPU (kgsl vem do vendor; tudo é opcional)
# ---------------------------------------------------------------------------
apply_gpu() {
	[ "$GPU_ENABLE" = "1" ] || return 0
	_kgsl=/sys/class/kgsl/kgsl-3d0
	[ -d "$SYS$_kgsl" ] || { log "gpu: kgsl não encontrado"; return 0; }

	wpc "$_kgsl/devfreq/governor" msm-adreno-tz

	_all=$(rp "$_kgsl/devfreq/available_frequencies")
	if [ -n "$_all" ] && [ "$GPU_PCT" != "100" ]; then
		_max=$(echo "$_all" | tr ' ' '\n' | sort -n | tail -1)
		_target=$(( _max * GPU_PCT / 100 ))
		_sel=$(echo "$_all" | tr ' ' '\n' | sort -n | awk -v t="$_target" '$1 <= t {v=$1} END {print v}')
		[ -n "$_sel" ] && wpc "$_kgsl/devfreq/max_freq" "$_sel" && log "gpu: max_freq -> $_sel"
	else
		[ -n "$_all" ] && wpc "$_kgsl/devfreq/max_freq" "$(echo "$_all" | tr ' ' '\n' | sort -n | tail -1)"
	fi
	wpc "$_kgsl/min_pwrlevel" 0
	wpc "$_kgsl/force_clk_on" 0
	return 0
}

# ---------------------------------------------------------------------------
# I/O e f2fs
# ---------------------------------------------------------------------------
apply_io() {
	for _q in "$SYS"/sys/block/*; do
		_dev=${_q##*/}
		case "$_dev" in
		loop*|ram*|zram*|dm-*|sr*|mmcblk*boot*|mmcblk*rpmb*) continue ;;
		esac
		[ -e "$_q/queue/scheduler" ] || continue
		_q=${_q#$SYS}

		_avail=$(rp "$_q/queue/scheduler" | tr -d '[]')
		_pick=$(pick_first "$IO_SCHED_PREF" "$_avail")
		[ -n "$_pick" ] && wpc "$_q/queue/scheduler" "$_pick"

		wpc "$_q/queue/iostats" 0
		wpc "$_q/queue/add_random" 0
		wpc "$_q/queue/rotational" 0
		[ -n "$IO_READ_AHEAD_KB" ] && wpc "$_q/queue/read_ahead_kb" "$IO_READ_AHEAD_KB"
		[ -n "$IO_NR_REQUESTS" ] && wpc "$_q/queue/nr_requests" "$IO_NR_REQUESTS"
		[ -n "$IO_RQ_AFFINITY" ] && wpc "$_q/queue/rq_affinity" "$IO_RQ_AFFINITY"
		[ -n "$IO_WBT_LAT_USEC" ] && wpc "$_q/queue/wbt_lat_usec" "$IO_WBT_LAT_USEC"
		log "io/$_dev: sched=$(rp "$_q/queue/scheduler" | tr -d '[]') read_ahead=$(rp "$_q/queue/read_ahead_kb")kB"
	done
	return 0
}

apply_f2fs() {
	for _f in "$SYS"/sys/fs/f2fs/*; do
		[ -d "$_f" ] || continue
		wpc "${_f#$SYS}/iostat_enable" "$F2FS_IOSTAT"
	done
	return 0
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------
apply_net() {
	if [ -n "$TCP_CC" ] && contains_word "$(rp /proc/sys/net/ipv4/tcp_available_congestion_control)" "$TCP_CC"; then
		sysctl_set net.ipv4.tcp_congestion_control "$TCP_CC"
	fi
	sysctl_set net.ipv4.tcp_slow_start_after_idle 0
	sysctl_set net.ipv4.tcp_fastopen 3
	sysctl_set net.ipv4.tcp_fin_timeout 20
	sysctl_set net.core.somaxconn 1024
}

# ---------------------------------------------------------------------------
# Wakelock blocker (boeffla) e kprofiles
# ---------------------------------------------------------------------------
apply_wl() {
	_wl=/sys/class/misc/boeffla_wakelock_blocker/wakelock_blocker
	if [ -n "$WL_BLOCK_EXTRA" ]; then
		wpc "$_wl" "$WL_BLOCK_EXTRA"
		log "wl: lista extra aplicada ($WL_BLOCK_EXTRA)"
	else
		log "wl: mantendo a lista padrão do kernel"
	fi
	return 0
}

apply_kprofiles() {
	[ "$KPROFILES_CONTROL" = "1" ] || return 0
	[ -e "$SYS/sys/kernel/kprofiles/kp_mode" ] || return 0
	wpc /sys/kernel/kprofiles/kp_mode "$KP_MODE"
	log "kprofiles: kp_mode=$KP_MODE"
	return 0
}

# ---------------------------------------------------------------------------
# Perfis
# ---------------------------------------------------------------------------
set_profile_values() {
	case "$1" in
	battery)
		ZRAM_PCT=$ZRAM_PCT_BATTERY
		VM_SWAPPINESS=110; VM_PAGE_CLUSTER=0; VM_VFS_CACHE_PRESSURE=150
		VM_WATERMARK_SCALE=100; VM_MIN_FREE_KB=8192
		VM_DIRTY_BG_RATIO=5; VM_DIRTY_RATIO=20
		MGLRU_MIN_TTL_MS=500
		CLAMP_MIN=0; CLAMP_MAX=1024
		CAP_BIG_PCT=$CAP_BIG_BATTERY; CAP_LITTLE_PCT=$CAP_LITTLE_BATTERY
		RATE_LIMIT_US=4000; UP_RATE_LIMIT_US=2000; DOWN_RATE_LIMIT_US=6000
		SCHED_WAKEUP_GRANULARITY_NS=4000000; SCHED_MIGRATION_COST_NS=1000000
		IO_SCHED_PREF=$IO_SCHED_PREF_BATTERY; IO_READ_AHEAD_KB=128
		IO_RQ_AFFINITY=2; IO_WBT_LAT_USEC=""
		GPU_PCT=$GPU_PCT_BATTERY
		TCP_CC=$TCP_CC_BATTERY; KP_MODE=1; CPUIDLE_GOV=teo
		;;
	smooth)
		ZRAM_PCT=$ZRAM_PCT_SMOOTH
		VM_SWAPPINESS=90; VM_PAGE_CLUSTER=0; VM_VFS_CACHE_PRESSURE=110
		VM_WATERMARK_SCALE=150; VM_MIN_FREE_KB=12288
		VM_DIRTY_BG_RATIO=5; VM_DIRTY_RATIO=20
		MGLRU_MIN_TTL_MS=2000
		CLAMP_MIN=128; CLAMP_MAX=1024
		CAP_BIG_PCT=$CAP_BIG_SMOOTH; CAP_LITTLE_PCT=100
		RATE_LIMIT_US=1000; UP_RATE_LIMIT_US=500; DOWN_RATE_LIMIT_US=2000
		SCHED_WAKEUP_GRANULARITY_NS=2000000; SCHED_MIGRATION_COST_NS=500000
		IO_SCHED_PREF=$IO_SCHED_PREF_SMOOTH; IO_READ_AHEAD_KB=256
		IO_RQ_AFFINITY=2; IO_WBT_LAT_USEC=0
		GPU_PCT=$GPU_PCT_SMOOTH
		TCP_CC=$TCP_CC_SMOOTH; KP_MODE=3; CPUIDLE_GOV=""
		;;
	balanced|*)
		ZRAM_PCT=$ZRAM_PCT_BALANCED
		VM_SWAPPINESS=100; VM_PAGE_CLUSTER=0; VM_VFS_CACHE_PRESSURE=130
		VM_WATERMARK_SCALE=120; VM_MIN_FREE_KB=8192
		VM_DIRTY_BG_RATIO=5; VM_DIRTY_RATIO=20
		MGLRU_MIN_TTL_MS=1000
		CLAMP_MIN=0; CLAMP_MAX=1024
		CAP_BIG_PCT=100; CAP_LITTLE_PCT=100
		RATE_LIMIT_US=2000; UP_RATE_LIMIT_US=1000; DOWN_RATE_LIMIT_US=4000
		SCHED_WAKEUP_GRANULARITY_NS=3000000; SCHED_MIGRATION_COST_NS=750000
		IO_SCHED_PREF=$IO_SCHED_PREF_BALANCED; IO_READ_AHEAD_KB=128
		IO_RQ_AFFINITY=2; IO_WBT_LAT_USEC=""
		GPU_PCT=$GPU_PCT_BALANCED
		TCP_CC=$TCP_CC_BALANCED; KP_MODE=2; CPUIDLE_GOV=teo
		;;
	esac
	return 0
}

# ---------------------------------------------------------------------------
# Status / reset
# ---------------------------------------------------------------------------
show_status() {
	echo "khaje-tune v$VERSION"
	echo "perfil salvo : $(rp_file "$PROFILE_FILE")"
	echo "RAM          : $(ram_mb) MB"
	echo "zram         : $(rp /sys/block/zram0/disksize) bytes, algo=$(rp /sys/block/zram0/comp_algorithm | tr -d '[] ')"
	echo "swap         : $(grep -c . "$SYS/proc/swaps" 2>/dev/null) entrada(s)"
	echo "mglru        : enabled=$(rp /sys/kernel/mm/lru_gen/enabled) min_ttl_ms=$(rp /sys/kernel/mm/lru_gen/min_ttl_ms)"
	echo "vm           : swappiness=$(rp /proc/sys/vm/swappiness) page-cluster=$(rp /proc/sys/vm/page-cluster) vfs=$(rp /proc/sys/vm/vfs_cache_pressure) watermark=$(rp /proc/sys/vm/watermark_scale_factor) min_free=$(rp /proc/sys/vm/min_free_kbytes)"
	for _p_pref in "$SYS"/sys/devices/system/cpu/cpufreq/policy[0-9]*; do
		[ -e "$_p_pref/scaling_governor" ] || continue
		_p=${_p_pref#$SYS}
		echo "cpu ${_p##*/}     : gov=$(rp "$_p/scaling_governor") max=$(rp "$_p/scaling_max_freq") min=$(rp "$_p/scaling_min_freq") rate_limit=$(rp "$_p/schedutil/rate_limit_us")"
	done
	echo "clamp        : min=$(rp /proc/sys/kernel/sched_util_clamp_min) max=$(rp /proc/sys/kernel/sched_util_clamp_max)"
	echo "io           : $(for q in "$SYS"/sys/block/sd* "$SYS"/sys/block/mmcblk*; do [ -e "$q/queue/scheduler" ] && echo "${q##*/}=$(cat "$q/queue/scheduler" 2>/dev/null | tr -d '[]')"; done | tr '\n' ' ')"
	echo "gpu          : max_freq=$(rp /sys/class/kgsl/kgsl-3d0/devfreq/max_freq)"
	echo "kprofiles    : $(rp /sys/kernel/kprofiles/kp_mode)"
	echo "tcp cc       : $(rp /proc/sys/net/ipv4/tcp_congestion_control)"
	echo "cpuidle      : $(rp /sys/devices/system/cpu/cpuidle/current_governor)"
	echo "wl blocker   : $(rp /sys/class/misc/boeffla_wakelock_blocker/wakelock_blocker)"
	echo "pressao mem  : $(tr '\n' ' ' < "$SYS/proc/pressure/memory" 2>/dev/null)"
	echo "wakeups      : $(awk '$1 ~ /^active_since/ {print}' "$SYS/proc/timer_stats" 2>/dev/null)"
}

rp_file() { cat "$1" 2>/dev/null; }

apply_reset() {
	log "reset: devolvendo valores voláteis ao padrão"
	sysctl_set vm.swappiness 100
	sysctl_set vm.page-cluster 3
	sysctl_set vm.vfs_cache_pressure 100
	sysctl_set vm.watermark_scale_factor 10
	sysctl_set vm.dirty_background_ratio 10
	sysctl_set vm.dirty_ratio 20
	wpc /sys/kernel/mm/lru_gen/min_ttl_ms 0
	sysctl_set kernel.sched_util_clamp_min 0
	sysctl_set kernel.sched_util_clamp_max 1024
	for _p in "$SYS"/sys/devices/system/cpu/cpufreq/policy[0-9]*; do
		[ -e "$_p/cpuinfo_max_freq" ] || continue
		wpc "${_p#$SYS}/scaling_max_freq" "$(cat "$_p/cpuinfo_max_freq" 2>/dev/null)"
	done
	for _q in "$SYS"/sys/block/*; do
		[ -e "$_q/queue/scheduler" ] || continue
		case "${_q##*/}" in loop*|ram*|zram*|dm-*) continue ;; esac
		wpc "${_q#$SYS}/queue/scheduler" mq-deadline
	done
	log "reset: ok (reiniciar também restaura tudo)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
mkdir -p "$DATA_DIR" 2>/dev/null

MODE=apply
PROFILE_ARG=""
while [ $# -gt 0 ]; do
	case "$1" in
	status|--status)             MODE=status ;;
	zram|--zram)                 MODE=zram ;;
	reset|--reset)               MODE=reset ;;
	apply|--apply)               MODE=apply ;;
	battery|balanced|smooth)     PROFILE_ARG=$1 ;;
	-h|--help)
		sed -n '3,20p' "$0"
		exit 0
		;;
	*)
		echo "uso: khaje-tune.sh [apply|status|zram|reset] [battery|balanced|smooth]" >&2
		exit 1
		;;
	esac
	shift
done

trim_log
[ -f "$CONFIG" ] && . "$CONFIG" 2>/dev/null

PROFILE=${PROFILE_ARG:-$(rp_file "$PROFILE_FILE")}
PROFILE=${PROFILE:-balanced}

case "$MODE" in
status) show_status; exit 0 ;;
reset)  apply_reset;  exit 0 ;;
esac

set_profile_values "$PROFILE"
log "== khaje-tune v$VERSION: perfil '$PROFILE' (modo: $MODE) =="

if [ "$MODE" = "zram" ]; then
	apply_zram
	log "== zram: concluído =="
	exit 0
fi

echo "$PROFILE" > "$PROFILE_FILE" 2>/dev/null

apply_zram
apply_vm
apply_mglru
apply_cpu
apply_cpuidle
apply_gpu
apply_io
apply_f2fs
apply_net
apply_wl
apply_kprofiles

log "== tuning aplicado (perfil '$PROFILE') =="
log "swap: $(grep zram "$SYS/proc/swaps" 2>/dev/null)"
log "mem: $(awk '/MemTotal|MemAvailable|SwapTotal|SwapFree/ {printf "%s=%dMB ", $1, $2/1024}' "$SYS/proc/meminfo" 2>/dev/null)"

exit 0
