//! Translations of the texts the Rust side shows (messages returned to the app, block
//! pages, activity labels, YouTube types, holidays, built-in challenge texts).
//! Source texts are Portuguese; `{}` marks a variable part (template). Generated from the
//! app translations (Chinese Traditional via OpenCC s2twp).

/// (pt-BR, en-US, zh-Hans, zh-Hant)
pub static ENTRIES: &[(&str, &str, &str, &str)] = &[
    ("Curto demais: {} de {} caracteres.", "Too short: {} of {} characters.", "太短：{} / {} 个字符。", "太短：{} / {} 個字元。"),
    ("Texto fácil demais (\"{}…\"): {}", "Text too easy (\"{}…\"): {}", "文本太简单（“{}…”）：{}", "文本太簡單（“{}…”）：{}"),
    ("Poucas palavras: escreva frases (pelo menos 20 palavras).", "Too few words: write sentences (at least 20 words).", "单词太少：请写完整的句子（至少 20 个词）。", "單詞太少：請寫完整的句子（至少 20 個詞）。"),
    ("Muitas palavras repetidas.", "Too many repeated words.", "重复的词太多。", "重複的詞太多。"),
    ("Uma palavra se repete demais.", "One word is repeated too often.", "某个词重复次数过多。", "某個詞重複次數過多。"),
    ("Poucas letras diferentes.", "Too few different letters.", "不同的字母太少。", "不同的字母太少。"),
    ("Letras repetidas em sequência.", "Repeated letters in a row.", "有连续重复的字母。", "有連續重複的字母。"),
    ("O texto é um mesmo trecho repetido.", "The text is the same chunk repeated.", "文本是同一段内容的重复。", "文本是同一段內容的重複。"),
    ("Sequência de teclado (qwerty, asdf, 12345…).", "Keyboard sequence (qwerty, asdf, 12345…).", "包含键盘序列（qwerty、asdf、12345…）。", "包含鍵盤序列（qwerty、asdf、12345…）。"),
    ("Textos do desafio salvos.", "Challenge texts saved.", "挑战文本已保存。", "挑戰文本已儲存。"),
    ("App '{}' no navegador", "App '{}' in the browser", "应用“{}”在浏览器中", "應用「{}」在瀏覽器中"),
    ("Entidade '{}' bloqueada completamente!", "'{}' fully blocked!", "已完全拦截“{}”！", "已完全攔截「{}」！"),
    ("Item de quarentena REJEITADO e bloqueado.", "Quarantine item REJECTED and blocked.", "隔离项目已被拒绝并拦截。", "隔離項目已被拒絕並攔截。"),
    ("Anti-Burla ativo: não é possível liberar a guia anônima agora.", "Anti-Bypass on: incognito can't be allowed now.", "防绕过已开启：现在无法允许无痕模式。", "防繞過已開啟：現在無法允許無痕模式。"),
    ("Filtro de conteúdo adulto salvo.", "Adult content filter saved.", "成人内容过滤已保存。", "成人內容過濾已儲存。"),
    ("Configuração inicial concluída com sucesso!", "Initial setup finished!", "初始设置已完成！", "初始設定已完成！"),
    ("Erro ao salvar configuração: {}", "Error saving settings: {}", "保存设置时出错：{}", "儲存設定時出錯：{}"),
    ("Código ou senha de pareamento incorretos.", "Wrong pairing code or password.", "配对码或密码错误。", "配對碼或密碼錯誤。"),
    ("Onboarding reiniciado! A tela de configuração será exibida no próximo início.", "Setup restarted! The setup screen will show on the next start.", "设置向导已重置！下次启动时将显示设置页面。", "設定嚮導已重置！下次啟動時將顯示設定頁面。"),
    ("Consumo diário zerado com sucesso! Cota renovada.", "Daily usage reset! Quota renewed.", "今日用量已清零！配额已恢复。", "今日用量已清零！配額已恢復。"),
    ("Erro ao zerar consumo diário: {}", "Error resetting daily usage: {}", "清零今日用量时出错：{}", "清零今日用量時出錯：{}"),
    ("Tokens de emergência restaurados para 2!", "Emergency tokens restored to 2!", "紧急令牌已恢复为 2 个！", "緊急令牌已恢復為 2 個！"),
    ("Modo Nuclear ativado! Nenhuma regra pode ser modificada até o tempo expirar.", "Nuke mode on! No rule can be changed until the time runs out.", "Nuke 模式已开启！时间结束前不能修改任何规则。", "Nuke 模式已開啟！時間結束前不能修改任何規則。"),
    ("Modo Anti-Burla ativado! Para desativar, conclua o desafio de digitação estrito.", "Anti-Bypass mode on! To turn it off, complete the strict typing challenge.", "防绕过模式已开启！要关闭，请完成严格打字挑战。", "防繞過模式已開啟！要關閉，請完成嚴格打字挑戰。"),
    ("Modo Anti-Burla desativado com sucesso!", "Anti-Bypass mode turned off!", "防绕过模式已关闭！", "防繞過模式已關閉！"),
    ("Regra '{}' salva com sucesso!", "Rule '{}' saved!", "规则“{}”已保存！", "規則“{}”已儲存！"),
    ("Regra '{}' removida com sucesso!", "Rule '{}' removed!", "规则“{}”已删除！", "規則“{}”已刪除！"),
    ("Bloqueio total de '{}' desativado!", "Full block of '{}' turned off!", "已关闭“{}”的完全拦截！", "已關閉“{}”的完全攔截！"),
    ("Indisponível na versão de release.", "Not available in the release version.", "正式版中不可用。", "正式版中不可用。"),
    ("Anti-Burla desativado com sucesso (Modo Debug)!", "Anti-Bypass turned off (debug mode)!", "防绕过已关闭（调试模式）！", "防繞過已關閉（除錯模式）！"),
    ("Erro ao desativar Anti-Burla: {}", "Error turning off Anti-Bypass: {}", "关闭防绕过时出错：{}", "關閉防繞過時出錯：{}"),
    ("Item de quarentena APROVADO para execução.", "Quarantine item APPROVED to run.", "隔离项目已批准运行。", "隔離專案已批准執行。"),
    ("Falha ao salvar preferência de tema no banco.", "Failed to save the theme preference.", "保存主题偏好失败。", "儲存主題偏好失敗。"),
    ("Modo Anti-Burla está ativo! Desativar a proteção de loja dos launchers exige desativar o Anti-Burla primeiro.", "Anti-Bypass mode is on! Turning off the launcher store protection requires turning off Anti-Bypass first.", "防绕过模式已开启！关闭启动器商店保护前需要先关闭防绕过。", "防繞過模式已開啟！關閉啟動器商店保護前需要先關閉防繞過。"),
    ("Reação a burlas salva.", "Tampering reaction saved.", "绕过应对方式已保存。", "繞過應對方式已儲存。"),
    ("Assinatura da atualização inválida — pacote recusado.", "Invalid update signature — package refused.", "更新签名无效——已拒绝安装包。", "更新簽名無效——已拒絕安裝包。"),
    ("{} está na lista branca e num grupo de bloqueio ({}).", "{} is in a whitelist and in a block group ({}).", "{}同时在白名单和拦截分组中（{}）。", "{}同時在白名單和攔截分組中（{}）。"),
    ("{} está em duas listas brancas ({}).", "{} is in two whitelists ({}).", "{}在两个白名单中（{}）。", "{}在兩個白名單中（{}）。"),
    ("{} está em dois grupos de bloqueio com dias em comum ({}).", "{} is in two block groups with days in common ({}).", "{}在两个有重叠日期的拦截分组中（{}）。", "{}在兩個有重疊日期的攔截分組中（{}）。"),
    ("{} está na lista branca ({}), mas o \"Mostrar apenas\" do YouTube o esconde.", "{} is in the whitelist ({}), but YouTube \"Show only\" hides it.", "{}在白名单中（{}），但 YouTube 的“只显示”会隐藏它。", "{}在白名單中（{}），但 YouTube 的“只顯示”會隱藏它。"),
    ("O app '{}'", "The app '{}'", "应用“{}”", "應用“{}”"),
    ("O site '{}'", "The site '{}'", "网站“{}”", "網站“{}”"),
    ("O tipo do YouTube '{}'", "The YouTube type '{}'", "YouTube 类型“{}”", "YouTube 型別“{}”"),
    ("Conflito: {}", "Conflict: {}", "冲突：{}", "衝突：{}"),
    ("Banco de dados não foi inicializado!", "The database was not initialized!", "数据库尚未初始化！", "資料庫尚未初始化！"),
    ("Modo Anti-Burla está ativo! Não é possível desativar o filtro de jogos/launchers enquanto o Anti-Burla estiver ligado.", "Anti-Bypass mode is on! The games/launchers filter can't be turned off while Anti-Bypass is on.", "防绕过模式已开启！防绕过开启时无法关闭游戏/启动器过滤。", "防繞過模式已開啟！防繞過開啟時無法關閉遊戲/啟動器過濾。"),
    ("Modo Anti-Burla está ativo! A remoção da tag '{}' exige desativar o Anti-Burla primeiro.", "Anti-Bypass mode is on! Removing the tag '{}' requires turning off Anti-Bypass first.", "防绕过模式已开启！移除标签“{}”前需要先关闭防绕过。", "防繞過模式已開啟！移除標籤“{}”前需要先關閉防繞過。"),
    ("Modo Anti-Burla está ativo! A remoção de '{}' exige desativar o Anti-Burla primeiro.", "Anti-Bypass mode is on! Removing '{}' requires turning off Anti-Bypass first.", "防绕过模式已开启！移除“{}”前需要先关闭防绕过。", "防繞過模式已開啟！移除“{}”前需要先關閉防繞過。"),
    ("Modo Anti-Burla está ativo! Não é possível desligar o filtro +18 do Reddit.", "Anti-Bypass mode is on! The Reddit 18+ filter can't be turned off.", "防绕过模式已开启！无法关闭 Reddit 成人过滤。", "防繞過模式已開啟！無法關閉 Reddit 成人過濾。"),
    ("Modo Anti-Burla está ativo! Não é possível desligar o filtro +18 do X/Twitter.", "Anti-Bypass mode is on! The X/Twitter 18+ filter can't be turned off.", "防绕过模式已开启！无法关闭 X/Twitter 成人过滤。", "防繞過模式已開啟！無法關閉 X/Twitter 成人過濾。"),
    ("Modo Anti-Burla está ativo! Não é possível desligar o 'Mostrar apenas' do YouTube.", "Anti-Bypass mode is on! YouTube 'Show only' can't be turned off.", "防绕过模式已开启！无法关闭 YouTube 的“只显示”。", "防繞過模式已開啟！無法關閉 YouTube 的“只顯示”。"),
    ("Modo Anti-Burla está ativo! Adicionar o tipo '{}' ao 'Mostrar apenas' exige desativar o Anti-Burla.", "Anti-Bypass mode is on! Adding the type '{}' to 'Show only' requires turning off Anti-Bypass.", "防绕过模式已开启！将类型“{}”加入“只显示”需要先关闭防绕过。", "防繞過模式已開啟！將型別“{}”加入“只顯示”需要先關閉防繞過。"),
    ("Modo Anti-Burla está ativo! Não é possível desligar ou afrouxar o filtro de conteúdo adulto.", "Anti-Bypass mode is on! The adult content filter can't be turned off or loosened.", "防绕过模式已开启！无法关闭或放宽成人内容过滤。", "防繞過模式已開啟！無法關閉或放寬成人內容過濾。"),
    ("No modo parental o filtro de conteúdo adulto fica sempre ligado.", "In parental mode the adult content filter is always on.", "家长模式下成人内容过滤始终开启。", "家長模式下成人內容過濾始終開啟。"),
    ("Mídia em Execução", "Media playing", "媒体播放中", "媒體播放中"),
    ("Áudio em reprodução: {}", "Audio playing: {}", "正在播放音频：{}", "正在播放音訊：{}"),
    ("Jogo '{}' em execução (AppID {})", "Game '{}' running (AppID {})", "游戏“{}”运行中（AppID {}）", "遊戲“{}”執行中（AppID {}）"),
    ("Jogo '{}' em foco", "Game '{}' in focus", "游戏“{}”在前台", "遊戲“{}”在前臺"),
    ("Jogo '{}' com janela aberta", "Game '{}' with an open window", "游戏“{}”窗口已打开", "遊戲“{}”視窗已開啟"),
    ("App '{}' em foco", "App '{}' in focus", "应用“{}”在前台", "應用“{}”在前臺"),
    ("App '{}' com janela aberta", "App '{}' with an open window", "应用“{}”窗口已打开", "應用“{}”視窗已開啟"),
    ("App '{}' em 2º plano", "App '{}' in the background", "应用“{}”在后台运行", "應用“{}”在後臺執行"),
    ("Reação inválida.", "Invalid reaction.", "无效的应对方式。", "無效的應對方式。"),
    ("Anti-Burla ativo: a penalidade por burla não pode ser desligada agora.", "Anti-Bypass on: the tampering penalty can't be turned off now.", "防绕过已开启：现在无法关闭绕过惩罚。", "防繞過已開啟：現在無法關閉繞過懲罰。"),
    ("Sessão '{}' em reprodução: {}", "Session '{}' playing: {}", "会话“{}”正在播放：{}", "會話“{}”正在播放：{}"),
    ("Sessão '{}' ativa via web/palavra '{}'", "Session '{}' active via web/word '{}'", "会话“{}”通过网页/关键词“{}”生效", "會話“{}”通過網頁/關鍵詞“{}”生效"),
    ("'{}' em reprodução: {}", "'{}' playing: {}", "“{}”正在播放：{}", "“{}”正在播放：{}"),
    ("Regra inativa no dia de hoje", "Rule inactive today", "规则今天不生效", "規則今天不生效"),
    ("{} • Bloqueado por Janela de Horário", "{} • Blocked by time window", "{} • 被时间段拦截", "{} • 被時間段攔截"),
    ("{} • Isento: {}", "{} • Exempt: {}", "{} • 豁免：{}", "{} • 豁免：{}"),
    ("Regra não encontrada.", "Rule not found.", "未找到规则。", "未找到規則。"),
    ("Modo Anti-Burla está ativo! Aumentos de cota são estritamente proibidos até a desativação do Anti-Burla.", "Anti-Bypass mode is on! Quota increases are strictly forbidden until Anti-Bypass is turned off.", "防绕过模式已开启！关闭防绕过前严禁增加配额。", "防繞過模式已開啟！關閉防繞過前嚴禁增加配額。"),
    ("Catraca ativa! Proibido aumentar a cota pelas próximas {}h. Você só pode reduzir.", "Ratchet on! Increasing the quota is forbidden for the next {}h. You can only reduce it.", "棘轮已开启！接下来 {} 小时内禁止增加配额，只能减少。", "棘輪已開啟！接下來 {} 小時內禁止增加配額，只能減少。"),
    ("Você não possui mais Tokens de Emergência neste mês!", "You have no emergency tokens left this month!", "本月已没有紧急令牌！", "本月已沒有緊急令牌！"),
    ("Modo Anti-Burla ativo! Só é possível renomear grupos até o Anti-Burla ser desativado.", "Anti-Bypass mode on! Groups can only be renamed until Anti-Bypass is turned off.", "防绕过模式已开启！关闭防绕过前只能重命名分组。", "防繞過模式已開啟！關閉防繞過前只能重新命名分組。"),
    ("Modo Anti-Burla está ativo! Regras de bloqueio não podem ser removidas.", "Anti-Bypass mode is on! Block rules can't be removed.", "防绕过模式已开启！无法删除拦截规则。", "防繞過模式已開啟！無法刪除攔截規則。"),
    ("Modo Anti-Burla está ativo! O desbloqueio total é estritamente proibido até o Anti-Burla ser destravado.", "Anti-Bypass mode is on! Full unblocking is strictly forbidden until Anti-Bypass is unlocked.", "防绕过模式已开启！解锁防绕过前严禁完全解除拦截。", "防繞過模式已開啟！解鎖防繞過前嚴禁完全解除攔截。"),
    ("Anti-Burla ativo: os textos do desafio não podem ser alterados agora.", "Anti-Bypass on: the challenge texts can't be changed now.", "防绕过已开启：现在无法修改挑战文字。", "防繞過已開啟：現在無法修改挑戰文字。"),
    ("Modo Nuke Ativo! O bloqueio permanecerá até o fim do cronômetro. Restam {} segundos.", "Nuke mode on! The lock stays until the timer ends. {} seconds left.", "Nuke 模式已开启！锁定将持续到计时结束。还剩 {} 秒。", "Nuke 模式已開啟！鎖定將持續到計時結束。還剩 {} 秒。"),
    ("Texto do desafio incorreto. O desafio exige digitação com 100% de precisão sem erros.", "Wrong challenge text. The challenge requires typing with 100% accuracy, no mistakes.", "挑战文字不正确。挑战要求 100% 准确、没有任何错误地输入。", "挑戰文字不正確。挑戰要求 100% 準確、沒有任何錯誤地輸入。"),
    ("Texto do desafio incorreto.", "Wrong challenge text.", "挑战文字不正确。", "挑戰文字不正確。"),
    ("Detecção Automática", "Automatic detection", "自动检测", "自動檢測"),
    ("Nenhuma distração ativa no momento", "No active distraction right now", "当前没有活跃的干扰", "當前沒有活躍的干擾"),
    ("Confraternização Universal", "New Year's Day", "元旦", "元旦"),
    ("Paixão de Cristo", "Good Friday", "耶稣受难日", "耶穌受難日"),
    ("Tiradentes", "Tiradentes Day", "蒂拉登特斯日", "蒂拉登特斯日"),
    ("Dia do Trabalho", "Labour Day", "劳动节", "勞動節"),
    ("Independência do Brasil", "Brazil's Independence Day", "巴西独立日", "巴西獨立日"),
    ("Nossa Senhora Aparecida", "Our Lady of Aparecida", "圣母显灵日", "聖母顯靈日"),
    ("Finados", "All Souls' Day", "万灵节", "萬靈節"),
    ("Proclamação da República", "Republic Day", "共和国宣言日", "共和國宣言日"),
    ("Dia da Consciência Negra", "Black Consciousness Day", "黑人意识日", "黑人意識日"),
    ("Natal", "Christmas", "圣诞节", "聖誕節"),
    ("Carnaval (segunda)", "Carnival (Monday)", "狂欢节（周一）", "狂歡節（週一）"),
    ("Carnaval (terça)", "Carnival (Tuesday)", "狂欢节（周二）", "狂歡節（週二）"),
    ("Corpus Christi", "Corpus Christi", "基督圣体节", "基督聖體節"),
    ("Data inválida: {}", "Invalid date: {}", "日期无效：{}", "日期無效：{}"),
    ("Modo Anti-Burla está ativo! Adicionar o feriado {} exige desativar o Anti-Burla.", "Anti-Bypass mode is on! Adding the holiday {} requires turning off Anti-Bypass.", "防绕过模式已开启！添加节假日 {} 需要先关闭防绕过。", "防繞過模式已開啟！新增節假日 {} 需要先關閉防繞過。"),
    ("Modo Anti-Burla está ativo! Aumentar a cota de feriado exige desativar o Anti-Burla.", "Anti-Bypass mode is on! Increasing the holiday quota requires turning off Anti-Bypass.", "防绕过模式已开启！增加节假日配额需要先关闭防绕过。", "防繞過模式已開啟！增加節假日配額需要先關閉防繞過。"),
    ("Relógio do sistema {} em {}", "System clock {} by {}", "系统时钟{}了 {}", "系統時鐘{}了 {}"),
    ("adiantado", "moved forward", "调快", "調快"),
    ("atrasado", "moved back", "调慢", "調慢"),
    ("Relógio voltou {} desde a última sessão", "Clock went back {} since the last session", "时钟自上次会话以来倒退了 {}", "時鐘自上次會話以來倒退了 {}"),
    ("Relógio do sistema difere da hora da internet em {}", "System clock differs from internet time by {}", "系统时钟与网络时间相差 {}", "系統時鐘與網路時間相差 {}"),
    ("Anti-Burla desligado sem o desafio", "Anti-Bypass turned off without the challenge", "未完成挑战就关闭了防绕过", "未完成挑戰就關閉了防繞過"),
    ("Configuração protegida alterada ({})", "Protected setting changed ({})", "受保护的设置被修改（{}）", "受保護的設定被修改（{}）"),
    ("Regra '{}' apagada", "Rule '{}' deleted", "规则“{}”被删除", "規則“{}”被刪除"),
    ("Regra '{}' afrouxada", "Rule '{}' loosened", "规则“{}”被放宽", "規則“{}”被放寬"),
    ("Lista branca '{}' criada", "Whitelist '{}' created", "白名单“{}”被创建", "白名單“{}”被建立"),
    ("Lista branca '{}' alterada", "Whitelist '{}' changed", "白名单“{}”被修改", "白名單“{}”被修改"),
    ("Tempo de uso de hoje apagado", "Today's usage time deleted", "今天的使用时间被删除", "今天的使用時間被刪除"),
    ("Tokens de emergência alterados", "Emergency tokens changed", "紧急令牌被修改", "緊急令牌被修改"),
    ("Filtros de conteúdo afrouxados", "Content filters loosened", "内容过滤被放宽", "內容過濾被放寬"),
    ("Filtro de conteúdo adulto afrouxado", "Adult content filter loosened", "成人内容过滤被放宽", "成人內容過濾被放寬"),
    ("Filtro de conteúdo adulto apagado", "Adult content filter deleted", "成人内容过滤被删除", "成人內容過濾被刪除"),
    ("Bloqueio da guia anônima desligado", "Incognito block turned off", "无痕模式禁用被关闭", "無痕模式停用被關閉"),
    ("Tipos personalizados do YouTube adicionados", "Custom YouTube types added", "添加了自定义 YouTube 类型", "添加了自定義 YouTube 型別"),
    ("Feriado adicionado", "Holiday added", "添加了节假日", "添加了節假日"),
    ("Cota de feriado aumentada", "Holiday quota increased", "节假日配额被增加", "節假日配額被增加"),
    ("Penalidade por burla desligada", "Tampering penalty turned off", "绕过惩罚被关闭", "繞過懲罰被關閉"),
    ("Penalidade encerrada antes da hora", "Penalty ended early", "惩罚被提前结束", "懲罰被提前結束"),
    ("Texto do desafio trocado por um texto fora da lista", "Challenge text replaced by a text outside the list", "挑战文字被替换为列表之外的文字", "挑戰文字被替換為列表之外的文字"),
    ("Banco de dados do Chronos apagado", "Chronos database deleted", "Chronos 数据库被删除", "Chronos 資料庫被刪除"),
    ("Banco de dados ilegível: {}", "Unreadable database: {}", "数据库无法读取：{}", "資料庫無法讀取：{}"),
    ("{} apagado ou alterado; restaurado", "{} deleted or changed; restored", "{} 被删除或修改；已恢复", "{} 被刪除或修改；已恢復"),
    ("Serviço do Chronos estava {}/{}; religado", "Chronos service was {}/{}; restarted", "Chronos 服务状态为 {}/{}；已重新启动", "Chronos 服務狀態為 {}/{}；已重新啟動"),
    ("Tentativa de encerrar o Modo Nuke antes da hora", "Attempt to end Nuke mode early", "试图提前结束 Nuke 模式", "試圖提前結束 Nuke 模式"),
    ("Modo Nuke ativo por mais {} min.", "Nuke mode on for {} more min.", "Nuke 模式还将持续 {} 分钟。", "Nuke 模式還將持續 {} 分鐘。"),
    ("Anti-Burla ativo: o Chronos não pode ser desinstalado agora.", "Anti-Bypass on: Chronos can't be uninstalled now.", "防绕过已开启：现在无法卸载 Chronos。", "防繞過已開啟：現在無法解除安裝 Chronos。"),
    ("Educacional", "Educational", "教育", "教育"),
    ("Ciência e Tecnologia", "Science & Technology", "科学与技术", "科學與技術"),
    ("Tutoriais", "Tutorials", "教程", "教程"),
    ("Música", "Music", "音乐", "音樂"),
    ("Podcasts", "Podcasts", "播客", "播客"),
    ("Modo Anti-Burla está ativo! Adicionar canais ou palavras ao tipo '{}' exige desativar o Anti-Burla.", "Anti-Bypass mode is on! Adding channels or words to the type '{}' requires turning off Anti-Bypass.", "防绕过模式已开启！向类型“{}”添加频道或关键词需要先关闭防绕过。", "防繞過模式已開啟！向型別“{}”新增頻道或關鍵詞需要先關閉防繞過。"),
    ("Filtro de Conteúdo Adulto", "Adult Content Filter", "成人内容过滤", "成人內容過濾"),
    ("Limite de Tempo Esgotado", "Time Limit Reached", "时间已用完", "時間已用完"),
    ("Conteúdo Adulto Bloqueado", "Adult Content Blocked", "已拦截成人内容", "已攔截成人內容"),
    ("Conteúdo de Jogo Bloqueado", "Game Content Blocked", "已拦截游戏内容", "已攔截遊戲內容"),
    ("Site Indisponível", "Site Unavailable", "网站不可用", "網站不可用"),
    ("Filtro de Conteúdo (Steam API / Launchers)", "Content filter (Steam API / launchers)", "内容过滤（Steam API / 启动器）", "內容過濾（Steam API / 啟動器）"),
    ("Esta página foi bloqueada pelo filtro de conteúdo adulto:", "This page was blocked by the adult content filter:", "此页面已被成人内容过滤拦截：", "此頁面已被成人內容過濾攔截："),
    ("Conteúdo adulto bloqueado ({})", "Adult content blocked ({})", "已拦截成人内容（{}）", "已攔截成人內容（{}）"),
    ("Conteúdo adulto", "Adult content", "成人内容", "成人內容"),
    ("(loja, página do jogo, guias, discussões ou artworks) foi bloqueado:", "(store, game page, guides, discussions or artwork) was blocked:", "（商店、游戏页面、指南、讨论或艺术作品）已被拦截：", "（商店、遊戲頁面、指南、討論或藝術作品）已被攔截："),
    ("O conteúdo", "The content", "内容", "內容"),
    ("não está disponível pois o seu tempo de tela diário acabou.", "is not available because your daily screen time is over.", "不可用，因为你今天的屏幕时间已用完。", "不可用，因為你今天的螢幕時間已用完。"),
    ("O site", "The site", "网站", "網站"),
    ("Status de segurança:", "Security status:", "安全状态：", "安全狀態："),
    ("Bloqueio Ativo pelo Chronos", "Blocked by Chronos", "Chronos 拦截中", "Chronos 攔截中"),
    ("Tempo de tela diário:", "Daily screen time:", "每日屏幕时间：", "每日螢幕時間："),
    ("Próxima liberação:", "Next release:", "下次解除：", "下次解除："),
    ("Amanhã à meia-noite (00:00)", "Tomorrow at midnight (00:00)", "明天午夜（00:00）", "明天午夜（00:00）"),
    ("Tokens de emergência não liberam conteúdo adulto. Se esta página foi bloqueada por engano, adicione-a às", "Emergency tokens don't unlock adult content. If this page was blocked by mistake, add it to the", "紧急令牌不能解锁成人内容。如果此页面被误拦截，请将其添加到", "緊急令牌不能解鎖成人內容。如果此頁面被誤攔截，請將其新增到"),
    ("Exceções", "Exceptions", "例外", "例外"),
    ("do Filtro de Conteúdo Adulto (Anti-Burla deve estar desativado).", "of the Adult Content Filter (Anti-Bypass must be off).", "（成人内容过滤，需关闭防绕过）。", "（成人內容過濾，需關閉防繞過）。"),
    ("Para liberar este conteúdo, remova a tag ou nome correspondente nas configurações de", "To allow this content, remove the matching tag or name in the settings of", "要允许此内容，请在以下设置中移除对应的标签或名称：", "要允許此內容，請在以下設定中移除對應的標籤或名稱："),
    ("(Anti-Burla deve estar desativado).", "(Anti-Bypass must be off).", "（需关闭防绕过）。", "（需關閉防繞過）。"),
    ("Launchers & Jogos", "Launchers & Games", "启动器与游戏", "啟動器與遊戲"),
    ("token(s)", "token(s)", "个令牌", "個令牌"),
    ("de emergência disponíveis este mês.", "of emergency available this month.", "本月可用的紧急令牌。", "本月可用的緊急令牌。"),
    ("Você possui", "You have", "你还有", "你還有"),
    ("Usar Token de Emergência (+1h)", "Use emergency token (+1h)", "使用紧急令牌（+1 小时）", "使用緊急令牌（+1 小時）"),
    ("Nenhum token de emergência restante para este mês.", "No emergency tokens left this month.", "本月没有剩余的紧急令牌。", "本月沒有剩餘的緊急令牌。"),
    ("Acesso Bloqueado pelo Chronos", "Access blocked by Chronos", "已被 Chronos 拦截", "已被 Chronos 攔截"),
    ("Página bloqueada pelo Chronos", "Page blocked by Chronos", "页面已被 Chronos 拦截", "頁面已被 Chronos 攔截"),
    ("Voltar", "Back", "返回", "返回"),
    ("Imagens +18 bloqueadas pelo Chronos", "18+ images blocked by Chronos", "成人图片已被 Chronos 拦截", "成人圖片已被 Chronos 攔截"),
    ("Post +18 bloqueado pelo Chronos", "18+ post blocked by Chronos", "成人帖子已被 Chronos 拦截", "成人帖子已被 Chronos 攔截"),
    ("Comunidade +18 bloqueada pelo Chronos", "18+ community blocked by Chronos", "成人社区已被 Chronos 拦截", "成人社群已被 Chronos 攔截"),
    ("Perfil +18 bloqueado pelo Chronos", "18+ profile blocked by Chronos", "成人账号已被 Chronos 拦截", "成人賬號已被 Chronos 攔截"),
    ("Subreddit +18 bloqueado pelo Chronos", "18+ subreddit blocked by Chronos", "成人版块已被 Chronos 拦截", "成人版塊已被 Chronos 攔截"),
    ("Filtro de launcher ativo", "Launcher filter on", "启动器过滤已开启", "啟動器過濾已開啟"),
    ("Conteúdo bloqueado por filtro de launcher", "Content blocked by the launcher filter", "内容已被启动器过滤拦截", "內容已被啟動器過濾攔截"),
    ("Antes de liberar a guia anônima, permita a extensão Chronos no modo anônimo.", "Before allowing incognito, allow the Chronos extension in incognito.", "在允许无痕模式之前，请先允许 Chronos 扩展在无痕模式下运行。", "在允許無痕模式之前，請先允許 Chronos 擴充套件在無痕模式下執行。"),
    ("A guia anônima foi liberada por 3 minutos para você permitir a extensão nela. Reabra o navegador, abra chrome://extensions, clique em \"Detalhes\" na extensão Chronos e ligue \"Permitir no modo anônimo\" (em cada navegador). Se não ligar a tempo, ou se desligar depois, o Chronos volta a bloquear a guia anônima.", "Incognito was allowed for 3 minutes so you can allow the extension there. Reopen the browser, open chrome://extensions, click \"Details\" on the Chronos extension and turn on \"Allow in Incognito\" (in each browser). If you don't turn it on in time, or turn it off later, Chronos blocks incognito again.", "无痕模式已允许 3 分钟，以便你允许扩展在其中运行。重新打开浏览器，打开 chrome://extensions，在 Chronos 扩展上点击“详情”，并开启“在无痕模式下启用”（每个浏览器都要）。如果没有及时开启，或之后又关闭，Chronos 会再次禁用无痕模式。", "無痕模式已允許 3 分鐘，以便你允許擴充套件在其中執行。重新開啟瀏覽器，開啟 chrome://extensions，在 Chronos 擴充套件上點選“詳情”，並開啟“在無痕模式下啟用”（每個瀏覽器都要）。如果沒有及時開啟，或之後又關閉，Chronos 會再次停用無痕模式。"),
    ("Cada texto precisa ter pelo menos {} caracteres (\"{}…\" é curto demais).", "Each text needs at least {} characters (\"{}…\" is too short).", "每段文字至少需要 {} 个字符（“{}…”太短）。", "每段文字至少需要 {} 個字元（“{}…”太短）。"),
    ("Textos do desafio salvos.", "Challenge texts saved.", "挑战文字已保存。", "挑戰文字已儲存。"),
    ("Eu reconheço plenamente que alterar meus limites agora é uma tentativa de ceder à procrastinação. Meus objetivos a longo prazo dependem da minha disciplina e consistência diária. Eu escolho manter o foco e cumprir minhas metas acima de qualquer distração passageira.", "I fully recognize that changing my limits now is an attempt to give in to procrastination. My long-term goals depend on my discipline and daily consistency. I choose to stay focused and meet my goals above any passing distraction.", "我完全承认，现在修改我的限制是在向拖延屈服。我的长期目标取决于我每天的自律和坚持。我选择保持专注，把实现目标放在任何短暂的干扰之上，绝不轻易放弃自己定下的计划。", "我完全承認，現在修改我的限制是在向拖延屈服。我的長期目標取決於我每天的自律和堅持。我選擇保持專注，把實現目標放在任何短暫的干擾之上，絕不輕易放棄自己定下的計劃。"),
    ("Eu sei que a vontade de liberar agora vai passar em poucos minutos. Cada vez que eu resisto, fica mais fácil resistir de novo. Eu prefiro o orgulho de ter cumprido o meu plano do que o alívio rápido de uma distração que eu mesmo decidi evitar.", "I know the urge to unlock now will pass in a few minutes. Every time I resist, it gets easier to resist again. I prefer the pride of having followed my plan to the quick relief of a distraction I decided to avoid myself.", "我知道现在想解锁的冲动几分钟后就会过去。每一次抵抗，下一次都会更容易。比起一时放松去做自己决定避开的事，我更愿意为坚持完成自己的计划而感到自豪和满足。", "我知道現在想解鎖的衝動幾分鐘後就會過去。每一次抵抗，下一次都會更容易。比起一時放鬆去做自己決定避開的事，我更願意為堅持完成自己的計劃而感到自豪和滿足。"),
    ("Os limites que eu configurei foram escolhidos com a cabeça fria, pensando no meu futuro. Desfazer esses limites num momento de impulso seria trair a pessoa que eu quero ser. Eu vou respirar fundo, voltar para a minha tarefa e terminar o que comecei.", "The limits I set were chosen with a clear head, thinking about my future. Undoing them in a moment of impulse would betray the person I want to be. I will take a deep breath, go back to my task and finish what I started.", "我设定的这些限制是在头脑清醒、为未来着想时决定的。在一时冲动下撤销它们，就是背叛我想成为的那个人。我会深呼吸，回到我的任务上，把已经开始的事情好好完成。", "我設定的這些限制是在頭腦清醒、為未來著想時決定的。在一時衝動下撤銷它們，就是背叛我想成為的那個人。我會深呼吸，回到我的任務上，把已經開始的事情好好完成。"),
    ("Tempo é o recurso mais valioso que eu tenho e não volta. Se eu liberar agora, vou trocar horas de progresso por alguns minutos de distração. Eu reconheço esse impulso, aceito que ele existe e mesmo assim escolho manter o meu compromisso com o foco.", "Time is the most valuable resource I have and it does not come back. If I unlock now, I will trade hours of progress for a few minutes of distraction. I recognize this impulse, accept that it exists and still choose to keep my commitment to focus.", "时间是我最宝贵的资源，一去不复返。如果现在解锁，我就是在用几个小时的进步换取几分钟的分心。我认识到这种冲动，接受它的存在，但仍然选择坚守我对专注的承诺，继续认真努力。", "時間是我最寶貴的資源，一去不復返。如果現在解鎖，我就是在用幾個小時的進步換取幾分鐘的分心。我認識到這種衝動，接受它的存在，但仍然選擇堅守我對專注的承諾，繼續認真努力。"),
];

