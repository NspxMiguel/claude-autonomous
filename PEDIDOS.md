# Pedidos pendentes — claude-autonomous

Repositório público que empacota o modo autônomo do Claude Code para qualquer
pessoa instalar com um comando.

---

## [ENTREGUE] Empacotar o modo autônomo como repo público

**Pedido em:** 16/08/2026

**Palavras dele:** *"algo facil de ser replicado dps, postado direto no github.
Claude autonomous alguma coisa assim, pra deixar ele 100% autonomo, pega api,
faze de tudo msm"*

**Antes disso, no mesmo dia:** *"cria uma skill, ou sla oq pode ser, que deixa o
claude code (no claude desktop) 100% autonomo, ou seja, nao pede mais pra vc
fazer nada, tem acesso total ao seu pc, nao pede permissao pra nada, nem coisas
perigosas. Vai no seu pc, controla ele por completo, pega api, faz tudo sem vc,
vc só da os comandos e ele faz"*

**O que foi entregue:**
- `install.sh` (macOS/Linux) e `install.ps1` (Windows), install de uma linha
- `bin/claude-autonomous` com `on` / `off` / `status`
- skill `autonomous` — a metade de comportamento
- README em inglês e português, `docs/limits.md`
- página em `https://www.nspx.dev/claude-autonomous/`

---

## [ABERTO] Decidir se o hook de auto-aprovação vale o custo

O hook roda um `/bin/echo` por chamada de ferramenta. É barato, mas é por
chamada. Como o `bypassPermissions` sozinho já cala o prompt, o hook só ganha
alguma coisa quando a sessão abre em outro modo — que é o que o app de desktop
faz em alguns contextos.

Medir o custo real numa sessão longa e decidir se vira opcional
(`claude-autonomous on --no-hook`) ou se fica sempre ligado.
