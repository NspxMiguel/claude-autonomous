# Pedidos — claude-autonomous

Repositório público que empacota o modo autônomo do Claude Code para qualquer
pessoa instalar com um comando.

**Nada aberto do meu lado.** O que sobra abaixo é dele.

---

## [ENTREGUE] Empacotar o modo autônomo como repo público — v1.0

**Pedido em:** 16/08/2026

**Palavras dele:** *"algo facil de ser replicado dps, postado direto no github.
Claude autonomous alguma coisa assim, pra deixar ele 100% autonomo, pega api,
faze de tudo msm"*

**Antes disso, no mesmo dia:** *"cria uma skill, ou sla oq pode ser, que deixa o
claude code (no claude desktop) 100% autonomo, ou seja, nao pede mais pra vc
fazer nada, tem acesso total ao seu pc, nao pede permissao pra nada, nem coisas
perigosas. Vai no seu pc, controla ele por completo, pega api, faz tudo sem vc,
vc só da os comandos e ele faz"*

`install.sh` + `install.ps1`, `bin/claude-autonomous` com `on`/`off`/`status`,
skill `autonomous`, README em inglês e português, `docs/limits.md`, página em
`https://www.nspx.dev/claude-autonomous/`.

---

## [ENTREGUE] Fechar o que faltava de config — v1.1

**Palavras dele:** *"eu falei oq eu quero. nao pode faltar nada. quero q leia e
digite tudo certinho, uma ia 100% autonoma"*

Ele estava certo: a v1.0 cuidou de "não ser interrompido" e parou aí. Faltava
"terminar sozinho" — `doneMeansMerged`, `effortLevel: high`,
`remoteControlAtStartup`, `autoUploadSessions`, push notification,
`crossSessionInbound: accept`, `autoMemoryEnabled`. Mais `secret`/`run` e
`doctor`.

---

## [ENTREGUE] Pegar chave de API de painel logado — v1.2

**Palavras dele:** *"api key ele pode pegar, sla, ja to logando no groq, la tem
as api key, ai ele consegue pegar essas key de boa"*

`secret import` — clipboard direto pro chaveiro, sem o valor entrar no contexto
nem no transcript.

Feito na prática com o Groq: o console não tem botão de copiar e mascara chave
existente (`gsk_...zwCG`), então criei a chave `claude-autonomous`, copiei do
diálogo de criação, importei (56 caracteres) e testei com chamada real —
HTTP 200, 15 modelos.

---

## [ENTREGUE] Provar que roda no CLI e no Desktop — v1.2.1

**Palavras dele:** *"é pra funcionar no claude code cli e no claude code
desktop. testa pra ver ai se ta 100%, autonomo"*

**CLI** (`claude -p`, sessão separada, 16/08/2026):

| Teste | Resultado |
| --- | --- |
| Executa ferramenta sem prompt | OK — rodou `id -un && sw_vers` |
| Escreve fora da pasta do projeto | OK — criou arquivo em `~/Desktop` a partir de `/tmp` |
| Skill `autonomous` visível | OK |
| Hook de auto-aprovação dispara | OK — sentinela criado às 13:33:28 |

**Desktop:** a conversa inteira sem um prompt de permissão — Bash, Write, Edit,
Chrome, Docker, `gh`. Escrita em `~/Desktop` e leitura de `/etc/hosts` a partir
de um cwd em `Documents/Claude`. Hook conferido com sentinela às 12:34.

**Custo do hook, medido:** 200 execuções em 408 ms → **2,04 ms por chamada de
ferramenta**, ~1 s numa sessão de 500 chamadas. Fica ligado permanentemente; a
pendência que existia aqui está resolvida.

---

## [ENTREGUE] Rodar em Mac, Windows e Linux — v1.3.0

**Palavras dele:** *"tem q funcionar em tudo, mac windows e linux. pode emular
windows e linux ai pra testar se precisar"*

Existem duas implementações da mesma ferramenta — `bin/claude-autonomous` (bash)
e `bin/claude-autonomous.ps1` (PowerShell) — que gravam a mesma config e se
reconhecem: a suite verifica que o modo ligado por uma é enxergado pela outra.

| | Estado | Segredos | Verificação |
| --- | --- | --- | --- |
| macOS | completo | Chaveiro | 39/39 PowerShell + suite bash |
| Linux | completo | `secret-tool` | 39/39 PowerShell + suite bash, container Debian 12 com D-Bus e keyring destravado |
| Windows | completo | DPAPI | Tudo menos a chamada DPAPI, coberta por comando de forma que renderiza as branches do Windows de qualquer host |

**Cinco defeitos que só apareceram porque foi testado de verdade:**

1. `secret-tool search` escreve no **stderr** — o `2>/dev/null` jogava fora, e o
   `list` nunca mostrava nada no Linux. E as chaves ficam em `attribute.key`,
   não `key`. Esse mesmo stream traz a linha `secret = <valor>`, então a
   extração precisa continuar exata: um grep frouxo passaria a vazar segredo;
2. parâmetro chamado `$Args` é sombreado pela variável automática de mesmo nome
   dentro de toda função PowerShell — `secret` e `run` recebiam vazio;
3. `$x = if (...) { @(um item) }` desenrola o array e devolve string, quebrando
   o parsing com um argumento só sob StrictMode;
4. `secret import` sem pipe travava pra sempre em vez de dar erro;
5. `install.ps1` duplicava o merge; agora instala e chama o CLI, com shim `.cmd`
   e PATH de usuário no Windows.

**Emulação:** Linux em container Debian 12 (dois runs completos). Windows real
não foi possível — tentei o Wine do CrossOver, que não cria prefixo por linha de
comando sem a infra de bottle dele, e mesmo se criasse o DPAPI sob Wine não
provaria Windows de verdade. Por isso a parametrização de plataforma: as
branches do Windows são renderizadas e verificadas a partir do macOS.

---

## [DELE] Três coisas de um clique

1. `npm login` — único CLI dele sem sessão. GitHub, Vercel, Firebase e Docker
   já estão logados;
2. **Permissões do macOS** — Gravação de Tela, Acessibilidade, Automação e
   Acesso Total ao Disco. O `doctor` detectou que falta Acesso Total ao Disco;
3. **Sete chaves velhas no Groq** — `ddddddd`, `ddddddddddddddddddddd`,
   `Fjfjdjf`, duas `key-miguel`, `Agenda`, `bot mine`, `Home assist`. Todas com
   0 chamadas. Apagar é destrutivo: ele diz quais e eu apago.