fn pick(e: &(&'static str, &'static str, &'static str, &'static str), lang: &str) -> &'static str {
    match lang {
        "en-US" => e.1,
        "zh-Hans" => e.2,
        "zh-Hant" => e.3,
        _ => e.0,
    }
}

/// Current app language (pt-BR when the database is not open).
pub fn current_lang() -> String {
    if crate::db::try_get_conn().is_none() {
        return "pt-BR".to_string();
    }
    crate::db::get_primary_language()
}

/// Exact translation of a whole text (or the text itself).
pub fn tr_exact_in(text: &str, lang: &str) -> String {
    let t = text.trim();
    ENTRIES
        .iter()
        .find(|e| e.0 == t)
        .map(|e| text.replacen(t, pick(e, lang), 1))
        .unwrap_or_else(|| text.to_string())
}

/// Matches `template` (with `{}` parts) inside `msg`; returns (start, end, captures).
fn match_template(msg: &str, template: &str, from: usize) -> Option<(usize, usize, Vec<String>)> {
    let parts: Vec<&str> = template.split("{}").collect();
    let first = parts[0];
    let start = if first.is_empty() { from } else { from + msg.get(from..)?.find(first)? };
    let mut pos = start + first.len();
    let mut caps = Vec::new();
    for (i, lit) in parts.iter().enumerate().skip(1) {
        let last = i == parts.len() - 1;
        if lit.is_empty() {
            if last {
                // Trailing placeholder: up to the end of the sentence/list item.
                let end = msg[pos..].find("; ").map(|o| pos + o).unwrap_or(msg.len());
                caps.push(msg[pos..end].to_string());
                pos = end;
            } else {
                return None;
            }
        } else {
            let o = msg.get(pos..)?.find(lit)?;
            caps.push(msg[pos..pos + o].to_string());
            pos += o + lit.len();
        }
    }
    if first.is_empty() && caps.first().is_some_and(|c| c.is_empty()) {
        return None;
    }
    Some((start, pos, caps))
}

