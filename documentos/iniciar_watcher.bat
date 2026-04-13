@echo off
:: iniciar_watcher.bat
:: Chamado pelo Agendador de Tarefas no login.
:: Garante que o Python rode com UTF-8 e em background.

set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1

cd /d C:\Users\djast

python watch_documentacao.py >> C:\Users\djast\watcher_log.txt 2>&1
