#!/bin/sh
# ============================================================
# H3C HM2004-DU 四核软中断亲和 —— 移植自 wuziwei/ponwrt-ZN504-HG5585F
# 并按实机中断表适配（MT7915+MT7916 双芯片 + qdma_eth 队列）
#
# 实机基线（2026-11-19）：
#   IRQ 17 airoha_eth.0    —— 控制面，低频
#   IRQ 21 airoha_eth.4    —— QDMA/转发主中断，275M 次，全压 CPU0
#   IRQ 47 mt7915e-hif     —— MT7916 HIF，4M 次
#   IRQ 55 mt7915e         —— MT7915 主核 MSI，6.7M 次
#   线程: mt76-tx phy0 / napi/phy0-0(6) / napi/qdma_eth-0(68)
#
# 策略：
#   CPU0 留给 timer/控制面
#   mt76-tx phy0   → CPU3（独占，发送不跟收包抢核）
#   napi/phy0-0    → 轮流 CPU1/2（WiFi 收包软中断打散）
#   napi/qdma_eth-0 → 轮流 CPU1/2/3（PON/有线转发软中断打散）
#   airoha_eth.4(IRQ21) → CPU2（转发主中断独立）
#   mt7915e-hif(IRQ47)  → CPU1
#   mt7915e(IRQ55)      → CPU3
# ============================================================
idx=0
for pid in $(ls /proc | grep '^[0-9]*$' | sort -n); do
    [ -r "/proc/$pid/comm" ] || continue
    read -r cname < "/proc/$pid/comm" 2>/dev/null || continue
    case "$cname" in
        mt76-tx*)
            # 发送线程独占 CPU3
            taskset -p 8 "$pid" >/dev/null 2>&1
            ;;
        napi/phy0-0)
            # WiFi 收包：CPU1/2 轮流
            case $((idx % 6)) in
                0|1|2) mask=2 ;;
                3|4|5) mask=4 ;;
            esac
            taskset -p "$mask" "$pid" >/dev/null 2>&1
            idx=$((idx + 1))
            ;;
        napi/qdma_eth-0)
            # PON/有线转发：CPU1/2/3 三核轮流（CPU0 留给控制面）
            case $((idx % 3)) in
                0) mask=2 ;;
                1) mask=4 ;;
                2) mask=8 ;;
            esac
            taskset -p "$mask" "$pid" >/dev/null 2>&1
            idx=$((idx + 1))
            ;;
    esac
done

# 硬中断亲和：用实际 IRQ 名匹配（比固定数字更稳）
for irq_dir in /proc/irq/*; do
    [ -d "$irq_dir" ] || continue
    irq=$(basename "$irq_dir")
    case "$irq" in
        ''|*[!0-9]*) continue ;;
    esac
    name=$(cat "$irq_dir/actions" 2>/dev/null | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]].*//' | head -1)
    case "$name" in
        airoha_eth.4)
            echo 4 > "$irq_dir/smp_affinity" 2>/dev/null   # CPU2
            ;;
        mt7915e-hif)
            echo 2 > "$irq_dir/smp_affinity" 2>/dev/null   # CPU1
            ;;
        mt7915e)
            echo 8 > "$irq_dir/smp_affinity" 2>/dev/null   # CPU3
            ;;
    esac
done
