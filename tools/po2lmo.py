#!/usr/bin/env python3
"""po2lmo — 把 gettext .po 编译成 LuCI 的 .lmo 二进制格式。

严格按 luci 的实现（modules/luci-base/src/po2lmo.c +
modules/luci-lua-runtime/src/template_lmo.c）复刻：

文件布局
    [ msgstr 数据区（每条 4 字节对齐，无分隔符） ]
    [ 索引表：n 条 lmo_entry，每条 16 字节，大端序 ]
    [ 4 字节：索引表相对文件起点的偏移（大端序） ]

lmo_entry 字段（全部大端 uint32）
    key_id   : sfh_hash(规范化后的 msgid)
    val_id   : 复数形式编号 + 1（普通条目恒为 1）
    offset   : 本条 msgstr 数据相对文件起点的绝对偏移
    length   : msgstr 字节长度（不含对齐填充）

注意
    · key_id/val_id 是**哈希值**，不是字符串偏移；
    · 索引按 key_id 升序排列（运行时二分查找）；
    · key 的规范化：空白折叠为单空格、去首尾空白。

方言差异
    luci 运行时 lmo 查找用的是 lmo_canon_hash()，它对 msgid 做了空白规范化。
    .po 里的 msgid 一般已经是规范形式，这里再规范化一次以保持一致。

用法：po2lmo.py input.po output.lmo
"""

import re
import struct
import sys


# --------------------------------------------------------------------------
# SuperFastHash（同 template_lmo.c 里的 sfh_hash）
# --------------------------------------------------------------------------
def _get16(data, off):
    return data[off] | (data[off + 1] << 8)


def sfh_hash(data):
    """返回 32 位无符号哈希。data 为 bytes。"""
    if not data:
        return 0

    length = len(data)
    rem = length & 3
    n = length >> 2
    h = length & 0xFFFFFFFF
    pos = 0

    for _ in range(n):
        h = (h + _get16(data, pos)) & 0xFFFFFFFF
        tmp = ((_get16(data, pos + 2) << 11) ^ h) & 0xFFFFFFFF
        h = ((h << 16) ^ tmp) & 0xFFFFFFFF
        pos += 4
        h = (h + (h >> 11)) & 0xFFFFFFFF

    if rem == 3:
        h = (h + _get16(data, pos)) & 0xFFFFFFFF
        h ^= (h << 16) & 0xFFFFFFFF
        h ^= (_signed8(data[pos + 2]) << 18) & 0xFFFFFFFF
        h = (h + (h >> 11)) & 0xFFFFFFFF
    elif rem == 2:
        h = (h + _get16(data, pos)) & 0xFFFFFFFF
        h ^= (h << 11) & 0xFFFFFFFF
        h = (h + (h >> 17)) & 0xFFFFFFFF
    elif rem == 1:
        h = (h + _signed8(data[pos])) & 0xFFFFFFFF
        h ^= (h << 10) & 0xFFFFFFFF
        h = (h + (h >> 1)) & 0xFFFFFFFF

    # 雪崩
    h ^= (h << 3) & 0xFFFFFFFF
    h = (h + (h >> 5)) & 0xFFFFFFFF
    h ^= (h << 4) & 0xFFFFFFFF
    h = (h + (h >> 17)) & 0xFFFFFFFF
    h ^= (h << 25) & 0xFFFFFFFF
    h = (h + (h >> 6)) & 0xFFFFFFFF

    return h & 0xFFFFFFFF


def _signed8(b):
    return b - 256 if b > 127 else b


def canon_key(msgid):
    """按 lmo_canon_hash 的方式规范化 msgid：空白折叠、去首尾空白。"""
    out = []
    prev_space = True  # 起始时视前一个字符为空白，从而去掉前导空白
    for ch in msgid:
        if ch.isspace():
            if not prev_space:
                out.append(' ')
            prev_space = True
        else:
            out.append(ch)
            prev_space = False
    # 去尾部空白
    while out and out[-1] == ' ':
        out.pop()
    return ''.join(out).encode('utf-8')


