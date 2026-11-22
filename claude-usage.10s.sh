#!/bin/bash
# <xbar.title>Claude Usage</xbar.title>
# <xbar.desc>Uso do Claude Code (sessão 5h e semana) + CPU/RAM</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>

# ---------- Config ----------
CLAUDE_INTERVAL=300          # segundos entre consultas ao Claude (5 min)
CLAUDE_TIMEOUT=90            # segundos máximos para o comando claude responder
CACHE_DIR="$HOME/Library/Caches/claude-usage-swiftbar"
CACHE="$CACHE_DIR/usage.txt"
LOCK="$CACHE_DIR/lock"

export PATH="$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
mkdir -p "$CACHE_DIR"

CLAUDE_BIN="$(command -v claude 2>/dev/null)"

# ---------- Atualiza cache do Claude em segundo plano ----------
now=$(date +%s)
mtime=0
[ -f "$CACHE" ] && mtime=$(stat -f %m "$CACHE" 2>/dev/null || echo 0)

# remove lock travado (mais velho que o timeout)
if [ -d "$LOCK" ]; then
  lt=$(stat -f %m "$LOCK" 2>/dev/null || echo 0)
  [ $((now - lt)) -gt $((CLAUDE_TIMEOUT + 30)) ] && rmdir "$LOCK" 2>/dev/null
fi

if [ "${1:-}" = "refresh" ]; then mtime=0; fi

if [ -n "$CLAUDE_BIN" ] && [ $((now - mtime)) -ge $CLAUDE_INTERVAL ] && mkdir "$LOCK" 2>/dev/null; then
  (
    tmp="$CACHE_DIR/usage.tmp"
    perl -e 'alarm shift; exec @ARGV' "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" -p "/usage" > "$tmp" 2>&1 < /dev/null
    if [ -s "$tmp" ]; then mv "$tmp" "$CACHE"; else rm -f "$tmp"; fi
    rmdir "$LOCK" 2>/dev/null
  ) > /dev/null 2>&1 &
fi

# ---------- Lê e interpreta o cache ----------
S_PCT=""; S_RST=""; W_PCT=""; W_RST=""; RAW=""
if [ -f "$CACHE" ]; then
  RAW="$(LC_ALL=C sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' -e $'s/\r//g' "$CACHE")"
  PARSED="$(printf '%s\n' "$RAW" | awk '
    BEGIN { sec="" }
    {
      low=tolower($0)
      if (low ~ /current session/)                 sec="s"
      else if (low ~ /current week/ && !seenw)    { sec="w"; seenw=1 }
      else if (low ~ /current week/)               sec=""
    }
    sec != "" && $0 ~ /[0-9]+(\.[0-9]+)?%/ && val[sec] == "" {
      match($0, /[0-9]+(\.[0-9]+)?%/); val[sec]=substr($0, RSTART, RLENGTH-1)
    }
    sec != "" && tolower($0) ~ /reset/ && rst[sec] == "" {
      line=$0; sub(/^.*[Rr]esets?[[:space:]]*(in|at|on)?[[:space:]]*/, "", line)
      sub(/[[:space:]]*\([^)]*\)[[:space:]]*$/, "", line); rst[sec]=line
    }
    END { printf "%s\t%s\t%s\t%s\n", val["s"], rst["s"], val["w"], rst["w"] }
  ')"
  S_PCT=$(printf '%s' "$PARSED" | cut -f1)
  S_RST=$(printf '%s' "$PARSED" | cut -f2)
  W_PCT=$(printf '%s' "$PARSED" | cut -f3)
  W_RST=$(printf '%s' "$PARSED" | cut -f4)
fi

color_for() {
  p=${1%%.*}
  [ -z "$p" ] && { echo "#8E8E93"; return; }
  if [ "$p" -ge 80 ]; then echo "#FF453A"
  elif [ "$p" -ge 50 ]; then echo "#FFD60A"
  else echo "#30D158"; fi
}

bar() {
  p=${1%%.*}; [ -z "$p" ] && p=0
  [ "$p" -gt 100 ] && p=100
  n=$(( (p + 5) / 10 )); out=""
  i=0; while [ $i -lt 10 ]; do
    if [ $i -lt $n ]; then out="${out}█"; else out="${out}░"; fi
    i=$((i+1))
  done
  echo "$out"
}

