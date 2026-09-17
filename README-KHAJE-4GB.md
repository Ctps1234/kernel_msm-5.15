# Kernel otimizado para 4 GB — khaje (SM6225)

Guia do que foi mudado neste kernel para melhorar **fluidez** e **bateria** nos
aparelhos da plataforma *khaje* com 4 GB de RAM:

* Redmi Note 12 4G (`tapas`/`topaz`)
* Redmi Note 13 4G NFC (`sapphire`/`sapphiren`)
* Redmi Pad SE (`xun`)

As mudanças são de dois tipos:

1. **Configuração de compilação** (o que o kernel traz ligado/desligado) —
   `arch/arm64/configs/khaje_4gb_tuning.fragment`, aplicado em
   `gki_defconfig`, `unified_defconfig` e `khaje-stock_defconfig`.
2. **Tuning em runtime** (o que é ajustado depois do boot) — o módulo
   `tuning/` (`khaje-tune.sh` + módulo Magisk/KernelSU).

---

## 1. Resumo das mudanças de configuração

| Opção | Antes | Depois | Por quê |
|---|---|---|---|
| `CONFIG_KASAN` | y | **n** | KASAN (mesmo na variante HW_TAGS) exige shadow memory e quarentena de objetos liberados, além de hooks em toda alocação. O SM6225 não tem MTE, então na prática ele só pesa. |
| `CONFIG_KFENCE` | y (amostra 500 ms) | **n** | Amostra alocações em runtime e mantém pool próprio; ganho zero em produção. |
| `CONFIG_UBSAN` (+`_TRAP`, `_BOUNDS`, `_ARRAY_BOUNDS`, `_LOCAL_BOUNDS`) | y | **n** | Cada acesso a array do kernel ganha uma checagem. Custo de CPU real em caminhos quentes. |
| `CONFIG_PAGE_OWNER` / `CONFIG_PAGE_PINNER` / `CONFIG_PAGE_EXTENSION` | y / y / y | **n** | `PAGE_EXTENSION` aloca um `struct page_ext` por página física (`page_ext_init()` no boot) ≈ **8 MB em 4 GB**, e o `page_owner` guarda stack traces de páginas. É instrumentação de debug. |
| `CONFIG_DEBUG_LIST` / `CONFIG_BUG_ON_DATA_CORRUPTION` | y | **n** | Checagem de integridade de listas encadeadas nas rotas quentes (inclusive scheduler). |
| `CONFIG_SLUB_DEBUG` | y | **n** | Metadados/checagens de slab que não são usados sem `slub_debug` no cmdline. |
| `CONFIG_SCHEDSTATS` | y | **n** | Contadores de estatística do scheduler atualizados no caminho quente. `SCHED_DEBUG` **continua ligado** (é ele que expõe os tunables em `/proc/sys/kernel/sched_*`). |
| `CONFIG_DEBUG_MUTEXES`, `_SPINLOCK`, `_LOCK_ALLOC`, `_PREEMPT`, `_ATOMIC_SLEEP` | y | **n** | Overhead de debug no locking. |
| `CONFIG_INIT_ON_ALLOC_DEFAULT_ON` | y | **n** | Zera **toda** alocação de memória do kernel (banda de memória + CPU). Continua sendo possível ligar por cmdline (`init_on_alloc=1`). |
| `CONFIG_WERROR` | y (na khaje-stock) | **n** | Evita que um warning do clang quebre o build. |
| `CONFIG_LRU_GEN_ENABLED` | n | **y** | **MGLRU ligado por padrão.** É o item mais importante para 4 GB: reclaim multi-geracional reduz tempo em `lru_lock`, escolhe melhor as páginas a descartar e diminui travadas quando a RAM enche (dados do próprio Google mostram queda grande em ciclos de kswapd e em falhas de página sob pressão). |
| `CONFIG_RCU_LAZY_DEFAULT_OFF` | y | **n** | Callbacks RCU "preguiçosos" por padrão = menos wakeups. *Só tem efeito se o cmdline do boot tiver `rcu_nocbs=all`* (ver §8). |
| `CONFIG_ZRAM` + `CONFIG_CRYPTO_LZ4KD` + `CONFIG_ZRAM_DEF_COMP_LZ4KD` | y + y (lzo-rle em gki/khaje-stock) | y + **lz4kd** | Troca o lzo-rle pelo **lz4kd** (LZ4 com dicionário): mesma ordem de velocidade do lz4 com taxa de compressão melhor — mais RAM efetiva e swap-in mais rápido. |
| `CONFIG_ZSMALLOC_STAT` | n | n (explícito) | Mantido desligado. |
| `CONFIG_F2FS_IOSTAT` | y | **n** | O `/data` é f2fs: o iostat conta cada operação de I/O no caminho quente. |
| `CONFIG_MQ_IOSCHED_SSG` + `MQ_SSG_DEFAULT` | n no gki | **y** | Habilita o scheduler SSG (o mesmo que a MSM usa no `unified_defconfig`) e o deixa como padrão; `mq-deadline`/`bfq` continuam disponíveis para troca em runtime. |
| `CONFIG_WQ_POWER_EFFICIENT_DEFAULT` | n no gki | **y** | Workqueues não-bound usam CPU com eficiência energética. |
| `CONFIG_CPU_IDLE_GOV_TEO` | y | y (explícito) | Mantido ligado (TEO costuma dar melhor bateria que o *menu*); é trocável em runtime. |
| `CONFIG_SCHED_DEBUG`, `CONFIG_UCLAMP_TASK`, `CONFIG_SCHED_THERMAL_PRESSURE`, `CONFIG_ENERGY_MODEL`, `CONFIG_SCHED_MC` | y | y (explícito) | Precisam continuar ligados: são eles que dão os tunables de runtime e o EAS. |
| `CONFIG_KALLSYMS`, `CONFIG_TMPFS_XATTR`, `CONFIG_TMPFS_POSIX_ACL` | parcial | **y** | O que o workflow de build já injetava (necessário para KernelSU/SUSFS e para apps que usam xattr). |

