# Extensão do Chronos Focus para Navegadores (Chrome / Chromium / Brave / Edge)

Esta extensão substitui automaticamente abas e acessos a sites bloqueados por uma página informativa nativa do Chronos, avisando que o limite diário acabou — em vez de roubar o foco para o aplicativo desktop.

## Como Ativar no Chrome / Chromium:
1. Abra o navegador (Google Chrome, Chromium, Brave, etc.).
2. Acesse a página de extensões digitando na barra de endereços: `chrome://extensions`.
3. No canto superior direito, ative a chave **"Modo do desenvolvedor"** (Developer mode).
4. No canto superior esquerdo, clique em **"Carregar sem compactação"** (Load unpacked).
5. Selecione esta pasta:
   `/home/dwu/Downloads/Faculdade/misc/chronos_app/chronos_extension`

Pronto! A extensão se conectará automaticamente ao daemon do Chronos (`http://127.0.0.1:4545`).
Quando o limite de um site (como YouTube, Twitter, etc.) se esgotar, o site será imediatamente substituído pela página de bloqueio criada.