# ---------- Sistema ----------
NCPU=$(sysctl -n hw.ncpu)
CPU=$(ps -A -o %cpu= | awk -v n="$NCPU" '{s+=$1} END {v=s/n; if (v>100) v=100; printf "%.0f", v}')
MEM_TOTAL=$(sysctl -n hw.memsize)
MEM_USED=$(vm_stat | awk -v total="$MEM_TOTAL" '
  /page size of/ { ps=$8 }
  /Pages active/ { a=$3 }
  /Pages wired/  { w=$4 }
  /occupied by compressor/ { c=$5 }
  END { gsub(/\./,"",a); gsub(/\./,"",w); gsub(/\./,"",c);
        used=(a+w+c)*ps; printf "%.1f %.0f %.0f", used/1073741824, total/1073741824, used*100/total }')
MEM_GB=$(echo "$MEM_USED" | cut -d' ' -f1)
MEM_TGB=$(echo "$MEM_USED" | cut -d' ' -f2)
MEM_PCT=$(echo "$MEM_USED" | cut -d' ' -f3)

# ---------- Barra de menus ----------
if [ -n "$S_PCT" ] || [ -n "$W_PCT" ]; then
  max=${S_PCT%%.*}; wv=${W_PCT%%.*}
  [ -z "$max" ] && max=0; [ -n "$wv" ] && [ "$wv" -gt "$max" ] && max=$wv
  echo "✳︎ ${S_PCT:-–}% · ${W_PCT:-–}% | color=$(color_for "$max") font=Menlo size=12"
elif [ -z "$CLAUDE_BIN" ]; then
  echo "✳︎ sem claude | color=#8E8E93"
elif [ ! -f "$CACHE" ]; then
  echo "✳︎ … | color=#8E8E93"
else
  echo "✳︎ ? | color=#FF9F0A"
fi

echo "---"

# ---------- Menu ----------
echo "Claude Code | size=13"
if [ -n "$S_PCT" ]; then
  echo "Sessão 5h   $(bar "$S_PCT")  ${S_PCT}% | font=Menlo size=12 color=$(color_for "$S_PCT")"
  [ -n "$S_RST" ] && echo "   reset: $S_RST | font=Menlo size=11 color=#8E8E93"
fi
if [ -n "$W_PCT" ]; then
  echo "Semana      $(bar "$W_PCT")  ${W_PCT}% | font=Menlo size=12 color=$(color_for "$W_PCT")"
  [ -n "$W_RST" ] && echo "   reset: $W_RST | font=Menlo size=11 color=#8E8E93"
fi
if [ -z "$S_PCT" ] && [ -z "$W_PCT" ]; then
  if [ -z "$CLAUDE_BIN" ]; then
    echo "Comando 'claude' não encontrado no PATH | color=#FF9F0A"
  elif [ ! -f "$CACHE" ]; then
    echo "Consultando o Claude, aguarde… | color=#8E8E93"
  else
    echo "Não consegui ler a saída. Texto bruto: | color=#FF9F0A"
    printf '%s\n' "$RAW" | head -25 | while IFS= read -r l; do
      l=$(printf '%s' "$l" | tr '|' '/')
      [ -n "$l" ] && echo "--$l | font=Menlo size=11"
    done
  fi
fi
if [ -f "$CACHE" ]; then
  age=$(( ( $(date +%s) - $(stat -f %m "$CACHE") ) / 60 ))
  echo "atualizado há ${age} min | size=11 color=#8E8E93"
fi

echo "---"
echo "Sistema | size=13"
echo "CPU         $(bar "$CPU")  ${CPU}% | font=Menlo size=12 color=$(color_for "$CPU")"
echo "RAM         $(bar "$MEM_PCT")  ${MEM_GB}/${MEM_TGB} GB | font=Menlo size=12 color=$(color_for "$MEM_PCT")"
echo "Top processos (CPU) | size=11 color=#8E8E93"
ps -Arceo pcpu=,rss=,comm= | head -5 | awk '{
  cpu=$1; mem=$2/1024; $1=""; $2=""; sub(/^  /,"");
  name=substr($0,1,22); gsub(/\|/,"/",name);
  printf "%-22s %5.1f%%  %5.0f MB | font=Menlo size=11\n", name, cpu, mem }'

echo "---"
echo "Atualizar Claude agora | bash='$0' param1=refresh terminal=false refresh=true"
echo "Monitor de Atividade | bash=/usr/bin/open param1=-a param2='Activity Monitor' terminal=false"