### O que foi **de propósito** deixado como está

* **`CONFIG_HZ`** (250 no gki/khaje-stock, 300 no unified): mudar HZ altera
  conversões de tempo compiladas nos módulos do vendor. O ganho seria marginal
  e o risco não compensa.
* **`CONFIG_TRANSPARENT_HUGEPAGE`** continua em `MADVISE` — `always` aumenta uso
  de RAM e causa pausas de compactação.
* **`CONFIG_HARDENED_USERCOPY`, `CONFIG_FORTIFY_SOURCE`, `CONFIG_SLAB_FREELIST_RANDOM/HARDENED`,
  SELinux, dm-verity/AVB**: ficam ligados. São baratos e mexem em segurança.
* **Termal** (`msm_thermal`, limites de temperatura): não foi tocado. Limitar
  temperatura é proteção do aparelho.
* **Tamanho de frequência/voltagem**: nenhuma mudança de clock por padrão (só o
  perfil `battery` do tuning limita a frequência máxima, e de forma reversível).
* **KMI/KernelSU**: nada de ABI. O workflow continua desligando o *KMI
  enforcement*; os módulos do vendor (kgsl, WLAN etc.) continuam carregando.

> Se você **desenvolve** kernel e precisa de KASAN/KFENCE/UBSAN, use o
> `gki_defconfig` original (sem o fragmento) para os seus testes. Em uso
> normal, essa instrumentação só custa CPU/RAM.

> `gki_defconfig` é compartilhado com outros alvos que existem nesta árvore
> (kalama, waipio, bengal...). Se um dia você voltar a compilar para eles a
> partir deste fork, lembre que o bloco do khaje 4 GB também estará lá —
> remova o bloco (§7) ou use os defconfigs específicos daquele alvo.

---

## 2. Como compilar

### GitHub Actions (o seu builder)

