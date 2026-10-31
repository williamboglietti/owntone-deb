#!/usr/bin/env bash
# Dans un conteneur Ubuntu 24.04 : le contrôle doit accepter un binaire x86-64 de base et
# refuser un binaire AVX2 et un binaire SSE4.1. Sans ce test, « aucun SSE4/AVX » ne prouve rien.
set -euo pipefail
apt-get update -qq && apt-get install -y -qq --no-install-recommends gcc libc6-dev binutils >/dev/null 2>&1
mkdir -p /neg/ok /neg/avx /neg/sse4
printf '#include <stdio.h>\nint main(int c,char **v){printf("%%d\\n",c*2);return 0;}\n' > /p.c
printf '#include <immintrin.h>\n#include <stdio.h>\nint main(int c,char **v){float a[8]={c};__m256 x=_mm256_loadu_ps(a);x=_mm256_add_ps(x,x);_mm256_storeu_ps(a,x);printf("%%f\\n",a[0]);return 0;}\n' > /t.c
printf '#include <smmintrin.h>\n#include <stdio.h>\nint main(int c,char **v){__m128i x=_mm_set1_epi32(c);x=_mm_mullo_epi32(x,x);printf("%%d\\n",_mm_extract_epi32(x,0));return 0;}\n' > /s.c
gcc -O2 -march=x86-64 /p.c -o /neg/ok/prog
gcc -O2 -mavx2 /t.c -o /neg/avx/prog
gcc -O2 -msse4.1 /s.c -o /neg/sse4/prog
check=/src/build/check-baseline.sh
"$check" /neg/ok >/dev/null || { echo "binaire de base refusé à tort" >&2; exit 1; }
! "$check" /neg/avx >/dev/null 2>&1 || { echo "binaire AVX2 accepté à tort" >&2; exit 1; }
! "$check" /neg/sse4 >/dev/null 2>&1 || { echo "binaire SSE4.1 accepté à tort" >&2; exit 1; }
echo "check-baseline : de base accepté, AVX2 et SSE4.1 refusés."
