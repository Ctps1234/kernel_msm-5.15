#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Testa o khaje-tune.sh em uma árvore falsa de /sys e /proc, sem precisar de
# aparelho. Roda em qualquer Linux com sh (POSIX).
#
# Uso: sh tuning/tests/fake-root-test.sh
set -u

SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)
TUNE="$SRC_DIR/khaje-tune.sh"
ROOT=${TMPDIR:-/tmp}/khaje-fake
DATA=${TMPDIR:-/tmp}/khaje-data
FAIL=0

msg()  { printf '%-58s %s\n' "$1" "$2"; }
ok()   { msg "$1" "OK"; }
bad()  { msg "$1" "FALHOU (esperado: $2, obtido: $3)"; FAIL=$((FAIL+1)); }

# Valor de um "arquivo de sysfs" da árvore falsa
val() { cat "$ROOT$1" 2>/dev/null; }
chk() {
	_v=$(val "$1")
	[ "$_v" = "$2" ] && ok "$1 = $2" || bad "$1" "$2" "$_v"
}

build_tree() {
	rm -rf "$ROOT" "$DATA"
	mkdir -p "$DATA"

	# proc
	mkdir -p "$ROOT/proc/sys/vm" "$ROOT/proc/sys/kernel" "$ROOT/proc/sys/net/ipv4" \
		"$ROOT/proc/sys/net/core" "$ROOT/proc/pressure"
	cat > "$ROOT/proc/meminfo" <<-EOF
	MemTotal:        3800000 kB
	MemFree:          500000 kB
	MemAvailable:    1500000 kB
	SwapTotal:       2280000 kB
	SwapFree:        2280000 kB
	EOF
	printf 'Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n/dev/block/zram0                         partition\t2280000\t\t0\t\t100\n' > "$ROOT/proc/swaps"
	printf 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n' > "$ROOT/proc/pressure/memory"
	echo 100 > "$ROOT/proc/sys/vm/swappiness"
	echo 3   > "$ROOT/proc/sys/vm/page-cluster"
	echo 100 > "$ROOT/proc/sys/vm/vfs_cache_pressure"
	echo 10  > "$ROOT/proc/sys/vm/watermark_scale_factor"
	echo 4096 > "$ROOT/proc/sys/vm/min_free_kbytes"
	echo 10  > "$ROOT/proc/sys/vm/dirty_background_ratio"
	echo 20  > "$ROOT/proc/sys/vm/dirty_ratio"
	echo 1   > "$ROOT/proc/sys/vm/stat_interval"
	echo 0   > "$ROOT/proc/sys/vm/panic_on_oom"
	echo 0   > "$ROOT/proc/sys/vm/overcommit_memory"
	echo 0   > "$ROOT/proc/sys/kernel/sched_schedstats"
	echo 1   > "$ROOT/proc/sys/kernel/sched_energy_aware"
	echo 0   > "$ROOT/proc/sys/kernel/sched_util_clamp_min"
	echo 1024 > "$ROOT/proc/sys/kernel/sched_util_clamp_max"
	echo 4000000 > "$ROOT/proc/sys/kernel/sched_wakeup_granularity_ns"
	echo 500000  > "$ROOT/proc/sys/kernel/sched_migration_cost_ns"
	echo cubic > "$ROOT/proc/sys/net/ipv4/tcp_congestion_control"
	echo "reno cubic westwood bbr" > "$ROOT/proc/sys/net/ipv4/tcp_available_congestion_control"
	echo 1 > "$ROOT/proc/sys/net/ipv4/tcp_slow_start_after_idle"
	echo 1 > "$ROOT/proc/sys/net/ipv4/tcp_fastopen"
	echo 60 > "$ROOT/proc/sys/net/ipv4/tcp_fin_timeout"
	echo 128 > "$ROOT/proc/sys/net/core/somaxconn"

	# zram / bloco / f2fs
	mkdir -p "$ROOT/sys/block/zram0" "$ROOT/sys/block/sda/queue" "$ROOT/sys/fs/f2fs/sda32"
	echo 0 > "$ROOT/sys/block/zram0/disksize"
	echo "lzo-rle lz4 lz4hc lz4kd zstd [lzo-rle]" > "$ROOT/sys/block/zram0/comp_algorithm"
	echo 0 > "$ROOT/sys/block/zram0/reset"
	echo "[mq-deadline] kyber bfq none ssg" > "$ROOT/sys/block/sda/queue/scheduler"
	for f in iostats add_random rotational read_ahead_kb nr_requests rq_affinity wbt_lat_usec; do
		case $f in
		iostats|add_random|rotational) echo 1 > "$ROOT/sys/block/sda/queue/$f" ;;
		read_ahead_kb) echo 128 > "$ROOT/sys/block/sda/queue/$f" ;;
		nr_requests)   echo 64  > "$ROOT/sys/block/sda/queue/$f" ;;
		rq_affinity)   echo 1   > "$ROOT/sys/block/sda/queue/$f" ;;
		wbt_lat_usec)  echo 2000 > "$ROOT/sys/block/sda/queue/$f" ;;
		esac
	done
	echo 1 > "$ROOT/sys/fs/f2fs/sda32/iostat_enable"

	# memória / tuning do kernel
	mkdir -p "$ROOT/sys/kernel/mm/lru_gen" "$ROOT/sys/kernel/kprofiles" \
		"$ROOT/sys/class/misc/boeffla_wakelock_blocker" \
		"$ROOT/sys/class/kgsl/kgsl-3d0/devfreq" \
		"$ROOT/sys/devices/system/cpu/cpufreq/policy0/schedutil" \
		"$ROOT/sys/devices/system/cpu/cpufreq/policy4/schedutil" \
		"$ROOT/sys/devices/system/cpu/cpuidle"
	echo 0 > "$ROOT/sys/kernel/mm/lru_gen/enabled"
	echo 0 > "$ROOT/sys/kernel/mm/lru_gen/min_ttl_ms"
	echo 2 > "$ROOT/sys/kernel/kprofiles/kp_mode"
	echo "qcom_rx_wakelock;IPA_WS" > "$ROOT/sys/class/misc/boeffla_wakelock_blocker/wakelock_blocker"
	echo msm-adreno-tz > "$ROOT/sys/class/kgsl/kgsl-3d0/devfreq/governor"
	echo "180000000 305000000 430000000 550000000 650000000 780000000" > "$ROOT/sys/class/kgsl/kgsl-3d0/devfreq/available_frequencies"
	echo 780000000 > "$ROOT/sys/class/kgsl/kgsl-3d0/devfreq/max_freq"
	echo 5 > "$ROOT/sys/class/kgsl/kgsl-3d0/min_pwrlevel"
	echo 1 > "$ROOT/sys/class/kgsl/kgsl-3d0/force_clk_on"

	# cpufreq: policy0 = 6x A55, policy4 = 2x A78
	echo schedutil > "$ROOT/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"
	echo "performance powersave schedutil schedhorizon" > "$ROOT/sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors"
	echo 2000000 > "$ROOT/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq"
	echo 2000000 > "$ROOT/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
	echo 300000  > "$ROOT/sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq"
	echo "300000 576000 768000 1017600 1248000 1516800 1804800 2000000" > "$ROOT/sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies"
	echo 1000 > "$ROOT/sys/devices/system/cpu/cpufreq/policy0/schedutil/rate_limit_us"
	cp "$ROOT/sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors" "$ROOT/sys/devices/system/cpu/cpufreq/policy4/scaling_available_governors"
	echo schedutil > "$ROOT/sys/devices/system/cpu/cpufreq/policy4/scaling_governor"
	echo 2400000 > "$ROOT/sys/devices/system/cpu/cpufreq/policy4/cpuinfo_max_freq"
	echo 2400000 > "$ROOT/sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq"
	echo 300000  > "$ROOT/sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq"
	echo "300000 768000 1228800 1632000 2016000 2208000 2400000" > "$ROOT/sys/devices/system/cpu/cpufreq/policy4/scaling_available_frequencies"
	echo 1000 > "$ROOT/sys/devices/system/cpu/cpufreq/policy4/schedutil/rate_limit_us"
	echo teo > "$ROOT/sys/devices/system/cpu/cpuidle/current_governor"
	echo "menu teo" > "$ROOT/sys/devices/system/cpu/cpuidle/available_governors"
	for c in 0 1 2 3 4 5 6 7; do
		mkdir -p "$ROOT/sys/devices/system/cpu/cpu$c"
		echo 1 > "$ROOT/sys/devices/system/cpu/cpu$c/online"
	done
}

