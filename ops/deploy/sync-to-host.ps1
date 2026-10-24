# =============================================================================
# ops/deploy/sync-to-host.ps1 - espelha o repositório (aqui, no seu PC) para o host.
#
# O host é a máquina de CI: ele tem a cópia da suíte que o cron executa.
# Sempre que editar tests/, ops/ ou configs, rode este script: ele copia,
# instala o que roda sozinho (cron/systemd) e, no fim, executa o oráculo —
# comparando o hash da suíte dos dois lados.
#
# Uso:
#   powershell -File ops\deploy\sync-to-host.ps1
#   powershell -File ops\deploy\sync-to-host.ps1 -NoCi     (só sincroniza)
# =============================================================================
param(
    [string]$Target = 'davy-jones-hermes',
    [string]$RemoteDir = '/home/usuario/hermes-architect',
    [switch]$NoCi
)

$ErrorActionPreference = 'Stop'
# este script vive em <repo>/ops/deploy/ -> a raiz é dois níveis acima
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# O ssh propaga o exit code do comando remoto; sem isto, uma instalação que
# falha (ex.: regra inválida) passaria batido e o deploy "terminaria ok".
function Assert-Ok([string]$what) {
    if ($LASTEXITCODE -ne 0) { throw "FALHOU: $what (exit $LASTEXITCODE)" }
}

Write-Host "== sincronizando $root -> ${Target}:$RemoteDir"

# diretórios no host (o ci/textfile precisa existir ANTES do compose subir:
# se o Docker criar, vira root-only e o CI não consegue escrever)
ssh $Target "mkdir -p '$RemoteDir/tests' '$RemoteDir/tools' '$RemoteDir/ops/bin' '$RemoteDir/ops/cron' '$RemoteDir/ops/systemd' '$RemoteDir/ops/docker' '$RemoteDir/monitoring' '$RemoteDir/nginx/conf.d' '$RemoteDir/searxng' '$RemoteDir/hermes-data' '$RemoteDir/ci/textfile' '$RemoteDir/docs'"

scp -q (Join-Path $root 'docker-compose.yml') "${Target}:$RemoteDir/docker-compose.yml"
# `docs` vai como árvore (architecture/runbooks/plans/reports/learning): o host
# precisa do conhecimento junto para recuperar a máquina sem depender deste PC.
foreach ($d in @('tests', 'tools', 'monitoring', 'hermes-data', 'ops', 'docs')) {
    scp -q -r (Join-Path $root $d) "${Target}:$RemoteDir/"
}

# .env: variáveis do compose (inclui API_SERVER_KEY). Fica fora do git; a cópia
# do host é gerada daqui para que o compose dos dois lados use o mesmo segredo.
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
    scp -q $envFile "${Target}:$RemoteDir/.env"
    ssh $Target "chmod 600 '$RemoteDir/.env'"
}

# Config do Hermes: o REPO é a fonte (a cópia em hermes-data/ era decorativa e
# divergiu em silêncio: 0.7 no repo x 0.3 em produção). Instala só quando muda e
# reinicia o gateway para aplicar.
$cfgPairs = @(
    @{ Local = 'hermes-data\config.yaml'; Remote = '/home/usuario/.hermes/config.yaml' },
    @{ Local = 'hermes-data\mem0.json';   Remote = '/home/usuario/.hermes/mem0.json' }
)
$cfgChanged = $false
foreach ($p in $cfgPairs) {
    $lh = (Get-FileHash (Join-Path $root $p.Local) -Algorithm SHA256).Hash.ToLower()
    $rh = (ssh $Target "sha256sum '$($p.Remote)' 2>/dev/null | cut -d' ' -f1").Trim().ToLower()
    $rh = ($rh -split "`n")[0].Trim()
    if ($lh -ne $rh) {
        scp -q (Join-Path $root $p.Local) "${Target}:/tmp/hermes-cfg"
        ssh $Target "install -m 640 /tmp/hermes-cfg '$($p.Remote)' && rm -f /tmp/hermes-cfg"
        Assert-Ok "instalação de $($p.Remote)"
        $cfgChanged = $true
        Write-Host "== config do Hermes atualizada: $($p.Remote)"
    }
}
if ($cfgChanged) {
    Write-Host '== reiniciando o gateway para aplicar a config'
    ssh $Target "docker restart hermes-agent >/dev/null"
    ssh $Target 'for i in $(seq 1 90); do curl -fsS --max-time 2 http://localhost:8642/health >/dev/null && exit 0; sleep 2; done; exit 1'
    Assert-Ok 'gateway saudável após aplicar a config'
}

