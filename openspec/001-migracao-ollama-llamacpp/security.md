# Segurança e operação

- O backend ficará somente na rede interna Docker.
- A porta não será publicada na LAN.
- A imagem será pinada por digest.
- O container não terá `docker.sock` nem `~/.ssh`.
- Modelos serão montados em modo somente leitura quando possível.
- O acesso à GPU será limitado aos dispositivos necessários.
- Logs terão rotação configurada.
- Healthcheck deverá representar prontidão real, não apenas processo vivo.
- Tokens e credenciais continuarão no `.env`.
- Firewall e `DOCKER-USER` serão verificados pelo oráculo.
- Métricas de disponibilidade, latência e erro serão adicionadas ao monitoramento.