run() { KHAJE_SYS_ROOT="$ROOT" KHAJE_DATA_DIR="$DATA" sh "$TUNE" "$@" >/dev/null 2>&1; }

# O kernel real sempre imprime a lista completa de schedulers com o ativo
# entre colchetes ao ler queue/scheduler; o arquivo falso guarda apenas o
# valor escrito, então restauramos o formato antes de cada cenário.
reset_sched() { echo "[mq-deadline] kyber bfq none ssg" > "$ROOT/sys/block/sda/queue/scheduler"; }

build_tree

# ---------------------------------------------------------------- balanced
reset_sched
run balanced
chk /sys/block/zram0/disksize           "$(( 3800000 / 1024 * 60 / 100 ))M"
chk /sys/block/zram0/comp_algorithm     lz4kd
chk /proc/sys/vm/swappiness             100
chk /proc/sys/vm/page-cluster           0
chk /proc/sys/vm/vfs_cache_pressure     130
chk /proc/sys/vm/watermark_scale_factor 120
chk /proc/sys/vm/min_free_kbytes        8192
chk /proc/sys/vm/dirty_background_ratio 5
chk /sys/kernel/mm/lru_gen/enabled      y
chk /sys/kernel/mm/lru_gen/min_ttl_ms   1000
chk /proc/sys/kernel/sched_util_clamp_min 0
chk /sys/devices/system/cpu/cpufreq/policy0/schedutil/rate_limit_us 2000
chk /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2000000
chk /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq 2400000
chk /proc/sys/net/ipv4/tcp_congestion_control bbr
chk /sys/block/sda/queue/scheduler      ssg
chk /sys/block/sda/queue/read_ahead_kb  128
chk /sys/block/sda/queue/iostats        0
chk /sys/fs/f2fs/sda32/iostat_enable    0
chk /sys/kernel/kprofiles/kp_mode       2
chk /sys/devices/system/cpu/cpuidle/current_governor teo
[ "$(cat "$DATA/profile")" = "balanced" ] && ok "perfil salvo = balanced" || bad "perfil salvo" balanced "$(cat "$DATA/profile" 2>/dev/null)"

