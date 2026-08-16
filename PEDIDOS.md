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

## [ENTREGUE] Fechar o que faltava — v1.1

**Pedido em:** 16/08/2026, reafirmando o anterior

**Palavras dele:** *"eu falei oq eu quero. nao pode faltar nada. quero q leia e
digite tudo certinho, uma ia 100% autonoma"*

**Ele estava certo: faltava config de verdade.** A v1.0 cuidou de "não ser
interrompido" e parou aí. Faltava "terminar sozinho":

- `doneMeansMerged` — o turno acaba num PR pronto ou num cron armado, não num
  relatório de status
- `effortLevel: high` — trabalho sem supervisão não tem revisor
- `remoteControlAtStartup`, `autoUploadSessions`, push notification — a sessão
  longa continua alcançável pelo celular
- `crossSessionInbound: accept` — as sessões dele passam trabalho entre si
- `autoMemoryEnabled`, `cleanupPeriodDays: 365`

**Mais:** `secret set` / `run` (credencial vai pro comando, não pro transcript,
via Chaveiro do macOS) e `doctor` (ferramentas, CLIs autenticadas, TCC).

---

## [ABERTO] O que ainda não é 100%, e por quê

Ele pediu que eu também **digite** — senha, código de 6 dígitos, formulário de
login. Isso eu não faço, e não é config: é limite meu. Falei na cara dele em vez
de deixar ele descobrir travado no meio de uma tarefa.

O que sobrou na prática, depois do `secret`/`run`:

1. **guardar um segredo novo no chaveiro** — um comando no terminal dele, uma vez
   por chave, entrada oculta. Depois disso eu uso à vontade;
2. **login em site que o Chrome dele não preenche sozinho**;
3. **código de 6 dígitos**.

**Ideia pra reduzir o item 2:** hoje eu abro o Chrome dele já logado e uso a
sessão. Para os sites onde ele tem senha salva, o autofill do próprio Chrome +
Touch ID resolve sem eu digitar nada. Mapear em quais serviços dele isso já
funciona e documentar, em vez de tratar "login" como um bloco só.

---

## [ABERTO] Decidir se o hook de auto-aprovação vale o custo

O hook roda um `/bin/echo` por chamada de ferramenta. É barato, mas é por
chamada. Como o `bypassPermissions` sozinho já cala o prompt, o hook só ganha
alguma coisa quando a sessão abre em outro modo — que é o que o app de desktop
faz em alguns contextos.

Medir o custo real numa sessão longa e decidir se vira opcional
(`claude-autonomous on --no-hook`) ou se fica sempre ligado.
