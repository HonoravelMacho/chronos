# AGENTS.md

<!-- ASTOS:START -->
## Mapa do repositório (ASTOS)
- Antes de explorar o código (e ao se perder no meio de um debug), leia `.astos/map.md`: arquivos, dependências, hubs, capabilities (câmera/hardware), riscos (god files, ciclos, TODOs), símbolos com linha e chamadas entre arquivos.
- Detalhe completo em `.astos/graph.json`; visual 3D para humanos em `.astos/index.html`.
- Mapa desatualizado? Rode `astos -f` para regenerar sem abrir o navegador (rápido: reaproveita arquivos inalterados; a interface 3D só regenera com `astos`).
- REGRA OBRIGATÓRIA: `astos -f` é sempre o ÚLTIMO comando de terminal de cada resposta que alterar código — sem exceção, sem abrir o navegador. O mapa nunca pode ficar desatualizado.
- Economize tokens: prefira queries a grep — `astos debug`, `astos q --symbol X`, `astos q --cap camera`, `astos trace --from A --to B`, `astos impact --file F`, `astos caps`, `astos hubs`, `astos risks`, `astos slice <pasta>`, `astos changed`, `astos status`, `astos explain --symbol X`, `astos hotspots`, `astos dead`, `astos tests --file X`. Ao debugar, comece por `astos debug`.
- Com MCP (`astos mcp --path .`), chame as mesmas queries como tools, sem shell.
- Pasta read-only (ex.: `/snap/...`)? `astos --path FONTE --output ~/mapas/<nome>` grava o 3D fora da fonte; sem código suportado o mapa sai em modo genérico (árvore de pastas).
- Se existir `graphify-out/graph.json` (Graphify), prefira-o em perguntas semânticas ("como X funciona"); use o mapa ASTOS para estrutura, hardware e dependências.
<!-- ASTOS:END -->