# ----------------------------------------------------------------- battery
reset_sched
run battery
chk /sys/block/zram0/disksize           "$(( 3800000 / 1024 * 70 / 100 ))M"
chk /proc/sys/vm/swappiness             110
chk /proc/sys/vm/vfs_cache_pressure     150
chk /sys/kernel/mm/lru_gen/min_ttl_ms   500
chk /sys/devices/system/cpu/cpufreq/policy0/schedutil/rate_limit_us 4000
chk /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq 2016000
chk /proc/sys/net/ipv4/tcp_congestion_control westwood
chk /sys/block/sda/queue/scheduler      mq-deadline
chk /sys/kernel/kprofiles/kp_mode       1

# ------------------------------------------------------------------ smooth
reset_sched
run smooth
chk /sys/block/zram0/disksize           "$(( 3800000 / 1024 * 50 / 100 ))M"
chk /proc/sys/vm/swappiness             90
chk /proc/sys/kernel/sched_util_clamp_min 128
chk /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq 2400000
chk /sys/devices/system/cpu/cpufreq/policy0/schedutil/rate_limit_us 1000
chk /sys/block/sda/queue/read_ahead_kb  256
chk /sys/kernel/kprofiles/kp_mode       3

# ------------------------------------------------------------------- reset
reset_sched
run reset
chk /proc/sys/vm/swappiness             100
chk /proc/sys/vm/page-cluster           3
chk /sys/kernel/mm/lru_gen/min_ttl_ms   0
chk /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq 2400000
chk /proc/sys/kernel/sched_util_clamp_min 0

# ------------------------------------------------------------------ status
if KHAJE_SYS_ROOT="$ROOT" KHAJE_DATA_DIR="$DATA" sh "$TUNE" status 2>/dev/null | grep -q "khaje-tune v"; then
	ok "status imprime cabecalho"
else
	bad "status" "cabecalho" "sem saida"
fi

echo
if [ "$FAIL" = "0" ]; then
	echo "todos os testes passaram"
else
	echo "$FAIL teste(s) falharam"
fi
exit "$FAIL"
