# tools/

## po2lmo.py

把 LuCI 的 gettext `.po` 翻译文件编译成 `.lmo` 二进制格式（LuCI 运行时实际加载的格式）。

### 为什么需要它

`luci.mk` 在构建时用 OpenWrt 的 `po2lmo` 工具把 `po/*.po` 编成 `*.lmo`，随
`luci-i18n-<包名>-<语言>` 包装进固件。但：

- 临时验证某个翻译改动时，不想为一行 `.po` 变更跑一整轮固件构建；
- 路由器上没有 `po2lmo`（它是构建期 host 工具，不装进固件）；
- 从源码编 `po2lmo` 需要 `plural_formula.h`，它由 OpenWrt 构建系统在
  `build_dir/host/` 里动态生成，不在 luci 仓库里 —— 单独编译会失败。

所以这里用 Python 复刻了一遍，输出与官方 `po2lmo` **字节级一致**。

### 用法

```bash
python3 tools/po2lmo.py input.po output.lmo
```

例：改完翻译后在路由器上即时生效（不重刷固件）

```bash
python3 tools/po2lmo.py packages/luci-app-kodexplorer/po/zh-cn/kodexplorer.po \
        /tmp/kodexplorer.zh-cn.lmo
scp /tmp/kodexplorer.zh-cn.lmo root@192.168.1.1:/usr/lib/lua/luci/i18n/
ssh root@192.168.1.1 'rm -f /tmp/luci-indexcache*; rm -rf /tmp/luci-modulecache'
```

### 格式说明

lmo 是 LuCI 自有的二进制容器（见 luci `modules/luci-base/src/lib/lmo.h`）：

```
[ msgstr 数据区，每条 4 字节对齐 ]
[ 索引表：n × 16 字节 lmo_entry，大端序 ]
[ 4 字节：索引表相对文件起点的偏移 ]
```

`lmo_entry` 字段（全部大端 uint32）：

| 字段 | 含义 |
|---|---|
| `key_id` | `sfh_hash(规范化后的 msgid)` |
| `val_id` | 复数形式编号 + 1。非复数条目恒为 `1`；`Plural-Forms` 头条目为 `0` |
| `offset` | 本条 msgstr 在文件中的绝对偏移 |
| `length` | msgstr 字节长度（不含对齐填充） |

要点：

- `key_id` 是**哈希值**不是偏移，用 SuperFastHash（`sfh_hash`）；
- 索引必须按 `key_id` 升序，运行时是二分查找；
- msgid 需做空白规范化（连续空白折叠为单空格、去首尾空白）；
- `.po` 头部的 `Plural-Forms:` 行会作为 `key_id=0, val_id=0` 的条目写入。

### 正确性验证

拿一个已发布的包做对照（`luci-app-samba4` 的 `po/zh_Hans/samba4.po` 与固件里
实际的 `samba4.zh-cn.lmo`）：

```
官方 1944B 38条  |  本工具 1944B 38条
key 集合相同: True
完全一致(含 val_id): True
```

即输出与官方 `po2lmo` 字节级相同。
