#!/usr/bin/env bash
# Refuse un binaire contenant des instructions AVX ou SSE4.1/4.2 : l'AMD E1-1200 les ignore
# et le programme s'arrêterait avec « instruction illégale ». Heuristique sur le désassemblage.
set -euo pipefail
root="${1:?répertoire à contrôler}"
pattern='\b(ymm[0-9]+|zmm[0-9]+|v(add|sub|mul|mov|xor|and|or|perm|broadcast|pxor|pcmp|pshuf|padd|psub|insert|extract)[a-z0-9]*|pcmp[ei]str[im]|pblendvb|blendv(pd|ps)|ptest|pminu?[dw]|pmaxu?[dw]|pmulld|pextr[bdq]|pinsr[bdq]|round[sp][sd]|dpp[sd]|crc32[bwlq]?)\b'
found=0
while IFS= read -r f; do
  head -c 4 "$f" | grep -q 'ELF' || continue
  if hits="$(objdump -d --no-show-raw-insn "$f" 2>/dev/null | grep -E "^\s+[0-9a-f]+:\s+$pattern" | head -5)" && [ -n "$hits" ]; then
    echo "Instruction hors x86-64 de base dans $f :" >&2
    echo "$hits" >&2
    found=1
  fi
done < <(find "$root" -type f \( -perm -u+x -o -name '*.so*' \))
[ "$found" -eq 0 ] && echo "Contrôle x86-64 de base : aucun SSE4/AVX."
exit "$found"
