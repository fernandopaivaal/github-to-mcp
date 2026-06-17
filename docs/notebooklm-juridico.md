# Análise de processos judiciais com NotebookLM + Claude

Fluxo para transformar **PDFs grandes de autos processuais** (2.000+ páginas) em
**relatórios jurídicos estruturados**, usando o NotebookLM como camada de
condensação antes de submeter ao Claude.

## Por que esse desenho

PDFs de milhares de páginas estouram o limite de contexto de qualquer LLM (e do
próprio NotebookLM por fonte). A ideia:

```
PDF gigante  →  NotebookLM (ingere + indexa)  →  relatório .md condensado  →  Claude (análise final)
```

O relatório intermediário cabe folgado no contexto do Claude, e você não perde
informação relevante.

## Onde isso roda (importante)

O NotebookLM exige **login no navegador (conta Google)**. Por segurança, essa
autenticação fica **na sua máquina local** — nunca em containers remotos/efêmeros
(exporia os cookies da sua conta). Portanto:

- Rode o **Claude Code localmente** para que ele controle o NotebookLM por você, **ou**
- Rode o script abaixo manualmente no seu terminal local.

## Setup (uma vez, local)

```bash
pip install "notebooklm-py[browser]"
python -m playwright install chromium
notebooklm login      # autentica na conta Google
notebooklm doctor     # deve mostrar Auth ✓ pass
```

A permissão `Bash(notebooklm *)` já está em `.claude/settings.json`, então o
Claude local pode chamar o CLI sem pedir aprovação a cada vez.

## Uso

```bash
# Um PDF
scripts/notebooklm-juridico.sh autos.pdf "Processo 1234567-89.2025"

# Vários volumes no mesmo notebook (recomendado p/ processos grandes)
scripts/notebooklm-juridico.sh vol1.pdf vol2.pdf vol3.pdf "Processo 1234567-89.2025"
```

O script: cria o notebook → envia o(s) PDF(s) → aguarda o processamento → gera um
relatório jurídico estruturado → salva em `./reports/<nome>-relatorio.md`.

Variáveis opcionais: `NLM_OUTDIR` (diretório de saída) e `NLM_FORMAT`
(`custom` padrão, ou `briefing-doc`/`study-guide`/`blog-post`).

## Limites do NotebookLM e PDFs de 2.000+ páginas

Os limites mudam com frequência e dependem do plano (gratuito vs. **Plus**). Regra
geral atual: dezenas de fontes por notebook e um **limite de palavras por fonte**
(na casa de centenas de milhares). Um único PDF de 2.000+ páginas pode **exceder o
limite de uma fonte** — por isso o ideal é **dividir o PDF em partes** e adicionar
cada parte como uma fonte separada **no mesmo notebook** (o relatório considera
todas as fontes juntas).

Dividir um PDF grande em blocos de ~500 páginas:

```bash
# Opção A: qpdf
qpdf --split-pages=500 autos.pdf parte.pdf
#   → gera parte-0001-0500.pdf, parte-0501-1000.pdf, ...

# Opção B: pdftk
pdftk autos.pdf burst output pagina_%04d.pdf   # 1 arquivo por página (depois reagrupe)

# Opção C: poppler
pdfseparate -f 1 -l 500 autos.pdf parte1_%d.pdf
```

Depois:

```bash
scripts/notebooklm-juridico.sh parte-0001-0500.pdf parte-0501-1000.pdf ... "Processo X"
```

Dica: se uma fonte falhar no processamento (status de erro), normalmente é
tamanho — reduza o tamanho do bloco e tente de novo. `notebooklm source clean -n <nb>`
remove fontes com erro/duplicadas.

## Perguntas diretas ao notebook

Além do relatório, dá para interrogar os autos:

```bash
notebooklm ask -n <notebook> "Quais os pedidos do autor e o valor da causa?"
notebooklm ask -n <notebook> "Liste todas as decisões com data e resultado."
notebooklm ask -n <notebook> "Há prazos correndo? Quais e até quando?"
```

As respostas vêm com citações `[1]`, `[2]` apontando para as fontes.

## Entregando ao Claude

Com o `.md` em mãos, peça ao Claude (local) algo como:
_"Analise `reports/processo-1234-relatorio.md` e me diga a estratégia de defesa,
os riscos e os próximos atos."_ — agora cabe no contexto e a análise é completa.
