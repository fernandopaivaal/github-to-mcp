#!/usr/bin/env bash
#
# split-pdf.sh — fatia um PDF grande em blocos de N páginas, para caber no
# limite por fonte do NotebookLM (PDFs de 2.000+ páginas geralmente excedem).
#
# Detecta automaticamente a ferramenta disponível: qpdf > pdftk > poppler.
#
# PRÉ-REQUISITO: uma destas instaladas localmente —
#   qpdf            (recomendado)   ex.: brew install qpdf | apt install qpdf
#   pdftk + pdfinfo                  ex.: apt install pdftk poppler-utils
#   pdfseparate + pdfunite (poppler) ex.: apt install poppler-utils
#
# USO:
#   scripts/split-pdf.sh <arquivo.pdf> [paginas_por_bloco]   # default: 500
#
# SAÍDA: <NLM_SPLITDIR ou ./split>/<nome>/<nome>-NNNN-MMMM.pdf
# Ao final, imprime o comando pronto para enviar os blocos ao NotebookLM.
#
set -euo pipefail

die() { echo "✗ $*" >&2; exit 1; }

PDF="${1:-}"
CHUNK="${2:-500}"
[ -n "$PDF" ] || die "Uso: $0 <arquivo.pdf> [paginas_por_bloco]"
[ -f "$PDF" ] || die "Arquivo não encontrado: $PDF"
[[ "$CHUNK" =~ ^[0-9]+$ ]] && [ "$CHUNK" -ge 1 ] || die "paginas_por_bloco deve ser um inteiro >= 1"

BASE="$(basename "$PDF" .pdf)"
OUTDIR="${NLM_SPLITDIR:-./split}/$BASE"
mkdir -p "$OUTDIR"

# Descobre o total de páginas (qpdf ou pdfinfo).
total=""
if command -v qpdf >/dev/null; then
  total="$(qpdf --show-npages "$PDF" 2>/dev/null || true)"
fi
if [ -z "$total" ] && command -v pdfinfo >/dev/null; then
  total="$(pdfinfo "$PDF" 2>/dev/null | awk '/^Pages:/ {print $2}')"
fi
[[ "$total" =~ ^[0-9]+$ ]] || die "Não foi possível contar as páginas (instale qpdf ou poppler-utils)."

echo "→ $PDF: $total páginas, blocos de $CHUNK → $OUTDIR"

pad() { printf '%04d' "$1"; }

if command -v qpdf >/dev/null; then
  qpdf --split-pages="$CHUNK" "$PDF" "$OUTDIR/$BASE.pdf"
  # qpdf nomeia como <base>-0001-0500.pdf automaticamente.
elif command -v pdftk >/dev/null; then
  start=1
  while [ "$start" -le "$total" ]; do
    end=$(( start + CHUNK - 1 )); [ "$end" -gt "$total" ] && end="$total"
    out="$OUTDIR/$BASE-$(pad "$start")-$(pad "$end").pdf"
    pdftk "$PDF" cat "$start"-"$end" output "$out"
    start=$(( end + 1 ))
  done
elif command -v pdfseparate >/dev/null && command -v pdfunite >/dev/null; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  start=1
  while [ "$start" -le "$total" ]; do
    end=$(( start + CHUNK - 1 )); [ "$end" -gt "$total" ] && end="$total"
    pdfseparate -f "$start" -l "$end" "$PDF" "$tmp/p-%d.pdf"
    out="$OUTDIR/$BASE-$(pad "$start")-$(pad "$end").pdf"
    # Reúne na ordem numérica correta.
    mapfile -t pages < <(ls "$tmp"/p-*.pdf | sort -t- -k2 -n)
    pdfunite "${pages[@]}" "$out"
    rm -f "$tmp"/p-*.pdf
    start=$(( end + 1 ))
  done
else
  die "Nenhuma ferramenta de PDF encontrada. Instale qpdf (recomendado), pdftk ou poppler-utils."
fi

echo
echo "✓ Blocos gerados em: $OUTDIR"
ls -1 "$OUTDIR"/*.pdf
echo
echo "Próximo passo — enviar todos os blocos ao mesmo notebook:"
echo "  scripts/notebooklm-juridico.sh $OUTDIR/*.pdf \"$BASE\""