/// Translates a message (whole texts, templates with variable parts, list items).
pub fn tr_msg_in(msg: &str, lang: &str) -> String {
    if lang == "pt-BR" || msg.is_empty() {
        return msg.to_string();
    }
    let exact = tr_exact_in(msg, lang);
    if exact != msg {
        return exact;
    }
    let mut out = msg.to_string();
    let mut templates: Vec<&(&str, &str, &str, &str)> = ENTRIES.iter().filter(|e| e.0.contains("{}")).collect();
    templates.sort_by_key(|e| std::cmp::Reverse(e.0.len()));
    for e in templates {
        let mut from = 0;
        while let Some((s, end, caps)) = match_template(&out, e.0, from) {
            let mut rendered = pick(e, lang).to_string();
            for c in caps {
                let c = tr_exact_in(&c, lang);
                rendered = rendered.replacen("{}", &c, 1);
            }
            out.replace_range(s..end, &rendered);
            from = s + rendered.len();
            if from >= out.len() {
                break;
            }
        }
    }
    // List items joined with "; " (vault violations, ...).
    if out.contains("; ") {
        out = out.split("; ").map(|p| tr_exact_in(p, lang)).collect::<Vec<_>>().join("; ");
    }
    out
}

pub fn tr_msg(msg: &str) -> String {
    tr_msg_in(msg, &current_lang())
}