# searxng: o container (uid 977) assume a posse de /etc/searxng, então copiamos
# via /tmp e instalamos com sudo no dono/modo corretos.
scp -q (Join-Path $root 'searxng\settings.yml') "${Target}:/tmp/searxng-settings.yml"
ssh $Target "sudo install -d -o 977 -g 977 -m 775 '$RemoteDir/searxng' && sudo install -o 977 -g 977 -m 600 /tmp/searxng-settings.yml '$RemoteDir/searxng/settings.yml' && rm -f /tmp/searxng-settings.yml"

# documentação de topo (útil para recuperação no host). O conhecimento em si
# viaja inteiro em docs/ (copiado acima como árvore); aqui sobram README e AGENTS.
$docs = Get-ChildItem -Path $root -Filter '*.md' -File
foreach ($f in $docs) { scp -q $f.FullName "${Target}:$RemoteDir/" }

# permissões de leitura: o Grafana (uid 472) lê monitoring/ por bind-mount e o
# umask do host cria diretórios 700 — sem o+rX o provisionamento dos dashboards
# falha com "permission denied" (bug encontrado na Fase 7). Não toca em nginx/certs.
ssh $Target "chmod -R a+rX '$RemoteDir/monitoring'"

# Prometheus só relê alert-rules.yml no start ou em SIGHUP (NÃO a cada
# evaluation_interval, como se supunha). Sem este reload, um deploy com regra
# nova roda em silêncio com as regras velhas.
ssh $Target "docker kill -s HUP prometheus >/dev/null 2>&1 || true"

# (re)instala o runner e o cron do CI — idempotente (install = /usr/bin/install)
ssh $Target "sudo install -m 755 '$RemoteDir/ops/bin/ci_run.sh' /usr/local/bin/hermes-ci && sudo install -m 644 '$RemoteDir/ops/cron/hermes-ci.cron' /etc/cron.d/hermes-ci && sudo chown root:root /etc/cron.d/hermes-ci"
Assert-Ok 'instalação do runner/cron do CI'

# firewall: o Docker recria a cadeia DOCKER-USER a cada restart, então o host
# precisa do script + unit. Antes eles existiam SÓ no host (não voltariam num
# rebuild); agora são versionados em ops/ e instalados aqui.
ssh $Target "sudo install -m 755 -o root -g root '$RemoteDir/ops/bin/docker-firewall.sh' /usr/local/bin/docker-firewall.sh && sudo install -m 644 -o root -g root '$RemoteDir/ops/systemd/docker-firewall.service' /etc/systemd/system/docker-firewall.service && sudo systemctl daemon-reload && sudo systemctl enable docker-firewall.service >/dev/null 2>&1 && sudo systemctl restart docker-firewall.service"
Assert-Ok 'instalação do firewall (DOCKER-USER)'

# backup: runner + cron versionados (antes só existiam no host, por instalação manual)
ssh $Target "sudo install -m 755 -o root -g root '$RemoteDir/ops/bin/backup_stack.sh' /usr/local/bin/hermes-backup && sudo install -m 644 -o root -g root '$RemoteDir/ops/cron/hermes-backup.cron' /etc/cron.d/hermes-backup"
Assert-Ok 'instalação do backup + cron'

# mem0: manutenção diária (dedup/teto/TTL) — script + cron versionados
ssh $Target "sudo install -m 755 -o root -g root '$RemoteDir/ops/bin/mem0_maintenance.py' /usr/local/bin/mem0-maintenance && sudo install -m 644 -o root -g root '$RemoteDir/ops/cron/mem0-maintenance.cron' /etc/cron.d/mem0-maintenance"
Assert-Ok 'instalação da manutenção do mem0 + cron'

# eixo de estudos: worker de ingestão do share (~/documents -> base do OWUI),
# a cada 15 min. A lógica fica em tools/rag_ingest.py; aqui vao o wrapper e o cron.
ssh $Target "sudo install -m 755 -o root -g root '$RemoteDir/ops/bin/rag_ingest.sh' /usr/local/bin/rag-ingest && sudo install -m 644 -o root -g root '$RemoteDir/ops/cron/rag-ingest.cron' /etc/cron.d/rag-ingest"
Assert-Ok 'instalação do worker de ingestão + cron'

