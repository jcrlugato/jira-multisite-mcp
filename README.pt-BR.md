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
- "Coloca a SHOP-41 no épico SHOP-10 e na fix version v1.0."

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

Clone o repositório e instale as gems:

```bash
mkdir -p ~/code
git clone https://github.com/jcrlugato/jira-multisite-mcp.git ~/code/jira-multisite-mcp
cd ~/code/jira-multisite-mcp
bundle install
```

Qualquer pasta serve, desde que o caminho não mude depois, porque a
configuração do Claude aponta para ela. Evite pastas sincronizadas por iCloud,
Dropbox ou Google Drive.

Depois, **na mesma pasta**, anote o caminho absoluto do Ruby que você acabou
de usar. Os passos 5 e 6 precisam dele:

```bash
mise which ruby     # ou: rbenv which ruby, asdf which ruby, which ruby
# /Users/voce/.local/share/mise/installs/ruby/3.4.7/bin/ruby
```

O Claude inicia o servidor sem o perfil do seu shell, então não encontra
sozinho um Ruby gerenciado por mise, rbenv, asdf ou chruby, e as gems do
`bundle install` só existem nesse Ruby. Use o caminho com a versão exata.
Atalhos como o `installs/ruby/3` do mise passam a apontar para o Ruby mais
novo que você instalar, e o servidor quebra na próxima atualização.

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

### 3. Guarde as credenciais

```bash
cp .env.example ~/.config/jira-multisite-mcp/.env
chmod 600 ~/.config/jira-multisite-mcp/.env
```

Abra o `~/.config/jira-multisite-mcp/.env` e preencha o seu e-mail e o token
do passo 1:

```bash
ATLASSIAN_EMAIL=voce@exemplo.com
ATLASSIAN_API_TOKEN=seu-token
```

- O arquivo fica ao lado do `sites.yml`, fora do repositório, então o token
  não tem como entrar num commit. Um `.env` na raiz do repositório também
  funciona (o git o ignora); o que está ao lado do `sites.yml` tem
  prioridade.
- O `chmod 600` deixa o arquivo legível só por você. O servidor avisa no log
  quando outros usuários conseguem lê-lo. No Windows, pule esse comando.
- O formato é um `CHAVE=valor` por linha, com aspas opcionais e comentários
  com `#`. Nada além disso é suportado.
- As linhas comentadas no fim do `.env.example` servem só para um site de
  outra conta Atlassian (`token_env` no passo 2). Apague-as se não precisar.

Você também pode passar as variáveis pela configuração do cliente MCP (`-e`
no Claude Code, `env` no Claude Desktop). Uma variável definida pelo cliente
vence o arquivo. A desvantagem: os apps mostram essa configuração na tela,
com o token, e renovar o token exige editar cada cliente.

### 4. Diga ao Claude como escrever issues (opcional, recomendado)

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

### 5. Teste à mão

