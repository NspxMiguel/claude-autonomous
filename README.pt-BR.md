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

**Windows** (não precisa de administrador)

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
claude-autonomous off      # desfaz tudo
```

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
