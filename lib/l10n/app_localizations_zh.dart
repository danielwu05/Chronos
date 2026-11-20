// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get chronosAntiCheatStrictFocusEngine => 'Chronos - 防绕过与严格专注引擎';

  @override
  String get chronosFocusEngine => 'Chronos 专注引擎';

  @override
  String get reiniciarBancoDeDados => '重置数据库？';

  @override
  String get desejaResetarCompletamenteOSqliteIntervalos =>
      '要完全重置 SQLite 吗？使用记录将被清除，棘轮将解锁，初始设置将重新开始。';

  @override
  String get cancelar => '取消';

  @override
  String get reiniciarTudo => '全部重置';

  @override
  String get parentalPai => '家长控制（家长）';

  @override
  String get parentalFilho => '家长控制（孩子）';

  @override
  String get autoControle => '自我控制';

  @override
  String focoP0(Object p0) {
    return '专注：$p0';
  }

  @override
  String get autoDeteccaoAtiva => '自动检测已开启';

  @override
  String get deteccaoAutomatica => '自动检测';

  @override
  String get antiCheatOff => '防绕过：关闭';

  @override
  String nukeP0DP1(Object p0, Object p1) {
    return 'Nuke：$p0天 $p1';
  }

  @override
  String nukeP0(Object p0) {
    return 'Nuke：$p0';
  }

  @override
  String get antiCheatAtivo => '防绕过已开启';

  @override
  String get refazerCadastroTrocarModo => '重新设置 / 切换模式';

  @override
  String get instalarExtensoesNosNavegadores => '在浏览器中安装扩展';

  @override
  String get sairDoAntiCheatDebug => '🛠️ 退出防绕过（调试）';

  @override
  String get reiniciarBancoCompleto => '重置整个数据库';

  @override
  String get zerarConsumoDiario => '清零今日用量';

  @override
  String destravarCatracaP0(Object p0) {
    return '解锁棘轮（$p0）';
  }

  @override
  String get restaurarTokens2 => '恢复令牌（+2）';

  @override
  String get tempoDeTela => '屏幕时间';

  @override
  String get monitorEmTempoReal => '实时监控';

  @override
  String get estatisticas => '统计';

  @override
  String get metricasDeConsumo => '使用指标';

  @override
  String get regrasWhitelist => '规则与白名单';

  @override
  String get limitesEGrupos => '限制与分组';

  @override
  String get configuracoes => '设置';

  @override
  String get aparenciaEAlertas => '外观与提醒';

  @override
  String get quarentena => '隔离区';

  @override
  String get modoNukeBloqueios => 'Nuke 模式与拦截';

  @override
  String get sqliteTestes => 'SQLite / 测试';

  @override
  String get depuracaoDoBanco => '数据库调试';

  @override
  String get chronos => 'Chronos';

  @override
  String get focusEngine => '专注引擎';

  @override
  String get alternarParaModoClaro => '切换到浅色模式';

  @override
  String get alternarParaModoEscuro => '切换到深色模式';

  @override
  String get modoClaro => '浅色模式';

  @override
  String get modoEscuro => '深色模式';

  @override
  String get estatisticasDeConsumoHistorico => '使用统计与历史';

  @override
  String get regrasDeBloqueioWhitelist => '拦截规则与白名单';

  @override
  String get configuracoesGeraisNotificacoes => '常规设置与通知';

  @override
  String get quarentenaModoNuke => '隔离区与 Nuke 模式';

  @override
  String get bancoDeDadosTestesSqlite => '数据库与 SQLite 测试';

  @override
  String get debugSairDoAntiCheat => '🛠️ [调试] 退出防绕过';

  @override
  String get instalarExtensoesEmNavegadores => '在浏览器中安装扩展';

  @override
  String get acoesGlobais => '全局操作';

  @override
  String get telaDeCadastro => '设置向导';

  @override
  String get debugSairDoAntiCheatImediatamente => '🛠️ [调试] 立即退出防绕过';

  @override
  String get instalarExtensoesEmTodosNavegadores => '在所有浏览器中安装扩展';

  @override
  String get acoesConfiguracao => '操作与设置';

  @override
  String get tempo => '时间';

  @override
  String get metricas => '指标';

  @override
  String get regras => '规则';

  @override
  String get ajustes => '设置';

  @override
  String get nuke => 'Nuke';

  @override
  String get sqlite => 'SQLite';

  @override
  String get sincronizandoComOMotorDeMonitoramento => '正在与监控引擎同步...';

  @override
  String get tentarConectarAgora => '立即尝试连接';

  @override
  String get etapaInicialTesteAQualquerMomento => '初始步骤：随时测试设置和自定义拦截。';

  @override
  String get voltarAoCadastro => '返回设置向导';

  @override
  String p0SessoesAtivasSimultaneamenteOTempo(Object p0) {
    return '⚡ $p0 个会话同时进行！屏幕时间正在并行计时。';
  }

  @override
  String get sessao => '会话';

  @override
  String get emExecucao => '运行中';

  @override
  String get tempoAtivo => '活动时间';

  @override
  String consumidoHojeP0(Object p0) {
    return '今日已用：$p0';
  }

  @override
  String limiteP0P1(Object p0, Object p1) {
    return '限制：$p0（$p1%）';
  }

  @override
  String get catracaAtiva => '棘轮已开启';

  @override
  String tokensP02(Object p0) {
    return '令牌：$p0/2';
  }

  @override
  String limiteDeTempoDeTelaP0(Object p0, Object p1) {
    return '屏幕时间限制：$p0（$p1%）';
  }

  @override
  String get controlesDeTempoDeTelaCatraca => '屏幕时间与棘轮控制';

  @override
  String get reduzirTempoDeTelaTeste15s => '减少屏幕时间（15 秒测试）';

  @override
  String get tentarAumentarTempoDeTela2h => '尝试增加屏幕时间（+2 小时）';

  @override
  String get trancarCatraca24h => '锁定棘轮（24 小时）';

  @override
  String get catracaTrancadaPor24hAumentosProibidos => '棘轮已锁定 24 小时！禁止增加时间。';

  @override
  String get usarTokenDeEmergencia1h => '使用紧急令牌（+1 小时）';

  @override
  String get bemVindoAoChronos => '欢迎使用 Chronos';

  @override
  String get seuMotorDeFocoEstritoE => '你的 Linux 严格专注与效率引擎。\n你打算如何使用这个应用？';

  @override
  String get controlePessoalAutoControle => '个人控制（自我控制）';

  @override
  String get paraGerenciarSeuProprioTempoE => '用于管理自己的时间和学习。';

  @override
  String get modoCatracaRatchetReducoesSaoImediatas => '棘轮模式：减少立即生效，增加会被阻止。';

  @override
  String get t2TokensMensaisDeEmergencia1h =>
      '每月 2 个紧急令牌（+1 小时，代价是 24 小时娱乐锁定）。';

  @override
  String get bloqueioAtivoComSobreposicaoDeJanela => '主动拦截，带窗口遮罩和自动暂停媒体。';

  @override
  String get configurarBloqueiosPessoais => '设置个人拦截';

  @override
  String get controleParentalSupervisao => '家长控制（监督）';

  @override
  String get paraPaisEResponsaveisGerenciaremDispositivos => '供家长和监护人管理孩子的设备。';

  @override
  String get dispositivoDoDependenteProtegidoContraAlteracoes =>
      '孩子的设备受到保护，防止修改和绕过。';

  @override
  String get pareamentoSeguroViaQrCodeOu => '通过二维码或主密码安全配对。';

  @override
  String get gestaoDeAprovacaoDeBinariosE => '程序审批与应用隔离管理。';

  @override
  String get configurarControleParental => '设置家长控制';

  @override
  String get personalizacaoDeBloqueioTempoDeTela => '自定义拦截与屏幕时间';

  @override
  String get ajusteOTempoDeTelaDiario => '设置初始每日屏幕时间和严格程度';

  @override
  String get distracoesABloquear => '要拦截的干扰';

  @override
  String get adicionarAppOuSite => '添加应用或网站';

  @override
  String get nenhumaSessaoPreConfiguradaCliqueEm =>
      '没有预设会话。\n点击上方的“添加应用或网站”来创建你的会话。';

  @override
  String get tempoDeTelaDiario => '每日屏幕时间：';

  @override
  String get bloqueioTotal => '完全拦截';

  @override
  String get t15Min => '15 分钟';

  @override
  String get t30Min => '30 分钟';

  @override
  String get t1Hora => '1 小时';

  @override
  String get t2Horas => '2 小时';

  @override
  String get diretrizesDeEnforcementDoChronos => 'Chronos 执行规则';

  @override
  String get ativarTravaDaCatraca24hIniciais => '开启棘轮锁定（前 24 小时）';

  @override
  String get impedeAumentosDeTempoDeTela => '第一天禁止增加屏幕时间，只能减少。';

  @override
  String get sequestroVisualDeFocoAlwaysOn => '强制专注画面（始终置顶全屏）';

  @override
  String get maximizaETravaAJanelaDo => '屏幕时间用完时，将 Chronos 窗口最大化并锁定在最上层。';

  @override
  String get pausaAtivaDeMidiaPlayerctlMpris2 => '主动暂停媒体（playerctl / MPRIS2）';

  @override
  String get interrompeAutomaticamenteVideosEMusicasEm => '自动停止后台播放的视频和音乐。';

  @override
  String get salvarBloqueiosEIniciarChronos => '保存拦截并启动 Chronos';

  @override
  String get controleParental => '家长控制';

  @override
  String get qualEOPapelDesteComputador => '这台电脑在家庭中的角色是什么？';

  @override
  String get dispositivoDoResponsavelPaiMae => '监护人的设备（家长）';

  @override
  String get esteComputadorTeraAutoridadeParaControlar => '这台电脑将有权控制规则和屏幕时间。';

  @override
  String get recebeSolicitacoesDeEmergenciaEAprovacoes => '接收紧急请求和隔离审批。';

  @override
  String get conectaAoComputadorDoFilhoUsando => '通过二维码或密码连接到孩子的电脑。';

  @override
  String get configurarComoDispositivoPai => '设置为家长设备';

  @override
  String get dispositivoDoDependenteFilho => '孩子的设备';

  @override
  String get esteComputadorSeraMonitoradoEProtegido => '这台电脑将被监控并防止分心。';

  @override
  String get asAlteracoesDeTempoDeTela => '修改屏幕时间需要监护人授权或密码。';

  @override
  String get exibeQrCodeECodigoPin => '显示二维码和 PIN 码，供监护人连接。';

  @override
  String get configurarComoDispositivoFilho => '设置为孩子设备';

  @override
  String chronosPairCodeP0(Object p0) {
    return 'chronos://pair?code=$p0';
  }

  @override
  String get pareamentoDispositivoFilho => '配对：孩子设备';

  @override
  String get pareamentoDispositivoDoResponsavel => '配对：监护人设备';

  @override
  String get conecteEsteComputadorAoAplicativoDo =>
      '使用二维码或 PIN/密码将这台电脑连接到监护人的应用。';

  @override
  String get escaneieOQrCodeOuInsira => '扫描二维码或输入孩子设备上显示的 PIN 码。';

  @override
  String get viaQrCode => '通过二维码';

  @override
  String get viaSenhaPin => '通过密码 / PIN';

  @override
  String get concluirEIniciarProtecao => '完成并开始保护';

  @override
  String get concluirEAbrirPainelDoResponsavel => '完成并打开监护人面板';

  @override
  String get protecaoObrigatoriaEmTodosOsNavegadores => '所有浏览器强制保护';

  @override
  String get configuraTodosOsNavegadoresDoDispositivo =>
      '设置本设备的所有浏览器，显示剩余时间并应用 HTML/CSS 过滤（Shorts、首页推荐、灰度）。只有通过防绕过验证后才能移除。';

  @override
  String get instalandoConfigurando => '正在安装和配置...';

  @override
  String get instalarAtualizarEmTodosOsNavegadores => '在所有浏览器中安装 / 更新';

  @override
  String get terminalAbertoDigiteSuaSenhaSudo =>
      '终端已打开！输入一次 sudo 密码以完成 Guard 安装。';

  @override
  String executeManualmenteP0(Object p0) {
    return '手动运行：$p0';
  }

  @override
  String get terminalAbertoDigiteSuaSenhaSudo2 => '终端已打开！只需输入一次 sudo 密码。';

  @override
  String executeNoTerminalP0(Object p0) {
    return '在终端中运行：$p0';
  }

  @override
  String get aponteODispositivoDoResponsavelPara => '用监护人的设备扫描这个二维码。';

  @override
  String get seEstiverUsandoAVersaoMobile => '如果使用手机版或摄像头，请对准孩子屏幕上的二维码。';

  @override
  String get ouColeAChaveUriDo => '或在此粘贴二维码的密钥/URI';

  @override
  String get chronosPairId => 'chronos://pair?id=...';

  @override
  String get codigoPinDePareamentoDesteDispositivo => '本设备的配对 PIN 码：';

  @override
  String get definirSenhaMestraDeDesbloqueioLocal => '设置本地解锁主密码（可选）';

  @override
  String get digiteUmaSenhaParaAlterarTempo => '输入密码以便现场修改屏幕时间';

  @override
  String get digiteOCodigoPinOuSenha => '输入孩子屏幕上显示的 PIN 码或密码：';

  @override
  String get chrXxxxOuSenha => 'CHR-XXXX 或密码';

  @override
  String get validarEParear => '验证并配对';

  @override
  String get orgKdeStatusnotifierwatcher => 'org.kde.StatusNotifierWatcher';

  @override
  String get abrirChronos => '打开 Chronos';

  @override
  String get desinstalarChronos => '卸载 Chronos…';

  @override
  String get antiBurlaAtivoOChronosNao => '防绕过已开启：开启期间无法卸载 Chronos。';

  @override
  String get chronosFocus => 'Chronos 专注';

  @override
  String get chronosMonitoramentoAtivo => 'Chronos - 正在监控';

  @override
  String oAplicativoP0EstaSendoMonitorado(Object p0, Object p1) {
    return '应用“$p0”正在会话“$p1”中被监控。';
  }

  @override
  String get chronosTempoDeTelaRestante => 'Chronos - 剩余屏幕时间';

  @override
  String p0RestamApenasP1MinutoP2(Object p0, Object p1) {
    return '$p0：屏幕时间只剩 $p1 分钟！';
  }

  @override
  String get chronosTempoDeTelaEsgotado => 'Chronos - 屏幕时间已用完';

  @override
  String p0OTempoDeTelaDiario(Object p0) {
    return '$p0：今天的屏幕时间已全部用完！';
  }

  @override
  String chronosAlertaPeriodicoP0Min(Object p0) {
    return 'Chronos - 定时提醒（$p0 分钟）';
  }

  @override
  String p0P1MinUtilizadosHojeRestam(Object p0, Object p1, Object p2) {
    return '$p0：今天已用 $p1 分钟 • 屏幕时间还剩 $p2 分钟。';
  }

  @override
  String get todas => '全部';

  @override
  String get jogos => '游戏';

  @override
  String get navegadores => '浏览器';

  @override
  String get comunicacao => '通讯';

  @override
  String get internet => '互联网';

  @override
  String get midia => '媒体';

  @override
  String get desenvolvimento => '开发';

  @override
  String get escritorio => '办公';

  @override
  String get graficos => '图形';

  @override
  String get educacao => '教育';

  @override
  String get sistema => '系统';

  @override
  String get utilitarios => '工具';

  @override
  String get outros => '其他';

  @override
  String adicionarTagP0(Object p0) {
    return '添加标签：$p0';
  }

  @override
  String get nomeDaTagExRedesSociais => '标签名称（例如：社交、工作、游戏）';

  @override
  String get adicionarTag => '添加标签';

  @override
  String p0JaFoiAdicionadoAoGrupo(Object p0) {
    return '“$p0”已在分组中。';
  }

  @override
  String get sessaoDeFoco => '专注会话';

  @override
  String get listaBranca => '白名单';

  @override
  String get selecionePeloMenosUmAplicativoOu => '请为分组至少选择一个应用或网站。';

  @override
  String p0HP1Min(Object p0, Object p1) {
    return '$p0 小时 $p1 分钟';
  }

  @override
  String get editarGrupoDeListaBranca => '编辑白名单分组';

  @override
  String get novoGrupoDeListaBranca => '新建白名单分组';

  @override
  String get adicionarAplicativosSitesAoGrupo => '向分组添加应用 / 网站';

  @override
  String get editarSessaoDeFoco => '编辑专注会话';

  @override
  String get criarSessaoDeFoco => '创建专注会话';

  @override
  String get appsESitesNaListaBranca => '白名单中的应用和网站永远不会被拦截或关闭，即使它们在其他分组中。';

  @override
  String get digiteONomeDoGrupoDe => '输入白名单分组名称（例如：学习工具）...';

  @override
  String get digiteONomeDaSessaoDe => '输入专注会话名称（例如：干扰与娱乐）...';

  @override
  String get nomeDoGrupoDeListaBranca => '白名单分组名称';

  @override
  String get nomeDaSessaoDeFoco => '专注会话名称';

  @override
  String aplicativosP0(Object p0) {
    return '应用（$p0）';
  }

  @override
  String sitesEPalavrasP0(Object p0) {
    return '网站与关键词（$p0）';
  }

  @override
  String youtubeP0(Object p0) {
    return 'YouTube（$p0）';
  }

  @override
  String p0AppsP1Sites(Object p0, Object p1) {
    return '$p0 个应用 • $p1 个网站';
  }

  @override
  String get salvarListaBranca => '保存白名单';

  @override
  String get salvarAppsNoGrupo => '保存分组中的应用';

  @override
  String get avancarTempoDeTelaRegras => '下一步：屏幕时间与规则';

  @override
  String get buscarPorNomeExecutavelOuTag => '按名称、可执行文件或标签搜索（例如：游戏、媒体）...';

  @override
  String get selecionarTudo => '全选';

  @override
  String get limpar => '清除';

  @override
  String get carregandoAplicativosInstalados => '正在加载已安装的应用...';

  @override
  String get nenhumAplicativoEncontradoParaOFiltro => '没有符合该筛选/标签的应用。';

  @override
  String get limparFiltroDeTag => '清除标签筛选';

  @override
  String get jaNoGrupo => '已在分组中';

  @override
  String get tag => '+ 标签';

  @override
  String get videosDessesTiposNaoDescontamO =>
      '这些类型的视频不计入 YouTube 屏幕时间。可用上限限制每天的豁免时长（留空 = 不限）。';

  @override
  String get tetoMinDia => '上限（分钟/天）';

  @override
  String get semTeto => '不限';

  @override
  String get digiteDominioOuPalavraChaveEx =>
      '输入域名或关键词（例如：youtube.com、reels、shorts）...';

  @override
  String get adicionar => '添加';

  @override
  String sitesEPalavrasChaveAdicionadosP0(Object p0) {
    return '已添加的网站与关键词（$p0）：';
  }

  @override
  String get limparNovos => '清除新增';

  @override
  String get limparTodos => '全部清除';

  @override
  String get nenhumSiteOuPalavraChaveAdicionado => '此会话中尚未添加网站或关键词。';

  @override
  String p0JaNoGrupo(Object p0) {
    return '$p0（已在分组中）';
  }

  @override
  String editarTempoDeBloqueioP0(Object p0) {
    return '编辑拦截时间：$p0';
  }

  @override
  String tempoDeTelaP0(Object p0) {
    return '屏幕时间：$p0';
  }

  @override
  String sessaoP0(Object p0) {
    return '会话：$p0';
  }

  @override
  String get grupoDeFocoUnificado => '统一专注分组';

  @override
  String p0AplicativosEP1SitesInclusos(Object p0, Object p1) {
    return '包含 $p0 个应用和 $p1 个网站。';
  }

  @override
  String get todosOsAplicativosESitesDesta => '此会话中的所有应用和网站共享同一个每日屏幕时间配额。';

  @override
  String get limiteDeTempoDeTelaRelogio => '屏幕时间限制（数字时钟）：';

  @override
  String get bloqueioTotal2 => '完全拦截';

  @override
  String get nenhumAcessoPermitidoDuranteODia => '全天不允许访问';

  @override
  String p0DeUsoPermitido(Object p0) {
    return '允许使用 $p0';
  }

  @override
  String get bloquearTotalmente0MinDeTempo => '完全拦截（0 分钟屏幕时间）';

  @override
  String get impedeQualquerInicializacaoDoGrupoImediatamente =>
      '立即阻止分组中的任何应用启动';

  @override
  String get tempoDeTelaDiferenciadoNoFinal => '周末使用不同的屏幕时间';

  @override
  String get permiteConfigurarMaisTempoParaSabado => '可以为周六和周日设置更多时间';

  @override
  String tempoFimDeSemanaP0(Object p0) {
    return '周末时间：$p0';
  }

  @override
  String get tempoDeTelaDiferenciadoEmFeriados => '节假日使用不同的屏幕时间';

  @override
  String valeNosFeriadosNacionaisENas(Object p0) {
    return '适用于国家法定节假日和你在设置中添加的日期，优先于周末设置。$p0';
  }

  @override
  String tempoEmFeriadosP0(Object p0) {
    return '节假日时间：$p0';
  }

  @override
  String get diasDaSemanaAtivos => '生效的星期：';

  @override
  String get todos => '全部';

  @override
  String get diasUteis => '工作日';

  @override
  String get finsDeSemana => '周末';

  @override
  String get seg => '周一';

  @override
  String get ter => '周二';

  @override
  String get qua => '周三';

  @override
  String get qui => '周四';

  @override
  String get sex => '周五';

  @override
  String get sab => '周六';

  @override
  String get dom => '周日';

  @override
  String get bloqueioPorJanelaDeHorario => '按时间段拦截';

  @override
  String get bloqueiaOGrupoDentroDeUm => '在每天固定的时间段拦截该分组';

  @override
  String inicioP0(Object p0) {
    return '开始：$p0';
  }

  @override
  String fimP0(Object p0) {
    return '结束：$p0';
  }

  @override
  String get modo => '模式：';

  @override
  String get bloquearDentro => '时间段内拦截';

  @override
  String get permitirSomenteDentro => '仅在时间段内允许';

  @override
  String get notificacaoPorTempoRestante => '剩余时间通知';

  @override
  String get avisaAos155E1 => '在屏幕时间结束前 15、5 和 1 分钟提醒';

  @override
  String get notificacaoPeriodica => '定时通知';

  @override
  String get emiteLembretesRegularesEnquantoASessao => '在会话使用期间定时发送提醒';

  @override
  String get intervaloDaNotificacaoPeriodica => '定时通知间隔：';

  @override
  String aCadaP0Min(Object p0) {
    return '每 $p0 分钟';
  }

  @override
  String get salvarGrupoDeFoco => '保存专注分组';

  @override
  String get permitaAExtensaoNoAnonimo => '允许扩展在无痕模式下运行';

  @override
  String get abrirNosNavegadores => '在浏览器中打开';

  @override
  String get entendi => '知道了';

  @override
  String get guiaAnonimaBloqueadaNosNavegadores => '已在浏览器中禁用无痕模式。';

  @override
  String get guiaAnonimaLiberada => '已允许无痕模式。';

  @override
  String get nenhumNavegadorChromiumEncontrado => '未找到 Chromium 浏览器。';

  @override
  String abertoEmP0(Object p0) {
    return '已在 $p0 中打开：在 Chronos 扩展中开启“在无痕模式下启用”。';
  }

  @override
  String get ativarProtecaoPorDns => '开启 DNS 保护？';

  @override
  String get oDnsFamiliaPassaAValer =>
      '家庭 DNS 将对整台电脑生效。部分应用和网络可能失去功能：\n\n• 屏蔽外部 DNS 的学校、公司或酒店网络可能无法上网；\n• 内网网站和服务（内网、按名称访问的打印机）可能无法打开；\n• VPN、网络游戏、流媒体应用或容器（Docker）可能无法解析地址；\n• 路由器的 DNS 和浏览器的“安全 DNS”将不再使用。\n\n之后关闭需要管理员密码，防绕过开启时无法关闭。';

  @override
  String get entendiAtivar => '知道了，开启';

  @override
  String get filtroDeConteudoAdulto => '成人内容过滤';

  @override
  String get modoParentalOFiltroFicaSempre => '家长模式：过滤始终开启。';

  @override
  String get ativarFiltro => '开启过滤';

  @override
  String get bloqueiaSitesAdultosComATela => '使用 Chronos 拦截页面拦截成人网站。';

  @override
  String get bloquearGuiaAnonimaEConvidado => '禁用无痕和访客模式';

  @override
  String impedeJanelasAnonimasPrivadasEO(Object p0) {
    return '在所有浏览器中禁用无痕/隐私窗口和访客模式$p0。重新允许需要管理员密码，防绕过开启时无法允许。';
  }

  @override
  String get permitirAExtensaoNoAnonimoAbrir => '允许扩展在无痕模式下运行（在浏览器中打开）';

  @override
  String extensaoPermitidaNoAnonimoEmP0(Object p0) {
    return '扩展已在 $p0 个打开的浏览器中允许无痕模式。';
  }

  @override
  String extensaoSemPermissaoNoAnonimoEm(Object p0, Object p1, Object p2) {
    return '扩展在 $p1 个浏览器中有 $p0 个未允许无痕模式$p2。';
  }

  @override
  String get filtroLigadoMasNadaEstaBloqueando =>
      '过滤已开启，但没有任何拦截：请开启成人网站列表、安全搜索或 DNS。';

  @override
  String get listaDeSitesAdultos => '成人网站列表';

  @override
  String p0SitesConhecidosAtualizaTodaSemana(Object p0) {
    return '$p0 个已知网站（每周更新）。';
  }

  @override
  String get baixandoALista => '正在下载列表…';

  @override
  String get iaDeImagensLocal => '图像 AI（本地）';

  @override
  String get desfocaImagensAteUmModeloDe =>
      '在本地 AI 模型检查前模糊图片；成人图片保持模糊，含多张的页面会被拦截。不会上传任何内容。';

  @override
  String get safesearchForcado => '强制安全搜索';

  @override
  String get googleBingEDuckduckgoEmModo =>
      'Google、Bing 和 DuckDuckGo 使用安全模式；YouTube 使用受限模式。';

  @override
  String get protecaoPorDnsComputadorInteiro => 'DNS 保护（整台电脑）';

  @override
  String get usaUmDnsFamiliaEmTodo =>
      '在整个系统使用家庭 DNS：适用于所有浏览器和应用。由 Chronos Guard 应用（关闭需要管理员密码）。';

  @override
  String get servicoDeDnsFamilia => '家庭 DNS 服务';

  @override
  String get dnsDoChronosDesligadoMasO =>
      'Chronos DNS 已关闭，但网络的 DNS（路由器/运营商）已在过滤成人内容——仅在此网络有效。';

  @override
  String get dnsDoSistemaNormalSemDns => '系统 DNS：正常（未使用家庭 DNS）。';

  @override
  String dnsDoSistemaP0AtivoP1(Object p0, Object p1) {
    return '系统 DNS：$p0 已开启$p1。';
  }

  @override
  String get registrarTentativas => '记录尝试';

  @override
  String anotaDataESiteDeCada(Object p0) {
    return '记录每次拦截的日期和网站$p0。';
  }

  @override
  String get ultimasTentativas => '最近的尝试';

  @override
  String get verHistoricoCompleto => '查看完整历史';

  @override
  String get excecoesSitesNuncaBloqueadosPorEste => '例外（此过滤永不拦截的网站）';

  @override
  String get exSiteDaEscolaCom => '例如：school-site.com';

  @override
  String get hoje => '今天';

  @override
  String get t7Dias => '7 天';

  @override
  String get t30Dias => '30 天';

  @override
  String get tudo => '全部';

  @override
  String get listaDeSites => '网站列表';

  @override
  String get reddit => 'Reddit';

  @override
  String get iaDeImagens => '图像 AI';

  @override
  String get historicoDeTentativas => '尝试历史';

  @override
  String p0TentativaS(Object p0) {
    return '$p0 次尝试';
  }

  @override
  String get nenhumaTentativaNestePeriodo => '此期间没有尝试。';

  @override
  String get fechar => '关闭';

  @override
  String p0HP1M(Object p0, Object p1) {
    return '$p0小时 $p1分';
  }

  @override
  String get semDados => '无数据';

  @override
  String get estatisticasDeTempoDeTela => '屏幕时间统计';

  @override
  String get consumoConsolidadoTendenciasSemanaisERanking =>
      '总体用量、每周趋势以及应用和网站排名。';

  @override
  String get atualizar => '刷新';

  @override
  String get consumoHoje => '今日用量';

  @override
  String get tempoEmAppsSitesMonitorados => '受监控应用/网站的时间';

  @override
  String get mediaSemanal => '每周平均';

  @override
  String get baseadoNosUltimos7Dias => '基于最近 7 天';

  @override
  String get diaDePico => '高峰日';

  @override
  String get tendenciaVsSemanaAnterior => '与上周相比的趋势';

  @override
  String get estavel => '稳定';

  @override
  String get maisTempoDeTela => '屏幕时间增加';

  @override
  String get menosTempoDeTela => '屏幕时间减少';

  @override
  String get appsSitesMonitorados => '受监控的应用/网站';

  @override
  String get mediaDiaria => '每日平均';

  @override
  String get ultimos7Dias => '最近 7 天';

  @override
  String get tendencia => '趋势';

  @override
  String get maisTela => '更多屏幕';

  @override
  String get menosTela => '更少屏幕';

  @override
  String get tempoIsentoNoYoutubeListaBranca => 'YouTube 豁免时间（白名单）';

  @override
  String p0P1Em7Dias(Object p0, Object p1) {
    return '$p0：7 天内 $p1';
  }

  @override
  String get consumoDiarioNosUltimos7Dias => '最近 7 天的每日用量';

  @override
  String totalP0(Object p0) {
    return '总计：$p0';
  }

  @override
  String get nenhumDadoDiarioRegistrado => '没有记录到每日数据。';

  @override
  String get top5AppsSitesMaisConsumidos => '使用最多的 5 个应用和网站（最近 7 天）';

  @override
  String get nenhumaAtividadeRegistradaNaSemanaAinda => '本周尚无活动记录。';

  @override
  String p0DoTotal(Object p0) {
    return '占总数 $p0%';
  }

  @override
  String get colarNaoEPermitidoDigiteO => '❌ 不允许粘贴：请输入文字。';

  @override
  String get erroDetectadoNoModoStayfocusdQualquer =>
      '❌ 检测到错误！在 StayFocusd 模式下，任何一个错误字符都会清空全部文字。请仔细输入！';

  @override
  String get selecioneUmaDuracaoValidaMaiorQue => '请为 Nuke 模式选择大于 0 分钟的有效时长。';

  @override
  String get ativarOAntiBurla => '开启防绕过？';

  @override
  String enquantoOAntiBurlaEstiverAtivo(Object p0) {
    return '防绕过开启期间：\n\n• 无法卸载 Chronos；\n• 它会在后台持续运行，关闭后会自动重新打开；\n• 规则、过滤和扩展不能放宽。\n\n$p0';
  }

  @override
  String get noModoNukeIssoSoAcaba => '在 Nuke 模式下，只有时间结束才会解除。';

  @override
  String get paraDesativarSeraPrecisoCompletarO => '要关闭它，你需要完成挑战。';

  @override
  String modoNukeAtivadoPorP0Configuracoes(Object p0) {
    return '☢️ Nuke 模式已开启 $p0！设置和扩展已锁定。';
  }

  @override
  String get modoAntiCheatAtivadoComDesafio => '🛡️ 已开启带严格挑战的防绕过模式！';

  @override
  String erroAoAtivarP0(Object p0) {
    return '开启时出错：$p0';
  }

  @override
  String get antiCheatDesativadoComSucessoModificacoes => '🔓 防绕过已关闭！可以修改了。';

  @override
  String erroP0(Object p0) {
    return '错误：$p0';
  }

  @override
  String get protecaoAntiCheatAtiva => '防绕过保护已开启';

  @override
  String get configurarModoAntiCheat => '设置防绕过模式';

  @override
  String get oAntiCheatImpedeVoceDe =>
      '防绕过会阻止你在意志薄弱时绕过 Chronos、解除拦截或提高限制，并防止扩展被移除。';

  @override
  String get escolhaOMetodoDeTravamento => '选择锁定方式：';

  @override
  String get desafioDeDigitacaoEstritoEstiloStayfocusd =>
      '严格打字挑战（StayFocusd 风格）';

  @override
  String get qualquerTentativaDeDesativarOuAumentar =>
      '任何关闭或提高屏幕时间限制的尝试，都需要毫无错误地重新输入一段很长的承诺文字。打错一个字符？文字会被清空！';

  @override
  String get modoNukeBloqueioTotalPorTempo => 'Nuke 模式（定时完全锁定）';

  @override
  String get trava100OChronosPorUm =>
      '在一段时间内 100% 锁定 Chronos。在此期间，直到时间结束前都无法解锁或修改任何内容。';

  @override
  String get duracaoDoTravamentoNukeScrollPara => 'Nuke 锁定时长（滚动调整）：';

  @override
  String ativarModoNukeP0(Object p0) {
    return '开启 NUKE 模式（$p0）';
  }

  @override
  String get ativarAntiCheatRestrito => '开启严格防绕过';

  @override
  String get modoNukeEmAndamento => 'NUKE 模式进行中';

  @override
  String get nenhumaAlteracaoDeTempoDeTela => '在时间结束前，不允许修改屏幕时间、规则或移除扩展。';

  @override
  String get desafioDeDigitacaoStayfocusd => 'StayFocusd 打字挑战';

  @override
  String get paraDestravarOAplicativoELiberar => '要解锁应用并允许修改，请准确无误地输入下面的文字：';

  @override
  String progressoP0P1Caracteres(Object p0, Object p1) {
    return '进度：$p0 / $p1 个字符';
  }

  @override
  String get comeceADigitarOTextoAqui => '在这里开始输入文字...';

  @override
  String get destravarAntiCheat => '解锁防绕过';

  @override
  String get debugDesativarAntiCheatImediatamente => '🛠️ 调试：立即关闭防绕过';

  @override
  String get debugAntiCheatENukeDesativados => '🛠️ [调试] 防绕过和 Nuke 已关闭！';

  @override
  String get instalarAtualizarExtensaoEmTodosNavegadores => '在所有浏览器中安装 / 更新扩展';

  @override
  String get pacoteEmbutido => '内置安装包';

  @override
  String get atualizarGuard => '更新 Guard';

  @override
  String get politicaGuard => 'Guard 策略';

  @override
  String get ativoNosNavegadores => '已在浏览器中启用';

  @override
  String get nenhumNavegadorSuportadoDetectado => '未检测到支持的浏览器。';

  @override
  String get protegidoPeloProxySeletivoLocal127 =>
      '由本地选择性代理（127.0.0.1:4546）+ CA 证书保护——Firefox 正式版不会在 about:addons 中列出未签名的 .xpi，但拦截和 HTML/CSS 过滤照常工作。';

  @override
  String get instalacaoManualFallbackAvancado => '手动安装 / 高级备用方案';

  @override
  String get baixarChromeZip => '下载 Chrome 版（.zip）';

  @override
  String extensaoSalvaEmP0(Object p0) {
    return '扩展已保存到：$p0';
  }

  @override
  String get erroAoSalvarZipEmDownloads => '保存 zip 到“下载”文件夹时出错。';

  @override
  String get baixarFirefoxXpi => '下载 Firefox 版（.xpi）';

  @override
  String get erroAoSalvarXpiEmDownloads => '保存 xpi 到“下载”文件夹时出错。';

  @override
  String get ativarNoChromeManual => '在 Chrome 中启用（手动）';

  @override
  String get ativarNoFirefoxManual => '在 Firefox 中启用（手动）';

  @override
  String get comandoTerminalGuard => '终端命令（Guard）';

  @override
  String get reiniciarNavegadoresParaAtivar => '重启浏览器以启用？';

  @override
  String osSeguintesNavegadoresJaEstaoAbertos(Object p0) {
    return '以下浏览器已经打开，需要关闭并重新打开才能加载 Chronos 扩展：\n\n$p0\n\n现在关闭并重新打开吗？';
  }

  @override
  String get agoraNao => '暂不';

  @override
  String get fecharEReabrirAgora => '立即关闭并重新打开';

  @override
  String navegadoresReiniciadosP0(Object p0) {
    return '浏览器已重启（$p0）！';
  }

  @override
  String get acessoBloqueadoPeloChronos => '已被 CHRONOS 拦截';

  @override
  String oTempoDeTelaDiarioPara(Object p0) {
    return '$p0 今天的屏幕时间已全部用完。';
  }

  @override
  String get reproducaoMprisPausadaAutomaticamente => '已自动暂停 MPRIS 播放。';

  @override
  String get janelaSobrepostaAtivaEnquantoOApp => '干扰应用处于前台时，遮罩窗口保持开启。';

  @override
  String usarTokenDeEmergencia1hP0(Object p0) {
    return '使用紧急令牌（+1 小时）[$p0/2]';
  }

  @override
  String get avisoConsumirUmTokenDeEmergencia => '警告：使用紧急令牌会锁定所有娱乐活动 24 小时！';

  @override
  String get nenhumTokenDeEmergenciaRestantePara => '本月没有剩余的紧急令牌。回到学习和专注吧！';

  @override
  String get idiomaPrincipalSteamApiDefinidoPara => '主语言已设置为英语。';

  @override
  String get idiomaPrincipalSteamApiDefinidoPara2 => '主语言已设置为葡萄牙语（巴西）。';

  @override
  String get modoNukeAtivoRemocaoDaExtensao => 'Nuke 模式已开启：时间结束前禁止移除扩展。';

  @override
  String get remocaoCanceladaConcluaAVerificacaoAnti => '已取消移除：完成防绕过验证后才能移除扩展。';

  @override
  String get antiCheatAindaAtivoRemocaoBloqueada => '防绕过仍在开启。禁止移除。';

  @override
  String get removerExtensaoPoliticas => '移除扩展和策略？';

  @override
  String get verificacaoAntiCheatConcluidaIssoRemovera =>
      '防绕过验证已通过。这将从所有浏览器中移除 Chronos 扩展、External Extensions 链接和 Chronos Guard（Chrome/Chromium/Firefox 策略），直到你重新安装。\n\n确认移除？';

  @override
  String get removerDeTodosOsNavegadores => '从所有浏览器中移除';

  @override
  String get filtrosAntiDistracaoSalvosComSucesso => '防干扰过滤已保存！';

  @override
  String p0JaEstaNaLista(Object p0) {
    return '“$p0”已在列表中。';
  }

  @override
  String get antiCheatAtivoDesativeOAnti => '防绕过已开启：关闭防绕过后才能移除标签或游戏名。';

  @override
  String get antiCheatAtivoDesativeOAnti2 => '防绕过已开启：关闭防绕过后才能移除启动器商店保护。';

  @override
  String get configuracoesGerais => '常规设置';

  @override
  String get ajustesDeNotificacoesExtensoesLocaisModo => '通知、本地扩展、模式与安全';

  @override
  String get versaoEAtualizacoes => '版本与更新';

  @override
  String chronosP0AsAtualizacoesSaoVerificadas(Object p0) {
    return 'Chronos $p0 —— 打开应用时检查更新。';
  }

  @override
  String chronosP0BuildDeDesenvolvimentoSem(Object p0) {
    return 'Chronos $p0（开发版本——不自动更新）。';
  }

  @override
  String get procurarAtualizacoes => '检查更新';

  @override
  String get desinstalarChronos2 => '卸载 Chronos';

  @override
  String get notificacoesDeDesktop => '桌面通知';

  @override
  String get oModoNaoPerturbeDoSistema => '系统的“勿扰”模式已开启：关闭前不会显示 Chronos 的通知。';

  @override
  String get verificar => '检查';

  @override
  String get notificarInicioDeAppMonitorado => '受监控应用启动时通知';

  @override
  String get exibeUmaNotificacaoNoDesktopAvisando => '显示桌面通知，提示正在运行的应用正在计时。';

  @override
  String get notificacaoDeAppMonitoradoAtivada => '受监控应用通知已开启';

  @override
  String get notificacaoDeAppMonitoradoDesativada => '受监控应用通知已关闭';

  @override
  String get alertasDeTempoDeTelaRestante => '剩余屏幕时间提醒';

  @override
  String get avisosAutomaticosQuandoRestarem15m5m =>
      '每日屏幕时间剩余 15、5 和 1 分钟时自动提醒。';

  @override
  String get avisosPeriodicosDeUsoAtivo => '定时使用提醒';

  @override
  String get lembretesEmIntervalosRegularesExA => '按固定间隔（例如每 15 分钟）提醒已使用的时间。';

  @override
  String get extensoesDosNavegadores => '浏览器扩展';

  @override
  String get protegeTodosOsNavegadoresDoDispositivo =>
      '离线保护设备上的所有浏览器：Chromium 系浏览器（Chrome、Chromium、Brave、Edge、Vivaldi、Opera）使用本地扩展，Firefox 使用选择性专注代理 + 本地 CA。';

  @override
  String get navegadoresDetectadosNoSistema => '系统中检测到的浏览器：';

  @override
  String get extensaoRemovidaAposVerificacaoAntiCheat =>
      '通过防绕过验证后已移除扩展。点击下方在所有浏览器中重新安装。';

  @override
  String get configurandoNavegadoresGuard => '正在配置浏览器和 Guard...';

  @override
  String get protecaoPermanenteDoSistemaAntiBurla => '永久系统保护（浏览器防绕过）';

  @override
  String get protecaoDoSistemaAtivaTrancada => '系统保护已开启并锁定';

  @override
  String get politicasForcadasAtivasEmChromeChromium =>
      '已在 Chrome/Chromium/Brave/Edge/Vivaldi/Opera（已签名 CRX3）和 Firefox 正式版（选择性专注代理 + 本地 CA + PAC，about:policies 中无警告）中启用强制策略。已禁止移除扩展和无痕浏览。';

  @override
  String get reAplicarPoliticasDoSistema => '重新应用系统策略';

  @override
  String get politicasDoSistemaVerificadasERe => '系统策略已检查并重新应用！';

  @override
  String get falhaAoReAplicarPoliticas => '重新应用策略失败。';

  @override
  String get removendo => '正在移除...';

  @override
  String get removerExtensaoVerificarAntiCheat => '移除扩展（防绕过验证）';

  @override
  String get oChronosGuardInstaladoPossuiPoliticas =>
      '已安装的 Chronos Guard 使用旧策略（例如 Firefox 正式版中未签名的 ExtensionSettings）。点击上方的“在所有浏览器中安装 / 更新”一键修复。';

  @override
  String get oChronosGuardGravaPoliticasPermanentes =>
      'Chronos Guard 会（经你的 Polkit 授权）在 /etc/ 中写入永久策略，防止手动卸载和无痕浏览。使用上方的主按钮一键开启。';

  @override
  String get atualizarGuardViaPolkit1Clique => '通过 Polkit 更新 Guard（一键）';

  @override
  String get ativarGuardViaPolkit1Clique => '通过 Polkit 开启 Guard（一键）';

  @override
  String get modoDoAplicativoCadastro => '应用模式与设置';

  @override
  String modoAtivoP0(Object p0) {
    return '当前模式：$p0';
  }

  @override
  String get configuradoComPinEProtecaoParental => '已设置 PIN 和家长限制保护。';

  @override
  String get focadoEmAutonomiaComprometimentoPessoalE => '注重自主、个人承诺和效率。';

  @override
  String get trocarModoRefazerCadastro => '切换模式 / 重新设置';

  @override
  String get antiCheatProtecaoContraBurlar => '防绕过与防绕过保护';

  @override
  String modoNukeAtivoP0SRestantes(Object p0) {
    return 'Nuke 模式已开启（剩余 $p0 秒）';
  }

  @override
  String get antiCheatAtivoDesafioStayfocusd => '防绕过已开启（StayFocusd 挑战）';

  @override
  String get antiCheatDesativado => '防绕过已关闭';

  @override
  String get bloqueiaModificacoesDeRegrasAumentoDe =>
      '阻止修改规则、在意志薄弱时提高限制以及移除扩展。';

  @override
  String get gerenciarAntiCheat => '管理防绕过';

  @override
  String get ativarAntiCheat => '开启防绕过';

  @override
  String get textosDoDesafio => '挑战文字';

  @override
  String get antiBurlaAtivoOsTextosDo => '防绕过已开启：现在无法修改挑战文字。';

  @override
  String get gerenciamentoDeDadosLocaisOffline => '本地数据管理（离线）';

  @override
  String get todasAsInformacoesRegrasETempos =>
      'Chronos 的所有信息、规则和屏幕时间都 100% 保存在你的电脑上。';

  @override
  String get zerarConsumoDiarioDeHoje => '清零今日用量';

  @override
  String get reiniciarBancoDeDadosCompleto => '重置整个数据库';

  @override
  String get reiniciarBancoDeDados2 => '重置数据库';

  @override
  String get atencaoIssoIraApagarTodasAs =>
      '注意：这将删除你创建的所有拦截规则，并将数据库恢复到初始状态。要继续吗？';

  @override
  String get zerarTudo => '全部清零';

  @override
  String get instalarProtecaoPermanente => '安装永久保护';

  @override
  String get estaEtapaConfiguraOsArquivosDe =>
      '此步骤会在 /etc/ 中写入官方策略文件，并启用 systemd 服务，永久锁定扩展以防绕过。';

  @override
  String get comoDesejaProsseguir => '你想如何继续？';

  @override
  String get opcao1CliqueEmAbrirTerminal =>
      '方式 1：点击“打开终端”，在打开的窗口中输入一次 sudo 密码。\n方式 2：或复制下面的命令，在你常用的终端中运行：';

  @override
  String get copiarComando => '复制命令';

  @override
  String get comandoCopiadoParaAAreaDe => '命令已复制到剪贴板！';

  @override
  String get verificarStatus => '检查状态';

  @override
  String get protecaoDoSistemaAtivaEConfirmada => '系统保护已开启并确认！';

  @override
  String get protecaoAindaPendenteDeInstalacao => '保护尚未安装。';

  @override
  String get abrirTerminal => '打开终端';

  @override
  String get terminalAbertoDigiteSuaSenhaNa => '终端已打开！在窗口中输入密码以完成。';

  @override
  String get naoFoiPossivelAbrirOTerminal => '无法自动打开终端。命令已复制！';

  @override
  String get ativarNoGoogleChrome => '在 Google Chrome 中启用';

  @override
  String get oGoogleChromeOficialBloqueiaInjecoes =>
      '出于安全考虑，官方 Google Chrome 会阻止通过命令行隐藏注入。要启用，只需加载一次本地文件夹（大约 10 秒）。';

  @override
  String get passoAPassoRapido => '快速步骤：';

  @override
  String get cliqueNoBotaoAbrirChromeAbaixo =>
      '点击下方的“打开 Chrome”。Chrome 会打开 chrome://extensions，并复制文件夹路径。';

  @override
  String get noChromeAtiveAChaveModo => '在 Chrome 中，打开右上角的“开发者模式”。';

  @override
  String get cliqueNoBotaoCarregarSemCompactacao => '点击“加载已解压的扩展程序”（左上角）。';

  @override
  String get pressioneCtrlVOuSelecioneA => '按 Ctrl+V 或选择扩展文件夹并确认。';

  @override
  String get copiarCaminho => '复制路径';

  @override
  String get caminhoCopiadoParaAAreaDe => '路径已复制到剪贴板！';

  @override
  String get baixarZip => '下载 .zip';

  @override
  String arquivoSalvoEmP0(Object p0) {
    return '文件已保存到：$p0';
  }

  @override
  String get erroAoGerarZipParaDownloads => '在“下载”文件夹中生成 zip 时出错。';

  @override
  String get abrirChrome => '打开 Chrome';

  @override
  String get chromeAbertoCaminhoCopiadoParaA => 'Chrome 已打开！路径已复制到剪贴板。';

  @override
  String get ativarExtensaoNoFirefox => '在 Firefox 中启用扩展';

  @override
  String get noFirefoxReleasePadraoAMozilla =>
      '在标准 Firefox 正式版中，Mozilla 要求外部 .xpi 必须签名——因此 Chronos 的永久保护通过 Chronos Guard 的本地选择性代理 + CA 证书实现。对于 Firefox ESR/Dev/LibreWolf/Zen 或在 about:debugging 中临时测试，请使用 .xpi：';

  @override
  String get cliqueNoBotaoAbrirFirefoxAbaixo => '点击下方的“打开 Firefox”直接进入调试页面。';

  @override
  String get cliqueNoBotaoCarregarExtensaoTemporaria => '点击“临时载入附加组件...”。';

  @override
  String get selecioneOArquivoManifestJsonNa =>
      '选择下方文件夹中的“manifest.json”，或 ~/Downloads 中的 .xpi 文件。';

  @override
  String get caminhoDoManifestJsonCopiado => 'manifest.json 路径已复制！';

  @override
  String get erroAoGerarXpiParaDownloads => '在“下载”文件夹中生成 xpi 时出错。';

  @override
  String get abrirFirefox => '打开 Firefox';

  @override
  String get firefoxAbertoCaminhoCopiadoParaA => 'Firefox 已打开！路径已复制到剪贴板。';

  @override
  String get aparenciaModoDeTema => '外观与主题';

  @override
  String get personalizeOTemaVisualDoChronos =>
      '自定义 Chronos 的外观。浅色模式针对明亮环境优化，对比度高；深色模式可减轻眼睛疲劳。';

  @override
  String get idiomaPrincipalTagsAutocompleteSteamApi => '语言';

  @override
  String get asTagsSaoEnviadasEmIngles => '应用、扩展和拦截页面使用的语言。Steam 标签在可用时以此语言显示。';

  @override
  String get portuguesBr => 'Português (BR)';

  @override
  String get englishUs => 'English (US)';

  @override
  String get configBravesoftwareBraveBrowser =>
      '.config/BraveSoftware/Brave-Browser';

  @override
  String get aoAtivarOAntiBurlaO =>
      '如果你添加了自己的文字，Chronos 只会从中随机抽取（不再使用默认文字）。没有自定义文字时使用默认文字。每段文字之间用空行分隔（每段至少 120 个字符）。防绕过开启时无法修改。';

  @override
  String get seuTextoAqui => '在这里输入你的文字…';

  @override
  String get salvar => '保存';

  @override
  String get atualizacoesDaExtensao => '扩展更新';

  @override
  String get atualizarExtensoesAutomaticamente => '自动更新扩展';

  @override
  String get quandoOChronosForAtualizadoOs => 'Chronos 更新后，浏览器会自动安装新扩展。';

  @override
  String get firefoxAtualizaAoReabrirONavegador =>
      'Firefox：同样通过 Chronos 更新（已签名的版本）。';

  @override
  String get atualizarExtensoesAgora => '立即更新扩展';

  @override
  String get pedidoEnviadoOChromeInstalaA => '请求已发送。浏览器将在几秒内安装新版本。';

  @override
  String get mostrarApenasVideosDestesTipos => '只显示这些类型的视频';

  @override
  String get escolhaAoMenosUmTipoAbaixo => '请在下方至少选择一种类型以开启。';

  @override
  String get aHomeEOsRelacionadosSo => '首页和相关视频只显示所选类型。搜索仍显示全部内容（并计时）。';

  @override
  String get escolhaAoMenosUmTipoAntes => '开启前请至少选择一种类型。';

  @override
  String get importarDaListaBranca => '从白名单导入';

  @override
  String get nenhumTipoDoYoutubeNaLista => '白名单中没有 YouTube 类型。';

  @override
  String get tiposPorCanalPalavra => '按频道/关键词分类';

  @override
  String get filtrosDeConteudoAntiDistracaoPor => '内容过滤与按平台防干扰（StayFocusd 风格）';

  @override
  String get configureFiltrosDeCssEHtml =>
      '为每个应用或社交网络设置 CSS 和 HTML 过滤。无需完全拦截网站即可去除多巴胺诱因。';

  @override
  String get detoxGlobalTodosOsSites => '全局排毒（所有网站）';

  @override
  String get modoPretoEBrancoGrayscaleDetox => '黑白模式（灰度排毒）';

  @override
  String get aplicaEscalaDeCinzaEmTodas => '对所有页面应用灰度，减少强迫性浏览。';

  @override
  String get bloquearNotificacoesEBadges => '屏蔽通知和角标';

  @override
  String get removeSinosVermelhosEAlertasNumericos => '移除所有网站上的红色铃铛和数字提醒，避免打扰。';

  @override
  String get youtubeFocus => 'YouTube 专注';

  @override
  String get bloquearYoutubeShorts => '屏蔽 YouTube Shorts';

  @override
  String get ocultaCarrosseisDeShortsNaHome => '隐藏首页、搜索和侧边栏中的 Shorts 轮播。';

  @override
  String get ocultarFeedDaHome => '隐藏首页推荐';

  @override
  String get ocultaTodasAsRecomendacoesAlgoritmicasDa =>
      '隐藏 YouTube 首页的所有算法推荐。';

  @override
  String get ocultarVideosRelacionadosBarraLateral => '隐藏相关视频（侧边栏）';

  @override
  String get removeSugestoesDeVideosAoLado => '移除播放器旁的视频推荐，避免分心。';

  @override
  String get ocultarComentariosDoYoutube => '隐藏 YouTube 评论';

  @override
  String get ocultaTodaASecaoDeComentarios => '隐藏所有视频的整个评论区。';

  @override
  String get instagramFocus => 'Instagram 专注';

  @override
  String get bloquearInstagramReels => '屏蔽 Instagram Reels';

  @override
  String get removeAAbaEOCarrossel => '移除 Instagram 网页版的 Reels 标签和短视频轮播。';

  @override
  String get ocultarFeedPrincipalExplore => '隐藏主信息流和探索';

  @override
  String get ocultaOFeedInfinitoDePostagens => '隐藏首页无限滚动的帖子和推荐。';

  @override
  String get ocultarComentariosDoInstagram => '隐藏 Instagram 评论';

  @override
  String get ocultaComentariosSobPostagensEVideos => '隐藏帖子和视频下的评论。';

  @override
  String get tiktokFocus => 'TikTok 专注';

  @override
  String get bloquearFeedDeVideosRecomendados => '屏蔽推荐视频信息流';

  @override
  String get bloqueiaOFluxoInfinitoDeVideos => '屏蔽 TikTok 无限滚动的“为你推荐”短视频。';

  @override
  String get redditFocus => 'Reddit 专注';

  @override
  String get bloquearFeedPrincipalPopular => '屏蔽主页 / 热门信息流';

  @override
  String get ocultaATimelineDePostsInfinitos => '隐藏 r/all 和 Reddit 首页无限滚动的帖子。';

  @override
  String get ocultarSecoesDeComentarios => '隐藏评论区';

  @override
  String get ocultaAsArvoresDeDiscussaoE => '隐藏 Reddit 帖子中的讨论和评论。';

  @override
  String get bloquearConteudo18Nsfw => '屏蔽成人内容（NSFW）';

  @override
  String get escondePostsNsfwNosFeedsE =>
      '隐藏信息流和搜索中的 NSFW 帖子，并拦截成人版块和帖子。防绕过开启时无法关闭。';

  @override
  String get xTwitterFocus => 'X / Twitter 专注';

  @override
  String get bloquearTimelineFeedPrincipal => '屏蔽时间线 / 主信息流';

  @override
  String get ocultaATimelineParaVoceE => '隐藏 X（Twitter）上的“为你推荐”和“正在关注”时间线。';

  @override
  String get ocultarAssuntosDoMomentoTrending => '隐藏热门话题';

  @override
  String get removeABarraLateralDeTendencias => '移除趋势和探索新闻侧边栏。';

  @override
  String get bloquearConteudo18Sensivel => '屏蔽成人内容（敏感）';

  @override
  String get escondePostsComMidiaSensivelE =>
      '隐藏含敏感媒体的帖子，并拦截被标记为敏感的账号。防绕过开启时无法关闭。';

  @override
  String get linkedinFocus => 'LinkedIn 专注';

  @override
  String get bloquearFeedDeNoticiasDoLinkedin => '屏蔽 LinkedIn 动态';

  @override
  String get ocultaATimelineDePostagensPara => '隐藏帖子时间线，只专注于消息和个人资料。';

  @override
  String get hudFlutuanteNosNavegadoresPilula => '浏览器悬浮 HUD（胶囊）';

  @override
  String get opacidadeDaPilulaAlfa => '胶囊不透明度';

  @override
  String get controlaATransparenciaDaPilulaRecolhida => '控制浏览器中收起的胶囊和闭眼图标的透明度。';

  @override
  String get tamanhoDaPilula => '胶囊大小';

  @override
  String get ajustaAEscalaDaPilulaE => '调整胶囊大小和闭眼图标的直径（始终等于胶囊高度）。';

  @override
  String get aoEsconderPilulaMostrarIconeDe => '隐藏胶囊时显示可拖动的眼睛图标';

  @override
  String get quandoAtivoMinimizarTransformaAPilula =>
      '开启时，最小化会把胶囊变成同样高度、可拖动的圆形闭眼按钮；关闭时会完全隐藏（按 Alt+Shift+C 重新显示）。';

  @override
  String get launchersJogosSteamApiHeroicEpic =>
      '启动器与游戏（Steam API、Heroic、Epic、GOG、Lutris）';

  @override
  String get antiCheatAtivoRemocaoBloqueada => '防绕过已开启（禁止移除）';

  @override
  String get ativarFiltroEmLaunchersLojasDe => '在启动器和游戏商店中开启过滤';

  @override
  String get bloqueiaJogosEmExecucaoPaginasDe =>
      '通过 Steam API 按名称或标签拦截正在运行的游戏、商店页面、指南、讨论和艺术作品。随时可以添加；移除需要关闭防绕过。';

  @override
  String get antiCheatAtivoDesativeOAnti3 => '防绕过已开启：关闭防绕过后才能关闭启动器过滤。';

  @override
  String get tagsProibidasSteamApi => '禁止的标签（Steam API）';

  @override
  String get buscarTagNaSteamApiEx => '在 Steam API 中搜索标签（例如：动作、类魂、恐怖、FPS）...';

  @override
  String get nomesDeJogosProibidos => '禁止的游戏名称';

  @override
  String get buscarJogoNaSteamApiEx =>
      '在 Steam API 中搜索游戏（例如：Counter-Strike 2、Elden Ring）...';

  @override
  String get protegerLojaComunidadeDentroDaSteam =>
      '保护 Steam/Heroic 内的商店/社区（代理 + NSS）';

  @override
  String ocultarJogosDetectadosP0(Object p0) {
    return '隐藏检测到的游戏（$p0）';
  }

  @override
  String get consultarJogosDosLaunchersSteamApi => '查询启动器中的游戏（Steam API）';

  @override
  String get nenhumJogoInstaladoDetectadoNosLaunchers =>
      '本地启动器（Steam、Heroic、Lutris、Bottles）中未检测到已安装的游戏。';

  @override
  String get bloquearJogo => '+ 拦截游戏';

  @override
  String tagCanonicaSteamApiP0(Object p0) {
    return 'Steam API 标准标签：$p0';
  }

  @override
  String get sugestoesSteamApi => 'Steam API 建议：';

  @override
  String enviaP0ParaASteamApi(Object p0) {
    return '将“$p0”发送到 Steam API';
  }

  @override
  String get desativarTodos => '全部关闭';

  @override
  String get ativarTodos => '全部开启';

  @override
  String get nomeDoFeriado => '节日名称';

  @override
  String get exFeriasAniversario => '例如：假期、生日';

  @override
  String get feriados => '节假日';

  @override
  String hojeEFeriadoP0AsCotas(Object p0) {
    return '今天是节假日：$p0——各会话的节假日配额生效。';
  }

  @override
  String get aCotaDeFeriadoEDefinida => '节假日配额在每个会话中设置（与周末配额相同）。';

  @override
  String get proximosFeriados => '即将到来的节假日';

  @override
  String get feriadosPersonalizados => '自定义节假日';

  @override
  String get comOAntiBurlaLigadoNao => '防绕过开启时无法添加节假日（只能删除）。';

  @override
  String get adicionarUmaDataComACota => '添加一个使用会话节假日配额的日期';

  @override
  String get adicionarData => '添加日期';

  @override
  String get antiBurlaLigadoAdicionarFeriadosEsta => '防绕过已开启：禁止添加节假日。';

  @override
  String get nenhum => '无。';

  @override
  String get remover => '删除';

  @override
  String varreduraConcluidaP0ProcessosAuditadosQuarentena(Object p0) {
    return '扫描完成。已审查/隔离 $p0 个进程。';
  }

  @override
  String get inspecaoDeBinariosQuarentena => '程序检查与隔离';

  @override
  String get protecaoContraBinariosNaoEmpacotadosPelo =>
      '防护未由 pacman 打包或在 /usr/bin 之外运行的程序';

  @override
  String get escanearProcessos => '扫描进程';

  @override
  String get nenhumProcessoNaoConfiavelEmQuarentena => '隔离区中没有不受信任的进程！';

  @override
  String get cliqueEmEscanearProcessosParaAuditar => '点击“扫描进程”审查官方系统之外正在运行的程序。';

  @override
  String get aprovarBinario => '批准程序';

  @override
  String get rejeitarBloquear => '拒绝并拦截';

  @override
  String get modoAntiCheatAtivo => '防绕过模式已开启！';

  @override
  String oChronosEstaNoModoNuke(Object p0, Object p1) {
    return 'Chronos 处于 Nuke 模式（剩余 $p0 分钟）。计时结束前不允许$p1。';
  }

  @override
  String naoEPermitidoP0EnquantoO(Object p0) {
    return '防绕过开启时不允许$p0。要修改规则，请先完成防绕过的严格打字挑战。';
  }

  @override
  String get entendido => '明白了';

  @override
  String get resolverDesafio => '完成挑战';

  @override
  String get desbloquearEntidades => '解除拦截';

  @override
  String get removerRegrasDeBloqueio => '删除拦截规则';

  @override
  String get editarTempoDeBloqueioEAgendamento => '编辑拦截时间和计划';

  @override
  String finsDeSemanaP0(Object p0) {
    return '周末：$p0';
  }

  @override
  String tempoDeTelaP0P1P2(Object p0, Object p1, Object p2) {
    return '屏幕时间：$p0$p1 • $p2';
  }

  @override
  String get renomear => '重命名';

  @override
  String get nome => '名称';

  @override
  String get adicionarAppsOuSitesAoGrupo => '向分组添加应用或网站（只允许重命名）';

  @override
  String get editarGruposDeListaBranca => '编辑白名单分组';

  @override
  String get adicionarGruposDeListaBranca => '添加白名单分组';

  @override
  String get removerGrupoDeListaBranca => '删除白名单分组';

  @override
  String get desejaRealmenteRemoverEsteGrupoDe =>
      '确定要删除这个白名单分组吗？其中的应用和网站将不再受保护，会重新被计时或拦截。';

  @override
  String get removerAplicativoDoGrupoDeBloqueio => '从拦截分组中移除应用';

  @override
  String get removerDoGrupoDeBloqueio => '从拦截分组中移除';

  @override
  String desejaRealmenteRemoverP0DesteGrupo(Object p0) {
    return '确定要从这个拦截分组中移除“$p0”吗？';
  }

  @override
  String erroAoRemoverAplicativoP0(Object p0) {
    return '移除应用时出错：$p0';
  }

  @override
  String get removerDaListaBranca => '从白名单中移除';

  @override
  String desejaRemoverP0DestaListaBranca(Object p0) {
    return '要从这个白名单中移除“$p0”吗？该应用将不再受拦截保护。';
  }

  @override
  String erroAoRemoverDaListaBranca(Object p0) {
    return '从白名单中移除时出错：$p0';
  }

  @override
  String get t0mBloqueioTotal => '0 分钟（完全拦截）';

  @override
  String p0AplicativoS(Object p0) {
    return '$p0 个应用';
  }

  @override
  String p0SiteSPalavraS(Object p0) {
    return '$p0 个网站/关键词';
  }

  @override
  String get permitirSomente => '仅允许';

  @override
  String get bloquear => '拦截';

  @override
  String janelaP0P1P2(Object p0, Object p1, Object p2) {
    return '时间段：$p0 $p1-$p2';
  }

  @override
  String get extensaoProtecaoDosNavegadores => '扩展与浏览器保护';

  @override
  String get oChronosAplicaAExtensaoEm =>
      'Chronos 在 Chromium 浏览器中使用扩展，在 Firefox 中使用选择性代理 + CA，完全离线。';

  @override
  String navegadoresInstaladosDetectadosP0(Object p0) {
    return '检测到的已安装浏览器（$p0）：';
  }

  @override
  String servidorLocalAtivoNaPortaP0(Object p0) {
    return '本地服务器运行在端口 $p0';
  }

  @override
  String get chromeAbertoEmChromeExtensionsCole =>
      'Chrome 已打开 chrome://extensions！加载已解压的扩展时粘贴复制的路径。';

  @override
  String get firefoxAbertoEmAboutPoliciesPara =>
      'Firefox 已打开 about:policies，可查看本地策略。';

  @override
  String get terminalAbertoParaAutorizacaoDoChronos =>
      '已为 Chronos Guard 授权打开终端！';

  @override
  String get comandoCopiadoExecuteNoTerminalPara => '命令已复制！在终端中运行以安装 Guard。';

  @override
  String get configurando => '正在配置...';

  @override
  String get comandoGuardCopiadoParaOTerminal => 'Guard 命令已复制！';

  @override
  String sessoesBloqueiosP0(Object p0) {
    return '会话与拦截（$p0）';
  }

  @override
  String listaBrancaWhitelistP0(Object p0) {
    return '白名单（$p0）';
  }

  @override
  String conflitosEncontradosP0(Object p0) {
    return '发现冲突（$p0）';
  }

  @override
  String eMaisP0(Object p0) {
    return '…… 还有 $p0 个。';
  }

  @override
  String get extensaoWeb => '网页扩展';

  @override
  String get novaSessaoDeBloqueio => '新建拦截会话';

  @override
  String sessoesConfiguradasP0(Object p0) {
    return '已配置的会话（$p0）';
  }

  @override
  String get nenhumaSessaoCriadaAindaCliqueEm => '尚未创建会话。\n点击“新建拦截会话”将应用或网站分组。';

  @override
  String get catracaTravadaAumentosProibidos => '棘轮已锁定（禁止增加）';

  @override
  String get recolher => '收起';

  @override
  String get expandir => '展开';

  @override
  String get editarTempoDeBloqueio => '编辑拦截时间';

  @override
  String get adicionarAppsSitesAoGrupo => '向分组添加应用 / 网站';

  @override
  String get focarNoDashboard => '在仪表盘中聚焦';

  @override
  String get desbloquear => '解除拦截';

  @override
  String get bloquearCompletamente => '完全拦截';

  @override
  String get removerSessao => '删除会话';

  @override
  String get recolherItensDaSessao => '收起会话项目';

  @override
  String get expandirParaVerTodosOsApps => '展开查看所有应用和网站';

  @override
  String get adicionarAplicativosSitesPermitidoNoAnti => '添加应用 / 网站（防绕过下允许）';

  @override
  String get sessaoSelecionada => '已选会话';

  @override
  String aplicativosBloqueadosP0(Object p0) {
    return '被拦截的应用（$p0）：';
  }

  @override
  String removerP0DoGrupoAntiCheat(Object p0) {
    return '从分组中移除 $p0（受防绕过限制）';
  }

  @override
  String sitesEPalavrasChaveBloqueadosP0(Object p0) {
    return '被拦截的网站和关键词（$p0）：';
  }

  @override
  String get nenhumAplicativoOuSiteListadoNesta => '此会话中没有列出应用或网站。';

  @override
  String gruposDeListaBrancaP0(Object p0) {
    return '白名单分组（$p0）';
  }

  @override
  String get nenhumGrupoDeListaBrancaCriado =>
      '尚未创建白名单分组。\n白名单中的应用和网站不会被拦截或关闭。';

  @override
  String get protecaoTotal => '完全保护';

  @override
  String p0TiposYoutube(Object p0) {
    return '$p0 种 YouTube 类型';
  }

  @override
  String get itensProtegidosContraContagemDeTempo => '这些项目不计入屏幕时间，也不会被自动关闭';

  @override
  String youtubePermitidoP0(Object p0) {
    return '允许的 YouTube：$p0';
  }

  @override
  String get recolherItens => '收起项目';

  @override
  String get expandirItens => '展开项目';

  @override
  String get editarGrupo => '编辑分组';

  @override
  String get removerGrupo => '删除分组';

  @override
  String aplicativosProtegidosP0(Object p0) {
    return '受保护的应用（$p0）：';
  }

  @override
  String removerP0DaListaBranca(Object p0) {
    return '从白名单中移除 $p0';
  }

  @override
  String sitesEPalavrasProtegidosP0(Object p0) {
    return '受保护的网站和关键词（$p0）：';
  }

  @override
  String tiposDoYoutubePermitidosP0(Object p0) {
    return '允许的 YouTube 类型（$p0）：';
  }

  @override
  String get registroDeBurlas => '绕过记录';

  @override
  String get cofreDoChronosAtivoComO =>
      'Chronos 保险库已开启：防绕过开启时，修改数据库、停止服务、删除自启动或更改时钟都会在几秒内被撤销并记录在这里。';

  @override
  String get cofreDoChronosNaoInstaladoInstale =>
      'Chronos 保险库未安装：请安装/更新浏览器保护（Chronos Guard）以开启防绕过层。';

  @override
  String relogioDoSistemaCorrigidoEmP0(Object p0) {
    return '系统时钟已校正 $p0 分钟（Chronos 使用可信时间）。';
  }

  @override
  String penalidadeAtivaTodasAsSessoesBloqueadas(Object p0) {
    return '惩罚生效：所有会话将被拦截至 $p0。';
  }

  @override
  String get aoDetectarUmaBurla => '检测到绕过时';

  @override
  String get restaurarERegistrar => '恢复并记录';

  @override
  String get restaurarRegistrarEBloquearTudoAte => '恢复、记录并拦截所有内容直到午夜';

  @override
  String get comOAntiBurlaAtivoNao => '防绕过开启时无法切换回较轻的选项。';

  @override
  String get nenhumaTentativaDeBurlaRegistrada => '没有记录到绕过尝试。';

  @override
  String get bancoEditado => '数据库被修改';

  @override
  String get bancoApagado => '数据库被删除';

  @override
  String get servicoParado => '服务被停止';

  @override
  String get servicoApagado => '服务被删除';

  @override
  String get autostartApagado => '自启动被删除';

  @override
  String get relogioAlterado => '时钟被更改';

  @override
  String get desbloqueioRecusado => '解锁被拒绝';

  @override
  String get historicoDeBurlas => '绕过历史';

  @override
  String p0EventoS(Object p0) {
    return '$p0 个事件';
  }

  @override
  String get nenhumaBurlaNestePeriodo => '此期间没有绕过。';

  @override
  String get naoEPossivelDesinstalar => '无法卸载';

  @override
  String get oAntiBurlaEstaAtivoEnquanto => '防绕过已开启。开启期间无法关闭或卸载 Chronos。';

  @override
  String get desinstalarOChronos => '卸载 Chronos？';

  @override
  String get istoRemoveOChronosDoComputador =>
      '这将从电脑中移除 Chronos：后台应用、浏览器扩展、系统保护（可能需要你的密码）、自启动和 Chronos 服务。';

  @override
  String get apagarTambemMeusDados => '同时删除我的数据';

  @override
  String get regrasHistoricoDeUsoEConfiguracoes => '规则、使用历史和设置。不勾选则保留，以便重新安装。';

  @override
  String get desinstalar => '卸载';

  @override
  String get atualizacaoAutomaticaSoFuncionaNaVersao =>
      '自动更新仅适用于已安装的版本（开发版本不适用）。';

  @override
  String oChronosJaEstaNaVersao(Object p0) {
    return 'Chronos 已是最新版本（$p0）。';
  }

  @override
  String get baixando => '正在下载…';

  @override
  String get verificandoAssinatura => '正在验证签名…';

  @override
  String get instalando => '正在安装…';

  @override
  String get atualizandoAProtecaoDoSistemaPode => '正在更新系统保护（可能需要你的密码）…';

  @override
  String get reiniciandoOChronos => '正在重启 Chronos…';

  @override
  String get aProtecaoDoSistemaGuardNao => '系统保护（Guard）这次没有更新。你可以稍后在设置中更新。';

  @override
  String novaVersaoDoChronosP0(Object p0) {
    return 'Chronos 新版本：$p0';
  }

  @override
  String voceEstaNaVersaoP0Deseja(Object p0) {
    return '你当前的版本是 $p0。现在更新吗？';
  }

  @override
  String falhaNaAtualizacaoP0(Object p0) {
    return '更新失败：$p0';
  }

  @override
  String get depois => '稍后';

  @override
  String get tentarNovamente => '重试';

  @override
  String get atualizarAgora => '立即更新';

  @override
  String get deUmNomeAoTipoNovo => '请为新类型命名。';

  @override
  String get tiposDoYoutubePorCanalOu => '按频道或关键词划分的 YouTube 类型';

  @override
  String get exCanalFlowPodcastContaComo =>
      '例如：频道“Flow Podcast”计为播客；关键词“minecraft”会创建类型“Minecraft”。多个频道或关键词用逗号分隔。';

  @override
  String get tipo => '类型';

  @override
  String get novoTipo => '新类型…';

  @override
  String get nomeDoTipo => '类型名称';

  @override
  String get canais => '频道';

  @override
  String get palavrasNoTituloTags => '标题/标签中的关键词';

  @override
  String get adicionarRegra => '添加规则';

  @override
  String hojeP0(Object p0) {
    return ' 今天：$p0。';
  }

  @override
  String get escolhaDosPaisSuffix => '（家长的选择）';

  @override
  String get guiaAnonimaSeraBloqueadaSuffix => ' —— 无痕模式将再次被禁用';

  @override
  String get safesearchNosNavegadoresSuffix => ' + 浏览器安全搜索';

  @override
  String get todosOsNavegadoresJaPermitemAnonimo => '所有浏览器都已允许扩展在无痕模式下运行。';

  @override
  String get iaDeImagensNaTelaInteira => '全屏图像 AI（本地）';

  @override
  String get iaTelaInteiraDescricao =>
      '每约 2 秒检查任意应用（不仅是浏览器）的当前窗口，出现 18+ 内容时遮住屏幕。全部在本机进行，不保存任何内容。会占用少量 CPU。';

  @override
  String get iaTelaInteiraNaoSuportada => '仅在安装了 grim 的 Hyprland 上可用。';

  @override
  String get conteudoAdultoDetectadoNaTela => '检测到 18+ 内容';

  @override
  String coberturaTelaTexto(String window) {
    return 'Chronos 在窗口“$window”中发现成人内容。请先关闭或更换内容再返回。';
  }

  @override
  String get entendiVoltar => '知道了，返回';

  @override
  String appBloqueadoTitulo(String app) {
    return '$app 已被屏蔽';
  }

  @override
  String get motivoQuota => '今天的时间额度已用完。';

  @override
  String get motivoJanela => '当前时段已被屏蔽。';

  @override
  String get motivoForcado => '此应用已被完全屏蔽。';

  @override
  String get motivoPenalidade => '因绕过尝试而处于惩罚中。';

  @override
  String get motivoLazer => '强制休息进行中。';

  @override
  String get appFechadoPeloChronos => 'Chronos 已关闭该应用。';

  @override
  String get extVersaoAtualizada => '（已是最新）';

  @override
  String extVersaoPendente(String version) {
    return '→ $version 待更新';
  }

  @override
  String extFirefoxPrecisaAssinar(String version) {
    return '→ $version 等待 Mozilla 签名（运行 scripts/run-release.sh）';
  }

  @override
  String extVersaoDisponivel(String version) {
    return '可用版本：$version';
  }

  @override
  String get contaDaCriancaProtegida => '受保护的孩子账户';

  @override
  String contaProtegidaDescricao(String user) {
    return '账户“$user”不是管理员：无法移除 Chronos。Wi-Fi、U 盘、打印机、蓝牙、关机以及从官方仓库安装软件仍然可用。';
  }

  @override
  String contaEhAdministradoraAviso(String user) {
    return '账户“$user”是管理员（sudo），可以用 root 权限移除 Chronos。保护此账户：它将不再是管理员，Chronos 只允许日常操作。需要另一个管理员账户（监护人）的密码。';
  }

  @override
  String contaSemAdministrador(String user) {
    return '账户“$user”已不是管理员：无法移除 Chronos。';
  }

  @override
  String get protegerEstaConta => '保护此账户';

  @override
  String get devolverAdministrador => '恢复管理员权限';

  @override
  String get feitoValeNoProximoLogin => '完成。下次登录后生效。';

  @override
  String get guardNaoInstaladoAtiveAProtecao => '未安装 Chronos Guard：请先开启浏览器保护。';

  @override
  String get autorizacaoCancelada => '授权已取消。';

  @override
  String get textosDesafioExplicacao =>
      '你的文字会替换默认文字：挑战只会从中抽取。没有自定义文字时使用默认文字。每段至少 120 个字符。防绕过开启时无法修改。';

  @override
  String get recusarTextosFaceis => '拒绝过于简单的文字';

  @override
  String get recusarTextosFaceisDescricao =>
      '拒绝包含重复词语、字母种类过少、键盘序列或多次复制同一段内容的文字。';

  @override
  String get semTextosUsaOsPadrao => '没有自定义文字：挑战使用默认文字。';

  @override
  String get adicionarTexto => '添加文字';

  @override
  String get editarTexto => '编辑文字';

  @override
  String p0Caracteres(int count) {
    return '$count 个字符';
  }

  @override
  String get textoAprovado => '文字合格。';

  @override
  String get ok => '确定';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get chronosAntiCheatStrictFocusEngine => 'Chronos - 防繞過與嚴格專注引擎';

  @override
  String get chronosFocusEngine => 'Chronos 專注引擎';

  @override
  String get reiniciarBancoDeDados => '重置資料庫？';

  @override
  String get desejaResetarCompletamenteOSqliteIntervalos =>
      '要完全重置 SQLite 嗎？使用記錄將被清除，棘輪將解鎖，初始設定將重新開始。';

  @override
  String get cancelar => '取消';

  @override
  String get reiniciarTudo => '全部重置';

  @override
  String get parentalPai => '家長控制（家長）';

  @override
  String get parentalFilho => '家長控制（孩子）';

  @override
  String get autoControle => '自我控制';

  @override
  String focoP0(Object p0) {
    return '專注：$p0';
  }

  @override
  String get autoDeteccaoAtiva => '自動檢測已開啟';

  @override
  String get deteccaoAutomatica => '自動檢測';

  @override
  String get antiCheatOff => '防繞過：關閉';

  @override
  String nukeP0DP1(Object p0, Object p1) {
    return 'Nuke：$p0天 $p1';
  }

  @override
  String nukeP0(Object p0) {
    return 'Nuke：$p0';
  }

  @override
  String get antiCheatAtivo => '防繞過已開啟';

  @override
  String get refazerCadastroTrocarModo => '重新設定 / 切換模式';

  @override
  String get instalarExtensoesNosNavegadores => '在瀏覽器中安裝擴充套件';

  @override
  String get sairDoAntiCheatDebug => '🛠️ 退出防繞過（除錯）';

  @override
  String get reiniciarBancoCompleto => '重置整個資料庫';

  @override
  String get zerarConsumoDiario => '清零今日用量';

  @override
  String destravarCatracaP0(Object p0) {
    return '解鎖棘輪（$p0）';
  }

  @override
  String get restaurarTokens2 => '恢復令牌（+2）';

  @override
  String get tempoDeTela => '螢幕時間';

  @override
  String get monitorEmTempoReal => '即時監控';

  @override
  String get estatisticas => '統計';

  @override
  String get metricasDeConsumo => '使用指標';

  @override
  String get regrasWhitelist => '規則與白名單';

  @override
  String get limitesEGrupos => '限制與分組';

  @override
  String get configuracoes => '設定';

  @override
  String get aparenciaEAlertas => '外觀與提醒';

  @override
  String get quarentena => '隔離區';

  @override
  String get modoNukeBloqueios => 'Nuke 模式與攔截';

  @override
  String get sqliteTestes => 'SQLite / 測試';

  @override
  String get depuracaoDoBanco => '資料庫除錯';

  @override
  String get chronos => 'Chronos';

  @override
  String get focusEngine => '專注引擎';

  @override
  String get alternarParaModoClaro => '切換到淺色模式';

  @override
  String get alternarParaModoEscuro => '切換到深色模式';

  @override
  String get modoClaro => '淺色模式';

  @override
  String get modoEscuro => '深色模式';

  @override
  String get estatisticasDeConsumoHistorico => '使用統計與歷史';

  @override
  String get regrasDeBloqueioWhitelist => '攔截規則與白名單';

  @override
  String get configuracoesGeraisNotificacoes => '常規設定與通知';

  @override
  String get quarentenaModoNuke => '隔離區與 Nuke 模式';

  @override
  String get bancoDeDadosTestesSqlite => '資料庫與 SQLite 測試';

  @override
  String get debugSairDoAntiCheat => '🛠️ [除錯] 退出防繞過';

  @override
  String get instalarExtensoesEmNavegadores => '在瀏覽器中安裝擴充套件';

  @override
  String get acoesGlobais => '全域性操作';

  @override
  String get telaDeCadastro => '設定嚮導';

  @override
  String get debugSairDoAntiCheatImediatamente => '🛠️ [除錯] 立即退出防繞過';

  @override
  String get instalarExtensoesEmTodosNavegadores => '在所有瀏覽器中安裝擴充套件';

  @override
  String get acoesConfiguracao => '操作與設定';

  @override
  String get tempo => '時間';

  @override
  String get metricas => '指標';

  @override
  String get regras => '規則';

  @override
  String get ajustes => '設定';

  @override
  String get nuke => 'Nuke';

  @override
  String get sqlite => 'SQLite';

  @override
  String get sincronizandoComOMotorDeMonitoramento => '正在與監控引擎同步...';

  @override
  String get tentarConectarAgora => '立即嘗試連線';

  @override
  String get etapaInicialTesteAQualquerMomento => '初始步驟：隨時測試設定和自定義攔截。';

  @override
  String get voltarAoCadastro => '返回設定嚮導';

  @override
  String p0SessoesAtivasSimultaneamenteOTempo(Object p0) {
    return '⚡ $p0 個會話同時進行！螢幕時間正在並行計時。';
  }

  @override
  String get sessao => '會話';

  @override
  String get emExecucao => '執行中';

  @override
  String get tempoAtivo => '活動時間';

  @override
  String consumidoHojeP0(Object p0) {
    return '今日已用：$p0';
  }

  @override
  String limiteP0P1(Object p0, Object p1) {
    return '限制：$p0（$p1%）';
  }

  @override
  String get catracaAtiva => '棘輪已開啟';

  @override
  String tokensP02(Object p0) {
    return '令牌：$p0/2';
  }

  @override
  String limiteDeTempoDeTelaP0(Object p0, Object p1) {
    return '螢幕時間限制：$p0（$p1%）';
  }

  @override
  String get controlesDeTempoDeTelaCatraca => '螢幕時間與棘輪控制';

  @override
  String get reduzirTempoDeTelaTeste15s => '減少螢幕時間（15 秒測試）';

  @override
  String get tentarAumentarTempoDeTela2h => '嘗試增加螢幕時間（+2 小時）';

  @override
  String get trancarCatraca24h => '鎖定棘輪（24 小時）';

  @override
  String get catracaTrancadaPor24hAumentosProibidos => '棘輪已鎖定 24 小時！禁止增加時間。';

  @override
  String get usarTokenDeEmergencia1h => '使用緊急令牌（+1 小時）';

  @override
  String get bemVindoAoChronos => '歡迎使用 Chronos';

  @override
  String get seuMotorDeFocoEstritoE => '你的 Linux 嚴格專注與效率引擎。\n你打算如何使用這個應用？';

  @override
  String get controlePessoalAutoControle => '個人控制（自我控制）';

  @override
  String get paraGerenciarSeuProprioTempoE => '用於管理自己的時間和學習。';

  @override
  String get modoCatracaRatchetReducoesSaoImediatas => '棘輪模式：減少立即生效，增加會被阻止。';

  @override
  String get t2TokensMensaisDeEmergencia1h =>
      '每月 2 個緊急令牌（+1 小時，代價是 24 小時娛樂鎖定）。';

  @override
  String get bloqueioAtivoComSobreposicaoDeJanela => '主動攔截，帶視窗遮罩和自動暫停媒體。';

  @override
  String get configurarBloqueiosPessoais => '設定個人攔截';

  @override
  String get controleParentalSupervisao => '家長控制（監督）';

  @override
  String get paraPaisEResponsaveisGerenciaremDispositivos => '供家長和監護人管理孩子的裝置。';

  @override
  String get dispositivoDoDependenteProtegidoContraAlteracoes =>
      '孩子的裝置受到保護，防止修改和繞過。';

  @override
  String get pareamentoSeguroViaQrCodeOu => '通過二維碼或主密碼安全配對。';

  @override
  String get gestaoDeAprovacaoDeBinariosE => '程式審批與應用隔離管理。';

  @override
  String get configurarControleParental => '設定家長控制';

  @override
  String get personalizacaoDeBloqueioTempoDeTela => '自定義攔截與螢幕時間';

  @override
  String get ajusteOTempoDeTelaDiario => '設定初始每日螢幕時間和嚴格程度';

  @override
  String get distracoesABloquear => '要攔截的干擾';

  @override
  String get adicionarAppOuSite => '新增應用或網站';

  @override
  String get nenhumaSessaoPreConfiguradaCliqueEm =>
      '沒有預設會話。\n點選上方的“新增應用或網站”來建立你的會話。';

  @override
  String get tempoDeTelaDiario => '每日螢幕時間：';

  @override
  String get bloqueioTotal => '完全攔截';

  @override
  String get t15Min => '15 分鐘';

  @override
  String get t30Min => '30 分鐘';

  @override
  String get t1Hora => '1 小時';

  @override
  String get t2Horas => '2 小時';

  @override
  String get diretrizesDeEnforcementDoChronos => 'Chronos 執行規則';

  @override
  String get ativarTravaDaCatraca24hIniciais => '開啟棘輪鎖定（前 24 小時）';

  @override
  String get impedeAumentosDeTempoDeTela => '第一天禁止增加螢幕時間，只能減少。';

  @override
  String get sequestroVisualDeFocoAlwaysOn => '強制專注畫面（始終置頂全屏）';

  @override
  String get maximizaETravaAJanelaDo => '螢幕時間用完時，將 Chronos 視窗最大化並鎖定在最上層。';

  @override
  String get pausaAtivaDeMidiaPlayerctlMpris2 => '主動暫停媒體（playerctl / MPRIS2）';

  @override
  String get interrompeAutomaticamenteVideosEMusicasEm => '自動停止後臺播放的影片和音樂。';

  @override
  String get salvarBloqueiosEIniciarChronos => '儲存攔截並啟動 Chronos';

  @override
  String get controleParental => '家長控制';

  @override
  String get qualEOPapelDesteComputador => '這臺電腦在家庭中的角色是什麼？';

  @override
  String get dispositivoDoResponsavelPaiMae => '監護人的裝置（家長）';

  @override
  String get esteComputadorTeraAutoridadeParaControlar => '這臺電腦將有權控制規則和螢幕時間。';

  @override
  String get recebeSolicitacoesDeEmergenciaEAprovacoes => '接收緊急請求和隔離審批。';

  @override
  String get conectaAoComputadorDoFilhoUsando => '通過二維碼或密碼連線到孩子的電腦。';

  @override
  String get configurarComoDispositivoPai => '設定為家長裝置';

  @override
  String get dispositivoDoDependenteFilho => '孩子的裝置';

  @override
  String get esteComputadorSeraMonitoradoEProtegido => '這臺電腦將被監控並防止分心。';

  @override
  String get asAlteracoesDeTempoDeTela => '修改螢幕時間需要監護人授權或密碼。';

  @override
  String get exibeQrCodeECodigoPin => '顯示二維碼和 PIN 碼，供監護人連線。';

  @override
  String get configurarComoDispositivoFilho => '設定為孩子裝置';

  @override
  String chronosPairCodeP0(Object p0) {
    return 'chronos://pair?code=$p0';
  }

  @override
  String get pareamentoDispositivoFilho => '配對：孩子裝置';

  @override
  String get pareamentoDispositivoDoResponsavel => '配對：監護人裝置';

  @override
  String get conecteEsteComputadorAoAplicativoDo =>
      '使用二維碼或 PIN/密碼將這臺電腦連線到監護人的應用。';

  @override
  String get escaneieOQrCodeOuInsira => '掃描二維碼或輸入孩子裝置上顯示的 PIN 碼。';

  @override
  String get viaQrCode => '通過二維碼';

  @override
  String get viaSenhaPin => '通過密碼 / PIN';

  @override
  String get concluirEIniciarProtecao => '完成並開始保護';

  @override
  String get concluirEAbrirPainelDoResponsavel => '完成並開啟監護人面板';

  @override
  String get protecaoObrigatoriaEmTodosOsNavegadores => '所有瀏覽器強制保護';

  @override
  String get configuraTodosOsNavegadoresDoDispositivo =>
      '設定本裝置的所有瀏覽器，顯示剩餘時間並應用 HTML/CSS 過濾（Shorts、首頁推薦、灰度）。只有通過防繞過驗證後才能移除。';

  @override
  String get instalandoConfigurando => '正在安裝和配置...';

  @override
  String get instalarAtualizarEmTodosOsNavegadores => '在所有瀏覽器中安裝 / 更新';

  @override
  String get terminalAbertoDigiteSuaSenhaSudo =>
      '終端已開啟！輸入一次 sudo 密碼以完成 Guard 安裝。';

  @override
  String executeManualmenteP0(Object p0) {
    return '手動執行：$p0';
  }

  @override
  String get terminalAbertoDigiteSuaSenhaSudo2 => '終端已開啟！只需輸入一次 sudo 密碼。';

  @override
  String executeNoTerminalP0(Object p0) {
    return '在終端中執行：$p0';
  }

  @override
  String get aponteODispositivoDoResponsavelPara => '用監護人的裝置掃描這個二維碼。';

  @override
  String get seEstiverUsandoAVersaoMobile => '如果使用手機版或攝像頭，請對準孩子螢幕上的二維碼。';

  @override
  String get ouColeAChaveUriDo => '或在此貼上二維碼的金鑰/URI';

  @override
  String get chronosPairId => 'chronos://pair?id=...';

  @override
  String get codigoPinDePareamentoDesteDispositivo => '本裝置的配對 PIN 碼：';

  @override
  String get definirSenhaMestraDeDesbloqueioLocal => '設定本地解鎖主密碼（可選）';

  @override
  String get digiteUmaSenhaParaAlterarTempo => '輸入密碼以便現場修改螢幕時間';

  @override
  String get digiteOCodigoPinOuSenha => '輸入孩子螢幕上顯示的 PIN 碼或密碼：';

  @override
  String get chrXxxxOuSenha => 'CHR-XXXX 或密碼';

  @override
  String get validarEParear => '驗證並配對';

  @override
  String get orgKdeStatusnotifierwatcher => 'org.kde.StatusNotifierWatcher';

  @override
  String get abrirChronos => '開啟 Chronos';

  @override
  String get desinstalarChronos => '解除安裝 Chronos…';

  @override
  String get antiBurlaAtivoOChronosNao => '防繞過已開啟：開啟期間無法解除安裝 Chronos。';

  @override
  String get chronosFocus => 'Chronos 專注';

  @override
  String get chronosMonitoramentoAtivo => 'Chronos - 正在監控';

  @override
  String oAplicativoP0EstaSendoMonitorado(Object p0, Object p1) {
    return '應用“$p0”正在會話“$p1”中被監控。';
  }

  @override
  String get chronosTempoDeTelaRestante => 'Chronos - 剩餘螢幕時間';

  @override
  String p0RestamApenasP1MinutoP2(Object p0, Object p1) {
    return '$p0：螢幕時間只剩 $p1 分鐘！';
  }

  @override
  String get chronosTempoDeTelaEsgotado => 'Chronos - 螢幕時間已用完';

  @override
  String p0OTempoDeTelaDiario(Object p0) {
    return '$p0：今天的螢幕時間已全部用完！';
  }

  @override
  String chronosAlertaPeriodicoP0Min(Object p0) {
    return 'Chronos - 定時提醒（$p0 分鐘）';
  }

  @override
  String p0P1MinUtilizadosHojeRestam(Object p0, Object p1, Object p2) {
    return '$p0：今天已用 $p1 分鐘 • 螢幕時間還剩 $p2 分鐘。';
  }

  @override
  String get todas => '全部';

  @override
  String get jogos => '遊戲';

  @override
  String get navegadores => '瀏覽器';

  @override
  String get comunicacao => '通訊';

  @override
  String get internet => '網際網路';

  @override
  String get midia => '媒體';

  @override
  String get desenvolvimento => '開發';

  @override
  String get escritorio => '辦公';

  @override
  String get graficos => '圖形';

  @override
  String get educacao => '教育';

  @override
  String get sistema => '系統';

  @override
  String get utilitarios => '工具';

  @override
  String get outros => '其他';

  @override
  String adicionarTagP0(Object p0) {
    return '新增標籤：$p0';
  }

  @override
  String get nomeDaTagExRedesSociais => '標籤名稱（例如：社交、工作、遊戲）';

  @override
  String get adicionarTag => '新增標籤';

  @override
  String p0JaFoiAdicionadoAoGrupo(Object p0) {
    return '“$p0”已在分組中。';
  }

  @override
  String get sessaoDeFoco => '專注會話';

  @override
  String get listaBranca => '白名單';

  @override
  String get selecionePeloMenosUmAplicativoOu => '請為分組至少選擇一個應用或網站。';

  @override
  String p0HP1Min(Object p0, Object p1) {
    return '$p0 小時 $p1 分鐘';
  }

  @override
  String get editarGrupoDeListaBranca => '編輯白名單分組';

  @override
  String get novoGrupoDeListaBranca => '新建白名單分組';

  @override
  String get adicionarAplicativosSitesAoGrupo => '向分組新增應用 / 網站';

  @override
  String get editarSessaoDeFoco => '編輯專注會話';

  @override
  String get criarSessaoDeFoco => '建立專注會話';

  @override
  String get appsESitesNaListaBranca => '白名單中的應用和網站永遠不會被攔截或關閉，即使它們在其他分組中。';

  @override
  String get digiteONomeDoGrupoDe => '輸入白名單分組名稱（例如：學習工具）...';

  @override
  String get digiteONomeDaSessaoDe => '輸入專注會話名稱（例如：干擾與娛樂）...';

  @override
  String get nomeDoGrupoDeListaBranca => '白名單分組名稱';

  @override
  String get nomeDaSessaoDeFoco => '專注會話名稱';

  @override
  String aplicativosP0(Object p0) {
    return '應用（$p0）';
  }

  @override
  String sitesEPalavrasP0(Object p0) {
    return '網站與關鍵詞（$p0）';
  }

  @override
  String youtubeP0(Object p0) {
    return 'YouTube（$p0）';
  }

  @override
  String p0AppsP1Sites(Object p0, Object p1) {
    return '$p0 個應用 • $p1 個網站';
  }

  @override
  String get salvarListaBranca => '儲存白名單';

  @override
  String get salvarAppsNoGrupo => '儲存分組中的應用';

  @override
  String get avancarTempoDeTelaRegras => '下一步：螢幕時間與規則';

  @override
  String get buscarPorNomeExecutavelOuTag => '按名稱、執行檔或標籤搜尋（例如：遊戲、媒體）...';

  @override
  String get selecionarTudo => '全選';

  @override
  String get limpar => '清除';

  @override
  String get carregandoAplicativosInstalados => '正在載入已安裝的應用...';

  @override
  String get nenhumAplicativoEncontradoParaOFiltro => '沒有符合該篩選/標籤的應用。';

  @override
  String get limparFiltroDeTag => '清除標籤篩選';

  @override
  String get jaNoGrupo => '已在分組中';

  @override
  String get tag => '+ 標籤';

  @override
  String get videosDessesTiposNaoDescontamO =>
      '這些型別的影片不計入 YouTube 螢幕時間。可用上限限制每天的豁免時長（留空 = 不限）。';

  @override
  String get tetoMinDia => '上限（分鐘/天）';

  @override
  String get semTeto => '不限';

  @override
  String get digiteDominioOuPalavraChaveEx =>
      '輸入域名或關鍵詞（例如：youtube.com、reels、shorts）...';

  @override
  String get adicionar => '新增';

  @override
  String sitesEPalavrasChaveAdicionadosP0(Object p0) {
    return '已新增的網站與關鍵詞（$p0）：';
  }

  @override
  String get limparNovos => '清除新增';

  @override
  String get limparTodos => '全部清除';

  @override
  String get nenhumSiteOuPalavraChaveAdicionado => '此會話中尚未新增網站或關鍵詞。';

  @override
  String p0JaNoGrupo(Object p0) {
    return '$p0（已在分組中）';
  }

  @override
  String editarTempoDeBloqueioP0(Object p0) {
    return '編輯攔截時間：$p0';
  }

  @override
  String tempoDeTelaP0(Object p0) {
    return '螢幕時間：$p0';
  }

  @override
  String sessaoP0(Object p0) {
    return '會話：$p0';
  }

  @override
  String get grupoDeFocoUnificado => '統一專注分組';

  @override
  String p0AplicativosEP1SitesInclusos(Object p0, Object p1) {
    return '包含 $p0 個應用和 $p1 個網站。';
  }

  @override
  String get todosOsAplicativosESitesDesta => '此會話中的所有應用和網站共享同一個每日螢幕時間配額。';

  @override
  String get limiteDeTempoDeTelaRelogio => '螢幕時間限制（數字時鐘）：';

  @override
  String get bloqueioTotal2 => '完全攔截';

  @override
  String get nenhumAcessoPermitidoDuranteODia => '全天不允許訪問';

  @override
  String p0DeUsoPermitido(Object p0) {
    return '允許使用 $p0';
  }

  @override
  String get bloquearTotalmente0MinDeTempo => '完全攔截（0 分鐘螢幕時間）';

  @override
  String get impedeQualquerInicializacaoDoGrupoImediatamente =>
      '立即阻止分組中的任何應用啟動';

  @override
  String get tempoDeTelaDiferenciadoNoFinal => '週末使用不同的螢幕時間';

  @override
  String get permiteConfigurarMaisTempoParaSabado => '可以為週六和週日設定更多時間';

  @override
  String tempoFimDeSemanaP0(Object p0) {
    return '週末時間：$p0';
  }

  @override
  String get tempoDeTelaDiferenciadoEmFeriados => '節假日使用不同的螢幕時間';

  @override
  String valeNosFeriadosNacionaisENas(Object p0) {
    return '適用於國家法定節假日和你在設定中新增的日期，優先於週末設定。$p0';
  }

  @override
  String tempoEmFeriadosP0(Object p0) {
    return '節假日時間：$p0';
  }

  @override
  String get diasDaSemanaAtivos => '生效的星期：';

  @override
  String get todos => '全部';

  @override
  String get diasUteis => '工作日';

  @override
  String get finsDeSemana => '週末';

  @override
  String get seg => '週一';

  @override
  String get ter => '週二';

  @override
  String get qua => '週三';

  @override
  String get qui => '週四';

  @override
  String get sex => '週五';

  @override
  String get sab => '週六';

  @override
  String get dom => '週日';

  @override
  String get bloqueioPorJanelaDeHorario => '按時間段攔截';

  @override
  String get bloqueiaOGrupoDentroDeUm => '在每天固定的時間段攔截該分組';

  @override
  String inicioP0(Object p0) {
    return '開始：$p0';
  }

  @override
  String fimP0(Object p0) {
    return '結束：$p0';
  }

  @override
  String get modo => '模式：';

  @override
  String get bloquearDentro => '時間段內攔截';

  @override
  String get permitirSomenteDentro => '僅在時間段內允許';

  @override
  String get notificacaoPorTempoRestante => '剩餘時間通知';

  @override
  String get avisaAos155E1 => '在螢幕時間結束前 15、5 和 1 分鐘提醒';

  @override
  String get notificacaoPeriodica => '定時通知';

  @override
  String get emiteLembretesRegularesEnquantoASessao => '在會話使用期間定時傳送提醒';

  @override
  String get intervaloDaNotificacaoPeriodica => '定時通知間隔：';

  @override
  String aCadaP0Min(Object p0) {
    return '每 $p0 分鐘';
  }

  @override
  String get salvarGrupoDeFoco => '儲存專注分組';

  @override
  String get permitaAExtensaoNoAnonimo => '允許擴充套件在無痕模式下執行';

  @override
  String get abrirNosNavegadores => '在瀏覽器中開啟';

  @override
  String get entendi => '知道了';

  @override
  String get guiaAnonimaBloqueadaNosNavegadores => '已在瀏覽器中停用無痕模式。';

  @override
  String get guiaAnonimaLiberada => '已允許無痕模式。';

  @override
  String get nenhumNavegadorChromiumEncontrado => '未找到 Chromium 瀏覽器。';

  @override
  String abertoEmP0(Object p0) {
    return '已在 $p0 中開啟：在 Chronos 擴充套件中開啟“在無痕模式下啟用”。';
  }

  @override
  String get ativarProtecaoPorDns => '開啟 DNS 保護？';

  @override
  String get oDnsFamiliaPassaAValer =>
      '家庭 DNS 將對整臺電腦生效。部分應用和網路可能失去功能：\n\n• 遮蔽外部 DNS 的學校、公司或酒店網路可能無法上網；\n• 內網網站和服務（內網、按名稱訪問的印表機）可能無法開啟；\n• VPN、網路遊戲、流媒體應用或容器（Docker）可能無法解析地址；\n• 路由器的 DNS 和瀏覽器的“安全 DNS”將不再使用。\n\n之後關閉需要管理員密碼，防繞過開啟時無法關閉。';

  @override
  String get entendiAtivar => '知道了，開啟';

  @override
  String get filtroDeConteudoAdulto => '成人內容過濾';

  @override
  String get modoParentalOFiltroFicaSempre => '家長模式：過濾始終開啟。';

  @override
  String get ativarFiltro => '開啟過濾';

  @override
  String get bloqueiaSitesAdultosComATela => '使用 Chronos 攔截頁面攔截成人網站。';

  @override
  String get bloquearGuiaAnonimaEConvidado => '停用無痕和訪客模式';

  @override
  String impedeJanelasAnonimasPrivadasEO(Object p0) {
    return '在所有瀏覽器中停用無痕/隱私視窗和訪客模式$p0。重新允許需要管理員密碼，防繞過開啟時無法允許。';
  }

  @override
  String get permitirAExtensaoNoAnonimoAbrir => '允許擴充套件在無痕模式下執行（在瀏覽器中開啟）';

  @override
  String extensaoPermitidaNoAnonimoEmP0(Object p0) {
    return '擴充套件已在 $p0 個開啟的瀏覽器中允許無痕模式。';
  }

  @override
  String extensaoSemPermissaoNoAnonimoEm(Object p0, Object p1, Object p2) {
    return '擴充套件在 $p1 個瀏覽器中有 $p0 個未允許無痕模式$p2。';
  }

  @override
  String get filtroLigadoMasNadaEstaBloqueando =>
      '過濾已開啟，但沒有任何攔截：請開啟成人網站列表、安全搜尋或 DNS。';

  @override
  String get listaDeSitesAdultos => '成人網站列表';

  @override
  String p0SitesConhecidosAtualizaTodaSemana(Object p0) {
    return '$p0 個已知網站（每週更新）。';
  }

  @override
  String get baixandoALista => '正在下載列表…';

  @override
  String get iaDeImagensLocal => '影像 AI（本地）';

  @override
  String get desfocaImagensAteUmModeloDe =>
      '在本地 AI 模型檢查前模糊圖片；成人圖片保持模糊，含多張的頁面會被攔截。不會上傳任何內容。';

  @override
  String get safesearchForcado => '強制安全搜尋';

  @override
  String get googleBingEDuckduckgoEmModo =>
      'Google、Bing 和 DuckDuckGo 使用安全模式；YouTube 使用受限模式。';

  @override
  String get protecaoPorDnsComputadorInteiro => 'DNS 保護（整臺電腦）';

  @override
  String get usaUmDnsFamiliaEmTodo =>
      '在整個系統使用家庭 DNS：適用於所有瀏覽器和應用。由 Chronos Guard 應用（關閉需要管理員密碼）。';

  @override
  String get servicoDeDnsFamilia => '家庭 DNS 服務';

  @override
  String get dnsDoChronosDesligadoMasO =>
      'Chronos DNS 已關閉，但網路的 DNS（路由器/運營商）已在過濾成人內容——僅在此網路有效。';

  @override
  String get dnsDoSistemaNormalSemDns => '系統 DNS：正常（未使用家庭 DNS）。';

  @override
  String dnsDoSistemaP0AtivoP1(Object p0, Object p1) {
    return '系統 DNS：$p0 已開啟$p1。';
  }

  @override
  String get registrarTentativas => '記錄嘗試';

  @override
  String anotaDataESiteDeCada(Object p0) {
    return '記錄每次攔截的日期和網站$p0。';
  }

  @override
  String get ultimasTentativas => '最近的嘗試';

  @override
  String get verHistoricoCompleto => '檢視完整歷史';

  @override
  String get excecoesSitesNuncaBloqueadosPorEste => '例外（此過濾永不攔截的網站）';

  @override
  String get exSiteDaEscolaCom => '例如：school-site.com';

  @override
  String get hoje => '今天';

  @override
  String get t7Dias => '7 天';

  @override
  String get t30Dias => '30 天';

  @override
  String get tudo => '全部';

  @override
  String get listaDeSites => '網站列表';

  @override
  String get reddit => 'Reddit';

  @override
  String get iaDeImagens => '影像 AI';

  @override
  String get historicoDeTentativas => '嘗試歷史';

  @override
  String p0TentativaS(Object p0) {
    return '$p0 次嘗試';
  }

  @override
  String get nenhumaTentativaNestePeriodo => '此期間沒有嘗試。';

  @override
  String get fechar => '關閉';

  @override
  String p0HP1M(Object p0, Object p1) {
    return '$p0小時 $p1分';
  }

  @override
  String get semDados => '無資料';

  @override
  String get estatisticasDeTempoDeTela => '螢幕時間統計';

  @override
  String get consumoConsolidadoTendenciasSemanaisERanking =>
      '總體用量、每週趨勢以及應用和網站排名。';

  @override
  String get atualizar => '重新整理';

  @override
  String get consumoHoje => '今日用量';

  @override
  String get tempoEmAppsSitesMonitorados => '受監控應用/網站的時間';

  @override
  String get mediaSemanal => '每週平均';

  @override
  String get baseadoNosUltimos7Dias => '基於最近 7 天';

  @override
  String get diaDePico => '高峰日';

  @override
  String get tendenciaVsSemanaAnterior => '與上週相比的趨勢';

  @override
  String get estavel => '穩定';

  @override
  String get maisTempoDeTela => '螢幕時間增加';

  @override
  String get menosTempoDeTela => '螢幕時間減少';

  @override
  String get appsSitesMonitorados => '受監控的應用/網站';

  @override
  String get mediaDiaria => '每日平均';

  @override
  String get ultimos7Dias => '最近 7 天';

  @override
  String get tendencia => '趨勢';

  @override
  String get maisTela => '更多螢幕';

  @override
  String get menosTela => '更少螢幕';

  @override
  String get tempoIsentoNoYoutubeListaBranca => 'YouTube 豁免時間（白名單）';

  @override
  String p0P1Em7Dias(Object p0, Object p1) {
    return '$p0：7 天內 $p1';
  }

  @override
  String get consumoDiarioNosUltimos7Dias => '最近 7 天的每日用量';

  @override
  String totalP0(Object p0) {
    return '總計：$p0';
  }

  @override
  String get nenhumDadoDiarioRegistrado => '沒有記錄到每日資料。';

  @override
  String get top5AppsSitesMaisConsumidos => '使用最多的 5 個應用和網站（最近 7 天）';

  @override
  String get nenhumaAtividadeRegistradaNaSemanaAinda => '本週尚無活動記錄。';

  @override
  String p0DoTotal(Object p0) {
    return '佔總數 $p0%';
  }

  @override
  String get colarNaoEPermitidoDigiteO => '❌ 不允許貼上：請輸入文字。';

  @override
  String get erroDetectadoNoModoStayfocusdQualquer =>
      '❌ 檢測到錯誤！在 StayFocusd 模式下，任何一個錯誤字元都會清空全部文字。請仔細輸入！';

  @override
  String get selecioneUmaDuracaoValidaMaiorQue => '請為 Nuke 模式選擇大於 0 分鐘的有效時長。';

  @override
  String get ativarOAntiBurla => '開啟防繞過？';

  @override
  String enquantoOAntiBurlaEstiverAtivo(Object p0) {
    return '防繞過開啟期間：\n\n• 無法解除安裝 Chronos；\n• 它會在後臺持續執行，關閉後會自動重新開啟；\n• 規則、過濾和擴充套件不能放寬。\n\n$p0';
  }

  @override
  String get noModoNukeIssoSoAcaba => '在 Nuke 模式下，只有時間結束才會解除。';

  @override
  String get paraDesativarSeraPrecisoCompletarO => '要關閉它，你需要完成挑戰。';

  @override
  String modoNukeAtivadoPorP0Configuracoes(Object p0) {
    return '☢️ Nuke 模式已開啟 $p0！設定和擴充套件已鎖定。';
  }

  @override
  String get modoAntiCheatAtivadoComDesafio => '🛡️ 已開啟帶嚴格挑戰的防繞過模式！';

  @override
  String erroAoAtivarP0(Object p0) {
    return '開啟時出錯：$p0';
  }

  @override
  String get antiCheatDesativadoComSucessoModificacoes => '🔓 防繞過已關閉！可以修改了。';

  @override
  String erroP0(Object p0) {
    return '錯誤：$p0';
  }

  @override
  String get protecaoAntiCheatAtiva => '防繞過保護已開啟';

  @override
  String get configurarModoAntiCheat => '設定防繞過模式';

  @override
  String get oAntiCheatImpedeVoceDe =>
      '防繞過會阻止你在意志薄弱時繞過 Chronos、解除攔截或提高限制，並防止擴充套件被移除。';

  @override
  String get escolhaOMetodoDeTravamento => '選擇鎖定方式：';

  @override
  String get desafioDeDigitacaoEstritoEstiloStayfocusd =>
      '嚴格打字挑戰（StayFocusd 風格）';

  @override
  String get qualquerTentativaDeDesativarOuAumentar =>
      '任何關閉或提高螢幕時間限制的嘗試，都需要毫無錯誤地重新輸入一段很長的承諾文字。打錯一個字元？文字會被清空！';

  @override
  String get modoNukeBloqueioTotalPorTempo => 'Nuke 模式（定時完全鎖定）';

  @override
  String get trava100OChronosPorUm =>
      '在一段時間內 100% 鎖定 Chronos。在此期間，直到時間結束前都無法解鎖或修改任何內容。';

  @override
  String get duracaoDoTravamentoNukeScrollPara => 'Nuke 鎖定時長（滾動調整）：';

  @override
  String ativarModoNukeP0(Object p0) {
    return '開啟 NUKE 模式（$p0）';
  }

  @override
  String get ativarAntiCheatRestrito => '開啟嚴格防繞過';

  @override
  String get modoNukeEmAndamento => 'NUKE 模式進行中';

  @override
  String get nenhumaAlteracaoDeTempoDeTela => '在時間結束前，不允許修改螢幕時間、規則或移除擴充套件。';

  @override
  String get desafioDeDigitacaoStayfocusd => 'StayFocusd 打字挑戰';

  @override
  String get paraDestravarOAplicativoELiberar => '要解鎖應用並允許修改，請準確無誤地輸入下面的文字：';

  @override
  String progressoP0P1Caracteres(Object p0, Object p1) {
    return '進度：$p0 / $p1 個字元';
  }

  @override
  String get comeceADigitarOTextoAqui => '在這裡開始輸入文字...';

  @override
  String get destravarAntiCheat => '解鎖防繞過';

  @override
  String get debugDesativarAntiCheatImediatamente => '🛠️ 除錯：立即關閉防繞過';

  @override
  String get debugAntiCheatENukeDesativados => '🛠️ [除錯] 防繞過和 Nuke 已關閉！';

  @override
  String get instalarAtualizarExtensaoEmTodosNavegadores =>
      '在所有瀏覽器中安裝 / 更新擴充套件';

  @override
  String get pacoteEmbutido => '內建安裝包';

  @override
  String get atualizarGuard => '更新 Guard';

  @override
  String get politicaGuard => 'Guard 策略';

  @override
  String get ativoNosNavegadores => '已在瀏覽器中啟用';

  @override
  String get nenhumNavegadorSuportadoDetectado => '未檢測到支援的瀏覽器。';

  @override
  String get protegidoPeloProxySeletivoLocal127 =>
      '由本地選擇性代理（127.0.0.1:4546）+ CA 證書保護——Firefox 正式版不會在 about:addons 中列出未簽名的 .xpi，但攔截和 HTML/CSS 過濾照常工作。';

  @override
  String get instalacaoManualFallbackAvancado => '手動安裝 / 高階備用方案';

  @override
  String get baixarChromeZip => '下載 Chrome 版（.zip）';

  @override
  String extensaoSalvaEmP0(Object p0) {
    return '擴充套件已儲存到：$p0';
  }

  @override
  String get erroAoSalvarZipEmDownloads => '儲存 zip 到“下載”資料夾時出錯。';

  @override
  String get baixarFirefoxXpi => '下載 Firefox 版（.xpi）';

  @override
  String get erroAoSalvarXpiEmDownloads => '儲存 xpi 到“下載”資料夾時出錯。';

  @override
  String get ativarNoChromeManual => '在 Chrome 中啟用（手動）';

  @override
  String get ativarNoFirefoxManual => '在 Firefox 中啟用（手動）';

  @override
  String get comandoTerminalGuard => '終端命令（Guard）';

  @override
  String get reiniciarNavegadoresParaAtivar => '重啟瀏覽器以啟用？';

  @override
  String osSeguintesNavegadoresJaEstaoAbertos(Object p0) {
    return '以下瀏覽器已經開啟，需要關閉並重新開啟才能載入 Chronos 擴充套件：\n\n$p0\n\n現在關閉並重新開啟嗎？';
  }

  @override
  String get agoraNao => '暫不';

  @override
  String get fecharEReabrirAgora => '立即關閉並重新開啟';

  @override
  String navegadoresReiniciadosP0(Object p0) {
    return '瀏覽器已重啟（$p0）！';
  }

  @override
  String get acessoBloqueadoPeloChronos => '已被 CHRONOS 攔截';

  @override
  String oTempoDeTelaDiarioPara(Object p0) {
    return '$p0 今天的螢幕時間已全部用完。';
  }

  @override
  String get reproducaoMprisPausadaAutomaticamente => '已自動暫停 MPRIS 播放。';

  @override
  String get janelaSobrepostaAtivaEnquantoOApp => '干擾應用處於前臺時，遮罩視窗保持開啟。';

  @override
  String usarTokenDeEmergencia1hP0(Object p0) {
    return '使用緊急令牌（+1 小時）[$p0/2]';
  }

  @override
  String get avisoConsumirUmTokenDeEmergencia => '警告：使用緊急令牌會鎖定所有娛樂活動 24 小時！';

  @override
  String get nenhumTokenDeEmergenciaRestantePara => '本月沒有剩餘的緊急令牌。回到學習和專注吧！';

  @override
  String get idiomaPrincipalSteamApiDefinidoPara => '主語言已設定為英語。';

  @override
  String get idiomaPrincipalSteamApiDefinidoPara2 => '主語言已設定為葡萄牙語（巴西）。';

  @override
  String get modoNukeAtivoRemocaoDaExtensao => 'Nuke 模式已開啟：時間結束前禁止移除擴充套件。';

  @override
  String get remocaoCanceladaConcluaAVerificacaoAnti =>
      '已取消移除：完成防繞過驗證後才能移除擴充套件。';

  @override
  String get antiCheatAindaAtivoRemocaoBloqueada => '防繞過仍在開啟。禁止移除。';

  @override
  String get removerExtensaoPoliticas => '移除擴充套件和策略？';

  @override
  String get verificacaoAntiCheatConcluidaIssoRemovera =>
      '防繞過驗證已通過。這將從所有瀏覽器中移除 Chronos 擴充套件、External Extensions 連結和 Chronos Guard（Chrome/Chromium/Firefox 策略），直到你重新安裝。\n\n確認移除？';

  @override
  String get removerDeTodosOsNavegadores => '從所有瀏覽器中移除';

  @override
  String get filtrosAntiDistracaoSalvosComSucesso => '防干擾過濾已儲存！';

  @override
  String p0JaEstaNaLista(Object p0) {
    return '“$p0”已在列表中。';
  }

  @override
  String get antiCheatAtivoDesativeOAnti => '防繞過已開啟：關閉防繞過後才能移除標籤或遊戲名。';

  @override
  String get antiCheatAtivoDesativeOAnti2 => '防繞過已開啟：關閉防繞過後才能移除啟動器商店保護。';

  @override
  String get configuracoesGerais => '常規設定';

  @override
  String get ajustesDeNotificacoesExtensoesLocaisModo => '通知、本地擴充套件、模式與安全';

  @override
  String get versaoEAtualizacoes => '版本與更新';

  @override
  String chronosP0AsAtualizacoesSaoVerificadas(Object p0) {
    return 'Chronos $p0 —— 開啟應用時檢查更新。';
  }

  @override
  String chronosP0BuildDeDesenvolvimentoSem(Object p0) {
    return 'Chronos $p0（開發版本——不自動更新）。';
  }

  @override
  String get procurarAtualizacoes => '檢查更新';

  @override
  String get desinstalarChronos2 => '解除安裝 Chronos';

  @override
  String get notificacoesDeDesktop => '桌面通知';

  @override
  String get oModoNaoPerturbeDoSistema => '系統的“勿擾”模式已開啟：關閉前不會顯示 Chronos 的通知。';

  @override
  String get verificar => '檢查';

  @override
  String get notificarInicioDeAppMonitorado => '受監控應用啟動時通知';

  @override
  String get exibeUmaNotificacaoNoDesktopAvisando => '顯示桌面通知，提示正在執行的應用正在計時。';

  @override
  String get notificacaoDeAppMonitoradoAtivada => '受監控應用通知已開啟';

  @override
  String get notificacaoDeAppMonitoradoDesativada => '受監控應用通知已關閉';

  @override
  String get alertasDeTempoDeTelaRestante => '剩餘螢幕時間提醒';

  @override
  String get avisosAutomaticosQuandoRestarem15m5m =>
      '每日螢幕時間剩餘 15、5 和 1 分鐘時自動提醒。';

  @override
  String get avisosPeriodicosDeUsoAtivo => '定時使用提醒';

  @override
  String get lembretesEmIntervalosRegularesExA => '按固定間隔（例如每 15 分鐘）提醒已使用的時間。';

  @override
  String get extensoesDosNavegadores => '瀏覽器擴充套件';

  @override
  String get protegeTodosOsNavegadoresDoDispositivo =>
      '離線保護裝置上的所有瀏覽器：Chromium 系瀏覽器（Chrome、Chromium、Brave、Edge、Vivaldi、Opera）使用本地擴充套件，Firefox 使用選擇性專注代理 + 本地 CA。';

  @override
  String get navegadoresDetectadosNoSistema => '系統中檢測到的瀏覽器：';

  @override
  String get extensaoRemovidaAposVerificacaoAntiCheat =>
      '通過防繞過驗證後已移除擴充套件。點選下方在所有瀏覽器中重新安裝。';

  @override
  String get configurandoNavegadoresGuard => '正在配置瀏覽器和 Guard...';

  @override
  String get protecaoPermanenteDoSistemaAntiBurla => '永久系統保護（瀏覽器防繞過）';

  @override
  String get protecaoDoSistemaAtivaTrancada => '系統保護已開啟並鎖定';

  @override
  String get politicasForcadasAtivasEmChromeChromium =>
      '已在 Chrome/Chromium/Brave/Edge/Vivaldi/Opera（已簽名 CRX3）和 Firefox 正式版（選擇性專注代理 + 本地 CA + PAC，about:policies 中無警告）中啟用強制策略。已禁止移除擴充套件和無痕瀏覽。';

  @override
  String get reAplicarPoliticasDoSistema => '重新應用系統策略';

  @override
  String get politicasDoSistemaVerificadasERe => '系統策略已檢查並重新應用！';

  @override
  String get falhaAoReAplicarPoliticas => '重新應用策略失敗。';

  @override
  String get removendo => '正在移除...';

  @override
  String get removerExtensaoVerificarAntiCheat => '移除擴充套件（防繞過驗證）';

  @override
  String get oChronosGuardInstaladoPossuiPoliticas =>
      '已安裝的 Chronos Guard 使用舊策略（例如 Firefox 正式版中未簽名的 ExtensionSettings）。點選上方的“在所有瀏覽器中安裝 / 更新”一鍵修復。';

  @override
  String get oChronosGuardGravaPoliticasPermanentes =>
      'Chronos Guard 會（經你的 Polkit 授權）在 /etc/ 中寫入永久策略，防止手動解除安裝和無痕瀏覽。使用上方的主按鈕一鍵開啟。';

  @override
  String get atualizarGuardViaPolkit1Clique => '通過 Polkit 更新 Guard（一鍵）';

  @override
  String get ativarGuardViaPolkit1Clique => '通過 Polkit 開啟 Guard（一鍵）';

  @override
  String get modoDoAplicativoCadastro => '應用模式與設定';

  @override
  String modoAtivoP0(Object p0) {
    return '當前模式：$p0';
  }

  @override
  String get configuradoComPinEProtecaoParental => '已設定 PIN 和家長限制保護。';

  @override
  String get focadoEmAutonomiaComprometimentoPessoalE => '注重自主、個人承諾和效率。';

  @override
  String get trocarModoRefazerCadastro => '切換模式 / 重新設定';

  @override
  String get antiCheatProtecaoContraBurlar => '防繞過與防繞過保護';

  @override
  String modoNukeAtivoP0SRestantes(Object p0) {
    return 'Nuke 模式已開啟（剩餘 $p0 秒）';
  }

  @override
  String get antiCheatAtivoDesafioStayfocusd => '防繞過已開啟（StayFocusd 挑戰）';

  @override
  String get antiCheatDesativado => '防繞過已關閉';

  @override
  String get bloqueiaModificacoesDeRegrasAumentoDe =>
      '阻止修改規則、在意志薄弱時提高限制以及移除擴充套件。';

  @override
  String get gerenciarAntiCheat => '管理防繞過';

  @override
  String get ativarAntiCheat => '開啟防繞過';

  @override
  String get textosDoDesafio => '挑戰文字';

  @override
  String get antiBurlaAtivoOsTextosDo => '防繞過已開啟：現在無法修改挑戰文字。';

  @override
  String get gerenciamentoDeDadosLocaisOffline => '本地資料管理（離線）';

  @override
  String get todasAsInformacoesRegrasETempos =>
      'Chronos 的所有資訊、規則和螢幕時間都 100% 儲存在你的電腦上。';

  @override
  String get zerarConsumoDiarioDeHoje => '清零今日用量';

  @override
  String get reiniciarBancoDeDadosCompleto => '重置整個資料庫';

  @override
  String get reiniciarBancoDeDados2 => '重置資料庫';

  @override
  String get atencaoIssoIraApagarTodasAs =>
      '注意：這將刪除你建立的所有攔截規則，並將資料庫恢復到初始狀態。要繼續嗎？';

  @override
  String get zerarTudo => '全部清零';

  @override
  String get instalarProtecaoPermanente => '安裝永久保護';

  @override
  String get estaEtapaConfiguraOsArquivosDe =>
      '此步驟會在 /etc/ 中寫入官方策略檔案，並啟用 systemd 服務，永久鎖定擴充套件以防繞過。';

  @override
  String get comoDesejaProsseguir => '你想如何繼續？';

  @override
  String get opcao1CliqueEmAbrirTerminal =>
      '方式 1：點選“開啟終端”，在開啟的視窗中輸入一次 sudo 密碼。\n方式 2：或複製下面的命令，在你常用的終端中執行：';

  @override
  String get copiarComando => '複製命令';

  @override
  String get comandoCopiadoParaAAreaDe => '命令已複製到剪貼簿！';

  @override
  String get verificarStatus => '檢查狀態';

  @override
  String get protecaoDoSistemaAtivaEConfirmada => '系統保護已開啟並確認！';

  @override
  String get protecaoAindaPendenteDeInstalacao => '保護尚未安裝。';

  @override
  String get abrirTerminal => '開啟終端';

  @override
  String get terminalAbertoDigiteSuaSenhaNa => '終端已開啟！在視窗中輸入密碼以完成。';

  @override
  String get naoFoiPossivelAbrirOTerminal => '無法自動開啟終端。命令已複製！';

  @override
  String get ativarNoGoogleChrome => '在 Google Chrome 中啟用';

  @override
  String get oGoogleChromeOficialBloqueiaInjecoes =>
      '出於安全考慮，官方 Google Chrome 會阻止通過命令列隱藏注入。要啟用，只需載入一次本地資料夾（大約 10 秒）。';

  @override
  String get passoAPassoRapido => '快速步驟：';

  @override
  String get cliqueNoBotaoAbrirChromeAbaixo =>
      '點選下方的“開啟 Chrome”。Chrome 會開啟 chrome://extensions，並複製資料夾路徑。';

  @override
  String get noChromeAtiveAChaveModo => '在 Chrome 中，開啟右上角的“開發者模式”。';

  @override
  String get cliqueNoBotaoCarregarSemCompactacao => '點選“載入已解壓的擴充套件程式”（左上角）。';

  @override
  String get pressioneCtrlVOuSelecioneA => '按 Ctrl+V 或選擇擴充套件資料夾並確認。';

  @override
  String get copiarCaminho => '複製路徑';

  @override
  String get caminhoCopiadoParaAAreaDe => '路徑已複製到剪貼簿！';

  @override
  String get baixarZip => '下載 .zip';

  @override
  String arquivoSalvoEmP0(Object p0) {
    return '檔案已儲存到：$p0';
  }

  @override
  String get erroAoGerarZipParaDownloads => '在“下載”資料夾中生成 zip 時出錯。';

  @override
  String get abrirChrome => '開啟 Chrome';

  @override
  String get chromeAbertoCaminhoCopiadoParaA => 'Chrome 已開啟！路徑已複製到剪貼簿。';

  @override
  String get ativarExtensaoNoFirefox => '在 Firefox 中啟用擴充套件';

  @override
  String get noFirefoxReleasePadraoAMozilla =>
      '在標準 Firefox 正式版中，Mozilla 要求外部 .xpi 必須簽名——因此 Chronos 的永久保護通過 Chronos Guard 的本地選擇性代理 + CA 證書實現。對於 Firefox ESR/Dev/LibreWolf/Zen 或在 about:debugging 中臨時測試，請使用 .xpi：';

  @override
  String get cliqueNoBotaoAbrirFirefoxAbaixo => '點選下方的“開啟 Firefox”直接進入除錯頁面。';

  @override
  String get cliqueNoBotaoCarregarExtensaoTemporaria => '點選“臨時載入附加元件...”。';

  @override
  String get selecioneOArquivoManifestJsonNa =>
      '選擇下方資料夾中的“manifest.json”，或 ~/Downloads 中的 .xpi 檔案。';

  @override
  String get caminhoDoManifestJsonCopiado => 'manifest.json 路徑已複製！';

  @override
  String get erroAoGerarXpiParaDownloads => '在“下載”資料夾中生成 xpi 時出錯。';

  @override
  String get abrirFirefox => '開啟 Firefox';

  @override
  String get firefoxAbertoCaminhoCopiadoParaA => 'Firefox 已開啟！路徑已複製到剪貼簿。';

  @override
  String get aparenciaModoDeTema => '外觀與主題';

  @override
  String get personalizeOTemaVisualDoChronos =>
      '自定義 Chronos 的外觀。淺色模式針對明亮環境最佳化，對比度高；深色模式可減輕眼睛疲勞。';

  @override
  String get idiomaPrincipalTagsAutocompleteSteamApi => '語言';

  @override
  String get asTagsSaoEnviadasEmIngles =>
      '應用、擴充套件和攔截頁面使用的語言。Steam 標籤在可用時以此語言顯示。';

  @override
  String get portuguesBr => 'Português (BR)';

  @override
  String get englishUs => 'English (US)';

  @override
  String get configBravesoftwareBraveBrowser =>
      '.config/BraveSoftware/Brave-Browser';

  @override
  String get aoAtivarOAntiBurlaO =>
      '如果你新增了自己的文字，Chronos 只會從中隨機抽取（不再使用預設文字）。沒有自訂文字時使用預設文字。每段文字之間用空行分隔（每段至少 120 個字元）。防繞過開啟時無法修改。';

  @override
  String get seuTextoAqui => '在這裡輸入你的文字…';

  @override
  String get salvar => '儲存';

  @override
  String get atualizacoesDaExtensao => '擴充套件更新';

  @override
  String get atualizarExtensoesAutomaticamente => '自動更新擴充套件';

  @override
  String get quandoOChronosForAtualizadoOs => 'Chronos 更新後，瀏覽器會自動安裝新擴充套件。';

  @override
  String get firefoxAtualizaAoReabrirONavegador =>
      'Firefox：同樣通過 Chronos 更新（已簽名的版本）。';

  @override
  String get atualizarExtensoesAgora => '立即更新擴充套件';

  @override
  String get pedidoEnviadoOChromeInstalaA => '請求已傳送。瀏覽器將在幾秒內安裝新版本。';

  @override
  String get mostrarApenasVideosDestesTipos => '只顯示這些型別的影片';

  @override
  String get escolhaAoMenosUmTipoAbaixo => '請在下方至少選擇一種型別以開啟。';

  @override
  String get aHomeEOsRelacionadosSo => '首頁和相關影片只顯示所選型別。搜尋仍顯示全部內容（並計時）。';

  @override
  String get escolhaAoMenosUmTipoAntes => '開啟前請至少選擇一種型別。';

  @override
  String get importarDaListaBranca => '從白名單匯入';

  @override
  String get nenhumTipoDoYoutubeNaLista => '白名單中沒有 YouTube 型別。';

  @override
  String get tiposPorCanalPalavra => '按頻道/關鍵詞分類';

  @override
  String get filtrosDeConteudoAntiDistracaoPor => '內容過濾與按平臺防干擾（StayFocusd 風格）';

  @override
  String get configureFiltrosDeCssEHtml =>
      '為每個應用或社交網路設定 CSS 和 HTML 過濾。無需完全攔截網站即可去除多巴胺誘因。';

  @override
  String get detoxGlobalTodosOsSites => '全域性排毒（所有網站）';

  @override
  String get modoPretoEBrancoGrayscaleDetox => '黑白模式（灰度排毒）';

  @override
  String get aplicaEscalaDeCinzaEmTodas => '對所有頁面應用灰度，減少強迫性瀏覽。';

  @override
  String get bloquearNotificacoesEBadges => '遮蔽通知和角標';

  @override
  String get removeSinosVermelhosEAlertasNumericos => '移除所有網站上的紅色鈴鐺和數字提醒，避免打擾。';

  @override
  String get youtubeFocus => 'YouTube 專注';

  @override
  String get bloquearYoutubeShorts => '遮蔽 YouTube Shorts';

  @override
  String get ocultaCarrosseisDeShortsNaHome => '隱藏首頁、搜尋和側邊欄中的 Shorts 輪播。';

  @override
  String get ocultarFeedDaHome => '隱藏首頁推薦';

  @override
  String get ocultaTodasAsRecomendacoesAlgoritmicasDa =>
      '隱藏 YouTube 首頁的所有演算法推薦。';

  @override
  String get ocultarVideosRelacionadosBarraLateral => '隱藏相關影片（側邊欄）';

  @override
  String get removeSugestoesDeVideosAoLado => '移除播放器旁的影片推薦，避免分心。';

  @override
  String get ocultarComentariosDoYoutube => '隱藏 YouTube 評論';

  @override
  String get ocultaTodaASecaoDeComentarios => '隱藏所有影片的整個評論區。';

  @override
  String get instagramFocus => 'Instagram 專注';

  @override
  String get bloquearInstagramReels => '遮蔽 Instagram Reels';

  @override
  String get removeAAbaEOCarrossel => '移除 Instagram 網頁版的 Reels 標籤和短影片輪播。';

  @override
  String get ocultarFeedPrincipalExplore => '隱藏主資訊流和探索';

  @override
  String get ocultaOFeedInfinitoDePostagens => '隱藏首頁無限滾動的帖子和推薦。';

  @override
  String get ocultarComentariosDoInstagram => '隱藏 Instagram 評論';

  @override
  String get ocultaComentariosSobPostagensEVideos => '隱藏帖子和影片下的評論。';

  @override
  String get tiktokFocus => 'TikTok 專注';

  @override
  String get bloquearFeedDeVideosRecomendados => '遮蔽推薦影片資訊流';

  @override
  String get bloqueiaOFluxoInfinitoDeVideos => '遮蔽 TikTok 無限滾動的“為你推薦”短影片。';

  @override
  String get redditFocus => 'Reddit 專注';

  @override
  String get bloquearFeedPrincipalPopular => '遮蔽主頁 / 熱門資訊流';

  @override
  String get ocultaATimelineDePostsInfinitos => '隱藏 r/all 和 Reddit 首頁無限滾動的帖子。';

  @override
  String get ocultarSecoesDeComentarios => '隱藏評論區';

  @override
  String get ocultaAsArvoresDeDiscussaoE => '隱藏 Reddit 帖子中的討論和評論。';

  @override
  String get bloquearConteudo18Nsfw => '遮蔽成人內容（NSFW）';

  @override
  String get escondePostsNsfwNosFeedsE =>
      '隱藏資訊流和搜尋中的 NSFW 帖子，並攔截成人版塊和帖子。防繞過開啟時無法關閉。';

  @override
  String get xTwitterFocus => 'X / Twitter 專注';

  @override
  String get bloquearTimelineFeedPrincipal => '遮蔽時間線 / 主資訊流';

  @override
  String get ocultaATimelineParaVoceE => '隱藏 X（Twitter）上的“為你推薦”和“正在關注”時間線。';

  @override
  String get ocultarAssuntosDoMomentoTrending => '隱藏熱門話題';

  @override
  String get removeABarraLateralDeTendencias => '移除趨勢和探索新聞側邊欄。';

  @override
  String get bloquearConteudo18Sensivel => '遮蔽成人內容（敏感）';

  @override
  String get escondePostsComMidiaSensivelE =>
      '隱藏含敏感媒體的帖子，並攔截被標記為敏感的賬號。防繞過開啟時無法關閉。';

  @override
  String get linkedinFocus => 'LinkedIn 專注';

  @override
  String get bloquearFeedDeNoticiasDoLinkedin => '遮蔽 LinkedIn 動態';

  @override
  String get ocultaATimelineDePostagensPara => '隱藏帖子時間線，只專注於訊息和個人資料。';

  @override
  String get hudFlutuanteNosNavegadoresPilula => '瀏覽器懸浮 HUD（膠囊）';

  @override
  String get opacidadeDaPilulaAlfa => '膠囊不透明度';

  @override
  String get controlaATransparenciaDaPilulaRecolhida => '控制瀏覽器中收起的膠囊和閉眼圖示的透明度。';

  @override
  String get tamanhoDaPilula => '膠囊大小';

  @override
  String get ajustaAEscalaDaPilulaE => '調整膠囊大小和閉眼圖示的直徑（始終等於膠囊高度）。';

  @override
  String get aoEsconderPilulaMostrarIconeDe => '隱藏膠囊時顯示可拖動的眼睛圖示';

  @override
  String get quandoAtivoMinimizarTransformaAPilula =>
      '開啟時，最小化會把膠囊變成同樣高度、可拖動的圓形閉眼按鈕；關閉時會完全隱藏（按 Alt+Shift+C 重新顯示）。';

  @override
  String get launchersJogosSteamApiHeroicEpic =>
      '啟動器與遊戲（Steam API、Heroic、Epic、GOG、Lutris）';

  @override
  String get antiCheatAtivoRemocaoBloqueada => '防繞過已開啟（禁止移除）';

  @override
  String get ativarFiltroEmLaunchersLojasDe => '在啟動器和遊戲商店中開啟過濾';

  @override
  String get bloqueiaJogosEmExecucaoPaginasDe =>
      '通過 Steam API 按名稱或標籤攔截正在執行的遊戲、商店頁面、指南、討論和藝術作品。隨時可以新增；移除需要關閉防繞過。';

  @override
  String get antiCheatAtivoDesativeOAnti3 => '防繞過已開啟：關閉防繞過後才能關閉啟動器過濾。';

  @override
  String get tagsProibidasSteamApi => '禁止的標籤（Steam API）';

  @override
  String get buscarTagNaSteamApiEx => '在 Steam API 中搜索標籤（例如：動作、類魂、恐怖、FPS）...';

  @override
  String get nomesDeJogosProibidos => '禁止的遊戲名稱';

  @override
  String get buscarJogoNaSteamApiEx =>
      '在 Steam API 中搜索遊戲（例如：Counter-Strike 2、Elden Ring）...';

  @override
  String get protegerLojaComunidadeDentroDaSteam =>
      '保護 Steam/Heroic 內的商店/社群（代理 + NSS）';

  @override
  String ocultarJogosDetectadosP0(Object p0) {
    return '隱藏檢測到的遊戲（$p0）';
  }

  @override
  String get consultarJogosDosLaunchersSteamApi => '查詢啟動器中的遊戲（Steam API）';

  @override
  String get nenhumJogoInstaladoDetectadoNosLaunchers =>
      '本地啟動器（Steam、Heroic、Lutris、Bottles）中未檢測到已安裝的遊戲。';

  @override
  String get bloquearJogo => '+ 攔截遊戲';

  @override
  String tagCanonicaSteamApiP0(Object p0) {
    return 'Steam API 標準標籤：$p0';
  }

  @override
  String get sugestoesSteamApi => 'Steam API 建議：';

  @override
  String enviaP0ParaASteamApi(Object p0) {
    return '將“$p0”傳送到 Steam API';
  }

  @override
  String get desativarTodos => '全部關閉';

  @override
  String get ativarTodos => '全部開啟';

  @override
  String get nomeDoFeriado => '節日名稱';

  @override
  String get exFeriasAniversario => '例如：假期、生日';

  @override
  String get feriados => '節假日';

  @override
  String hojeEFeriadoP0AsCotas(Object p0) {
    return '今天是節假日：$p0——各會話的節假日配額生效。';
  }

  @override
  String get aCotaDeFeriadoEDefinida => '節假日配額在每個會話中設定（與週末配額相同）。';

  @override
  String get proximosFeriados => '即將到來的節假日';

  @override
  String get feriadosPersonalizados => '自定義節假日';

  @override
  String get comOAntiBurlaLigadoNao => '防繞過開啟時無法新增節假日（只能刪除）。';

  @override
  String get adicionarUmaDataComACota => '新增一個使用會話節假日配額的日期';

  @override
  String get adicionarData => '新增日期';

  @override
  String get antiBurlaLigadoAdicionarFeriadosEsta => '防繞過已開啟：禁止新增節假日。';

  @override
  String get nenhum => '無。';

  @override
  String get remover => '刪除';

  @override
  String varreduraConcluidaP0ProcessosAuditadosQuarentena(Object p0) {
    return '掃描完成。已審查/隔離 $p0 個程序。';
  }

  @override
  String get inspecaoDeBinariosQuarentena => '程式檢查與隔離';

  @override
  String get protecaoContraBinariosNaoEmpacotadosPelo =>
      '防護未由 pacman 打包或在 /usr/bin 之外執行的程式';

  @override
  String get escanearProcessos => '掃描程序';

  @override
  String get nenhumProcessoNaoConfiavelEmQuarentena => '隔離區中沒有不受信任的程序！';

  @override
  String get cliqueEmEscanearProcessosParaAuditar => '點選“掃描程序”審查官方系統之外正在執行的程式。';

  @override
  String get aprovarBinario => '批准程式';

  @override
  String get rejeitarBloquear => '拒絕並攔截';

  @override
  String get modoAntiCheatAtivo => '防繞過模式已開啟！';

  @override
  String oChronosEstaNoModoNuke(Object p0, Object p1) {
    return 'Chronos 處於 Nuke 模式（剩餘 $p0 分鐘）。計時結束前不允許$p1。';
  }

  @override
  String naoEPermitidoP0EnquantoO(Object p0) {
    return '防繞過開啟時不允許$p0。要修改規則，請先完成防繞過的嚴格打字挑戰。';
  }

  @override
  String get entendido => '明白了';

  @override
  String get resolverDesafio => '完成挑戰';

  @override
  String get desbloquearEntidades => '解除攔截';

  @override
  String get removerRegrasDeBloqueio => '刪除攔截規則';

  @override
  String get editarTempoDeBloqueioEAgendamento => '編輯攔截時間和計劃';

  @override
  String finsDeSemanaP0(Object p0) {
    return '週末：$p0';
  }

  @override
  String tempoDeTelaP0P1P2(Object p0, Object p1, Object p2) {
    return '螢幕時間：$p0$p1 • $p2';
  }

  @override
  String get renomear => '重新命名';

  @override
  String get nome => '名稱';

  @override
  String get adicionarAppsOuSitesAoGrupo => '向分組新增應用或網站（只允許重新命名）';

  @override
  String get editarGruposDeListaBranca => '編輯白名單分組';

  @override
  String get adicionarGruposDeListaBranca => '新增白名單分組';

  @override
  String get removerGrupoDeListaBranca => '刪除白名單分組';

  @override
  String get desejaRealmenteRemoverEsteGrupoDe =>
      '確定要刪除這個白名單分組嗎？其中的應用和網站將不再受保護，會重新被計時或攔截。';

  @override
  String get removerAplicativoDoGrupoDeBloqueio => '從攔截分組中移除應用';

  @override
  String get removerDoGrupoDeBloqueio => '從攔截分組中移除';

  @override
  String desejaRealmenteRemoverP0DesteGrupo(Object p0) {
    return '確定要從這個攔截分組中移除“$p0”嗎？';
  }

  @override
  String erroAoRemoverAplicativoP0(Object p0) {
    return '移除應用時出錯：$p0';
  }

  @override
  String get removerDaListaBranca => '從白名單中移除';

  @override
  String desejaRemoverP0DestaListaBranca(Object p0) {
    return '要從這個白名單中移除“$p0”嗎？該應用將不再受攔截保護。';
  }

  @override
  String erroAoRemoverDaListaBranca(Object p0) {
    return '從白名單中移除時出錯：$p0';
  }

  @override
  String get t0mBloqueioTotal => '0 分鐘（完全攔截）';

  @override
  String p0AplicativoS(Object p0) {
    return '$p0 個應用';
  }

  @override
  String p0SiteSPalavraS(Object p0) {
    return '$p0 個網站/關鍵詞';
  }

  @override
  String get permitirSomente => '僅允許';

  @override
  String get bloquear => '攔截';

  @override
  String janelaP0P1P2(Object p0, Object p1, Object p2) {
    return '時間段：$p0 $p1-$p2';
  }

  @override
  String get extensaoProtecaoDosNavegadores => '擴充套件與瀏覽器保護';

  @override
  String get oChronosAplicaAExtensaoEm =>
      'Chronos 在 Chromium 瀏覽器中使用擴充套件，在 Firefox 中使用選擇性代理 + CA，完全離線。';

  @override
  String navegadoresInstaladosDetectadosP0(Object p0) {
    return '檢測到的已安裝瀏覽器（$p0）：';
  }

  @override
  String servidorLocalAtivoNaPortaP0(Object p0) {
    return '本地伺服器執行在埠 $p0';
  }

  @override
  String get chromeAbertoEmChromeExtensionsCole =>
      'Chrome 已開啟 chrome://extensions！載入已解壓的擴充套件時貼上複製的路徑。';

  @override
  String get firefoxAbertoEmAboutPoliciesPara =>
      'Firefox 已開啟 about:policies，可檢視本地策略。';

  @override
  String get terminalAbertoParaAutorizacaoDoChronos =>
      '已為 Chronos Guard 授權開啟終端！';

  @override
  String get comandoCopiadoExecuteNoTerminalPara => '命令已複製！在終端中執行以安裝 Guard。';

  @override
  String get configurando => '正在配置...';

  @override
  String get comandoGuardCopiadoParaOTerminal => 'Guard 命令已複製！';

  @override
  String sessoesBloqueiosP0(Object p0) {
    return '會話與攔截（$p0）';
  }

  @override
  String listaBrancaWhitelistP0(Object p0) {
    return '白名單（$p0）';
  }

  @override
  String conflitosEncontradosP0(Object p0) {
    return '發現衝突（$p0）';
  }

  @override
  String eMaisP0(Object p0) {
    return '…… 還有 $p0 個。';
  }

  @override
  String get extensaoWeb => '網頁擴充套件';

  @override
  String get novaSessaoDeBloqueio => '新建攔截會話';

  @override
  String sessoesConfiguradasP0(Object p0) {
    return '已配置的會話（$p0）';
  }

  @override
  String get nenhumaSessaoCriadaAindaCliqueEm => '尚未建立會話。\n點選“新建攔截會話”將應用或網站分組。';

  @override
  String get catracaTravadaAumentosProibidos => '棘輪已鎖定（禁止增加）';

  @override
  String get recolher => '收起';

  @override
  String get expandir => '展開';

  @override
  String get editarTempoDeBloqueio => '編輯攔截時間';

  @override
  String get adicionarAppsSitesAoGrupo => '向分組新增應用 / 網站';

  @override
  String get focarNoDashboard => '在儀表盤中聚焦';

  @override
  String get desbloquear => '解除攔截';

  @override
  String get bloquearCompletamente => '完全攔截';

  @override
  String get removerSessao => '刪除會話';

  @override
  String get recolherItensDaSessao => '收起會話專案';

  @override
  String get expandirParaVerTodosOsApps => '展開檢視所有應用和網站';

  @override
  String get adicionarAplicativosSitesPermitidoNoAnti => '新增應用 / 網站（防繞過下允許）';

  @override
  String get sessaoSelecionada => '已選會話';

  @override
  String aplicativosBloqueadosP0(Object p0) {
    return '被攔截的應用（$p0）：';
  }

  @override
  String removerP0DoGrupoAntiCheat(Object p0) {
    return '從分組中移除 $p0（受防繞過限制）';
  }

  @override
  String sitesEPalavrasChaveBloqueadosP0(Object p0) {
    return '被攔截的網站和關鍵詞（$p0）：';
  }

  @override
  String get nenhumAplicativoOuSiteListadoNesta => '此會話中沒有列出應用或網站。';

  @override
  String gruposDeListaBrancaP0(Object p0) {
    return '白名單分組（$p0）';
  }

  @override
  String get nenhumGrupoDeListaBrancaCriado =>
      '尚未建立白名單分組。\n白名單中的應用和網站不會被攔截或關閉。';

  @override
  String get protecaoTotal => '完全保護';

  @override
  String p0TiposYoutube(Object p0) {
    return '$p0 種 YouTube 型別';
  }

  @override
  String get itensProtegidosContraContagemDeTempo => '這些專案不計入螢幕時間，也不會被自動關閉';

  @override
  String youtubePermitidoP0(Object p0) {
    return '允許的 YouTube：$p0';
  }

  @override
  String get recolherItens => '收起專案';

  @override
  String get expandirItens => '展開專案';

  @override
  String get editarGrupo => '編輯分組';

  @override
  String get removerGrupo => '刪除分組';

  @override
  String aplicativosProtegidosP0(Object p0) {
    return '受保護的應用（$p0）：';
  }

  @override
  String removerP0DaListaBranca(Object p0) {
    return '從白名單中移除 $p0';
  }

  @override
  String sitesEPalavrasProtegidosP0(Object p0) {
    return '受保護的網站和關鍵詞（$p0）：';
  }

  @override
  String tiposDoYoutubePermitidosP0(Object p0) {
    return '允許的 YouTube 型別（$p0）：';
  }

  @override
  String get registroDeBurlas => '繞過記錄';

  @override
  String get cofreDoChronosAtivoComO =>
      'Chronos 保險庫已開啟：防繞過開啟時，修改資料庫、停止服務、刪除自啟動或更改時鐘都會在幾秒內被撤銷並記錄在這裡。';

  @override
  String get cofreDoChronosNaoInstaladoInstale =>
      'Chronos 保險庫未安裝：請安裝/更新瀏覽器保護（Chronos Guard）以開啟防繞過層。';

  @override
  String relogioDoSistemaCorrigidoEmP0(Object p0) {
    return '系統時鐘已校正 $p0 分鐘（Chronos 使用可信時間）。';
  }

  @override
  String penalidadeAtivaTodasAsSessoesBloqueadas(Object p0) {
    return '懲罰生效：所有會話將被攔截至 $p0。';
  }

  @override
  String get aoDetectarUmaBurla => '檢測到繞過時';

  @override
  String get restaurarERegistrar => '恢復並記錄';

  @override
  String get restaurarRegistrarEBloquearTudoAte => '恢復、記錄並攔截所有內容直到午夜';

  @override
  String get comOAntiBurlaAtivoNao => '防繞過開啟時無法切換回較輕的選項。';

  @override
  String get nenhumaTentativaDeBurlaRegistrada => '沒有記錄到繞過嘗試。';

  @override
  String get bancoEditado => '資料庫被修改';

  @override
  String get bancoApagado => '資料庫被刪除';

  @override
  String get servicoParado => '服務被停止';

  @override
  String get servicoApagado => '服務被刪除';

  @override
  String get autostartApagado => '自啟動被刪除';

  @override
  String get relogioAlterado => '時鐘被更改';

  @override
  String get desbloqueioRecusado => '解鎖被拒絕';

  @override
  String get historicoDeBurlas => '繞過歷史';

  @override
  String p0EventoS(Object p0) {
    return '$p0 個事件';
  }

  @override
  String get nenhumaBurlaNestePeriodo => '此期間沒有繞過。';

  @override
  String get naoEPossivelDesinstalar => '無法解除安裝';

  @override
  String get oAntiBurlaEstaAtivoEnquanto => '防繞過已開啟。開啟期間無法關閉或解除安裝 Chronos。';

  @override
  String get desinstalarOChronos => '解除安裝 Chronos？';

  @override
  String get istoRemoveOChronosDoComputador =>
      '這將從電腦中移除 Chronos：後臺應用、瀏覽器擴充套件、系統保護（可能需要你的密碼）、自啟動和 Chronos 服務。';

  @override
  String get apagarTambemMeusDados => '同時刪除我的資料';

  @override
  String get regrasHistoricoDeUsoEConfiguracoes => '規則、使用歷史和設定。不勾選則保留，以便重新安裝。';

  @override
  String get desinstalar => '解除安裝';

  @override
  String get atualizacaoAutomaticaSoFuncionaNaVersao =>
      '自動更新僅適用於已安裝的版本（開發版本不適用）。';

  @override
  String oChronosJaEstaNaVersao(Object p0) {
    return 'Chronos 已是最新版本（$p0）。';
  }

  @override
  String get baixando => '正在下載…';

  @override
  String get verificandoAssinatura => '正在驗證簽名…';

  @override
  String get instalando => '正在安裝…';

  @override
  String get atualizandoAProtecaoDoSistemaPode => '正在更新系統保護（可能需要你的密碼）…';

  @override
  String get reiniciandoOChronos => '正在重啟 Chronos…';

  @override
  String get aProtecaoDoSistemaGuardNao => '系統保護（Guard）這次沒有更新。你可以稍後在設定中更新。';

  @override
  String novaVersaoDoChronosP0(Object p0) {
    return 'Chronos 新版本：$p0';
  }

  @override
  String voceEstaNaVersaoP0Deseja(Object p0) {
    return '你當前的版本是 $p0。現在更新嗎？';
  }

  @override
  String falhaNaAtualizacaoP0(Object p0) {
    return '更新失敗：$p0';
  }

  @override
  String get depois => '稍後';

  @override
  String get tentarNovamente => '重試';

  @override
  String get atualizarAgora => '立即更新';

  @override
  String get deUmNomeAoTipoNovo => '請為新型別命名。';

  @override
  String get tiposDoYoutubePorCanalOu => '按頻道或關鍵詞劃分的 YouTube 型別';

  @override
  String get exCanalFlowPodcastContaComo =>
      '例如：頻道“Flow Podcast”計為播客；關鍵詞“minecraft”會建立型別“Minecraft”。多個頻道或關鍵詞用逗號分隔。';

  @override
  String get tipo => '型別';

  @override
  String get novoTipo => '新型別…';

  @override
  String get nomeDoTipo => '型別名稱';

  @override
  String get canais => '頻道';

  @override
  String get palavrasNoTituloTags => '標題/標籤中的關鍵詞';

  @override
  String get adicionarRegra => '新增規則';

  @override
  String hojeP0(Object p0) {
    return ' 今天：$p0。';
  }

  @override
  String get escolhaDosPaisSuffix => '（家長的選擇）';

  @override
  String get guiaAnonimaSeraBloqueadaSuffix => ' —— 無痕模式將再次被停用';

  @override
  String get safesearchNosNavegadoresSuffix => ' + 瀏覽器安全搜尋';

  @override
  String get todosOsNavegadoresJaPermitemAnonimo => '所有瀏覽器都已允許擴充套件在無痕模式下執行。';

  @override
  String get iaDeImagensNaTelaInteira => '全屏影像 AI（本地）';

  @override
  String get iaTelaInteiraDescricao =>
      '每約 2 秒檢查任意應用（不僅是瀏覽器）的當前視窗，出現 18+ 內容時遮住螢幕。全部在本機進行，不儲存任何內容。會佔用少量 CPU。';

  @override
  String get iaTelaInteiraNaoSuportada => '僅在安裝了 grim 的 Hyprland 上可用。';

  @override
  String get conteudoAdultoDetectadoNaTela => '檢測到 18+ 內容';

  @override
  String coberturaTelaTexto(String window) {
    return 'Chronos 在視窗“$window”中發現成人內容。請先關閉或更換內容再返回。';
  }

  @override
  String get entendiVoltar => '知道了，返回';

  @override
  String appBloqueadoTitulo(String app) {
    return '$app 已被遮蔽';
  }

  @override
  String get motivoQuota => '今天的時間額度已用完。';

  @override
  String get motivoJanela => '當前時段已被遮蔽。';

  @override
  String get motivoForcado => '此應用已被完全遮蔽。';

  @override
  String get motivoPenalidade => '因繞過嘗試而處於懲罰中。';

  @override
  String get motivoLazer => '強制休息進行中。';

  @override
  String get appFechadoPeloChronos => 'Chronos 已關閉該應用。';

  @override
  String get extVersaoAtualizada => '（已是最新）';

  @override
  String extVersaoPendente(String version) {
    return '→ $version 待更新';
  }

  @override
  String extFirefoxPrecisaAssinar(String version) {
    return '→ $version 等待 Mozilla 簽名（執行 scripts/run-release.sh）';
  }

  @override
  String extVersaoDisponivel(String version) {
    return '可用版本：$version';
  }

  @override
  String get contaDaCriancaProtegida => '受保護的孩子賬戶';

  @override
  String contaProtegidaDescricao(String user) {
    return '賬戶“$user”不是管理員：無法移除 Chronos。Wi-Fi、U 盤、印表機、藍牙、關機以及從官方倉庫安裝軟體仍然可用。';
  }

  @override
  String contaEhAdministradoraAviso(String user) {
    return '賬戶“$user”是管理員（sudo），可以用 root 許可權移除 Chronos。保護此賬戶：它將不再是管理員，Chronos 只允許日常操作。需要另一個管理員賬戶（監護人）的密碼。';
  }

  @override
  String contaSemAdministrador(String user) {
    return '賬戶“$user”已不是管理員：無法移除 Chronos。';
  }

  @override
  String get protegerEstaConta => '保護此賬戶';

  @override
  String get devolverAdministrador => '恢復管理員許可權';

  @override
  String get feitoValeNoProximoLogin => '完成。下次登入後生效。';

  @override
  String get guardNaoInstaladoAtiveAProtecao => '未安裝 Chronos Guard：請先開啟瀏覽器保護。';

  @override
  String get autorizacaoCancelada => '授權已取消。';

  @override
  String get textosDesafioExplicacao =>
      '你的文字會替換預設文字：挑戰只會從中抽取。沒有自定義文字時使用預設文字。每段至少 120 個字元。防繞過開啟時無法修改。';

  @override
  String get recusarTextosFaceis => '拒絕過於簡單的文字';

  @override
  String get recusarTextosFaceisDescricao =>
      '拒絕包含重複詞語、字母種類過少、鍵盤序列或多次複製同一段內容的文字。';

  @override
  String get semTextosUsaOsPadrao => '沒有自定義文字：挑戰使用預設文字。';

  @override
  String get adicionarTexto => '新增文字';

  @override
  String get editarTexto => '編輯文字';

  @override
  String p0Caracteres(int count) {
    return '$count 個字元';
  }

  @override
  String get textoAprovado => '文字合格。';

  @override
  String get ok => '確定';
}