# banco de questões (Fase 5 do eixo de estudos): provas/gabaritos do share ->
# ~/rag-state/questoes.db, a cada 30 min (aos :05/:35). Lógica em tools/questoes.py.
ssh $Target "sudo install -m 755 -o root -g root '$RemoteDir/ops/bin/questoes.sh' /usr/local/bin/questoes && sudo install -m 644 -o root -g root '$RemoteDir/ops/cron/questoes.cron' /etc/cron.d/questoes"
Assert-Ok 'instalação do banco de questões + cron'
# Primeiro import (idempotente): cria ~/rag-state/questoes.db e publica as
# estatísticas no share antes de o CI rodar — senão o primeiro CI veria banco vazio.
ssh $Target "sudo -u usuario /usr/local/bin/questoes"
Assert-Ok 'primeiro import do banco de questões'

# Tutor Tiradentes: o compose precisa já expor questoes.db como /data/questoes.db:ro.
# O instalador roda dentro do OWUI para usar uma sessão humana curta sem tirar o
# WEBUI_SECRET_KEY do container. A API nativa atualiza Function/modelo/ACL/base.
ssh $Target "docker cp '$RemoteDir/ops/open-webui/tutor_tiradentes.py' open-webui:/tmp/tutor_tiradentes.py && docker cp '$RemoteDir/ops/bin/install_tutor_tiradentes.py' open-webui:/tmp/install_tutor_tiradentes.py && docker exec open-webui python /tmp/install_tutor_tiradentes.py"
Assert-Ok 'instalação do Tutor Tiradentes no Open WebUI'

# TLS: validade do certificado autoassinado (nada renova por você) — script + cron
ssh $Target "sudo install -m 755 -o root -g root '$RemoteDir/ops/bin/tls_cert_metrics.sh' /usr/local/bin/tls-cert-metrics && sudo install -m 644 -o root -g root '$RemoteDir/ops/cron/tls-cert.cron' /etc/cron.d/tls-cert"
Assert-Ok 'instalação da métrica de validade do TLS + cron'

# ufw: política de portas do lab, versionada e idempotente (não faz reset)
ssh $Target "sudo install -m 755 -o root -g root '$RemoteDir/ops/bin/ufw-lab.sh' /usr/local/bin/ufw-lab.sh && sudo /usr/local/bin/ufw-lab.sh"
Assert-Ok 'instalação/aplicação da política do ufw'

# Samba: serviço de HOST (não container), ao lado do cron. O pacote é instalado
# uma vez à mão (`apt-get install -y samba`); aqui vão a config versionada e o
# serviço. `testparm` valida antes de reiniciar: config quebrada derrubaria o share.
ssh $Target "if command -v smbd >/dev/null 2>&1; then sudo install -m 644 -o root -g root '$RemoteDir/ops/samba/smb.conf' /etc/samba/smb.conf && sudo testparm -s /etc/samba/smb.conf >/dev/null && sudo systemctl enable smbd >/dev/null 2>&1 && sudo systemctl restart smbd; else echo '== Samba nao instalado (apt-get install -y samba) - share documentos pulado'; fi"
Assert-Ok 'instalação do Samba (smb.conf + smbd)'

# Rotação de logs do Docker (daemon.json). O daemon só lê no start, e o valor
# vale para containers NOVOS; os existentes precisam de `--force-recreate`.
$daemonPrev = (ssh $Target "sudo sha256sum /etc/docker/daemon.json 2>/dev/null | cut -d' ' -f1" 2>$null)
$daemonLocal = (Get-FileHash "$root\ops\docker\daemon.json" -Algorithm SHA256).Hash.ToLower()
ssh $Target "sudo install -m 644 -o root -g root '$RemoteDir/ops/docker/daemon.json' /etc/docker/daemon.json"
Assert-Ok 'instalação do /etc/docker/daemon.json'
if ("$daemonPrev".Trim() -ne $daemonLocal) {
    Write-Host '== daemon.json mudou: reiniciando o Docker (containers sobem sozinhos; firewall volta via PartOf=)'
    ssh $Target "sudo systemctl restart docker"
    Assert-Ok 'restart do Docker'
}

# hash da suíte: os dois lados têm a mesma versão?
$local = (Get-FileHash (Join-Path $root 'tests\verify_stack.sh') -Algorithm SHA256).Hash.ToLower()
$remote = (ssh $Target "sha256sum '$RemoteDir/tests/verify_stack.sh' | cut -d' ' -f1").Trim().ToLower()
$remote = ($remote -split "`n")[0].Trim()

if ($local -eq $remote) {
    Write-Host "== suíte sincronizada (sha256 $($local.Substring(0,12)))"
} else {
    Write-Warning "HASH DIFERENTE! local=$($local.Substring(0,12)) host=$($remote.Substring(0,12))"
    exit 1
}

