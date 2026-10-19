# saude-servidor

[![Testes](https://github.com/Euller-Pinheiro/saude-servidor/actions/workflows/testes.yml/badge.svg)](https://github.com/Euller-Pinheiro/saude-servidor/actions/workflows/testes.yml)
![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white)
![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-green)

**[English below](#english)**

Raio-x de um servidor Linux em uma tela. Roda em segundos, **só lê**: não instala, não reinicia e não altera nada. Por isso pode ser rodado em produção a qualquer hora, inclusive em vários servidores de uma vez.

Uso este script nos servidores que a [ESX Tecnologia](https://esxtecnologia.com) administra. É o tipo de checagem que encontra num minuto o que costuma passar meses sem ninguém ver: backup que parou ou nunca existiu, verificação falhando em silêncio, kernel esperando reinício, SSH aberto a força bruta.

## O que ele mostra

| Seção | Conteúdo |
|---|---|
| **Sistema** | SO, kernel, tempo no ar, carga, memória, swap e disco |
| **Reinício e atualizações** | reinício pendente (e o pacote que pediu), atualizações e quantas são de segurança, pacotes críticos (kernel, Docker, OpenSSH, bancos, web), se a atualização automática está ligada |
| **Serviços com falha** | `systemctl --failed` |
| **Docker** | contêineres e estado, alerta para `unhealthy`, `restarting` e `exited`, espaço recuperável |
| **Backup** | agendamentos de backup (systemd timers), o resultado da última execução de cada um, **há quanto tempo foi o último backup bem-sucedido** (alerta acima de 36h) e erros recentes no log |
| **Bancos de dados** | MySQL, MariaDB e PostgreSQL rodando no host ou em contêiner, e arquivos SQLite em uso |
| **Quedas e reinícios** | últimos boots, processos mortos por falta de memória (OOM) e erros no fim da sessão anterior ao último boot |
| **Segurança básica** | login SSH por senha e de root, tentativas de login falhas nas últimas 24h, firewall, fail2ban, agente Zabbix (no host ou em contêiner) |

## Uso

```bash
sudo bash saude-servidor.sh
```

Vários servidores de uma vez, do PowerShell do Windows, com o resultado num arquivo só:

```powershell
foreach ($ip in "10.0.0.11","10.0.0.12") {
  scp .\saude-servidor.sh root@${ip}:/usr/local/bin/
  ssh root@$ip "bash /usr/local/bin/saude-servidor.sh" | Tee-Object -Append -FilePath .\saude.txt
}
```

### Backup

A seção de backup reconhece qualquer timer do systemd com `backup` ou `restic` no nome. Para saber a idade do último backup bem-sucedido, ela lê um arquivo de marca, que pode conter um *epoch* ou só ter a data de modificação. O padrão é o do [backup-restic-r2](https://github.com/Euller-Pinheiro/backup-restic-r2), e dá para apontar outros:

```bash
SAUDE_MARCAS_BACKUP="/var/lib/meu-backup/ok" SAUDE_LOGS_BACKUP="/var/log/meu-backup.log" sudo -E bash saude-servidor.sh
```

## Testes

[`tests/test.sh`](tests/test.sh) roda o script de verdade no servidor do GitHub Actions e confere:
- que todas as seções aparecem;
- que nada foi escrito em `/etc` ou `/usr/local/bin`;
- que o stderr não traz erros.

Depois simula cenários de backup: em dia, atrasado, verificação que falhou, falha no log e servidor sem backup.

```bash
sudo ./tests/test.sh
```

## Autor

**Euller Pinheiro**, Diretor Técnico da [ESX Tecnologia](https://esxtecnologia.com), empresa de TI gerenciada, infraestrutura e desenvolvimento em São Paulo.

Quer esse raio-x rodando nos servidores da sua empresa, com alguém de olho nos alertas? [Fale com a ESX](https://esxtecnologia.com).

---

<a name="english"></a>
## English

A one-screen, **read-only** health report for Linux servers: OS and resources, pending reboots and security updates, failed units, Docker container health, **backup freshness** (systemd timers, last result, hours since last successful backup, log errors), databases in use, recent crashes and OOM kills, and basic SSH/firewall/fail2ban/Zabbix posture. Safe to run in production at any time. Tested in CI on a real runner plus simulated backup scenarios. Licensed under [MIT](LICENSE).