Antes de envolver o Claude, inicie o servidor do jeito que o Claude faz: sem
o perfil do shell, a partir de outra pasta, com o caminho do Ruby anotado na
[Instalação](#instalação).

```bash
cd / && env -i HOME="$HOME" \
  /caminho/absoluto/do/ruby ~/code/jira-multisite-mcp/bin/jira-multisite-mcp < /dev/null
```

Saída esperada:

```
jira-multisite-mcp: read ATLASSIAN_EMAIL, ATLASSIAN_API_TOKEN from /Users/voce/.config/jira-multisite-mcp/.env
jira-multisite-mcp <versão>: Ruby 3.4.7, sites acme, side-project
```

Qualquer outra coisa é um erro de inicialização que o Claude mostraria só
como "Connection closed"; veja [Solução de problemas](#solução-de-problemas).
Este teste confere a configuração e se as variáveis estão preenchidas, não se
o token é válido: isso fica para o passo 7. Sem o `< /dev/null`, o servidor
fica esperando um cliente; saia com Ctrl+C.

### 6. Conecte ao Claude

Use em todos os clientes o caminho absoluto do Ruby anotado na
[Instalação](#instalação). As credenciais vêm do arquivo `.env`, então a
configuração do cliente não guarda token.

#### Claude Code

```bash
claude mcp add jira-multisite -s user \
  -- /caminho/absoluto/do/ruby ~/code/jira-multisite-mcp/bin/jira-multisite-mcp
```

O `-s user` deixa o servidor disponível em todos os seus projetos. Rode `/mcp`
dentro do Claude Code para conferir se o `jira-multisite` está conectado.

Aqui o caminho absoluto do Ruby importa ainda mais. O Claude Code inicia o
servidor a partir do projeto que está aberto. Se esse projeto fixa outra
versão do Ruby com mise, rbenv, asdf ou chruby, um `ruby` sem caminho vira
essa versão, que não tem as gems do servidor: ele funciona em alguns projetos
e mostra "Connection closed" em outros.

#### Claude Desktop

1. **Feche o app (Cmd+Q).** Ele reescreve o arquivo de configuração enquanto
   está aberto e pode apagar a sua alteração.
2. **Adicione o servidor ao arquivo de configuração:**
   `~/Library/Application Support/Claude/claude_desktop_config.json` no macOS,
   `%APPDATA%\Claude\claude_desktop_config.json` no Windows. O arquivo pode
   já ter as preferências do próprio app: adicione a chave `mcpServers` ao
   lado delas, sem substituir o arquivo. No macOS, isto mescla a entrada e
   guarda um backup:

   ```bash
   F="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
   RUBY=/caminho/absoluto/do/ruby
   SERVER="$HOME/code/jira-multisite-mcp/bin/jira-multisite-mcp"
   [ -f "$F" ] || echo '{}' > "$F"
   cp "$F" "$F.bak"
   "$RUBY" -rjson -e '
     f, ruby, server = ARGV
     cfg = JSON.parse(File.read(f))
     (cfg["mcpServers"] ||= {})["jira-multisite"] = { "command" => ruby, "args" => [server] }
     File.write(f, JSON.pretty_generate(cfg) + "\n")
   ' "$F" "$RUBY" "$SERVER"
   "$RUBY" -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["mcpServers"]["jira-multisite"]' "$F"
   ```

   A última linha mostra a entrada. Para desfazer: `cp "$F.bak" "$F"`.
3. **Abra o app de novo** e confira se o `jira-multisite` aparece como ativo
   nas configurações de servidores MCP.

Para editar o arquivo à mão, a entrada é:

```json
{
  "mcpServers": {
    "jira-multisite": {
      "command": "/caminho/absoluto/do/ruby",
      "args": ["/Users/voce/code/jira-multisite-mcp/bin/jira-multisite-mcp"]
    }
  }
}
```

O botão de editar a configuração no app só mostra o arquivo no Finder; abra-o
com `open -e "$F"` ou no seu editor. Numa edição à mão é comum sumir uma `}`
ou sobrar uma vírgula, e aí o app ignora o servidor sem avisar. Confira o JSON
antes de reabrir o app:

```bash
ruby -rjson -e 'JSON.parse(File.read(ARGV[0])); puts "JSON ok"' "$F"
```

#### Já passa o token pela configuração do cliente?

Mova os valores para o arquivo `.env` (passo 3) e depois tire-os do cliente,
porque uma variável definida pelo cliente vence o arquivo:

- Claude Code: `claude mcp remove jira-multisite -s user` e depois o comando
  `claude mcp add` acima.
- Claude Desktop: apague da entrada o bloco `"env": { ... }`, junto com a
  vírgula antes dele, confira o JSON e reinicie o app.

#### Outros clientes MCP

Qualquer cliente que rode servidores stdio funciona (Cursor, Windsurf,
Zed...). O comando é o caminho absoluto do Ruby, com
`bin/jira-multisite-mcp` como argumento. As credenciais vêm do arquivo `.env`.

### 7. Confira

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
| `list_versions` | Versões de um projeto, com status (lançada, não lançada, arquivada) e data de lançamento. |
| `search_issues` | Busca por JQL. Com `site`: um site, com paginação. **Sem `site`: todos os sites em paralelo**; um site que falha é reportado e os outros continuam respondendo. |
| `get_issue` | Uma issue: campos, descrição e os últimos comentários, em texto simples. |
| `create_issue` | Cria com tipo, descrição, labels, prioridade, responsável, issue pai e fix versions. |
| `update_issue` | Altera título, descrição, labels, prioridade, responsável, issue pai ou fix versions. Só os campos informados mudam. |
| `transition_issue` | Muda o status. `to` compara com o nome da transição ou com o status de destino, sem diferenciar maiúsculas. Sem `to`, lista o que está disponível agora. |
| `add_comment` | Comenta em uma issue. |

Detalhes que vale saber:

- **Texto simples na entrada e na saída.** O Jira guarda descrições e
  comentários em Atlassian Document Format (JSON). O servidor converte nos
  dois sentidos; uma linha em branco inicia um novo parágrafo.
- **Responsável** aceita `me`, `none` (remove o responsável), um accountId ou
  um nome ou e-mail. Se um nome corresponder a várias pessoas, a tool devolve
  as opções em vez de chutar.
- **Issue pai e fix versions.** `parent` recebe a chave de uma issue
  (normalmente um épico); no `update_issue`, `none` remove o pai (não vale
  para subtarefas). `fix_versions` recebe nomes de versão vindos do
  `list_versions`; no `update_issue` a lista substitui as versões atuais, e
  `[]` remove todas.
- **Os erros são escritos para o modelo.** Uma transição inválida lista as
  válidas; um 401 diz qual site falhou e sugere conferir o token; uma versão ou
  issue pai recusada indica o `list_versions` ou uma busca por épicos. O
  Claude lê a mensagem e se corrige.
- As tools têm anotações MCP (somente leitura ou escrita), para que os
  clientes possam pedir confirmação antes de alterações.

## Segurança

- Um API token clássico da Atlassian **não tem escopo**: ele faz tudo o que a
  sua conta faz, em todos os sites, inclusive os de clientes. Trate-o como uma
  senha.
- O token fica em texto puro, no seu arquivo `.env` ou na configuração do
  cliente (`~/.claude.json` no Claude Code, `claude_desktop_config.json` no
  Claude Desktop). Mantenha esses arquivos fora de repositórios de dotfiles e
  de backups compartilhados. Prefira o `.env` com `chmod 600`: o servidor avisa
  no log quando outros usuários conseguem lê-lo, e os apps não o mostram na
  tela.
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
2. Substitua-o onde ele está guardado:
   - Arquivo `.env`: edite o `ATLASSIAN_API_TOKEN` e reinicie o Claude Desktop
     ou abra uma nova sessão do Claude Code.
   - Configuração do cliente, se você o passa por lá: edite o
     `ATLASSIAN_API_TOKEN` na opção `-e` (Claude Code: remova e adicione o
     servidor de novo) ou no bloco `env` (Claude Desktop) e reinicie o
     cliente.
3. Confira com "Lista os projetos do <site>".
4. Revogue o token antigo.

## Solução de problemas

Os diagnósticos vão para o stderr. O Claude Desktop os salva em
`~/Library/Logs/Claude/mcp-server-jira-multisite.log`; o Claude Code mostra o
estado do servidor em `/mcp`. Para ver erros de inicialização, rode o servidor à mão
como em [Teste à mão](#5-teste-à-mão). Problemas comuns:

| Sintoma | Causa e solução |
|---|---|
| `Sites file not found` | Crie `~/.config/jira-multisite-mcp/sites.yml` ou defina `JIRA_SITES_FILE`. |
| `environment variable ATLASSIAN_API_TOKEN is empty` | Não há arquivo `.env` onde o servidor procura (ao lado do `sites.yml` ou na raiz do repositório) nem a entrada `env` na configuração do cliente, ou o nome da variável em `token_env` está errado. Quando um `.env` é usado, o log mostra `read ... from <caminho>`. |
| `.env, line N: expected KEY=value` | Essa linha do arquivo `.env` não está no formato `CHAVE=valor`. O valor precisa caber em uma linha. |
| O servidor não aparece no Claude Desktop | Caminho do Ruby não absoluto, JSON inválido, ou o app estava aberto durante a edição. Veja o arquivo de log. |
| "Server disconnected" / "Connection closed" logo depois de atualizar o Ruby | O cliente aponta para um atalho do Ruby (como o `installs/ruby/3` do mise) que agora leva ao Ruby novo, sem as gems. Aponte para a versão exata e rode `bundle install` com esse Ruby. |
| Funciona em alguns projetos do Claude Code e mostra "Connection closed" em outros | Esses projetos fixam outra versão do Ruby, e o gerenciador de versões troca para ela. Registre o servidor com o caminho absoluto do Ruby (veja [Claude Code](#claude-code)). A linha de log `could not load its gems` mostra qual Ruby foi usado. |
| `could not load its gems` / `cannot load such file -- mcp` | Faltou rodar `bundle install`, ou o Claude usa um Ruby diferente daquele em que você instalou as gems. Use o caminho absoluto do Ruby na configuração do cliente. Depois de atualizar o Ruby, rode `bundle install` de novo. |
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
- Tools para sprints e campos personalizados.

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
lib/jira_multisite/env_file.rb  leitor do .env (credenciais fora da config do cliente)
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