# hash dos artefatos instalados (o CI não valida o conteúdo deles)
$fwPairs = @(
    @{ Local = 'ops\bin\ci_run.sh';              Remote = '/usr/local/bin/hermes-ci' },
    @{ Local = 'ops\cron\hermes-ci.cron';        Remote = '/etc/cron.d/hermes-ci' },
    @{ Local = 'ops\bin\docker-firewall.sh';     Remote = '/usr/local/bin/docker-firewall.sh' },
    @{ Local = 'ops\systemd\docker-firewall.service'; Remote = '/etc/systemd/system/docker-firewall.service' },
    @{ Local = 'ops\bin\backup_stack.sh';        Remote = '/usr/local/bin/hermes-backup' },
    @{ Local = 'ops\cron\hermes-backup.cron';    Remote = '/etc/cron.d/hermes-backup' },
    @{ Local = 'ops\bin\mem0_maintenance.py';    Remote = '/usr/local/bin/mem0-maintenance' },
    @{ Local = 'ops\cron\mem0-maintenance.cron'; Remote = '/etc/cron.d/mem0-maintenance' },
    @{ Local = 'ops\bin\tls_cert_metrics.sh';    Remote = '/usr/local/bin/tls-cert-metrics' },
    @{ Local = 'ops\cron\tls-cert.cron';         Remote = '/etc/cron.d/tls-cert' },
    @{ Local = 'ops\bin\questoes.sh';            Remote = '/usr/local/bin/questoes' },
    @{ Local = 'ops\cron\questoes.cron';         Remote = '/etc/cron.d/questoes' },
    @{ Local = 'ops\bin\ufw-lab.sh';             Remote = '/usr/local/bin/ufw-lab.sh' },
    @{ Local = 'ops\samba\smb.conf';             Remote = '/etc/samba/smb.conf' },
    @{ Local = 'ops\docker\daemon.json';         Remote = '/etc/docker/daemon.json' }
)
foreach ($p in $fwPairs) {
    $lh = (Get-FileHash (Join-Path $root $p.Local) -Algorithm SHA256).Hash.ToLower()
    $rh = (ssh $Target "sha256sum '$($p.Remote)' | cut -d' ' -f1")
    $rh = ($rh -split "`n")[0].Trim().ToLower()
    if ($lh -eq $rh) {
        Write-Host "== instalado ok: $($p.Remote) (sha256 $($lh.Substring(0,12)))"
    } else {
        Write-Warning "HASH DIFERENTE em $($p.Remote)! local=$($lh.Substring(0,12)) host=$($rh.Substring(0,12))"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Tarefas agendadas do Windows: lancadas via wscript + run-hidden.vbs.
# Chamar powershell.exe direto numa tarefa Interactive abre o console a cada
# 30 min e ROUBA O FOCO de quem esta digitando (aconteceu em 2026-10-22).
# Idempotente: se a tarefa existe, so troca a acao (gatilho/principal ficam);
# se nao existe, cria com o gatilho certo.
$vbs = Join-Path $root 'ops\windows\run-hidden.vbs'
if (-not (Test-Path $vbs)) {
    Write-Warning "run-hidden.vbs ausente: $vbs"
    exit 1
}

function Ensure-HermesTask([string]$name, [string]$script, $trigger) {
    $action = New-ScheduledTaskAction -Execute 'wscript.exe' `
        -Argument ('//nologo "{0}" {1}' -f $vbs, $script)
    $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($t) {
        Set-ScheduledTask -TaskName $name -Action $action | Out-Null
        Write-Host "== tarefa '$name' -> run-hidden.vbs (gatilho preservado)"
    } else {
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
            -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
            -Principal $principal | Out-Null
        Write-Host "== tarefa '$name' criada (run-hidden.vbs)"
    }
}

try {
    $t30 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 30) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    Ensure-HermesTask 'Hermes Lab Alerts' 'watch-alerts.ps1' $t30
    Ensure-HermesTask 'Hermes Lab Backup Pull' 'pull-backups.ps1' (New-ScheduledTaskTrigger -Daily -At '12:00')
} catch {
    Write-Warning "nao consegui (re)registrar as tarefas do Windows: $($_.Exception.Message)"
    exit 1
}

if ($NoCi) {
    Write-Host '== CI não executado (-NoCi)'
    exit 0
}
Write-Host '== rodando o oráculo no host (hermes-ci)...'
ssh $Target '/usr/local/bin/hermes-ci --quiet'
exit $LASTEXITCODE