1. Aba **Actions** → workflow **Build kernels** → **Run workflow**.
2. Preencha:

   | Campo | Valor |
   |---|---|
   | Kernel source URL | `https://github.com/Ctps1234/kernel_msm-5.15` |
   | Kernel branch | `arena/01a0ac9b-kernel-msm-5.15` |
   | Device (defconfig) | `unified` (recomendado) — também vale `gki` ou `khaje-stock` |
   | Custom localversion | `-khaje4gb` (opcional, aparece no `uname -r`) |
   | Build KSU variant | o que você já usa (`both`, `ksu` ou `noksu`) |

3. Baixe o ZIP (AnyKernel3) e faça flash pelo recovery / KernelSU.

Os três defconfigs já foram atualizados, então **qualquer** valor de *Device*
que você use pega o tuning (as mudanças são as mesmas nos três arquivos).

### Build local (dentro do checkout do kernel + manifest do ACK)

```sh
LTO=thin \
BUILD_CONFIG=common/build.config.gki.aarch64 \
build/build.sh -j$(nproc)
```

### Validar a configuração sem compilar

O script `scripts/local/kconfig_check.py` usa o mesmo parser do Kconfig para
mostrar o valor **efetivo** de cada opção depois de aplicar um defconfig:

```sh
python3 scripts/local/kconfig_check.py arch/arm64/configs/unified_defconfig /tmp/syms.txt
```

(Limitação: opções que dependem de recursos do compilador — `LTO`, `CFI`,
`ARM64_MTE`, `ARM64_LSE_ATOMICS` — são avaliadas com o GCC do host e por isso
aparecem como "n" nesse relatório; no build real, com clang, elas continuam
ligadas.)

---

## 3. Como instalar o tuning de runtime

O kernel otimizado já ajuda sozinho, mas é no runtime que dá para ajustar o zram,
o MGLRU, as frequências e o I/O conforme o seu uso.

```sh
sh tuning/build-module.sh      # gera tuning/dist/khaje-4gb-tuning-v1.0.0.zip
```

Instale esse ZIP como **módulo** no Magisk/KernelSU/APatch e reinicie.

* `post-fs-data.sh` redimensiona o zram antes do sistema subir.
* `service.sh` aplica o resto 25 s depois do boot e reaplica 60 s depois
  (para vencer o init/thermal, que reescrevem alguns valores).

### Trocar de perfil na hora

```sh
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh smooth'    # mais resposta
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh balanced'  # equilíbrio
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh battery'   # mais autonomia
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh status'    # ver valores atuais
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh reset'     # voltar ao padrão
```

O perfil escolhido fica salvo em `/data/adb/khaje4gb/profile` e é reaplicado em
todo boot. O log fica em `/data/adb/khaje4gb/tune.log`.

### Ajustes finos

`/data/adb/khaje4gb/config.sh` (criado na instalação a partir de
`tuning/module/config.example.sh`) sobrescreve qualquer valor do script —
tamanho do zram, algoritmo, limites de frequência, lista extra de wakelocks etc.

---

## 4. O que cada perfil faz

| Ajuste | `battery` | `balanced` (padrão) | `smooth` |
|---|---|---|---|
| zram (tamanho) | 70 % da RAM | 60 % da RAM | 50 % da RAM |
| zram (algoritmo) | lz4kd | lz4kd | lz4kd |
| `vm.swappiness` | 110 | 100 | 90 |
| `vm.page-cluster` | 0 | 0 | 0 |
| `vm.vfs_cache_pressure` | 150 | 130 | 110 |
| `vm.watermark_scale_factor` | 100 | 120 | 150 |
| MGLRU `min_ttl_ms` | 500 | 1000 | 2000 |
| `sched_util_clamp_min` | 0 | 0 | 128 |
| `schedutil/rate_limit_us` | 4000 | 2000 | 1000 |
| freq. máx. do cluster grande | 85 % | 100 % | 100 % |
| GPU (freq. máx.) | 70 % | 100 % | 100 % |
| scheduler de I/O | mq-deadline | ssg | ssg |
| `read_ahead_kb` (UFS) | 128 | 128 | 256 |
| WBT (`wbt_lat_usec`) | padrão | padrão | 0 |
| TCP congestion control | westwood | bbr | bbr |
| governador de idle | teo | teo | padrão |
| kprofiles (`kp_mode`) | 1 | 2 | 3 |