# --------------------------------------------------------------------------
# .po 解析
# --------------------------------------------------------------------------
def parse_po(path):
    """返回 (header_plural, [(msgid, msgstr), ...])。

    header_plural 来自 .po 头部 msgid "" 的 msgstr 里的
    `Plural-Forms: nplurals=N; plural=...;` 行 —— luci 会把它作为
    key_id=0 的特殊条目存进 lmo（运行时不用于翻译，但官方 po2lmo 会写入，
    这里保持一致以免与官方产物有差异）。
    """
    entries = []
    msgid = None
    msgstr = None
    header_plural = None
    in_header = False
    mode = None

    def flush():
        nonlocal msgid, msgstr, header_plural, in_header
        if msgid is not None and msgstr is not None:
            if msgid == "" and msgstr != "":
                # 文件头：抽取 Plural-Forms
                for line in msgstr.split("\n"):
                    if line.lower().startswith("plural-forms:"):
                        header_plural = line.split(":", 1)[1].strip()
                        break
            elif msgid != "" and msgstr != "":
                entries.append((msgid, msgstr))
        msgid = msgstr = None

    def unescape(s):
        return (s.replace('\\n', '\n')
                 .replace('\\t', '\t')
                 .replace('\\r', '\r')
                 .replace('\\"', '"')
                 .replace('\\\\', '\\'))

    with open(path, encoding='utf-8', errors='replace') as fh:
        for raw in fh:
            line = raw.rstrip('\n')
            if not line.strip():
                flush()
                mode = None
                continue
            if line.startswith('#'):
                continue

            m = re.match(r'^msgid\s+"(.*)"\s*$', line)
            if m:
                if msgid is not None and msgstr is not None:
                    flush()
                msgid = unescape(m.group(1))
                msgstr = None
                mode = 'id'
                continue

            m = re.match(r'^msgstr\s+"(.*)"\s*$', line)
            if m:
                msgstr = unescape(m.group(1))
                mode = 'str'
                continue

            m = re.match(r'^"(.*)"\s*$', line)
            if m:
                piece = unescape(m.group(1))
                if mode == 'id' and msgid is not None:
                    msgid += piece
                elif mode == 'str' and msgstr is not None:
                    msgstr += piece
                continue

    flush()
    return header_plural, entries


# --------------------------------------------------------------------------
# lmo 构建
# --------------------------------------------------------------------------
def build_lmo(header_plural, entries):
    # 同一 key 保留最后一条
    table = {}
    for k, v in entries:
        table[canon_key(k)] = v.encode('utf-8')

    # 数据区 + 记录
    data_area = bytearray()
    records = []   # (key_id, val_id, offset, length)

    # (1) Plural-Forms 特殊条目（key_id=0, val_id=0），与官方 po2lmo 保持一致
    if header_plural:
        pb = header_plural.encode('utf-8')
        records.append((0, 0, len(data_area), len(pb)))
        data_area += pb
        data_area += b'\0' * ((4 - (len(pb) % 4)) % 4)

    # (2) 普通条目
    for key, val in table.items():
        key_id = sfh_hash(key)
        val_id = sfh_hash(val)
        if key_id == val_id:
            # 与原文一致：key 与 val 哈希相同则跳过（等价于未翻译）
            continue

        offset = len(data_area)
        length = len(val)
        records.append((key_id, 1, offset, length))
        data_area += val
        # 4 字节对齐
        pad = (4 - (length % 4)) % 4
        data_area += b'\0' * pad

    # 索引按 key_id 升序（运行时二分查找）
    records.sort(key=lambda r: r[0])

    out = bytearray()
    out += data_area

    idx_offset = len(out)
    for key_id, val_id, offset, length in records:
        out += struct.pack('>IIII', key_id, val_id, offset, length)

    # 尾随 4 字节：索引表起点
    out += struct.pack('>I', idx_offset)
    return bytes(out)


def main():
    if len(sys.argv) != 3:
        print('Usage: po2lmo.py input.po output.lmo', file=sys.stderr)
        return 1

    header_plural, entries = parse_po(sys.argv[1])
    if not entries:
        print('Error: no translatable entries found', file=sys.stderr)
        return 1

    data = build_lmo(header_plural, entries)
    with open(sys.argv[2], 'wb') as fh:
        fh.write(data)

    print(f'po2lmo: {len(entries)} po entries -> {sys.argv[2]} ({len(data)} bytes)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
