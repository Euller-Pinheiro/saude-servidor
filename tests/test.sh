#!/usr/bin/env bash
# Testes do saude-servidor.sh: roda no servidor real do CI e com systemctl/backup simulados.
# shellcheck disable=SC2034
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/saude-servidor.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
f=0; ok() { if eval "$2"; then echo "  [ok]    $1"; else echo "  [FALHA] $1"; f=$((f+1)); fi; }

echo "1. Servidor real (só leitura)"
antes="$(find /etc /usr/local/bin -newer "$S" -type f 2>/dev/null | wc -l)"
bash "$S" > "$T/real.out" 2>"$T/real.err"; rc=$?
ok "termina sem erro"                         '[[ $rc -eq 0 ]]'
for sec in Sistema "Reinício e atualizações" "Serviços com falha" Docker Backup "Bancos de dados presentes" "Quedas e reinícios recentes" "Segurança básica"; do
    ok "seção: $sec"                          "grep -q '^== $sec' '$T/real.out'"
done
ok "nada é escrito em /etc ou /usr/local/bin" '[[ "$(find /etc /usr/local/bin -newer "$S" -type f 2>/dev/null | wc -l)" == "$antes" ]]'
ok "sem erros de sintaxe/comando no stderr"   '! grep -qiE "syntax error|command not found|unbound variable" "$T/real.err"'

echo "2. Backup simulado"
mkdir -p "$T/bin"
cat > "$T/bin/systemctl" <<'SC'
#!/bin/bash
case "$*" in
 *list-timers*) echo "Tue 2026-10-20 06:41:16 UTC 9h Mon 2026-10-19 06:44:01 UTC 14h ago backup-restic.timer backup-restic.service"
                echo "Sun 2026-10-25 08:26:45 UTC 5 days Sun 2026-10-18 08:29:22 UTC 1 day ago backup-restic-check.timer backup-restic-check.service"
                echo "Tue 2026-10-20 00:00:00 UTC 3h Mon 2026-10-19 00:00:01 UTC 20h ago dpkg-db-backup.timer dpkg-db-backup.service";;
 *backup-restic-check.service*Result*) echo failed;;
 *Result*) echo success;;
 *) exit 3;;
esac
SC
chmod +x "$T/bin/systemctl"
touch -d '-40 hours' "$T/velho"; date -d '-2 hours' +%s > "$T/recente"
echo "2026-10-19 03:00:01 [backup] FALHA no restic backup" > "$T/b.log"
PATH="$T/bin:$PATH" SAUDE_MARCAS_BACKUP="$T/velho $T/recente" SAUDE_LOGS_BACKUP="$T/b.log" bash "$S" > "$T/sim.out" 2>/dev/null
ok "lista os agendamentos de backup"          'grep -q "backup-restic.service .*próxima" "$T/sim.out"'
ok "ignora o dpkg-db-backup do sistema"       '! grep -q "dpkg-db-backup" "$T/sim.out"'
ok "acusa a verificação que falhou"           'grep -q "ATENÇÃO: última execução de backup-restic-check.service terminou com: failed" "$T/sim.out"'
ok "marca por data: 40h -> ATRASADO"          'grep -q "40h00m atrás   <- ATRASADO" "$T/sim.out"'
ok "marca por epoch: 2h -> em dia"            'grep -q "2h00m atrás$" "$T/sim.out"'
ok "mostra a falha do log"                    'grep -q "log: .*FALHA no restic backup" "$T/sim.out"'

echo "3. Sem backup nenhum"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/systemctl"
PATH="$T/bin:$PATH" bash "$S" > "$T/sem.out" 2>/dev/null
ok "avisa que não há backup"                  'grep -q "NENHUM agendamento de backup" "$T/sem.out"'

echo
(( f == 0 )) && echo "Todos os testes passaram." || { echo "$f falha(s)"; exit 1; }