Observações:

* `page-cluster=0` faz o swap-in do zram ler 1 página por vez em vez de 8 —
  menos latência e menos trabalho inútil (o zram é memória, não disco).
* `min_ttl_ms` do MGLRU protege o *working set*: quanto maior, menos o sistema
  descarta páginas quentes (menos "reabrir o app"). `smooth` usa 2000 ms.
* O perfil `battery` limita a frequência máxima do cluster grande, mas os
  núcleos pequenos continuam livres — a maior parte do uso do dia a dia roda
  neles.
* Tudo é volátil: **reiniciar restaura o padrão do kernel**.

---

## 5. Como verificar se o kernel está otimizado

O `unified_defconfig` mantém `CONFIG_IKCONFIG_PROC=y`, então dá para ler a
configuração real do kernel em execução:

```sh
su -c 'zcat /proc/config.gz | grep -E "KASAN|KFENCE|UBSAN|PAGE_OWNER|PAGE_EXTENSION|LRU_GEN_ENABLED|ZRAM_DEF_COMP|F2FS_IOSTAT|MQ_SSG_DEFAULT|INIT_ON_ALLOC"'
```

Esperado:

```
# CONFIG_KASAN is not set
# CONFIG_KFENCE is not set
# CONFIG_UBSAN is not set
# CONFIG_PAGE_OWNER is not set
# CONFIG_PAGE_EXTENSION is not set
# CONFIG_INIT_ON_ALLOC_DEFAULT_ON is not set
CONFIG_LRU_GEN_ENABLED=y
CONFIG_ZRAM_DEF_COMP="lz4kd"
CONFIG_MQ_SSG_DEFAULT=y
# CONFIG_F2FS_IOSTAT is not set
```

Depois do boot, com o módulo instalado:

```sh
su -c 'cat /sys/kernel/mm/lru_gen/enabled'          # 0x0007 (ligado)
su -c 'cat /sys/block/zram0/disksize'               # ~2,2 GB (60% de 3,7 GB)
su -c 'cat /sys/block/zram0/comp_algorithm'         # [lz4kd] ...
su -c 'cat /proc/sys/vm/swappiness'                 # 100
su -c 'cat /proc/swaps'                             # zram0 ativo
su -c 'sh /data/adb/modules/khaje4gb/khaje-tune.sh status'
```

---

## 6. Como medir o ganho (sem enganação)

Todas as mudanças são de *overhead* e de política de memória — o ganho aparece
como **menos travadas e menos mortes de app**, e não como um número de
benchmark bonito. Sugestão de medição antes/depois (mesmo uso, mesmo tempo de
tela):

```sh
# pressão de memória (quanto menor, melhor) — deixe rodando e compare médias
su -c 'cat /proc/pressure/memory'

# eficiência do zram: compr_data_size / orig_data_size
su -c 'cat /sys/block/zram0/mm_stat'

# trocas de contexto/latência do scheduler
su -c 'cat /proc/schedstat | head -3'

# jank por app
adb shell dumpsys gfxinfo com.seu.app | grep -i jank

# bateria (mAh consumidos e tempo estimado)
adb shell dumpsys batterystats --charged | head -40

# wakelocks que mais acordam a CPU (root)
su -c 'cat /sys/kernel/debug/wakeup_sources | sort -k6 -n -r | head -15'
```

Dicas de leitura:

* `full avg10` do `pressure/memory` alto = o sistema está travando por falta de
  RAM; MGLRU + zram maior derrubam isso.
* Se a bateria piorar no perfil `balanced`, teste `battery`; se travar, teste
  `smooth` (ou aumente `VM_WATERMARK_SCALE`).

---

## 7. Reverter

