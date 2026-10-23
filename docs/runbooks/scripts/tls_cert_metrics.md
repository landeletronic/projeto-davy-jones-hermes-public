# tls_cert_metrics.sh — validade do certificado no Prometheus

| | |
|---|---|
| Arquivo | `ops/bin/tls_cert_metrics.sh` |
| Instalado como | `/usr/local/bin/tls-cert-metrics` |
| Agendamento | `ops/cron/tls-cert.cron` → **03:20** (antes do backup) |
| Argumento | caminho do `.crt` (default `nginx/certs/server.crt`) |
| Métricas | `hermes_tls_cert_expiry_timestamp_seconds`, `_not_before_…`, `_days_left`, `_last_check_…` |

## Por que lê o arquivo e não a rede

O alerta é sobre o que **será servido no próximo reload**. A divergência "arquivo novo × nginx
servindo o antigo" é coberta pelo check de **fingerprint** da suíte, não por esta métrica.

## Rodar à mão

```bash
ssh davy-jones-hermes 'sudo /usr/local/bin/tls-cert-metrics'
ssh davy-jones-hermes 'grep hermes_tls_cert /home/tlandskron/hermes-architect/ci/textfile/*.prom'
```

Esperado: `days_left` positivo e decrescente dia a dia.

## Alertas ligados

- `LabTLSCertExpiring` — menos de **30 dias**;
- `LabTLSCertExpired` — `days_left < 0` (FAIL na suíte).

## Se falhar

| Sintoma | Causa | Ação |
|---|---|---|
| exit 2 / "certificado ausente" | caminho errado ou cert removido | conferir `nginx/certs/server.crt` |
| `days_left` não muda | cron não roda | `systemctl is-active cron` |
| alerta <30 dias | hora de renovar | `tools/make_tls_cert.sh --force --reload` |

## Reinstalar

```powershell
powershell -File ops\deploy\sync-to-host.ps1
```