/// Translates the known fixed texts inside an HTML page (block pages).
pub fn localize_html_in(html: &str, lang: &str) -> String {
    if lang == "pt-BR" {
        return html.to_string();
    }
    let mut fixed: Vec<&(&str, &str, &str, &str)> =
        ENTRIES.iter().filter(|e| !e.0.contains("{}") && e.0.chars().count() >= 6).collect();
    fixed.sort_by_key(|e| std::cmp::Reverse(e.0.len()));
    let mut out = html.to_string();
    for e in fixed {
        if out.contains(e.0) {
            out = out.replace(e.0, pick(e, lang));
        }
    }
    let lang_attr = match lang {
        "en-US" => "en",
        "zh-Hans" => "zh-Hans",
        "zh-Hant" => "zh-Hant",
        _ => "pt-BR",
    };
    out.replacen("<html lang=\"pt-BR\">", &format!("<html lang=\"{lang_attr}\">"), 1)
}

pub fn localize_html(html: &str) -> String {
    localize_html_in(html, &current_lang())
}

/// The Portuguese source and every translation of a text (challenge verification
/// accepts the text shown in any app language).
pub fn variants(text: &str) -> Vec<String> {
    let t = text.trim();
    match ENTRIES.iter().find(|e| e.0 == t) {
        Some(e) => vec![e.0.to_string(), e.1.to_string(), e.2.to_string(), e.3.to_string()],
        None => vec![t.to_string()],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn templates_lists_and_html() {
        assert_eq!(tr_msg_in("Regra 'Jogos' salva com sucesso!", "en-US"), "Rule 'Jogos' saved!");
        assert_eq!(tr_msg_in("Relógio do sistema adiantado em 2 h", "en-US"), "System clock moved forward by 2 h");
        assert_eq!(
            tr_msg_in("Anti-Burla desligado sem o desafio; Regra 'X' apagada", "zh-Hans"),
            "未完成挑战就关闭了防绕过; 规则“X”被删除"
        );
        assert_eq!(tr_msg_in("Conflito: O app 'aether' está na lista branca e num grupo de bloqueio (A, B).", "en-US"),
            "Conflict: The app 'aether' is in a whitelist and in a block group (A, B).");
        assert_eq!(tr_msg_in("Educacional", "zh-Hant"), "教育");
        assert_eq!(tr_msg_in("qualquer coisa", "en-US"), "qualquer coisa");
        assert_eq!(tr_msg_in("Regra 'x' salva com sucesso!", "pt-BR"), "Regra 'x' salva com sucesso!");
        let html = localize_html_in("<html lang=\"pt-BR\"><h1>Site Indisponível</h1><span>Status de segurança:</span></html>", "en-US");
        assert!(html.contains("Site Unavailable") && html.contains("Security status:") && html.contains("lang=\"en\""));
        assert_eq!(variants(crate::engine::STAYFOCUSD_CHALLENGE_TEXT).len(), 4);
    }
}

#[cfg(test)]
mod challenge_msg_tests {
    #[test]
    fn strength_messages_translate() {
        let msg = "Texto fácil demais (\"abc abc…\"): Muitas palavras repetidas.";
        let en = super::tr_msg_in(msg, "en-US");
        assert!(en.starts_with("Text too easy"), "{en}");
        assert!(en.contains("Too many repeated words."), "{en}");
    }
}
