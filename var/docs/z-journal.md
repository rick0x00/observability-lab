# z-journal

Log simples do projeto.  
Sem romance, só o que foi feito mesmo.

## Linha do tempo

| Data/Hora | O que estava pegando | O que foi feito | Resultado |
|---|---|---|---|
| 2026-03-06 21:05 | Sexta-feira à noite, início real do projeto com prazo curto e muita coisa pra fechar | Fiz planejamento primeiro, sem código ainda | Norte definido |
| 2026-03-06 21:40 | Faltava critério claro do que era "feito" ou "meia boca" | Criei `var/docs/1-review.md` com regra dura de aceite | Base de auditoria pronta |
| 2026-03-06 22:20 | Escopo ainda espalhado | Criei `var/docs/02-planning.md` com árvore de paths e entregas | Plano fechado |
| 2026-03-06 23:10 | Tempo apertado pra construir tudo na mão do zero | Usei ChatGPT (site) com base no planning, pedindo blocos objetivos | Ganho de velocidade |
| 2026-03-07 09:05 | Saída inicial da IA vinha "quase certa", mas não do jeito que eu queria | Passei contexto + arquivo problemático e fui ajustando em cima | Fluxo ficou controlado |
| 2026-03-07 09:50 | Bootstrap local estava confuso | Organizei fluxo em `var/scripts/bootstrap` + tasks diretas | Setup repetível |
| 2026-03-07 10:30 | Cluster local precisava subir limpo e previsível | Ajustes de bootstrap e validações de kubeconfig/contexto | `kubectl` estável |
| 2026-03-07 11:20 | Acesso web ruim para validar stack no navegador | Criei camada de ingress e hosts locais | App/Grafana/Kibana acessíveis |
| 2026-03-07 12:10 | Decisão de ingress | Mantive Traefik porque o cluster local já entrega isso fácil | Menos complexidade |
| 2026-03-07 13:05 | Deploy espalhado e difícil de manter | Padronizei deploy por Helmfile por stack | Admin e manutenção mais simples |
| 2026-03-07 14:00 | Manifestos duplicados e estrutura confusa | Consolidado em `k8s/` raiz com overlays por ambiente | Estrutura mais limpa |
| 2026-03-07 15:15 | App precisava cumprir contrato dos endpoints e logs | Mantive Podinfo com shim simples para endpoints/logs exigidos | Comportamento esperado |
| 2026-03-07 16:20 | Qualidade mínima do container | Ajustes no Dockerfile para segurança e padrão do desafio | Build consistente |
| 2026-03-07 17:40 | Observabilidade parcial | Fechei métricas + dashboard Grafana com queries reais | Painéis úteis |
| 2026-03-08 09:00 | Logging sem padronização boa | Fechei Filebeat + Logstash + Elasticsearch + Kibana | Pipeline de logs ok |
| 2026-03-08 09:55 | Campos de log obrigatórios precisavam aparecer de verdade | Ajustei parsing e índice por ambiente/data | Campos esperados no ES |
| 2026-03-08 10:40 | Segredo sensível espalhado em texto plano | Decidi usar SOPS com KMS GCP | Gestão de segredo ficou séria |
| 2026-03-08 11:30 | Integração de segredo ainda manual demais | Padronizei decrypt em scripts/tasks com wrapper | Uso diário ficou simples |
| 2026-03-08 12:45 | Dashboard Kibana com referência quebrada em alguns testes | Limpei estrutura e reimport controlado | Dashboard estável |
| 2026-03-08 14:10 | HPA e validações estavam pouco confiáveis | Ajustei validação de escala e checks de runtime | Evidência melhor |
| 2026-03-08 15:35 | Lint/build/deploy com variação entre ambientes | Normalizei scripts em `ci/scripts/` | Execução mais previsível |
| 2026-03-08 17:05 | Precisava suportar GitHub e GitLab sem dor | Mantive pipeline canônica + wrappers de plataforma | Reuso bom |
| 2026-03-08 19:10 | Ainda apareciam erros pontuais de deploy no ELK | Ajustes de ordem, restart e check de auth | Deploy ficou estável |
| 2026-03-09 20:25 | Fase de finalização e limpeza | Revisão de docs, tasks e consistência geral | Projeto quase fechado |
| 2026-03-09 22:05 | Pequenos bugs de script e path quebrando fora da raiz | Corrigi scripts para path absoluto e fallback | Menos erro bobo |
| 2026-03-10 19:30 | Rodada final de validação | Teste fim a fim na VM (app, métricas, logs, HPA) | Stack funcional |
| 2026-03-10 21:10 | Fechamento do ciclo | Ajustes finais no conteúdo e organização do repo | Entrega pronta |

## Nota curta sobre uso de IA

Foi usado ChatGPT no processo, sim.  
Mas não foi "copiar e colar cego".

Fluxo foi esse:
- eu planejava antes (`1-review.md` e `02-planning.md`);
- mandava contexto e arquivo quebrado;
- pegava resposta;
- ajustava manualmente até ficar do jeito certo.

Sem planejamento isso não teria funcionado.

## Estado atual

- Projeto está pronto e funcional no ambiente local.
- Stack completa validada em runtime na VM.
- Segredos sensíveis já entram no fluxo com SOPS.
- Helmfiles e tasks estão organizados para manter fácil.
- Falta só fechar a pipeline final do jeito definitivo para publicação.
