#!/usr/bin/env bash
#
# notebooklm-juridico.sh — fluxo de análise de processos judiciais via NotebookLM.
#
# Cria um notebook, envia um (ou vários) PDFs como fontes, aguarda o
# processamento, gera um relatório jurídico estruturado e o baixa em Markdown.
#
# PRÉ-REQUISITOS (na sua máquina local, NÃO no container remoto):
#   pip install "notebooklm-py[browser]"
#   python -m playwright install chromium
#   notebooklm login          # autentica na sua conta Google (1x)
#
# USO:
#   scripts/notebooklm-juridico.sh <arquivo.pdf> ["Título do notebook"]
#   scripts/notebooklm-juridico.sh autos-vol1.pdf autos-vol2.pdf "Proc 1234"
#
# VARIÁVEIS DE AMBIENTE OPCIONAIS:
#   NLM_OUTDIR    diretório de saída dos relatórios (default: ./reports)
#   NLM_FORMAT    custom|briefing-doc|study-guide|blog-post (default: custom)
#
set -euo pipefail

OUTDIR="${NLM_OUTDIR:-./reports}"
FORMAT="${NLM_FORMAT:-custom}"

die() { echo "✗ $*" >&2; exit 1; }

[ "$#" -ge 1 ] || die "Uso: $0 <arquivo.pdf> [arquivo2.pdf ...] [\"Título\"]"
command -v notebooklm >/dev/null || die "CLI 'notebooklm' não encontrado. Rode: pip install 'notebooklm-py[browser]'"
command -v jq >/dev/null || die "'jq' é necessário."

# Separa os PDFs (existem no disco) de um eventual título final (último arg que não é arquivo).
PDFS=()
TITLE=""
for arg in "$@"; do
  if [ -f "$arg" ]; then
    PDFS+=("$arg")
  else
    TITLE="$arg"
  fi
done
[ "${#PDFS[@]}" -ge 1 ] || die "Nenhum PDF válido encontrado nos argumentos."
[ -n "$TITLE" ] || TITLE="Processo $(basename "${PDFS[0]}" .pdf)"

echo "→ Criando notebook: $TITLE"
NB="$(notebooklm create "$TITLE" --json | jq -r '.id // .notebook_id // .notebookId // empty')"
[ -n "$NB" ] || die "Falha ao obter o ID do notebook (verifique a autenticação: notebooklm doctor)."
echo "  notebook: $NB"

for PDF in "${PDFS[@]}"; do
  echo "→ Enviando: $PDF (arquivos grandes podem demorar)…"
  SRC="$(notebooklm source add "$PDF" -n "$NB" --type file --timeout 600 --json \
        | jq -r '.id // .source_id // .sourceId // empty')"
  [ -n "$SRC" ] || die "Falha ao adicionar a fonte: $PDF"
  echo "  fonte: $SRC — aguardando processamento…"
  notebooklm source wait "$SRC" -n "$NB" --timeout 1800 --interval 5 \
    || die "Processamento da fonte falhou ou estourou o tempo: $PDF (pode ter excedido o limite de tamanho — veja docs/notebooklm-juridico.md)"
done

echo "→ Gerando relatório de análise jurídica ($FORMAT)…"
PROMPT_FILE="$(mktemp)"
trap 'rm -f "$PROMPT_FILE"' EXIT
cat > "$PROMPT_FILE" <<'PROMPT'
Você é um assistente jurídico brasileiro. Analise as fontes (autos de processo
judicial) e produza um relatório estruturado em português do Brasil, objetivo e
citando as fontes [1], [2] ao longo do texto.

Primeiro, identifique a(s) área(s) jurídica(s) do processo (ex.: cível,
trabalhista, tributário, penal, administrativo, consumidor, família, empresarial)
e adapte a análise a ela(s). Use exatamente estas seções:

1. Identificação: número do processo, vara/juízo/tribunal, área(s) jurídica(s),
   partes (autor/reclamante/exequente e réu/reclamada/executado, com respectivos
   advogados), valor da causa e fase processual atual.
2. Síntese fática: fatos relevantes em ordem cronológica, sempre com as datas.
3. Pedidos e causa de pedir.
4. Teses e fundamentos jurídicos de cada parte (com os dispositivos legais e as
   súmulas/precedentes citados).
5. Provas produzidas e sua relevância.
6. Decisões e andamentos (despachos, decisões interlocutórias, sentenças,
   acórdãos), com data e teor resumido de cada um.
7. Prazos em aberto e próximos atos processuais esperados.
8. Pontos controvertidos e riscos (incluindo prescrição/decadência e nulidades).
9. Análise por área jurídica — preencha apenas as aplicáveis ao processo:
   - Cível: natureza da obrigação/responsabilidade (contratual ou
     extracontratual), nexo causal, danos (material, moral, lucros cessantes),
     cláusulas contratuais relevantes e tutelas/medidas de urgência.
   - Trabalhista: vínculo empregatício, verbas rescisórias, horas extras, FGTS,
     adicionais, dano moral, responsabilidade subsidiária/solidária e eventual
     execução com cálculos.
   - Tributário: tributo(s) e competência, fato gerador, base de cálculo,
     lançamento, decadência/prescrição, certidão de dívida ativa, garantias e
     discussão administrativa x judicial.
   - Outras áreas (penal, administrativo, consumidor, família, empresarial etc.):
     faça a análise específica equivalente, destacando os institutos próprios da
     matéria.
10. Recomendações e próximos passos (estratégia, recursos cabíveis e seus prazos).

Seja preciso com nomes, números e datas. Se alguma informação não constar nos
autos, escreva "não consta nas fontes".
PROMPT

if [ "$FORMAT" = "custom" ]; then
  notebooklm generate report --format custom --prompt-file "$PROMPT_FILE" \
    -n "$NB" --wait --timeout 600 --retry 2
else
  notebooklm generate report --format "$FORMAT" \
    -n "$NB" --wait --timeout 600 --retry 2
fi

mkdir -p "$OUTDIR"
OUT="$OUTDIR/$(basename "${PDFS[0]}" .pdf)-relatorio.md"
notebooklm download report -n "$NB" "$OUT"

echo
echo "✓ Relatório salvo em: $OUT"
echo "  Notebook: $NB"
echo
echo "Próximo passo: envie '$OUT' ao Claude para a análise final, ou faça"
echo "perguntas direto ao notebook, ex.:"
echo "  notebooklm ask -n $NB \"Quais os riscos de sucumbência neste processo?\""
