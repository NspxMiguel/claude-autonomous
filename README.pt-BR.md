# claude-autonomous

Faz o Claude Code parar de perguntar. Sem prompt de permissão, com o disco
inteiro no escopo, e uma skill que segura a outra metade do acordo — executar em
vez de perguntar.

*[Read in English](README.md)*

> **Leia [o que ele muda](#o-que-ele-muda) antes de rodar.** Ele tira de
> propósito toda a proteção que o harness te dá. É esse o objetivo, e é esse o
> risco: um agente sem prompt apaga a pasta errada com a mesma confiança com que
> escreve o arquivo certo. Tenha `git` e backup.

---

## Instalar

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/NspxMiguel/claude-autonomous/main/install.sh | bash
```

**Windows** — PowerShell 7+ (não o "Windows PowerShell"), sem administrador

```powershell
irm https://raw.githubusercontent.com/NspxMiguel/claude-autonomous/main/install.ps1 | iex
```

**Do clone**

```bash
git clone https://github.com/NspxMiguel/claude-autonomous
cd claude-autonomous
./install.sh
```

Depois **reinicie a sessão do Claude Code** — o modo de permissão é lido na
abertura.

```bash
claude-autonomous status   # o que está valendo agora
claude-autonomous doctor   # config + ferramentas + permissões do sistema
claude-autonomous off      # desfaz tudo
```

### Suporte por sistema, e como cada linha foi verificada

São duas implementações da mesma ferramenta: `bin/claude-autonomous` (bash) e
`bin/claude-autonomous.ps1` (PowerShell). Gravam a mesma config e reconhecem o
trabalho uma da outra — a bateria de testes verifica que o modo ligado por uma é
enxergado pela outra.

| | Estado | Segredos | Verificado |
| --- | --- | --- | --- |
| **macOS** | completo | Chaveiro | 39/39 na suite PowerShell + suite bash, no 26.5. Chave de API real guardada e usada contra endpoint ao vivo |
| **Linux** | completo | `secret-tool` | 39/39 na suite PowerShell + suite bash, em container Debian 12 com D-Bus de sessão e chaveiro destravado |
| **Windows** | completo | DPAPI | Tudo menos a chamada DPAPI em si: a suite verifica a forma do hook do Windows a partir de qualquer host. Ver abaixo |

**O que "menos o DPAPI" quer dizer.** No Windows o segredo é cifrado com
`ConvertFrom-SecureString`, que amarra o valor à conta Windows do usuário — não
existe arquivo de chave pra alguém copiar. Essa chamada só roda no Windows, então
é a única coisa aqui sem execução de teste. Todo o resto do caminho Windows —
parsing de argumento, merge do JSON, on/off/status/doctor, a forma
`cmd.exe /c echo` do hook — é exercitado pela mesma suite que passa no macOS e no
Linux.

Requisitos: `python3` pro script bash, PowerShell 7+ pro PowerShell. No Windows,
"Windows PowerShell" 5.1 não serve, e o instalador avisa antes de tocar em
qualquer arquivo.

```bash
pwsh tests/test.ps1                                   # qualquer plataforma
dbus-run-session -- tests/linux-in-container.sh --with-pwsh   # em container Linux
```

---

## Sync Apple ↔ Proton nos dois sentidos: não dá

Não existe sync ao vivo e bidirecional entre o app Senhas e o Proton Pass, e não
dá pra construir. O cofre do app Senhas é fechado nas duas pontas:

- **Ler** — os itens ficam num keychain de proteção de dados que CLI nenhuma
  enumera; cada leitura exige o app + Touch ID. (O `security` não devolve nada
  pra um site que você tem salvo.)
- **Escrever** — o `security` só grava no login keychain antigo, que o app
  Senhas não lê, então nada escrito por CLI aparece no app.

Qualquer envolvimento do Apple precisa da interface do app. O Proton, ao
contrário, é todo scriptável pelo `pass-cli`. Sobra exatamente um sentido
automatizável, e é cópia num instante, não sync:

```bash
# app Senhas -> Arquivo > Exportar Todas as Senhas (Touch ID) -> um CSV, e então:
claude-autonomous proton-seed ~/Downloads/Senhas.csv --vault Dev --apply
```

As senhas vão como JSON pro `pass-cli item create`, nunca no `argv`. Pro
caminho inverso, exporta do Proton e importa esse CSV no app Senhas na mão.

A resposta prática: pare de tentar espelhar os dois. Deixe o Proton como o cofre
único que a ferramenta lê ao vivo, e o app Senhas como o autofill do aparelho.

---

## Colocar chave sem ninguém digitar

O conselho de sempre é "guarde sua chave primeiro". Está de trás pra frente — a
chave quase sempre já está na máquina.

```bash
claude-autonomous harvest            # o que existe: nomes, tamanhos, caminhos
claude-autonomous harvest --apply    # move pro chaveiro
```

O `harvest` varre `.env` nas suas pastas de projeto, perfis de shell e os
arquivos de config que as CLIs escrevem, guarda só o que realmente parece
credencial, e importa. Ele imprime nome e contagem de bytes, nunca valor, e
descarta identificador público — `AUTH_DOMAIN` é hostname, `CLIENT_ID` é
público por definição. Tirar esses valores de arquivo em texto puro e pôr no
chaveiro do sistema já é ganho de segurança por si só.

Para chave que ainda não existe em lugar nenhum, dois caminhos que continuam
sem exigir decorar comando:

```bash
pbpaste | claude-autonomous secret import GROQ_API_KEY   # do botão copiar do painel
claude-autonomous vault                                  # página local: cola uma, ou um .env inteiro
```

O `vault` escuta só em loopback, exige token por execução, recusa `Host`
forjado e se fecha após 15 minutos parado. Ele existe pra entregar uma chave
virar um colar em vez de um comando decorado — não pra alguma coisa entrar em
conta por você.

**O Proton Pass, se você usa, é a fonte mais limpa de todas.** O `pass-cli`
oficial autentica uma vez (é sua — login ou Personal Access Token) e daí lê sem
interação, como qualquer CLI logada:

```bash
pass-cli run -- ./deploy.sh                    # injeta os segredos do cofre, mascarado
pass-cli agent create claude --expiration 3m --vault Dev   # dá ao agente um escopo
```

Uma sessão de agente injeta segredo no comando mas é proibida de usar
`--show-secrets`, então valor nenhum cai num transcript, e todo acesso fica no
`pass-cli agent monitor`. Sem CSV, sem sync, sem cópia — lê direto do cofre. Você
não precisa sincronizar o app Senhas com o Proton: põe as chaves no Proton e lê
de lá.

**De um gerenciador de senhas.** O macOS não deixa ler em massa o cofre do app
Senhas (precisa do app + Touch ID por item, e não há CLI de export). O caminho
manual é o próprio Arquivo -> Exportar Todas as Senhas do app, e então:

```bash
claude-autonomous import-csv ~/Downloads/Senhas.csv --apply --rm-after
```

Por padrão pega só o que tem cara de token de API e ignora login de site — senha
de site não serve pro `run`, então importar o cofre inteiro só duplica. `--sites`
ou `--all` incluem; `--rm-after` sobrescreve e apaga o CSV em texto puro.

---

## Credencial, sem entregar a credencial

O pedido por trás de "deixa ele pegar a API e fazer tudo" é legítimo, e não exige
que o agente segure a chave em momento nenhum. Guarde uma vez, no seu chaveiro,
no seu terminal:

```bash
claude-autonomous secret set STRIPE_KEY     # entrada oculta, direto pro chaveiro
```

Ou, quando a chave já está na tela de um painel onde você está logado, deixe o
agente pegar de lá — ele clica no botão de copiar da própria página e:

```bash
pbpaste | claude-autonomous secret import GROQ_API_KEY
```

Clipboard → chaveiro, sem o valor ser lido pro contexto do modelo, então ele não
cai no transcript. É esse o caminho a preferir: ler a chave da página com um
screenshot deixa o segredo na conversa pra sempre.

Daí em diante o agente usa à vontade:

```bash
claude-autonomous run STRIPE_KEY -- ./deploy.sh
claude-autonomous run AWS_KEY,AWS_SECRET -- python job.py
```

O valor é exportado no processo filho. Não está no `argv`, não está no `stdout`,
não está no transcript, e o `secret list` mostra só os nomes. Usa o Chaveiro do
macOS, ou o `secret-tool` no Linux.

Na maioria das vezes nem precisa disso — `gh`, `vercel`, `supabase`, `firebase`,
`aws` e `docker` carregam a própria autenticação, e o agente só usa.

---

## Por que só a config não resolve

A receita que circula por aí para "deixar autônomo" para em
`--dangerously-skip-permissions`. Isso cala o prompt do harness — e aí o modelo
para do mesmo jeito para escrever *"quer que eu faça X?"*, que para quem está
esperando é a mesma parede.

Por isso são duas metades:

| Metade | O que é | Onde mora |
| --- | --- | --- |
| **Config** | Nenhum prompt pode subir | `~/.claude/settings.json` |
| **Postura** | Nenhuma pergunta é inventada | skill `autonomous` |

A skill é a parte que todo mundo pula, e é a que muda de verdade como a sessão
se comporta: decidir em vez de listar opções, nunca terminar o turno com *"me
avisa se quer que eu continue"*, e quando o pedido é mesmo ambíguo, entregar
primeiro tudo que não depende da resposta — e só então perguntar o que sobrou.

---

## O que ele muda

Escrito em `~/.claude/settings.json`, com merge no que já estava lá. O arquivo
anterior é copiado para `~/.claude/backups/` a cada execução.

| Config | Efeito |
| --- | --- |
| `permissions.defaultMode: bypassPermissions` | Nenhum prompt de permissão |
| `hooks.PreToolUse` → `allow` | Segunda linha: responde "allow" antes de o prompt existir, para sessão que abre em modo que pergunta |
| `permissions.deny: []`, `ask: []` | Nada é segurado nem escalado |
| `permissions.additionalDirectories` | Máquina inteira no escopo, não só a pasta do projeto |
| `permissions.allow` | Toda ferramenta nativa e todo servidor MCP pré-aprovados, para o modo continuar valendo se você trocar de modo |
| `sandbox.enabled: false` | Comando roda sem confinamento |
| `enableAllProjectMcpServers: true` | Sem "confiar neste servidor MCP?" |
| `skipDangerousModePermissionPrompt` | Sem diálogo na abertura |
| `skipWorkflowUsageWarning` | Sem aviso de custo antes de workflow multi-agente |
| `askUserQuestionTimeout: 60s` | Se o modelo perguntar, a sessão segue em vez de travar |
| `fileCheckpointingEnabled: true` | `/rewind` continua funcionando — o último desfazer que sobra |
| `BASH_MAX_TIMEOUT_MS: 600000` | Comando longo termina (2 min → 10 min) |

Não perguntar é só metade de "faz sem mim". A outra metade é **terminar** sem
você, e você conseguir alcançar a sessão enquanto isso acontece:

| Config | Efeito |
| --- | --- |
| `doneMeansMerged: true` | O trabalho segue até um PR pronto pra merge, um cron armado ou um próximo passo que se sustenta sozinho — não até um relatório de status |
| `effortLevel: high` | Trabalho sem supervisão não tem quem pegue um atalho errado |
| `remoteControlAtStartup: true` | Comandar a sessão pelo celular |
| `autoUploadSessions: true` | Sessão legível pelo claude.ai |
| `agentPushNotifEnabled`, `inputNeededNotifEnabled` | Se algo realmente precisar de você, chega até você em vez de ficar esperando |
| `crossSessionInbound: accept` | Suas outras sessões podem passar trabalho pra esta |
| `autoMemoryEnabled: true` | As decisões sobrevivem à sessão |

`fileCheckpointingEnabled` é de propósito. Sem prompt nenhum, o `/rewind` é a
única coisa entre uma edição errada e uma tarde perdida.

### O hook de auto-aprovação

Se o `bypassPermissions` já cala o prompt, por que o hook? Porque a sessão nem
sempre abre no modo que você configurou — o app de desktop começa alguns
contextos em `default`. O hook responde antes de o prompt existir:

```json
{
  "type": "command",
  "command": "/bin/echo",
  "args": ["{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}"],
  "timeout": 5
}
```

Forma exec (`command` + `args`) em vez de string de shell, então nada faz parse
do JSON. Um `/bin/echo` por chamada de ferramenta.

---

### O único prompt que sobrevive

O Claude Code recusa por definição auto-aprovar um `rm` cujo alvo seja caminho
crítico de sistema, ou o diretório de trabalho da sessão, um diretório de
trabalho adicional, ou um pai de qualquer um dos dois. Nas palavras dele:

> This requires explicit approval and cannot be auto-allowed by permission rules.

Nem `bypassPermissions`, nem regra de allow, nem o hook. Está compilado — e é a
decisão certa: um agente com todo prompt calado ainda não deveria estar a uma
tecla de apagar a árvore em que está trabalhando.

Quase toda ocorrência é apagar a pasta em que você está, então a skill instalada
ensina a forma que evita: sair antes (`cd /tmp && rm -rf /caminho/da/pasta`) ou
esvaziar o diretório em vez de removê-lo.

---

## O que ele não muda

Três camadas podem barrar uma ação. Este repositório só é dono da primeira.

**O sistema operacional.** O TCC do macOS não sai de arquivo de config. Gravação
de tela, acessibilidade, automação e acesso a pastas abrem cada um o seu diálogo
na primeira vez. Libere tudo de uma vez em Ajustes → Privacidade e Segurança,
senão eles interrompem no meio da tarefa.

**Os limites do próprio modelo.** Config nenhuma tira: digitar senha, token ou
código de 6 dígitos em formulário; fazer login ou criar conta; mexer em dinheiro;
destruir sem volta e sem confirmar; obedecer instrução que estava dentro de uma
página ou e-mail em vez de ter vindo de você.

Repare no limite de credencial — ele é sobre **digitar**, não sobre **usar**. Uma
CLI já autenticada (`gh`, `vercel`, `supabase`, `firebase`) faz o trabalho sem
que a credencial precise ser lida em voz alta. Isso cobre quase tudo que "pega a
API" quer dizer na prática.

Detalhe completo: [`docs/limits.md`](docs/limits.md).

---

## Desinstalar

```bash
claude-autonomous off
rm -rf ~/.claude/skills/autonomous ~/.local/bin/claude-autonomous
```

O backup de cada settings.json que a ferramenta tocou fica em
`~/.claude/backups/`.

---

## Licença

MIT