**Tuning de runtime:** desinstale o módulo no Magisk/KernelSU (ou
`rm -rf /data/adb/modules/khaje4gb`) e reinicie. Nada mais fica no sistema —
todos os ajustes são em sysfs/sysctl.

**Configuração do kernel:** o bloco aplicado fica no fim de cada defconfig e
começa na linha marcadora. Para remover:

```sh
sed -i '/===== Khaje 4GB: fluidez + bateria/,$d' \
  arch/arm64/configs/gki_defconfig \
  arch/arm64/configs/unified_defconfig \
  arch/arm64/configs/khaje-stock_defconfig
```

Ou simplesmente `git revert` do commit que aplicou as mudanças e compile de novo.

---

## 8. Limites, riscos e letras miúdas

* **Sem instrumentação de debug** (KASAN/KFENCE/UBSAN/PAGE_OWNER) você perde
  detectores de corrupção. Isso não afeta o modelo de segurança do Android
  (SELinux, verificação de boot, dm-verity continuam intactos), mas se algo
  estranho acontecer no kernel, o diagnóstico fica mais difícil. Para
  depurar, builde o defconfig original.
* **`RCU_LAZY`**: só faz efeito se o cmdline tiver `rcu_nocbs=all`. Confira com
  `cat /proc/cmdline`. Sem isso, a opção simplesmente não muda nada.
* **Wakelock blocker** (`/sys/class/misc/boeffla_wakelock_blocker/`): o kernel já
  bloqueia por padrão a lista de wakelocks "lixo" da QTI (`qcom_rx_wakelock`,
  `IPA_*`, `DIAG_WS`, `RMNET_*`, `rmnet_ctl`, `hal_bluetooth_lock`). Adicionar
  `wlan*`/`NETLINK` pode **atrasar notificações** com a tela apagada — deixei
  essa lista extra vazia de propósito.
* **zram grande + swappiness alto** sempre troca CPU por RAM. Em jogos pesados
  ou multitarefa extrema, o perfil `smooth` (zram menor, watermark maior) tende
  a dar resposta melhor; o `battery` prioriza memória disponível.
* Se a ROM reconfigurar o zram depois do boot (raro), o módulo reaplica 60 s
  depois; confira com `cat /sys/block/zram0/disksize`.
* Alvos com 6 GB (variantes `sapphire`?) também funcionam, mas o script calcula
  o zram em % da RAM — não há nada fixo em "4 GB".

---

## 9. Arquivos envolvidos

| Arquivo | O que é |
|---|---|
| `arch/arm64/configs/khaje_4gb_tuning.fragment` | O delta de configuração, documentado linha a linha |
| `arch/arm64/configs/{gki,unified,khaje-stock}_defconfig` | Defconfigs com o fragmento aplicado no fim |
| `tuning/khaje-tune.sh` | Aplicador de tuning em runtime (perfis + `status`/`reset`) |
| `tuning/module/` | Módulo Magisk/KernelSU (`module.prop`, `service.sh`, `post-fs-data.sh`, ...) |
| `tuning/build-module.sh` | Roda os testes e empacota o ZIP do módulo |
| `tuning/tests/fake-root-test.sh` | Testes automatizados do tuning usando `/sys` e `/proc` falsos |
| `scripts/local/kconfig_check.py` | Valida um defconfig usando o parser real do Kconfig |

---

## 10. Próximos passos opcionais (não incluídos)

* Adicionar `rcu_nocbs=all` ao cmdline (via `CONFIG_CMDLINE_EXTEND` ou editando
  o boot.img) para o `RCU_LAZY` valer de fato.
* Trocar o CFS por um scheduler alternativo (você já tem o fork do **BORE**):
  BORE + MGLRU é uma combinação popular para fluidez em aparelhos de entrada.
* Usar `zstd` no zram (`ZRAM_ALGO_PREF="zstd lz4kd"`) se o objetivo for a maior
  economia de RAM possível, aceitando compressão mais cara.
* Um `profile` automático por app (ex.: modo `smooth` quando o jogo está em
  primeiro plano) usando `service.sh` + `dumpsys` — dá para fazer no módulo.
