# tuning/ — tuning de runtime para khaje (4 GB)

Complemento do kernel otimizado (`README-KHAJE-4GB.md`). Aqui mora tudo que é
ajustado **depois do boot**: tamanho/algoritmo do zram, MGLRU, VM, frequências,
scheduler, I/O, rede e (opcional) wakelocks.

```
tuning/
├── khaje-tune.sh                # o aplicador (perfis battery|balanced|smooth)
├── build-module.sh              # testa + empacota o ZIP do módulo
├── module/                      # esqueleto do módulo Magisk/KernelSU/APatch
│   ├── module.prop
│   ├── customize.sh
│   ├── post-fs-data.sh          # zram, antes do zygote
│   ├── service.sh               # resto do tuning, depois do boot
│   ├── uninstall.sh
│   └── config.example.sh
└── tests/fake-root-test.sh      # testes com /sys e /proc falsos
```

## Instalação

```sh
sh tuning/build-module.sh            # roda os testes e gera o ZIP
```

O ZIP sai em `tuning/dist/khaje-4gb-tuning-vX.Y.Z.zip`. Instale como módulo no
Magisk/KernelSU/APatch e reinicie.

## Uso no dia a dia

```sh
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh status'    # ver tudo
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh smooth'    # trocar perfil
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh zram'      # só o zram
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh reset'     # padrão do kernel
```

* Perfil ativo: `/data/adb/khaje4gb/profile`
* Log: `/data/adb/khaje4gb/tune.log`
* Overrides: `/data/adb/khaje4gb/config.sh` (veja `module/config.example.sh`)

## Perfis (valores completos)

| Ajuste | battery | balanced | smooth |
|---|---|---|---|
| zram | 70 % da RAM | 60 % | 50 % |
| swappiness | 110 | 100 | 90 |
| page-cluster | 0 | 0 | 0 |
| vfs_cache_pressure | 150 | 130 | 110 |
| watermark_scale_factor | 100 | 120 | 150 |
| min_free_kbytes | 8192 | 8192 | 12288 |
| dirty_background_ratio / dirty_ratio | 5 / 20 | 5 / 20 | 5 / 20 |
| MGLRU min_ttl_ms | 500 | 1000 | 2000 |
| sched_util_clamp_min / max | 0 / 1024 | 0 / 1024 | 128 / 1024 |
| schedutil rate_limit_us | 4000 | 2000 | 1000 |
| schedhorizon up/down (se for o governor) | 2000 / 6000 | 1000 / 4000 | 500 / 2000 |
| sched_wakeup_granularity_ns | 4 ms | 3 ms | 2 ms |
| sched_migration_cost_ns | 1 ms | 0,75 ms | 0,5 ms |
| freq. máx. cluster grande | 85 % | 100 % | 100 % |
| GPU freq. máx. | 70 % | 100 % | 100 % |
| I/O scheduler | mq-deadline | ssg | ssg |
| read_ahead_kb | 128 | 128 | 256 |
| wbt_lat_usec | padrão | padrão | 0 |
| TCP cc | westwood | bbr | bbr |
| cpuidle | teo | teo | padrão |
| kprofiles kp_mode | 1 | 2 | 3 |

## Segurança do script

* Só escreve onde o arquivo existe **e** é gravável: nada de paths fixos
  assumidos — funciona em ROMs diferentes, com/sem kgsl, com/sem boeffla.
* Evita reescrever valor igual (`wpc`) para não pegar lock à toa.
* O zram só é redimensionado em `post-fs-data` (antes de existir app usando
  swap); `swapoff` → `reset` → `comp_algorithm` → `disksize` → `swapon`.
* Todos os ajustes são voláteis: reboot = padrão do kernel.

## Adicionar um ajuste novo

1. Ponha o valor padrão no topo do `khaje-tune.sh` (e documente no
   `module/config.example.sh`).
2. Escolha o valor em cada perfil dentro de `set_profile_values()`.
3. Aplique dentro da função correspondente (`apply_vm`, `apply_cpu`, `apply_io`,
   `apply_gpu`, ...) usando `wpc`/`sysctl_set`.
4. Rode os testes: `sh tuning/tests/fake-root-test.sh`. Se o ajuste for novo,
   adicione o arquivo falso correspondente em `tests/fake-root-test.sh`
   (função `build_tree`) e a asserção no perfil desejado.

## Compatibilidade

* Testado em shell POSIX (roda igual em `mksh` do Android e em `dash` do Linux).
* Requer root (o módulo Magisk/KernelSU já roda como root).
* Sem o kernel otimizado o script continua funcionando, mas recursos como
  MGLRU ligado por padrão e o zram em lz4kd dependem da configuração de
  compilação (`khaje_4gb_tuning.fragment`).
