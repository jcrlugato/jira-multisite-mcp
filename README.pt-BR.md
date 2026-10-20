# jira-multisite-mcp

[![test](https://github.com/jcrlugato/jira-multisite-mcp/actions/workflows/test.yml/badge.svg)](https://github.com/jcrlugato/jira-multisite-mcp/actions/workflows/test.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Um servidor MCP que permite ao Claude trabalhar com **vários sites do Jira
Cloud na mesma conversa**.

*[Read in English](README.md)*

```
Você:   O que está atribuído a mim e ainda aberto, em todos os meus clientes?
Claude: [busca em 5 sites do Jira em paralelo]
        acme: SHOP-41 Checkout falha no Safari (In Progress), SHOP-38 ...
        side-project: SP-12 Migrar para Postgres 17 (Selected for development)
        ...
```

## Por quê

O conector MCP oficial da Atlassian autoriza **um site por conexão**. Se você
é consultor, freelancer ou trabalha com várias empresas, cada uma com o próprio
`algumacoisa.atlassian.net`, passa o dia desconectando e reconectando, e nunca
consegue perguntar sobre todos de uma vez.

Este servidor recebe uma lista de sites, usa um único API token e adiciona o
parâmetro `site` a todas as tools. Ele roda na sua máquina via stdio, então
funciona com o Claude Code, o Claude Desktop e outros clientes MCP.

É Ruby puro, com uma única dependência: a gem oficial
[`mcp`](https://github.com/modelcontextprotocol/ruby-sdk). HTTP, JSON e YAML
vêm da biblioteca padrão.

## O que dá para pedir

- "Lista meus sites do Jira."
- "O que está aberto e atribuído a mim em todos os sites?"
- "Mostra a SHOP-41 do acme com os últimos comentários."
- "Cria um bug no acme: o checkout falha no Safari 18. Atribui a mim."
- "Move a SHOP-41 para In Review e comenta que a correção está em staging."
- "Quais transições estão disponíveis para a SP-12?"

## Como funciona

```
Claude Code / Claude Desktop
        │  MCP via stdio (o app inicia o processo)
        ▼
bin/jira-multisite-mcp ── lê ~/.config/jira-multisite-mcp/sites.yml
        │  HTTPS, API REST v3 do Jira Cloud, basic auth (e-mail + API token)
        ├──▶ https://acme.atlassian.net
        ├──▶ https://side-project.atlassian.net
        └──▶ ...
```

O processo é iniciado pelo app do Claude quando ele abre e encerrado quando
ele fecha. Fica parado até o Claude chamar uma tool. Usa algumas dezenas de MB
de memória.

## Requisitos

- Ruby 3.1 ou mais recente
- Sites do Jira **Cloud** (`*.atlassian.net`). Jira Server / Data Center não é
  suportado.
- Uma conta Atlassian com acesso a esses sites

## Instalação

```bash
mkdir -p ~/code
git clone https://github.com/jcrlugato/jira-multisite-mcp.git ~/code/jira-multisite-mcp
cd ~/code/jira-multisite-mcp
bundle install
```

Qualquer pasta serve, desde que o caminho não mude depois, porque a
configuração do Claude aponta para ela. Evite pastas sincronizadas por iCloud,
Dropbox ou Google Drive.

## Configuração

### 1. Gere um API token

Acesse <https://id.atlassian.com/manage-profile/security/api-tokens> e clique
em **Create API token**. Um único token funciona em todos os sites a que a sua
conta tem acesso.

O formulário vem com validade de **uma semana**. Escolha **90 dias**; veja o
motivo em [Validade e renovação do token](#validade-e-renovação-do-token).

### 2. Liste os seus sites

```bash
mkdir -p ~/.config/jira-multisite-mcp
cp config/sites.example.yml ~/.config/jira-multisite-mcp/sites.yml
```

Edite o arquivo:

```yaml
sites:
  acme:
    url: https://acme.atlassian.net
    description: Acme Corp (cliente)
  side-project:
    url: https://side-project.atlassian.net
```

- A chave (`acme`) é o apelido que você e o Claude usam. Prefira algo curto.
- `description` é opcional. O Claude a vê, o que ajuda quando você fala
  "Acme" em vez do apelido.
- O arquivo fica fora do projeto de propósito: você pode atualizar ou apagar
  o código sem perder a lista. Use `JIRA_SITES_FILE` para guardá-lo em outro
  lugar.
- **Tokens nunca vão neste arquivo.** Eles vêm de variáveis de ambiente.

Um site de **outra conta Atlassian** pode ter credenciais próprias:

```yaml
  outro-cliente:
    url: https://outro-cliente.atlassian.net
    email: voce@outro-cliente.com
    token_env: OUTRO_CLIENTE_ATLASSIAN_TOKEN   # nome da variável de ambiente
```

### 3. Diga ao Claude como escrever issues (opcional, recomendado)

Sem orientação, o Claude escreve issues razoáveis. Com orientação, ele escreve
as **suas** issues. Adicione `guidelines` em texto livre, gerais e por site:

```yaml
guidelines: |
  Escreva as issues em português.
  Título: "[Área] Verbo + objeto", ex.: "[API] Retornar 404 para pedido inexistente".
  Descrição com as seções: Contexto, O que fazer, Critérios de aceite (em lista).
  Story = funcionalidade percebida pelo usuário; Task = trabalho técnico; Bug = algo que funcionava e quebrou.
  Sempre me mostre o rascunho e espere a minha confirmação antes de criar a issue.

sites:
  acme:
    url: https://acme.atlassian.net
    guidelines: |
      Projeto padrão: SHOP.
      Áreas: [Storefront], [Checkout], [Admin].
      Bugs sempre incluem passos para reproduzir e o navegador.
```

Como isso chega ao Claude:

- As diretrizes **gerais** vão nas instruções do servidor, que o cliente
  recebe ao conectar.
- As diretrizes **de cada site** são devolvidas pelo `list_sites`, e a tool
  `create_issue` orienta o Claude a segui-las.

Dicas para boas diretrizes:

- **Seja concreto.** "Título: `[Área] Verbo + objeto`" funciona; "escreva bons
  títulos" não.
- **Dê um exemplo** de título ou descrição. O Claude imita exemplos com mais
  fidelidade do que segue regras.
- **Diga quando perguntar.** "Sempre me mostre o rascunho antes" é o padrão
  mais seguro enquanto você se acostuma.
- **Coloque as convenções de cada cliente no site dele.** Chave do projeto,
  áreas, campos obrigatórios, idioma se o cliente usar outro.

As diretrizes são lidas quando o servidor inicia. Depois de editar, reinicie o
Claude Desktop ou abra uma nova sessão do Claude Code.

### 4. Conecte ao Claude

#### Claude Code

```bash
claude mcp add jira-multisite -s user \
  -e ATLASSIAN_EMAIL=voce@exemplo.com \
  -e ATLASSIAN_API_TOKEN=seu-token \
  -- ~/code/jira-multisite-mcp/bin/jira-multisite-mcp
```

O `-s user` deixa o servidor disponível em todos os seus projetos. Rode `/mcp`
dentro do Claude Code para conferir se o `jira-multisite` está conectado.

#### Claude Desktop

O arquivo de configuração é
`~/Library/Application Support/Claude/claude_desktop_config.json` no macOS e
`%APPDATA%\Claude\claude_desktop_config.json` no Windows. Adicione:

```json
{
  "mcpServers": {
    "jira-multisite": {
      "command": "/caminho/absoluto/do/ruby",
      "args": ["/Users/voce/code/jira-multisite-mcp/bin/jira-multisite-mcp"],
      "env": {
        "ATLASSIAN_EMAIL": "voce@exemplo.com",
        "ATLASSIAN_API_TOKEN": "seu-token"
      }
    }
  }
}
```

Três coisas costumam dar problema:

1. **Use o caminho absoluto do Ruby.** O Claude Desktop não carrega o perfil
   do seu shell, então um Ruby instalado via mise, rbenv, asdf ou chruby não
   está no `PATH` dele. Descubra o caminho com `mise which ruby` (ou
   `rbenv which ruby`, `which ruby`).
2. **O arquivo pode já existir** com as preferências do próprio app.
   Adicione a chave `mcpServers` ao lado delas; não substitua o arquivo. O
   script abaixo faz essa mesclagem para você.
3. **Feche o app (Cmd+Q) antes de editar** e abra de novo depois. O app
   regrava o arquivo e pode sobrescrever a sua alteração se estiver aberto.

Script de mesclagem (macOS). Rode a primeira linha sozinha, cole o token
quando for pedido (ele não aparece na tela) e depois cole o resto. Ajuste os
dois caminhos antes.

```bash
printf "Token Atlassian: "; read -s ATLASSIAN_API_TOKEN; echo; export ATLASSIAN_API_TOKEN
```

```bash
F="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
[ -f "$F" ] || echo '{}' > "$F"
cp "$F" "$F.bak"
ruby -rjson -e '
  f = ARGV[0]
  cfg = JSON.parse(File.read(f))
  cfg["mcpServers"] ||= {}
  cfg["mcpServers"]["jira-multisite"] = {
    "command" => "/caminho/absoluto/do/ruby",
    "args"    => ["/Users/voce/code/jira-multisite-mcp/bin/jira-multisite-mcp"],
    "env"     => {
      "ATLASSIAN_EMAIL"     => "voce@exemplo.com",
      "ATLASSIAN_API_TOKEN" => ENV.fetch("ATLASSIAN_API_TOKEN")
    }
  }
  File.write(f, JSON.pretty_generate(cfg) + "\n")
' "$F"
ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["mcpServers"].keys' "$F"
```

A última linha deve imprimir `jira-multisite`. Para desfazer:
`cp "$F.bak" "$F"`.

#### Outros clientes MCP

Qualquer cliente que rode servidores stdio funciona (Cursor, Windsurf,
Zed...). O comando é `bin/jira-multisite-mcp` (ou
`ruby bin/jira-multisite-mcp`), com `ATLASSIAN_EMAIL` e `ATLASSIAN_API_TOKEN`
no ambiente.

### 5. Confira

Peça nesta ordem. Cada passo testa uma camada:

1. "Lista meus sites do Jira." Sem chamada de rede: testa a configuração.
2. "Lista os projetos do acme." Testa o token em um site.
3. "O que está atribuído a mim e não concluído, em todos os sites?" Testa a
   busca em paralelo.

## Tools

| Tool | O que faz |
|---|---|
| `list_sites` | Sites configurados e diretrizes. Sem chamada de rede. |
| `list_projects` | Chaves e nomes dos projetos visíveis para você em um site. |
| `search_issues` | Busca por JQL. Com `site`: um site, com paginação. **Sem `site`: todos os sites em paralelo**; um site que falha é reportado e os outros continuam respondendo. |
| `get_issue` | Uma issue: campos, descrição e os últimos comentários, em texto simples. |
| `create_issue` | Cria com tipo, descrição, labels, prioridade, responsável e issue pai. |
| `update_issue` | Altera título, descrição, labels, prioridade ou responsável. Só os campos informados mudam. |
| `transition_issue` | Muda o status. `to` compara com o nome da transição ou com o status de destino, sem diferenciar maiúsculas. Sem `to`, lista o que está disponível agora. |
| `add_comment` | Comenta em uma issue. |

Detalhes que vale saber:

- **Texto simples na entrada e na saída.** O Jira guarda descrições e
  comentários em Atlassian Document Format (JSON). O servidor converte nos
  dois sentidos; uma linha em branco inicia um novo parágrafo.
- **Responsável** aceita `me`, `none` (remove o responsável), um accountId ou
  um nome ou e-mail. Se um nome corresponder a várias pessoas, a tool devolve
  as opções em vez de chutar.
- **Os erros são escritos para o modelo.** Uma transição inválida lista as
  válidas; um 401 diz qual site falhou e sugere conferir o token. O Claude lê
  a mensagem e se corrige.
- As tools têm anotações MCP (somente leitura ou escrita), para que os
  clientes possam pedir confirmação antes de alterações.

## Segurança

- Um API token clássico da Atlassian **não tem escopo**: ele faz tudo o que a
  sua conta faz, em todos os sites, inclusive os de clientes. Trate-o como uma
  senha.
- O token fica em texto puro na configuração do cliente (`~/.claude.json` no
  Claude Code, `claude_desktop_config.json` no Claude Desktop). Mantenha esses
  arquivos fora de repositórios de dotfiles e de backups compartilhados.
- O `sites.yml` nunca guarda tokens, e o `list_sites` nunca os devolve.
- O servidor só se comunica com as URLs `https://` do seu `sites.yml`. Nada
  é enviado a outro lugar e nada é gravado em disco.

## Validade e renovação do token

**Escolha 90 dias.** A Atlassian permite até um ano; o formulário vem com uma
semana.

- Por que não um ano: o token não tem escopo e fica em texto puro. Uma
  validade menor limita o estrago se ele vazar.
- Por que não uma semana: renovar com muita frequência leva a renovações às
  pressas ou adiadas.

Dê ao token um nome que indique o uso (por exemplo, `claude-mcp`) e crie um
lembrete na agenda alguns dias antes de ele vencer.

**Como perceber que expirou:** todas as chamadas falham em todos os sites ao
mesmo tempo, com `Authentication failed for site '…': check the email and API
token.` Se só um site falhar, o token está bom e a sua conta perdeu o acesso
àquele site.

**Para renovar:**

1. Gere um token novo na mesma página da Atlassian.
2. Substitua-o no cliente:
   - Claude Code: `claude mcp remove jira-multisite` e depois o comando
     `claude mcp add` acima, com o token novo.
   - Claude Desktop: rode o script de mesclagem de novo, ou edite o
     `ATLASSIAN_API_TOKEN` na configuração, e então feche e reabra o app.
3. Confira com "Lista os projetos do <site>".
4. Revogue o token antigo.

## Solução de problemas

Os diagnósticos vão para o stderr. O Claude Desktop os salva em
`~/Library/Logs/Claude/mcp-server-jira-multisite.log`; o Claude Code mostra o
estado do servidor em `/mcp`. Rode o servidor à mão para ver erros de
inicialização:

```bash
ATLASSIAN_EMAIL=voce@exemplo.com ATLASSIAN_API_TOKEN=x \
  ~/code/jira-multisite-mcp/bin/jira-multisite-mcp < /dev/null
```

Ele imprime os sites carregados e termina. Problemas comuns:

| Sintoma | Causa e solução |
|---|---|
| `Sites file not found` | Crie `~/.config/jira-multisite-mcp/sites.yml` ou defina `JIRA_SITES_FILE`. |
| `environment variable ATLASSIAN_API_TOKEN is empty` | Falta a entrada `env` na configuração do cliente, ou o nome da variável em `token_env` está errado. |
| O servidor não aparece no Claude Desktop | Caminho do Ruby não absoluto, JSON inválido, ou o app estava aberto durante a edição. Veja o arquivo de log. |
| `cannot load such file -- mcp` | Faltou rodar `bundle install`, ou o Claude usa um Ruby diferente daquele em que você instalou as gems. Depois de atualizar o Ruby, rode `bundle install` de novo. |
| `Authentication failed` em todos os sites | Token expirado ou revogado, ou e-mail errado. |
| `Authentication failed` / `Not found` em um site | A sua conta não tem acesso a ele, ou a URL está errada. |
| Issues concluídas aparecem como abertas | O workflow do site coloca "Done" na categoria de status errada. Corrija no Jira: Space settings → Workflows → editar → status → Category. |

## Limitações

- **Só local (stdio).** Não funciona como conector personalizado no claude.ai
  pela web ou pelos apps de celular, que exigem um servidor HTTP remoto. Isso
  está no roadmap.
- Apenas Jira Cloud. API tokens clássicos com basic auth.
- Ainda sem anexos, sprints, registro de horas ou campos personalizados.
- `list_projects` devolve os 100 primeiros projetos de um site.

## Roadmap

- Modo remoto (Streamable HTTP + OAuth), para ser adicionado como conector
  personalizado no claude.ai, com um painel web simples para gerenciar as
  conexões.
- Tools para sprints, versões e campos personalizados.

Ideias e pull requests são bem-vindos.

## Desenvolvimento

```bash
bundle install
bundle exec rake test
```

Os testes não precisam de rede nem de conta no Jira: eles percorrem o caminho
real de requisições MCP, inclusive a validação de schema, contra um adaptador
HTTP simulado.

```
bin/jira-multisite-mcp          ponto de entrada stdio
lib/jira_multisite.rb           montagem do servidor, lista de tools, instruções
lib/jira_multisite/config.rb    sites.yml, diretrizes e credenciais
lib/jira_multisite/client.rb    cliente da API REST v3 do Jira, adaptador HTTP injetável
lib/jira_multisite/adf.rb       texto simples <-> Atlassian Document Format
lib/jira_multisite/registry.rb  clientes por site, entregues às tools via server_context
lib/jira_multisite/tools/       uma classe por tool, todas herdando de Tools::Base
```

As tools recebem os sites pelo `server_context` do MCP em vez de uma variável
global, então as mesmas classes podem rodar num app web multiusuário, com um
registry montado por requisição. Veja o [CONTRIBUTING.md](CONTRIBUTING.md)
para adicionar uma tool.

## Licença

[MIT](LICENSE)
