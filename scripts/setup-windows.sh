#!/usr/bin/env bash
#
# setup-windows.sh — prepara o ambiente local (Git Bash, no Windows) para o
# fluxo de análise jurídica com NotebookLM. Idempotente: pode rodar de novo.
#
# Pré-requisitos que precisam ser instalados ANTES (instaladores próprios):
#   - Git for Windows (este Git Bash)      https://git-scm.com/download/win
#   - Python 3.11+ (marque "Add to PATH")  https://python.org/downloads
#   - (opcional) qpdf p/ fatiar PDFs        winget install qpdf.qpdf
#
# USO (no Git Bash, dentro da pasta do projeto):
#   bash scripts/setup-windows.sh
#
set -euo pipefail

info() { echo "→ $*"; }
ok()   { echo "✓ $*"; }
warn() { echo "⚠ $*" >&2; }
die()  { echo "✗ $*" >&2; exit 1; }

# 1. Localiza o Python (python | py | python3).
PY=""
for c in python py python3; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || die "Python não encontrado. Instale em https://python.org (marque 'Add Python to PATH') e reabra o Git Bash."
ok "Python: $("$PY" --version 2>&1)"

# 2. Instala o notebooklm-py com o extra de navegador.
info "Instalando notebooklm-py[browser]…"
"$PY" -m pip install --quiet --upgrade "notebooklm-py[browser]" || die "Falha no pip install. Verifique sua conexão."
ok "notebooklm-py instalado"

# 3. Baixa o Chromium usado no login.
info "Instalando o navegador do Playwright (Chromium)…"
"$PY" -m playwright install chromium || warn "Não consegui instalar o Chromium agora; se o login falhar, rode: $PY -m playwright install chromium"

# 4. Confere se o CLI está no PATH.
NLM="notebooklm"
if ! command -v notebooklm >/dev/null 2>&1; then
  warn "O CLI 'notebooklm' não está no PATH — usando '$PY -m notebooklm'. (Reabrir o Git Bash costuma resolver o PATH.)"
  NLM="$PY -m notebooklm"
fi

# 5. Ferramenta para fatiar PDFs grandes.
if command -v qpdf >/dev/null 2>&1; then
  ok "qpdf disponível (para split-pdf.sh)"
elif command -v pdftk >/dev/null 2>&1; then
  ok "pdftk disponível (alternativa ao qpdf)"
else
  warn "Sem qpdf/pdftk. Para fatiar PDFs de 2.000+ páginas, instale no PowerShell: winget install qpdf.qpdf  (depois reabra o Git Bash)."
fi

# 6. Login no NotebookLM, se ainda não autenticado.
if $NLM doctor 2>/dev/null | grep -i "auth" | grep -qi "pass"; then
  ok "NotebookLM já autenticado."
else
  info "Abrindo o login do NotebookLM — faça login na sua conta Google na janela do navegador…"
  if ! $NLM login; then
    warn "Login com Chromium falhou; tentando com o Google Chrome do sistema…"
    $NLM login --browser chrome || die "Login falhou. Tente manualmente: $NLM login --browser chrome"
  fi
fi

# 7. Status final.
echo
info "Status final:"
$NLM doctor || true
echo
ok "Setup concluído. Próximos passos:"
echo "  scripts/split-pdf.sh autos.pdf 500"
echo "  scripts/notebooklm-juridico.sh split/autos/*.pdf \"Processo 1234\""
