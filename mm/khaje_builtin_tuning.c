// SPDX-License-Identifier: GPL-2.0
/*
 * Khaje 4GB builtin tuning - no external module needed
 * Applies balanced profile directly in kernel at boot
 *
 * Target: SM6225 (topaz/tapas/sapphire/xun) with 4GB RAM
 * Based on tuning/khaje-tune.sh balanced profile
 *
 * This file is compiled when CONFIG_KHAJE_4GB_BUILTIN_TUNING=y
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/swap.h>
#include <linux/sysctl.h>
#include <linux/writeback.h>
#include <linux/cpufreq.h>
#include <linux/kobject.h>
#include <linux/jiffies.h>
#include <linux/sched.h>
#include <linux/sched/sysctl.h>
#include <linux/tcp.h>

/* externs from other subsystems */
extern int page_cluster;
extern int watermark_scale_factor;
extern int sysctl_vfs_cache_pressure;
extern int vm_swappiness;
extern int dirty_background_ratio;
extern int vm_dirty_ratio;
extern unsigned int sysctl_sched_uclamp_util_min;
extern unsigned int sysctl_sched_uclamp_util_max;

#ifdef CONFIG_LRU_GEN
extern unsigned long lru_gen_min_ttl;
#endif

/* cpufreq tunables - we will set via cpufreq policies */
static void khaje_set_cpufreq_tuning(void)
{
#ifdef CONFIG_CPU_FREQ
	struct cpufreq_policy *policy;
	unsigned int cpu;
	int i = 0;

	for_each_possible_cpu(cpu) {
		policy = cpufreq_cpu_get(cpu);
		if (!policy)
			continue;
		/* Only process each policy once */
		if (policy->cpu != cpu) {
			cpufreq_cpu_put(policy);
			continue;
		}

		/* Ensure max freq is not artificially limited - set to cpuinfo_max */
		if (policy->max < policy->cpuinfo.max_freq)
			policy->max = policy->cpuinfo.max_freq;

		cpufreq_cpu_put(policy);
		i++;
		if (i > 8) /* safety: SM6225 has 8 cores */
			break;
	}
#endif
}

static void khaje_set_zram_tuning(void)
{
#ifdef CONFIG_ZRAM
	pr_info("khaje_builtin: zram default handled in zram_drv.c (60%% RAM, lz4kd)\n");
#endif
}

static int __init khaje_builtin_tuning_init(void)
{
	pr_info("khaje_builtin: applying 4GB balanced tuning (no external module)\n");

	/* VM tunables - balanced profile */
	page_cluster = 0;
	watermark_scale_factor = 120;
	sysctl_vfs_cache_pressure = 130;
	vm_swappiness = 100;
	dirty_background_ratio = 5;
	vm_dirty_ratio = 20;

#ifdef CONFIG_UCLAMP_TASK
	sysctl_sched_uclamp_util_min = 0;
	sysctl_sched_uclamp_util_max = 1024;
#endif

#ifdef CONFIG_LRU_GEN
	WRITE_ONCE(lru_gen_min_ttl, msecs_to_jiffies(1000));
#endif

	khaje_set_cpufreq_tuning();
	khaje_set_zram_tuning();

	pr_info("khaje_builtin: tuning applied: page_cluster=%d watermark=%d vfs_pressure=%d swappiness=%d dirty_bg=%d dirty=%d uclamp_min=%u uclamp_max=%u\n",
		page_cluster, watermark_scale_factor, sysctl_vfs_cache_pressure,
		vm_swappiness, dirty_background_ratio, vm_dirty_ratio,
		sysctl_sched_uclamp_util_min, sysctl_sched_uclamp_util_max);

	return 0;
}

late_initcall(khaje_builtin_tuning_init);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Khaje 4GB builtin tuning - balanced profile without external module");
MODULE_AUTHOR("khaje tuning");
