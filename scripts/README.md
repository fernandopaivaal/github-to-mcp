# Cola rápida — NotebookLM jurídico

Fluxo: **PDF grande → NotebookLM condensa → relatório `.md` → Claude analisa.**
Roda na **sua máquina local** (precisa de login no Google). Guia completo:
[`docs/notebooklm-juridico.md`](../docs/notebooklm-juridico.md).

## Setup (uma vez)

```bash
pip install "notebooklm-py[browser]"
python -m playwright install chromium
brew install qpdf          # macOS  (ou: sudo apt install qpdf)
notebooklm login           # login na conta Google no navegador
notebooklm doctor          # deve mostrar Auth ✓ pass
```

## Uso — PDF grande (2.000+ páginas)

```bash
scripts/split-pdf.sh autos.pdf 500                       # 1) fatia em blocos de 500 págs
scripts/notebooklm-juridico.sh split/autos/*.pdf "Proc 1234"   # 2) envia + gera relatório
```

## Uso — PDF pequeno (sem fatiar)

```bash
scripts/notebooklm-juridico.sh peticao.pdf "Proc 1234"
```

Relatório gerado em: `./reports/<nome>-relatorio.md`

## Depois

```bash
# Entregar ao Claude (Claude Code local, nesta pasta):
#   "Analise reports/<nome>-relatorio.md: estratégia, riscos e próximos atos."

# Ou perguntar direto aos autos:
notebooklm ask -n <notebook> "Há prazos correndo? Quais e até quando?"
notebooklm list                                          # ver IDs dos notebooks
```

## Opções úteis

| O quê                             | Como                                                         |
| --------------------------------- | ------------------------------------------------------------ |
| Bloco com outro tamanho           | `scripts/split-pdf.sh autos.pdf 300`                         |
| Diretório de saída do relatório   | `NLM_OUTDIR=./laudos scripts/notebooklm-juridico.sh ...`     |
| Formato pronto (em vez do custom) | `NLM_FORMAT=briefing-doc scripts/notebooklm-juridico.sh ...` |
| Limpar fontes com erro/duplicadas | `notebooklm source clean -n <notebook>`                      |
