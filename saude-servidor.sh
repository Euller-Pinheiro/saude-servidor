#!/usr/bin/env bash
# saude-servidor.sh — raio-x de saúde de um servidor Linux (SÓ LEITURA: não instala, não reinicia, não altera nada)
# Uso: sudo bash saude-servidor.sh
#   SAUDE_MARCAS_BACKUP="arq1 arq2"  arquivos tocados (ou com epoch) a cada backup bem-sucedido
#   SAUDE_LOGS_BACKUP="log1 log2"    logs de backup onde procurar ERRO/FALHA
export LC_ALL=C
t() { printf '\n== %s\n' "$*"; }
idade() { local f="$1"; [[ -s "$f" ]] || { echo "nunca"; return; }; local s=$(( $(date +%s) - $(cat "$f" 2>/dev/null || echo 0) )); printf '%dh%02dm atrás' $((s/3600)) $((s%3600/60)); }

echo "################ $(hostname) — $(date '+%Y-%m-%d %H:%M %Z')"
t "Sistema"
. /etc/os-release 2>/dev/null; echo "SO: ${PRETTY_NAME:-?}   kernel: $(uname -r)"
echo "No ar desde: $(uptime -s 2>/dev/null)   carga: $(cut -d' ' -f1-3 /proc/loadavg)"
free -h | awk 'NR<=3'
df -hP -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null | awk 'NR==1 || $5+0>=0'

t "Reinício e atualizações"
if [[ -f /var/run/reboot-required ]]; then echo "REINÍCIO PENDENTE por: $(sort -u /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' ')"; else echo "sem reinício pendente"; fi
up="$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)"
sec="$(apt list --upgradable 2>/dev/null | grep -c -- '-security' || true)"
echo "atualizações pendentes: $up (de segurança: $sec)"
apt list --upgradable 2>/dev/null | grep -E '^(linux-image|docker|containerd|openssh|mariadb|mysql|postgresql|nginx|apache2|php|nodejs|libc6)' | cut -d/ -f1 | head -15 | sed 's/^/  importante: /'
systemctl is-active unattended-upgrades >/dev/null 2>&1 && echo "atualização automática de segurança: ativa" || echo "atualização automática de segurança: INATIVA"

t "Serviços com falha"
systemctl --failed --no-legend --plain 2>/dev/null | awk '{print "  " $1}' | grep . || echo "  nenhum"

t "Docker"
if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then echo "  docker instalado mas o serviço NÃO responde"
elif command -v docker >/dev/null 2>&1; then
    docker ps -a --format '  {{.Names}}  |  {{.Status}}' 2>/dev/null | head -30
    docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -Ei 'unhealthy|restarting|exited' | sed 's/^/  ATENÇÃO: /'
    docker system df 2>/dev/null | sed 's/^/  /'
else echo "  docker não instalado"; fi

t "Backup"
timers="$(systemctl list-timers --all --no-legend 2>/dev/null | grep -iE 'backup|restic' | grep -v dpkg-db-backup || true)"
if [[ -n "$timers" ]]; then
    printf '%s\n' "$timers" | awk '{u=$NF; $NF=""; print "  " u "   próxima: " $1" "$2" "$3}'
    for u in $(printf '%s\n' "$timers" | awk '{print $NF}'); do
        r="$(systemctl show "$u" -p Result --value 2>/dev/null)"; [[ "$r" == success || -z "$r" ]] || echo "  ATENÇÃO: última execução de $u terminou com: $r"
    done
    for st in ${SAUDE_MARCAS_BACKUP:-/var/lib/backup-restic/last-success}; do
        [[ -e "$st" ]] || continue
        if [[ "$(head -c 20 "$st" 2>/dev/null)" =~ ^[0-9]+$ ]]; then s0=$(( $(date +%s) - $(cat "$st") )); else s0=$(( $(date +%s) - $(stat -c %Y "$st") )); fi
        printf '  último backup bem-sucedido: %dh%02dm atrás' $((s0/3600)) $((s0%3600/60))
        (( s0 > 129600 )) && printf '   <- ATRASADO (mais de 36h)'
        echo
    done
    # shellcheck disable=SC2086
    grep -hE 'ERRO|FALHA' ${SAUDE_LOGS_BACKUP:-/var/log/backup-restic.log} 2>/dev/null | tail -3 | sed 's/^/  log: /'
else
    echo "  NENHUM agendamento de backup encontrado neste servidor"
fi

t "Bancos de dados presentes"
for s in mariadb mysql postgresql; do systemctl is-active "$s" >/dev/null 2>&1 && echo "  serviço $s ativo"; done
command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -Ei 'postgres|mysql|mariadb|mongo|redis' | sed 's/^/  contêiner: /'
find /opt /srv /var/lib -maxdepth 4 \( -name '*.sqlite3' -o -name '*.sqlite' -o -name '*.db' \) -size +0 2>/dev/null | grep -v -E '/(node_modules|venv|\.venv|containerd|docker)/' | head -10 | sed 's/^/  arquivo: /'

t "Quedas e reinícios recentes"
last -x reboot shutdown 2>/dev/null | head -6 | sed 's/^/  /'
echo "  -- processos mortos por falta de memória (OOM), últimos 7 dias:"
journalctl -k --since "-7 days" --no-pager 2>/dev/null | grep -iE 'out of memory|oom-kill|killed process' | tail -8 | sed 's/^/  /' | grep . || echo "  nenhum"
echo "  -- erros no fim da sessão anterior (antes do último boot):"
journalctl -b -1 -p err -n 15 --no-pager -q 2>/dev/null | sed 's/^/  /' | grep . || echo "  (sem registro do boot anterior)"

t "Segurança básica"
echo "  logins SSH por senha: $(sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')   root: $(sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')"
echo "  falhas de login SSH nas últimas 24h: $(journalctl -u ssh -u sshd --since '-24 hours' --no-pager 2>/dev/null | grep -c 'Failed password\|Invalid user')"
command -v ufw >/dev/null 2>&1 && echo "  firewall ufw: $(ufw status 2>/dev/null | head -1)"
systemctl is-active fail2ban >/dev/null 2>&1 && echo "  fail2ban: ativo" || echo "  fail2ban: não ativo"
if systemctl is-active -q zabbix-agent2 2>/dev/null || systemctl is-active -q zabbix-agent 2>/dev/null; then echo "  agente Zabbix: ativo"
elif command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qi 'zabbix-agent'; then echo "  agente Zabbix: ativo (em contêiner)"
else echo "  agente Zabbix: NÃO ativo"; fi
echo
