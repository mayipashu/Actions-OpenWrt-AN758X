#!/bin/sh
# H3C HM2004-DU 四核亲和 v2 —— 修复: 独立计数器 + /proc/interrupts 匹配
# v1 的 bug: phy0-0 与 qdma_eth 共用 idx，68 个 qdma 把计数推走，
#            phy0-0 取模错乱全堆一个核; /proc/irq/*/actions 在本机
#            内核不存在（中断名是子目录），硬中断匹配全部落空。
idx_phy=0
idx_qdma=0
for pid in $(ls /proc | grep "^[0-9]*$" | sort -n); do
    [ -r "/proc/$pid/comm" ] || continue
    read -r cname < "/proc/$pid/comm" 2>/dev/null || continue
    case "$cname" in
        mt76-tx*)
            taskset -p 8 "$pid" >/dev/null 2>&1
            ;;
        napi/phy0-0)
            case $((idx_phy % 6)) in
                0|1|2) mask=2 ;;
                3|4|5) mask=4 ;;
            esac
            taskset -p "$mask" "$pid" >/dev/null 2>&1
            idx_phy=$((idx_phy + 1))
            ;;
        napi/qdma_eth-0)
            case $((idx_qdma % 3)) in
                0) mask=2 ;;
                1) mask=4 ;;
                2) mask=8 ;;
            esac
            taskset -p "$mask" "$pid" >/dev/null 2>&1
            idx_qdma=$((idx_qdma + 1))
            ;;
    esac
done
# 硬中断亲和：解析 /proc/interrupts（末列为中断名，首列为 IRQ 号）
while IFS=":" read -r irq rest; do
    irq=$(echo "$irq" | tr -d " ")
    case "$irq" in ""|*[!0-9]*) continue ;; esac
    name=$(echo "$rest" | awk "{print \$NF}")
    case "$name" in
        airoha_eth.4)  echo 4 > /proc/irq/$irq/smp_affinity 2>/dev/null ;; # CPU2
        mt7915e-hif)   echo 2 > /proc/irq/$irq/smp_affinity 2>/dev/null ;; # CPU1
        mt7915e)       echo 8 > /proc/irq/$irq/smp_affinity 2>/dev/null ;; # CPU3
    esac
done < /proc/interrupts
