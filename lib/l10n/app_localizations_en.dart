// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get chronosAntiCheatStrictFocusEngine =>
      'Chronos - Anti-Bypass & Strict Focus Engine';

  @override
  String get chronosFocusEngine => 'Chronos Focus Engine';

  @override
  String get reiniciarBancoDeDados => 'Reset database?';

  @override
  String get desejaResetarCompletamenteOSqliteIntervalos =>
      'Fully reset SQLite? Intervals will be cleared, the ratchet unlocked and the initial setup restarted.';

  @override
  String get cancelar => 'Cancel';

  @override
  String get reiniciarTudo => 'Reset everything';

  @override
  String get parentalPai => 'Parental (Parent)';

  @override
  String get parentalFilho => 'Parental (Child)';

  @override
  String get autoControle => 'Self-control';

  @override
  String focoP0(Object p0) {
    return 'Focus: $p0';
  }

  @override
  String get autoDeteccaoAtiva => 'Auto-detection on';

  @override
  String get deteccaoAutomatica => 'Automatic detection';

  @override
  String get antiCheatOff => 'Anti-Bypass: OFF';

  @override
  String nukeP0DP1(Object p0, Object p1) {
    return 'Nuke: ${p0}d $p1';
  }

  @override
  String nukeP0(Object p0) {
    return 'Nuke: $p0';
  }

  @override
  String get antiCheatAtivo => 'Anti-Bypass on';

  @override
  String get refazerCadastroTrocarModo => 'Redo setup / Change mode';

  @override
  String get instalarExtensoesNosNavegadores => 'Install browser extensions';

  @override
  String get sairDoAntiCheatDebug => '🛠️ Exit Anti-Bypass (Debug)';

  @override
  String get reiniciarBancoCompleto => 'Reset whole database';

  @override
  String get zerarConsumoDiario => 'Reset daily usage';

  @override
  String destravarCatracaP0(Object p0) {
    return 'Unlock ratchet ($p0)';
  }

  @override
  String get restaurarTokens2 => 'Restore tokens (+2)';

  @override
  String get tempoDeTela => 'Screen time';

  @override
  String get monitorEmTempoReal => 'Real-time monitor';

  @override
  String get estatisticas => 'Statistics';

  @override
  String get metricasDeConsumo => 'Usage metrics';

  @override
  String get regrasWhitelist => 'Rules & Whitelist';

  @override
  String get limitesEGrupos => 'Limits and groups';

  @override
  String get configuracoes => 'Settings';

  @override
  String get aparenciaEAlertas => 'Appearance and alerts';

  @override
  String get quarentena => 'Quarantine';

  @override
  String get modoNukeBloqueios => 'Nuke mode & blocks';

  @override
  String get sqliteTestes => 'SQLite / Tests';

  @override
  String get depuracaoDoBanco => 'Database debugging';

  @override
  String get chronos => 'Chronos';

  @override
  String get focusEngine => 'Focus Engine';

  @override
  String get alternarParaModoClaro => 'Switch to light mode';

  @override
  String get alternarParaModoEscuro => 'Switch to dark mode';

  @override
  String get modoClaro => 'Light mode';

  @override
  String get modoEscuro => 'Dark mode';

  @override
  String get estatisticasDeConsumoHistorico => 'Usage statistics & history';

  @override
  String get regrasDeBloqueioWhitelist => 'Block rules & whitelist';

  @override
  String get configuracoesGeraisNotificacoes =>
      'General settings & notifications';

  @override
  String get quarentenaModoNuke => 'Quarantine & Nuke mode';

  @override
  String get bancoDeDadosTestesSqlite => 'Database & SQLite tests';

  @override
  String get debugSairDoAntiCheat => '🛠️ [DEBUG] Exit Anti-Bypass';

  @override
  String get instalarExtensoesEmNavegadores => 'Install extensions in browsers';

  @override
  String get acoesGlobais => 'Global actions';

  @override
  String get telaDeCadastro => 'Setup screen';

  @override
  String get debugSairDoAntiCheatImediatamente =>
      '🛠️ [DEBUG] Exit Anti-Bypass now';

  @override
  String get instalarExtensoesEmTodosNavegadores =>
      'Install extensions in all browsers';

  @override
  String get acoesConfiguracao => 'Actions & settings';

  @override
  String get tempo => 'Time';

  @override
  String get metricas => 'Metrics';

  @override
  String get regras => 'Rules';

  @override
  String get ajustes => 'Settings';

  @override
  String get nuke => 'Nuke';

  @override
  String get sqlite => 'SQLite';

  @override
  String get sincronizandoComOMotorDeMonitoramento =>
      'Syncing with the monitoring engine...';

  @override
  String get tentarConectarAgora => 'Try to connect now';

  @override
  String get etapaInicialTesteAQualquerMomento =>
      'Initial step: try setting up and customizing blocks at any time.';

  @override
  String get voltarAoCadastro => 'Back to setup';

  @override
  String p0SessoesAtivasSimultaneamenteOTempo(Object p0) {
    return '⚡ $p0 sessions active at once! Screen time is being tracked in parallel.';
  }

  @override
  String get sessao => 'Session';

  @override
  String get emExecucao => 'Running';

  @override
  String get tempoAtivo => 'ACTIVE TIME';

  @override
  String consumidoHojeP0(Object p0) {
    return 'Used today: $p0';
  }

  @override
  String limiteP0P1(Object p0, Object p1) {
    return 'Limit: $p0 ($p1%)';
  }

  @override
  String get catracaAtiva => 'Ratchet on';

  @override
  String tokensP02(Object p0) {
    return 'Tokens: $p0/2';
  }

  @override
  String limiteDeTempoDeTelaP0(Object p0, Object p1) {
    return 'Screen time limit: $p0 ($p1%)';
  }

  @override
  String get controlesDeTempoDeTelaCatraca => 'Screen time & ratchet controls';

  @override
  String get reduzirTempoDeTelaTeste15s => 'Reduce screen time (15s test)';

  @override
  String get tentarAumentarTempoDeTela2h => 'Try to increase screen time (+2h)';

  @override
  String get trancarCatraca24h => 'Lock ratchet (24h)';

  @override
  String get catracaTrancadaPor24hAumentosProibidos =>
      'Ratchet locked for 24h! Increases are forbidden.';

  @override
  String get usarTokenDeEmergencia1h => 'Use emergency token (+1h)';

  @override
  String get bemVindoAoChronos => 'Welcome to Chronos';

  @override
  String get seuMotorDeFocoEstritoE =>
      'Your strict focus and productivity engine for Linux.\nHow do you plan to use this app?';

  @override
  String get controlePessoalAutoControle => 'Personal control (Self-control)';

  @override
  String get paraGerenciarSeuProprioTempoE =>
      'To manage your own time and studies.';

  @override
  String get modoCatracaRatchetReducoesSaoImediatas =>
      'Ratchet mode: reductions apply immediately, increases are blocked.';

  @override
  String get t2TokensMensaisDeEmergencia1h =>
      '2 monthly emergency tokens (+1h with a 24h leisure-lock penalty).';

  @override
  String get bloqueioAtivoComSobreposicaoDeJanela =>
      'Active blocking with window overlay and automatic media pause.';

  @override
  String get configurarBloqueiosPessoais => 'Set up personal blocks';

  @override
  String get controleParentalSupervisao => 'Parental control (Supervision)';

  @override
  String get paraPaisEResponsaveisGerenciaremDispositivos =>
      'For parents and guardians to manage their dependents\' devices.';

  @override
  String get dispositivoDoDependenteProtegidoContraAlteracoes =>
      'Dependent\'s device protected against changes and workarounds.';

  @override
  String get pareamentoSeguroViaQrCodeOu =>
      'Secure pairing via QR code or master password.';

  @override
  String get gestaoDeAprovacaoDeBinariosE =>
      'Approval of programs and app quarantine.';

  @override
  String get configurarControleParental => 'Set up parental control';

  @override
  String get personalizacaoDeBloqueioTempoDeTela =>
      'Customize blocks & screen time';

  @override
  String get ajusteOTempoDeTelaDiario =>
      'Set the initial daily screen time and the strictness level';

  @override
  String get distracoesABloquear => 'Distractions to block';

  @override
  String get adicionarAppOuSite => 'Add app or site';

  @override
  String get nenhumaSessaoPreConfiguradaCliqueEm =>
      'No preset sessions.\nClick \"Add app or site\" above to create your own sessions.';

  @override
  String get tempoDeTelaDiario => 'Daily screen time:';

  @override
  String get bloqueioTotal => 'Full block';

  @override
  String get t15Min => '15 min';

  @override
  String get t30Min => '30 min';

  @override
  String get t1Hora => '1 hour';

  @override
  String get t2Horas => '2 hours';

  @override
  String get diretrizesDeEnforcementDoChronos => 'Chronos enforcement rules';

  @override
  String get ativarTravaDaCatraca24hIniciais =>
      'Turn on ratchet lock (first 24h)';

  @override
  String get impedeAumentosDeTempoDeTela =>
      'Blocks screen time increases on the first day. You can only reduce screen time.';

  @override
  String get sequestroVisualDeFocoAlwaysOn =>
      'Visual focus takeover (always-on-top fullscreen)';

  @override
  String get maximizaETravaAJanelaDo =>
      'Maximizes and locks the Chronos window on top when screen time runs out.';

  @override
  String get pausaAtivaDeMidiaPlayerctlMpris2 =>
      'Active media pause (playerctl / MPRIS2)';

  @override
  String get interrompeAutomaticamenteVideosEMusicasEm =>
      'Automatically stops videos and music playing in the background.';

  @override
  String get salvarBloqueiosEIniciarChronos => 'Save blocks and start Chronos';

  @override
  String get controleParental => 'Parental control';

  @override
  String get qualEOPapelDesteComputador =>
      'What is this computer\'s role in the family?';

  @override
  String get dispositivoDoResponsavelPaiMae => 'Guardian\'s device (Parent)';

  @override
  String get esteComputadorTeraAutoridadeParaControlar =>
      'This computer will have authority to control rules and screen time.';

  @override
  String get recebeSolicitacoesDeEmergenciaEAprovacoes =>
      'Receives emergency requests and quarantine approvals.';

  @override
  String get conectaAoComputadorDoFilhoUsando =>
      'Connects to the child\'s computer using a QR code or password.';

  @override
  String get configurarComoDispositivoPai => 'Set up as parent device';

  @override
  String get dispositivoDoDependenteFilho => 'Dependent\'s device (Child)';

  @override
  String get esteComputadorSeraMonitoradoEProtegido =>
      'This computer will be monitored and protected against distractions.';

  @override
  String get asAlteracoesDeTempoDeTela =>
      'Screen time changes require the guardian\'s authorization or password.';

  @override
  String get exibeQrCodeECodigoPin =>
      'Shows a QR code and PIN for the guardian to connect.';

  @override
  String get configurarComoDispositivoFilho => 'Set up as child device';

  @override
  String chronosPairCodeP0(Object p0) {
    return 'chronos://pair?code=$p0';
  }

  @override
  String get pareamentoDispositivoFilho => 'Pairing: child device';

  @override
  String get pareamentoDispositivoDoResponsavel => 'Pairing: guardian device';

  @override
  String get conecteEsteComputadorAoAplicativoDo =>
      'Connect this computer to the guardian\'s app using a QR code or PIN/password.';

  @override
  String get escaneieOQrCodeOuInsira =>
      'Scan the QR code or enter the PIN shown on the child\'s device.';

  @override
  String get viaQrCode => 'Via QR code';

  @override
  String get viaSenhaPin => 'Via password / PIN';

  @override
  String get concluirEIniciarProtecao => 'Finish and start protection';

  @override
  String get concluirEAbrirPainelDoResponsavel =>
      'Finish and open the guardian panel';

  @override
  String get protecaoObrigatoriaEmTodosOsNavegadores =>
      'Mandatory protection in all browsers';

  @override
  String get configuraTodosOsNavegadoresDoDispositivo =>
      'Sets up every browser on this device to show remaining time and apply HTML/CSS filters (Shorts, home feed, grayscale). Removal is only allowed after the Anti-Bypass check.';

  @override
  String get instalandoConfigurando => 'Installing & configuring...';

  @override
  String get instalarAtualizarEmTodosOsNavegadores =>
      'Install / update in all browsers';

  @override
  String get terminalAbertoDigiteSuaSenhaSudo =>
      'Terminal opened! Type your sudo password once to finish the Guard.';

  @override
  String executeManualmenteP0(Object p0) {
    return 'Run manually: $p0';
  }

  @override
  String get terminalAbertoDigiteSuaSenhaSudo2 =>
      'Terminal opened! Type your sudo password just once.';

  @override
  String executeNoTerminalP0(Object p0) {
    return 'Run in the terminal: $p0';
  }

  @override
  String get aponteODispositivoDoResponsavelPara =>
      'Point the guardian\'s device at this QR code.';

  @override
  String get seEstiverUsandoAVersaoMobile =>
      'If you are using the mobile version or a camera, point it at the QR code on the child\'s screen.';

  @override
  String get ouColeAChaveUriDo => 'Or paste the QR code key/URI here';

  @override
  String get chronosPairId => 'chronos://pair?id=...';

  @override
  String get codigoPinDePareamentoDesteDispositivo =>
      'Pairing PIN of this device:';

  @override
  String get definirSenhaMestraDeDesbloqueioLocal =>
      'Set a local unlock master password (optional)';

  @override
  String get digiteUmaSenhaParaAlterarTempo =>
      'Type a password to change screen time in person';

  @override
  String get digiteOCodigoPinOuSenha =>
      'Type the PIN or password shown on the child\'s screen:';

  @override
  String get chrXxxxOuSenha => 'CHR-XXXX or password';

  @override
  String get validarEParear => 'Validate and pair';

  @override
  String get orgKdeStatusnotifierwatcher => 'org.kde.StatusNotifierWatcher';

  @override
  String get abrirChronos => 'Open Chronos';

  @override
  String get desinstalarChronos => 'Uninstall Chronos…';

  @override
  String get antiBurlaAtivoOChronosNao =>
      'Anti-Bypass is on: Chronos cannot be uninstalled while it is on.';

  @override
  String get chronosFocus => 'Chronos Focus';

  @override
  String get chronosMonitoramentoAtivo => 'Chronos - Monitoring on';

  @override
  String oAplicativoP0EstaSendoMonitorado(Object p0, Object p1) {
    return 'The app \"$p0\" is being monitored in the session \"$p1\".';
  }

  @override
  String get chronosTempoDeTelaRestante => 'Chronos - Remaining screen time';

  @override
  String p0RestamApenasP1MinutoP2(Object p0, Object p1) {
    return '$p0: only $p1 min of screen time left!';
  }

  @override
  String get chronosTempoDeTelaEsgotado => 'Chronos - Screen time used up';

  @override
  String p0OTempoDeTelaDiario(Object p0) {
    return '$p0: today\'s screen time is completely used up!';
  }

  @override
  String chronosAlertaPeriodicoP0Min(Object p0) {
    return 'Chronos - Periodic alert ($p0 min)';
  }

  @override
  String p0P1MinUtilizadosHojeRestam(Object p0, Object p1, Object p2) {
    return '$p0: $p1 min used today • $p2 min of screen time left.';
  }

  @override
  String get todas => 'All';

  @override
  String get jogos => 'Games';

  @override
  String get navegadores => 'Browsers';

  @override
  String get comunicacao => 'Communication';

  @override
  String get internet => 'Internet';

  @override
  String get midia => 'Media';

  @override
  String get desenvolvimento => 'Development';

  @override
  String get escritorio => 'Office';

  @override
  String get graficos => 'Graphics';

  @override
  String get educacao => 'Education';

  @override
  String get sistema => 'System';

  @override
  String get utilitarios => 'Utilities';

  @override
  String get outros => 'Other';

  @override
  String adicionarTagP0(Object p0) {
    return 'Add tag: $p0';
  }

  @override
  String get nomeDaTagExRedesSociais =>
      'Tag name (e.g. Social media, Work, Games)';

  @override
  String get adicionarTag => 'Add tag';

  @override
  String p0JaFoiAdicionadoAoGrupo(Object p0) {
    return '\"$p0\" is already in the group.';
  }

  @override
  String get sessaoDeFoco => 'Focus session';

  @override
  String get listaBranca => 'Whitelist';

  @override
  String get selecionePeloMenosUmAplicativoOu =>
      'Select at least one app or site for the group.';

  @override
  String p0HP1Min(Object p0, Object p1) {
    return '$p0 h $p1 min';
  }

  @override
  String get editarGrupoDeListaBranca => 'Edit whitelist group';

  @override
  String get novoGrupoDeListaBranca => 'New whitelist group';

  @override
  String get adicionarAplicativosSitesAoGrupo =>
      'Add apps / sites to the group';

  @override
  String get editarSessaoDeFoco => 'Edit focus session';

  @override
  String get criarSessaoDeFoco => 'Create focus session';

  @override
  String get appsESitesNaListaBranca =>
      'Whitelisted apps and sites will NEVER be blocked or closed, even if they are in other groups.';

  @override
  String get digiteONomeDoGrupoDe =>
      'Type the whitelist group name (e.g. Study tools)...';

  @override
  String get digiteONomeDaSessaoDe =>
      'Type the focus session name (e.g. Distractions & leisure)...';

  @override
  String get nomeDoGrupoDeListaBranca => 'Whitelist group name';

  @override
  String get nomeDaSessaoDeFoco => 'Focus session name';

  @override
  String aplicativosP0(Object p0) {
    return 'Apps ($p0)';
  }

  @override
  String sitesEPalavrasP0(Object p0) {
    return 'Sites and words ($p0)';
  }

  @override
  String youtubeP0(Object p0) {
    return 'YouTube ($p0)';
  }

  @override
  String p0AppsP1Sites(Object p0, Object p1) {
    return '$p0 apps • $p1 sites';
  }

  @override
  String get salvarListaBranca => 'Save whitelist';

  @override
  String get salvarAppsNoGrupo => 'Save apps in the group';

  @override
  String get avancarTempoDeTelaRegras => 'Next: screen time & rules';

  @override
  String get buscarPorNomeExecutavelOuTag =>
      'Search by name, executable or tag (e.g. Games, Media)...';

  @override
  String get selecionarTudo => 'Select all';

  @override
  String get limpar => 'Clear';

  @override
  String get carregandoAplicativosInstalados => 'Loading installed apps...';

  @override
  String get nenhumAplicativoEncontradoParaOFiltro =>
      'No app found for this filter/tag.';

  @override
  String get limparFiltroDeTag => 'Clear tag filter';

  @override
  String get jaNoGrupo => 'Already in the group';

  @override
  String get tag => '+ Tag';

  @override
  String get videosDessesTiposNaoDescontamO =>
      'Videos of these types don\'t use YouTube screen time. Use the cap to limit how much time per day is exempt (empty = no cap).';

  @override
  String get tetoMinDia => 'Cap (min/day)';

  @override
  String get semTeto => 'no cap';

  @override
  String get digiteDominioOuPalavraChaveEx =>
      'Type a domain or keyword (e.g. youtube.com, reels, shorts)...';

  @override
  String get adicionar => 'Add';

  @override
  String sitesEPalavrasChaveAdicionadosP0(Object p0) {
    return 'Sites and keywords added ($p0):';
  }

  @override
  String get limparNovos => 'Clear new';

  @override
  String get limparTodos => 'Clear all';

  @override
  String get nenhumSiteOuPalavraChaveAdicionado =>
      'No site or keyword added to this session yet.';

  @override
  String p0JaNoGrupo(Object p0) {
    return '$p0 (already in the group)';
  }

  @override
  String editarTempoDeBloqueioP0(Object p0) {
    return 'Edit block time: $p0';
  }

  @override
  String tempoDeTelaP0(Object p0) {
    return 'Screen time: $p0';
  }

  @override
  String sessaoP0(Object p0) {
    return 'Session: $p0';
  }

  @override
  String get grupoDeFocoUnificado => 'UNIFIED FOCUS GROUP';

  @override
  String p0AplicativosEP1SitesInclusos(Object p0, Object p1) {
    return '$p0 apps and $p1 sites included.';
  }

  @override
  String get todosOsAplicativosESitesDesta =>
      'All apps and sites in this session share the same daily screen time quota.';

  @override
  String get limiteDeTempoDeTelaRelogio => 'Screen time limit (digital clock):';

  @override
  String get bloqueioTotal2 => 'FULL BLOCK';

  @override
  String get nenhumAcessoPermitidoDuranteODia =>
      'No access allowed during the day';

  @override
  String p0DeUsoPermitido(Object p0) {
    return '$p0 of use allowed';
  }

  @override
  String get bloquearTotalmente0MinDeTempo =>
      'Block completely (0 min of screen time)';

  @override
  String get impedeQualquerInicializacaoDoGrupoImediatamente =>
      'Prevents any app in the group from starting, right away';

  @override
  String get tempoDeTelaDiferenciadoNoFinal =>
      'Different screen time on weekends';

  @override
  String get permiteConfigurarMaisTempoParaSabado =>
      'Lets you set more time for Saturday and Sunday';

  @override
  String tempoFimDeSemanaP0(Object p0) {
    return 'Weekend time: $p0';
  }

  @override
  String get tempoDeTelaDiferenciadoEmFeriados =>
      'Different screen time on holidays';

  @override
  String valeNosFeriadosNacionaisENas(Object p0) {
    return 'Applies on national holidays and on the dates you add in Settings. Takes priority over the weekend.$p0';
  }

  @override
  String tempoEmFeriadosP0(Object p0) {
    return 'Holiday time: $p0';
  }

  @override
  String get diasDaSemanaAtivos => 'Active weekdays:';

  @override
  String get todos => 'All';

  @override
  String get diasUteis => 'Weekdays';

  @override
  String get finsDeSemana => 'Weekends';

  @override
  String get seg => 'Mon';

  @override
  String get ter => 'Tue';

  @override
  String get qua => 'Wed';

  @override
  String get qui => 'Thu';

  @override
  String get sex => 'Fri';

  @override
  String get sab => 'Sat';

  @override
  String get dom => 'Sun';

  @override
  String get bloqueioPorJanelaDeHorario => 'Block by time window';

  @override
  String get bloqueiaOGrupoDentroDeUm =>
      'Blocks the group during a fixed time of day';

  @override
  String inicioP0(Object p0) {
    return 'Start: $p0';
  }

  @override
  String fimP0(Object p0) {
    return 'End: $p0';
  }

  @override
  String get modo => 'Mode:';

  @override
  String get bloquearDentro => 'Block inside';

  @override
  String get permitirSomenteDentro => 'Allow only inside';

  @override
  String get notificacaoPorTempoRestante => 'Remaining-time notification';

  @override
  String get avisaAos155E1 =>
      'Warns at 15, 5 and 1 minutes before screen time ends';

  @override
  String get notificacaoPeriodica => 'Periodic notification';

  @override
  String get emiteLembretesRegularesEnquantoASessao =>
      'Sends regular reminders while the session is in use';

  @override
  String get intervaloDaNotificacaoPeriodica =>
      'Periodic notification interval:';

  @override
  String aCadaP0Min(Object p0) {
    return 'Every $p0 min';
  }

  @override
  String get salvarGrupoDeFoco => 'Save focus group';

  @override
  String get permitaAExtensaoNoAnonimo => 'Allow the extension in incognito';

  @override
  String get abrirNosNavegadores => 'Open in browsers';

  @override
  String get entendi => 'Got it';

  @override
  String get guiaAnonimaBloqueadaNosNavegadores =>
      'Incognito blocked in browsers.';

  @override
  String get guiaAnonimaLiberada => 'Incognito allowed.';

  @override
  String get nenhumNavegadorChromiumEncontrado => 'No Chromium browser found.';

  @override
  String abertoEmP0(Object p0) {
    return 'Opened in $p0: turn on \"Allow in Incognito\" in the Chronos extension.';
  }

  @override
  String get ativarProtecaoPorDns => 'Turn on DNS protection?';

  @override
  String get oDnsFamiliaPassaAValer =>
      'The family DNS applies to the whole computer. Some apps and networks may lose features:\n\n• school, company or hotel networks that block external DNS may lose internet;\n• internal network sites and services (intranet, printers by name) may not open;\n• VPNs, online games, streaming apps or containers (Docker) may fail to resolve addresses;\n• the router\'s DNS and the browsers\' \"secure DNS\" stop being used.\n\nTurning it off later asks for the admin password, and is locked while Anti-Bypass is on.';

  @override
  String get entendiAtivar => 'Got it, turn on';

  @override
  String get filtroDeConteudoAdulto => 'Adult content filter';

  @override
  String get modoParentalOFiltroFicaSempre =>
      'Parental mode: the filter is always on.';

  @override
  String get ativarFiltro => 'Turn on filter';

  @override
  String get bloqueiaSitesAdultosComATela =>
      'Blocks adult sites with the Chronos block screen.';

  @override
  String get bloquearGuiaAnonimaEConvidado => 'Block incognito and guest mode';

  @override
  String impedeJanelasAnonimasPrivadasEO(Object p0) {
    return 'Blocks incognito/private windows and guest mode in all browsers$p0. Allowing them asks for the admin password and is locked while Anti-Bypass is on.';
  }

  @override
  String get permitirAExtensaoNoAnonimoAbrir =>
      'Allow the extension in incognito (open in browsers)';

  @override
  String extensaoPermitidaNoAnonimoEmP0(Object p0) {
    return 'Extension allowed in incognito in $p0 open browser(s).';
  }

  @override
  String extensaoSemPermissaoNoAnonimoEm(Object p0, Object p1, Object p2) {
    return 'Extension not allowed in incognito in $p0 of $p1 browser(s)$p2.';
  }

  @override
  String get filtroLigadoMasNadaEstaBloqueando =>
      'Filter on, but nothing is blocking: turn on the adult sites list, SafeSearch or DNS.';

  @override
  String get listaDeSitesAdultos => 'Adult sites list';

  @override
  String p0SitesConhecidosAtualizaTodaSemana(Object p0) {
    return '$p0 known sites (updated every week).';
  }

  @override
  String get baixandoALista => 'Downloading the list…';

  @override
  String get iaDeImagensLocal => 'Image AI (local)';

  @override
  String get desfocaImagensAteUmModeloDe =>
      'Blurs images until an AI model running on your computer checks them; 18+ ones stay blurred and pages with several are blocked. Nothing is sent out.';

  @override
  String get safesearchForcado => 'Forced SafeSearch';

  @override
  String get googleBingEDuckduckgoEmModo =>
      'Google, Bing and DuckDuckGo in safe mode; YouTube in Restricted Mode.';

  @override
  String get protecaoPorDnsComputadorInteiro =>
      'DNS protection (whole computer)';

  @override
  String get usaUmDnsFamiliaEmTodo =>
      'Uses a family DNS across the system: covers every browser and app. Applied by Chronos Guard (turning it off asks for the admin password).';

  @override
  String get servicoDeDnsFamilia => 'Family DNS service';

  @override
  String get dnsDoChronosDesligadoMasO =>
      'Chronos DNS is off, but the network\'s DNS (router/provider) already filters adult content — only on this network.';

  @override
  String get dnsDoSistemaNormalSemDns => 'System DNS: normal (no family DNS).';

  @override
  String dnsDoSistemaP0AtivoP1(Object p0, Object p1) {
    return 'System DNS: $p0 on$p1.';
  }

  @override
  String get registrarTentativas => 'Log attempts';

  @override
  String anotaDataESiteDeCada(Object p0) {
    return 'Records the date and site of each block$p0.';
  }

  @override
  String get ultimasTentativas => 'Latest attempts';

  @override
  String get verHistoricoCompleto => 'See full history';

  @override
  String get excecoesSitesNuncaBloqueadosPorEste =>
      'Exceptions (sites never blocked by this filter)';

  @override
  String get exSiteDaEscolaCom => 'e.g. school-site.com';

  @override
  String get hoje => 'Today';

  @override
  String get t7Dias => '7 days';

  @override
  String get t30Dias => '30 days';

  @override
  String get tudo => 'All';

  @override
  String get listaDeSites => 'site list';

  @override
  String get reddit => 'Reddit';

  @override
  String get iaDeImagens => 'image AI';

  @override
  String get historicoDeTentativas => 'Attempt history';

  @override
  String p0TentativaS(Object p0) {
    return '$p0 attempt(s)';
  }

  @override
  String get nenhumaTentativaNestePeriodo => 'No attempts in this period.';

  @override
  String get fechar => 'Close';

  @override
  String p0HP1M(Object p0, Object p1) {
    return '${p0}h ${p1}m';
  }

  @override
  String get semDados => 'No data';

  @override
  String get estatisticasDeTempoDeTela => 'Screen time statistics';

  @override
  String get consumoConsolidadoTendenciasSemanaisERanking =>
      'Overall usage, weekly trends and a ranking of apps and sites.';

  @override
  String get atualizar => 'Refresh';

  @override
  String get consumoHoje => 'Usage today';

  @override
  String get tempoEmAppsSitesMonitorados => 'Time in monitored apps/sites';

  @override
  String get mediaSemanal => 'Weekly average';

  @override
  String get baseadoNosUltimos7Dias => 'Based on the last 7 days';

  @override
  String get diaDePico => 'Peak day';

  @override
  String get tendenciaVsSemanaAnterior => 'Trend vs. previous week';

  @override
  String get estavel => 'Stable';

  @override
  String get maisTempoDeTela => 'More screen time';

  @override
  String get menosTempoDeTela => 'Less screen time';

  @override
  String get appsSitesMonitorados => 'Monitored apps/sites';

  @override
  String get mediaDiaria => 'Daily average';

  @override
  String get ultimos7Dias => 'Last 7 days';

  @override
  String get tendencia => 'Trend';

  @override
  String get maisTela => 'More screen';

  @override
  String get menosTela => 'Less screen';

  @override
  String get tempoIsentoNoYoutubeListaBranca =>
      'Exempt time on YouTube (whitelist)';

  @override
  String p0P1Em7Dias(Object p0, Object p1) {
    return '$p0: $p1 in 7 days';
  }

  @override
  String get consumoDiarioNosUltimos7Dias => 'Daily usage in the last 7 days';

  @override
  String totalP0(Object p0) {
    return 'Total: $p0';
  }

  @override
  String get nenhumDadoDiarioRegistrado => 'No daily data recorded.';

  @override
  String get top5AppsSitesMaisConsumidos =>
      'Top 5 most used apps & sites (last 7 days)';

  @override
  String get nenhumaAtividadeRegistradaNaSemanaAinda =>
      'No activity recorded this week yet.';

  @override
  String p0DoTotal(Object p0) {
    return '$p0% of total';
  }

  @override
  String get colarNaoEPermitidoDigiteO =>
      '❌ Pasting is not allowed: type the text.';

  @override
  String get erroDetectadoNoModoStayfocusdQualquer =>
      '❌ Mistake detected! In StayFocusd mode any wrong character resets the whole text. Type very carefully!';

  @override
  String get selecioneUmaDuracaoValidaMaiorQue =>
      'Select a valid duration longer than 0 minutes for Nuke mode.';

  @override
  String get ativarOAntiBurla => 'Turn on Anti-Bypass?';

  @override
  String enquantoOAntiBurlaEstiverAtivo(Object p0) {
    return 'While Anti-Bypass is on:\n\n• Chronos CANNOT be uninstalled;\n• it keeps running in the background and reopens by itself if closed;\n• rules, filters and extensions cannot be loosened.\n\n$p0';
  }

  @override
  String get noModoNukeIssoSoAcaba =>
      'In Nuke mode this only ends when the time is up.';

  @override
  String get paraDesativarSeraPrecisoCompletarO =>
      'To turn it off you will have to complete the challenge.';

  @override
  String modoNukeAtivadoPorP0Configuracoes(Object p0) {
    return '☢️ Nuke mode on for $p0! Settings and extensions locked.';
  }

  @override
  String get modoAntiCheatAtivadoComDesafio =>
      '🛡️ Anti-Bypass mode on with strict challenge!';

  @override
  String erroAoAtivarP0(Object p0) {
    return 'Error turning on: $p0';
  }

  @override
  String get antiCheatDesativadoComSucessoModificacoes =>
      '🔓 Anti-Bypass turned off! Changes allowed.';

  @override
  String erroP0(Object p0) {
    return 'Error: $p0';
  }

  @override
  String get protecaoAntiCheatAtiva => 'Anti-Bypass protection on';

  @override
  String get configurarModoAntiCheat => 'Set up Anti-Bypass mode';

  @override
  String get oAntiCheatImpedeVoceDe =>
      'Anti-Bypass stops you from getting around Chronos, unblocking or raising limits in weak moments, and protects the extension from removal.';

  @override
  String get escolhaOMetodoDeTravamento => 'Choose the lock method:';

  @override
  String get desafioDeDigitacaoEstritoEstiloStayfocusd =>
      'Strict typing challenge (StayFocusd style)';

  @override
  String get qualquerTentativaDeDesativarOuAumentar =>
      'Any attempt to turn it off or raise screen time limits requires retyping a long commitment text without a single mistake. One wrong character? The text resets!';

  @override
  String get modoNukeBloqueioTotalPorTempo =>
      'Nuke mode (full block for a period)';

  @override
  String get trava100OChronosPorUm =>
      'Locks Chronos 100% for a period of time. During it there is NO way to unlock or change anything until the time ends.';

  @override
  String get duracaoDoTravamentoNukeScrollPara =>
      'Nuke lock duration (scroll to adjust):';

  @override
  String ativarModoNukeP0(Object p0) {
    return 'TURN ON NUKE MODE ($p0)';
  }

  @override
  String get ativarAntiCheatRestrito => 'TURN ON STRICT ANTI-BYPASS';

  @override
  String get modoNukeEmAndamento => 'NUKE MODE RUNNING';

  @override
  String get nenhumaAlteracaoDeTempoDeTela =>
      'No changes to screen time, rules or extension removal are allowed until this time expires.';

  @override
  String get desafioDeDigitacaoStayfocusd => 'StayFocusd typing challenge';

  @override
  String get paraDestravarOAplicativoELiberar =>
      'To unlock the app and allow changes, type exactly the text below without a single mistake:';

  @override
  String progressoP0P1Caracteres(Object p0, Object p1) {
    return 'Progress: $p0 / $p1 characters';
  }

  @override
  String get comeceADigitarOTextoAqui => 'Start typing the text here...';

  @override
  String get destravarAntiCheat => 'UNLOCK ANTI-BYPASS';

  @override
  String get debugDesativarAntiCheatImediatamente =>
      '🛠️ Debug: turn off Anti-Bypass now';

  @override
  String get debugAntiCheatENukeDesativados =>
      '🛠️ [DEBUG] Anti-Bypass and Nuke turned off!';

  @override
  String get instalarAtualizarExtensaoEmTodosNavegadores =>
      'Install / update extension in all browsers';

  @override
  String get pacoteEmbutido => 'Bundled package';

  @override
  String get atualizarGuard => 'Update Guard';

  @override
  String get politicaGuard => 'Guard policy';

  @override
  String get ativoNosNavegadores => 'Active in browsers';

  @override
  String get nenhumNavegadorSuportadoDetectado =>
      'No supported browser detected.';

  @override
  String get protegidoPeloProxySeletivoLocal127 =>
      'Protected by the local selective proxy (127.0.0.1:4546) + CA certificate — Firefox Release doesn\'t list unsigned .xpi files in about:addons, but blocks and HTML/CSS filters work normally.';

  @override
  String get instalacaoManualFallbackAvancado =>
      'Manual install / advanced fallback';

  @override
  String get baixarChromeZip => 'Download Chrome (.zip)';

  @override
  String extensaoSalvaEmP0(Object p0) {
    return 'Extension saved to: $p0';
  }

  @override
  String get erroAoSalvarZipEmDownloads => 'Error saving the zip to Downloads.';

  @override
  String get baixarFirefoxXpi => 'Download Firefox (.xpi)';

  @override
  String get erroAoSalvarXpiEmDownloads => 'Error saving the xpi to Downloads.';

  @override
  String get ativarNoChromeManual => 'Turn on in Chrome (manual)';

  @override
  String get ativarNoFirefoxManual => 'Turn on in Firefox (manual)';

  @override
  String get comandoTerminalGuard => 'Terminal command (Guard)';

  @override
  String get reiniciarNavegadoresParaAtivar => 'Restart browsers to activate?';

  @override
  String osSeguintesNavegadoresJaEstaoAbertos(Object p0) {
    return 'These browsers are already open and must be closed and reopened to load the Chronos extension:\n\n$p0\n\nClose and reopen them now?';
  }

  @override
  String get agoraNao => 'Not now';

  @override
  String get fecharEReabrirAgora => 'Close and reopen now';

  @override
  String navegadoresReiniciadosP0(Object p0) {
    return 'Browsers restarted ($p0)!';
  }

  @override
  String get acessoBloqueadoPeloChronos => 'ACCESS BLOCKED BY CHRONOS';

  @override
  String oTempoDeTelaDiarioPara(Object p0) {
    return 'Today\'s screen time for $p0 is completely used up.';
  }

  @override
  String get reproducaoMprisPausadaAutomaticamente =>
      'MPRIS playback paused automatically.';

  @override
  String get janelaSobrepostaAtivaEnquantoOApp =>
      'Overlay window active while the distracting app is in focus.';

  @override
  String usarTokenDeEmergencia1hP0(Object p0) {
    return 'Use emergency token (+1h) [$p0/2]';
  }

  @override
  String get avisoConsumirUmTokenDeEmergencia =>
      'Warning: using an emergency token blocks all leisure activities for 24h!';

  @override
  String get nenhumTokenDeEmergenciaRestantePara =>
      'No emergency tokens left this month. Get back to your studies and focus!';

  @override
  String get idiomaPrincipalSteamApiDefinidoPara =>
      'Main language set to English.';

  @override
  String get idiomaPrincipalSteamApiDefinidoPara2 =>
      'Main language set to Portuguese (Brazil).';

  @override
  String get modoNukeAtivoRemocaoDaExtensao =>
      'Nuke mode on: extension removal blocked until time runs out.';

  @override
  String get remocaoCanceladaConcluaAVerificacaoAnti =>
      'Removal canceled: complete the Anti-Bypass check to remove the extension.';

  @override
  String get antiCheatAindaAtivoRemocaoBloqueada =>
      'Anti-Bypass still on. Removal blocked.';

  @override
  String get removerExtensaoPoliticas => 'Remove extension & policies?';

  @override
  String get verificacaoAntiCheatConcluidaIssoRemovera =>
      'Anti-Bypass check passed. This removes the Chronos extension, the External Extensions links and Chronos Guard (Chrome/Chromium/Firefox policies) from every browser until you reinstall.\n\nConfirm removal?';

  @override
  String get removerDeTodosOsNavegadores => 'Remove from all browsers';

  @override
  String get filtrosAntiDistracaoSalvosComSucesso =>
      'Anti-distraction filters saved!';

  @override
  String p0JaEstaNaLista(Object p0) {
    return '\"$p0\" is already in the list.';
  }

  @override
  String get antiCheatAtivoDesativeOAnti =>
      'Anti-Bypass on: turn off Anti-Bypass to remove tags or game names.';

  @override
  String get antiCheatAtivoDesativeOAnti2 =>
      'Anti-Bypass on: turn off Anti-Bypass to remove the launcher store protection.';

  @override
  String get configuracoesGerais => 'General settings';

  @override
  String get ajustesDeNotificacoesExtensoesLocaisModo =>
      'Notifications, local extensions, mode and security';

  @override
  String get versaoEAtualizacoes => 'Version and updates';

  @override
  String chronosP0AsAtualizacoesSaoVerificadas(Object p0) {
    return 'Chronos $p0 — updates are checked when the app opens.';
  }

  @override
  String chronosP0BuildDeDesenvolvimentoSem(Object p0) {
    return 'Chronos $p0 (development build — no automatic updates).';
  }

  @override
  String get procurarAtualizacoes => 'Check for updates';

  @override
  String get desinstalarChronos2 => 'Uninstall Chronos';

  @override
  String get notificacoesDeDesktop => 'Desktop notifications';

  @override
  String get oModoNaoPerturbeDoSistema =>
      'The system\'s \"Do not disturb\" mode is on: Chronos notifications won\'t show until you turn it off.';

  @override
  String get verificar => 'Check';

  @override
  String get notificarInicioDeAppMonitorado =>
      'Notify when a monitored app starts';

  @override
  String get exibeUmaNotificacaoNoDesktopAvisando =>
      'Shows a desktop notification saying the running app is being timed.';

  @override
  String get notificacaoDeAppMonitoradoAtivada =>
      'Monitored app notification on';

  @override
  String get notificacaoDeAppMonitoradoDesativada =>
      'Monitored app notification off';

  @override
  String get alertasDeTempoDeTelaRestante => 'Remaining screen time alerts';

  @override
  String get avisosAutomaticosQuandoRestarem15m5m =>
      'Automatic alerts when 15m, 5m and 1m of daily screen time are left.';

  @override
  String get avisosPeriodicosDeUsoAtivo => 'Periodic active-use alerts';

  @override
  String get lembretesEmIntervalosRegularesExA =>
      'Reminders at regular intervals (e.g. every 15 min) with the time already used.';

  @override
  String get extensoesDosNavegadores => 'Browser extensions';

  @override
  String get protegeTodosOsNavegadoresDoDispositivo =>
      'Protects every browser on the device offline: local extension in Chromium browsers (Chrome, Chromium, Brave, Edge, Vivaldi, Opera) and the selective Focus proxy + local CA in Firefox.';

  @override
  String get navegadoresDetectadosNoSistema =>
      'Browsers detected on the system:';

  @override
  String get extensaoRemovidaAposVerificacaoAntiCheat =>
      'Extension removed after the Anti-Bypass check. Click below to reinstall in all browsers.';

  @override
  String get configurandoNavegadoresGuard => 'Configuring browsers & Guard...';

  @override
  String get protecaoPermanenteDoSistemaAntiBurla =>
      'Permanent system protection (browser Anti-Bypass)';

  @override
  String get protecaoDoSistemaAtivaTrancada => 'System protection on & locked';

  @override
  String get politicasForcadasAtivasEmChromeChromium =>
      'Forced policies active in Chrome/Chromium/Brave/Edge/Vivaldi/Opera (signed CRX3) and Firefox Release (selective Focus proxy + local CA + PAC, no warnings in about:policies). Extension removal and incognito browsing are blocked.';

  @override
  String get reAplicarPoliticasDoSistema => 'Reapply system policies';

  @override
  String get politicasDoSistemaVerificadasERe =>
      'System policies checked and reapplied!';

  @override
  String get falhaAoReAplicarPoliticas => 'Failed to reapply policies.';

  @override
  String get removendo => 'Removing...';

  @override
  String get removerExtensaoVerificarAntiCheat =>
      'Remove extension (Anti-Bypass check)';

  @override
  String get oChronosGuardInstaladoPossuiPoliticas =>
      'The installed Chronos Guard has old policies (e.g. unsigned ExtensionSettings in Firefox Release). Click \"Install / update in all browsers\" above to fix it in 1 click.';

  @override
  String get oChronosGuardGravaPoliticasPermanentes =>
      'Chronos Guard writes permanent policies to /etc/ (with your Polkit authorization) to prevent manual uninstall and incognito browsing. Use the main button above to turn it on in 1 click.';

  @override
  String get atualizarGuardViaPolkit1Clique =>
      'Update Guard via Polkit (1 click)';

  @override
  String get ativarGuardViaPolkit1Clique =>
      'Turn on Guard via Polkit (1 click)';

  @override
  String get modoDoAplicativoCadastro => 'App mode & setup';

  @override
  String modoAtivoP0(Object p0) {
    return 'Active mode: $p0';
  }

  @override
  String get configuradoComPinEProtecaoParental =>
      'Set up with PIN and parental restrictions.';

  @override
  String get focadoEmAutonomiaComprometimentoPessoalE =>
      'Focused on autonomy, personal commitment and productivity.';

  @override
  String get trocarModoRefazerCadastro => 'Change mode / Redo setup';

  @override
  String get antiCheatProtecaoContraBurlar =>
      'Anti-Bypass & protection against workarounds';

  @override
  String modoNukeAtivoP0SRestantes(Object p0) {
    return 'Nuke mode on (${p0}s left)';
  }

  @override
  String get antiCheatAtivoDesafioStayfocusd =>
      'Anti-Bypass on (StayFocusd challenge)';

  @override
  String get antiCheatDesativado => 'Anti-Bypass off';

  @override
  String get bloqueiaModificacoesDeRegrasAumentoDe =>
      'Blocks rule changes, limit increases in weak moments and extension removal.';

  @override
  String get gerenciarAntiCheat => 'Manage Anti-Bypass';

  @override
  String get ativarAntiCheat => 'Turn on Anti-Bypass';

  @override
  String get textosDoDesafio => 'Challenge texts';

  @override
  String get antiBurlaAtivoOsTextosDo =>
      'Anti-Bypass on: the challenge texts can\'t be changed now.';

  @override
  String get gerenciamentoDeDadosLocaisOffline =>
      'Local data management (offline)';

  @override
  String get todasAsInformacoesRegrasETempos =>
      'All Chronos information, rules and screen times are stored 100% locally on your computer.';

  @override
  String get zerarConsumoDiarioDeHoje => 'Reset today\'s usage';

  @override
  String get reiniciarBancoDeDadosCompleto => 'Reset the whole database';

  @override
  String get reiniciarBancoDeDados2 => 'Reset database';

  @override
  String get atencaoIssoIraApagarTodasAs =>
      'Warning: this deletes every block rule you created and resets the database to its initial state. Continue?';

  @override
  String get zerarTudo => 'Reset everything';

  @override
  String get instalarProtecaoPermanente => 'Install permanent protection';

  @override
  String get estaEtapaConfiguraOsArquivosDe =>
      'This step writes the official policy files to /etc/ and enables the systemd service that permanently locks the extensions against workarounds.';

  @override
  String get comoDesejaProsseguir => 'How do you want to proceed?';

  @override
  String get opcao1CliqueEmAbrirTerminal =>
      'Option 1: click \"Open terminal\" to open a window where you type your sudo password ONCE.\nOption 2: or copy the command below and run it in your favorite terminal:';

  @override
  String get copiarComando => 'Copy command';

  @override
  String get comandoCopiadoParaAAreaDe => 'Command copied to the clipboard!';

  @override
  String get verificarStatus => 'Check status';

  @override
  String get protecaoDoSistemaAtivaEConfirmada =>
      'System protection on and confirmed!';

  @override
  String get protecaoAindaPendenteDeInstalacao =>
      'Protection still pending installation.';

  @override
  String get abrirTerminal => 'Open terminal';

  @override
  String get terminalAbertoDigiteSuaSenhaNa =>
      'Terminal opened! Type your password in the window to finish.';

  @override
  String get naoFoiPossivelAbrirOTerminal =>
      'Couldn\'t open the terminal automatically. Command copied!';

  @override
  String get ativarNoGoogleChrome => 'Turn on in Google Chrome';

  @override
  String get oGoogleChromeOficialBloqueiaInjecoes =>
      'Official Google Chrome blocks hidden command-line injections for security. To turn it on, just load the local folder once (takes 10 seconds).';

  @override
  String get passoAPassoRapido => 'Quick steps:';

  @override
  String get cliqueNoBotaoAbrirChromeAbaixo =>
      'Click \"Open Chrome\" below. Chrome opens chrome://extensions and the folder path is copied.';

  @override
  String get noChromeAtiveAChaveModo =>
      'In Chrome, turn on \"Developer mode\" in the top-right corner.';

  @override
  String get cliqueNoBotaoCarregarSemCompactacao =>
      'Click \"Load unpacked\" (top-left corner).';

  @override
  String get pressioneCtrlVOuSelecioneA =>
      'Press Ctrl+V or select the extension folder and confirm.';

  @override
  String get copiarCaminho => 'Copy path';

  @override
  String get caminhoCopiadoParaAAreaDe => 'Path copied to the clipboard!';

  @override
  String get baixarZip => 'Download .zip';

  @override
  String arquivoSalvoEmP0(Object p0) {
    return 'File saved to: $p0';
  }

  @override
  String get erroAoGerarZipParaDownloads =>
      'Error creating the zip in Downloads.';

  @override
  String get abrirChrome => 'Open Chrome';

  @override
  String get chromeAbertoCaminhoCopiadoParaA =>
      'Chrome opened! Path copied to the clipboard.';

  @override
  String get ativarExtensaoNoFirefox => 'Turn on the extension in Firefox';

  @override
  String get noFirefoxReleasePadraoAMozilla =>
      'In standard Firefox Release, Mozilla requires a signature for external .xpi files — so Chronos\' permanent protection works through the local selective proxy + CA certificate via Chronos Guard. For Firefox ESR/Dev/LibreWolf/Zen or temporary tests in about:debugging, use the .xpi:';

  @override
  String get cliqueNoBotaoAbrirFirefoxAbaixo =>
      'Click \"Open Firefox\" below to go straight to the debugging tab.';

  @override
  String get cliqueNoBotaoCarregarExtensaoTemporaria =>
      'Click \"Load Temporary Add-on...\".';

  @override
  String get selecioneOArquivoManifestJsonNa =>
      'Select the \"manifest.json\" file in the folder below or the .xpi file in ~/Downloads.';

  @override
  String get caminhoDoManifestJsonCopiado => 'manifest.json path copied!';

  @override
  String get erroAoGerarXpiParaDownloads =>
      'Error creating the xpi in Downloads.';

  @override
  String get abrirFirefox => 'Open Firefox';

  @override
  String get firefoxAbertoCaminhoCopiadoParaA =>
      'Firefox opened! Path copied to the clipboard.';

  @override
  String get aparenciaModoDeTema => 'Appearance & theme';

  @override
  String get personalizeOTemaVisualDoChronos =>
      'Customize the Chronos look. Light mode is tuned for bright places with high contrast, and dark mode reduces eye strain.';

  @override
  String get idiomaPrincipalTagsAutocompleteSteamApi => 'Language';

  @override
  String get asTagsSaoEnviadasEmIngles =>
      'Language of the app, the extensions and the block pages. Steam tags are shown in this language when available.';

  @override
  String get portuguesBr => 'Português (BR)';

  @override
  String get englishUs => 'English (US)';

  @override
  String get configBravesoftwareBraveBrowser =>
      '.config/BraveSoftware/Brave-Browser';

  @override
  String get aoAtivarOAntiBurlaO =>
      'If you add your own texts, Chronos draws only from them (the default texts are no longer used). Without your own, it uses the defaults. Write one text per block, separated by a blank line (at least 120 characters each). Can\'t be changed while Anti-Bypass is on.';

  @override
  String get seuTextoAqui => 'Your text here…';

  @override
  String get salvar => 'Save';

  @override
  String get atualizacoesDaExtensao => 'Extension updates';

  @override
  String get atualizarExtensoesAutomaticamente =>
      'Update extensions automatically';

  @override
  String get quandoOChronosForAtualizadoOs =>
      'When Chronos is updated, browsers install the new extension by themselves.';

  @override
  String get firefoxAtualizaAoReabrirONavegador =>
      'Firefox: updated through Chronos too (signed versions).';

  @override
  String get atualizarExtensoesAgora => 'Update extensions now';

  @override
  String get pedidoEnviadoOChromeInstalaA =>
      'Request sent. Browsers install the new version in a few seconds.';

  @override
  String get mostrarApenasVideosDestesTipos =>
      'Show only videos of these types';

  @override
  String get escolhaAoMenosUmTipoAbaixo =>
      'Choose at least one type below to turn it on.';

  @override
  String get aHomeEOsRelacionadosSo =>
      'The home page and related videos only show the chosen types. Search still shows everything (and counts time).';

  @override
  String get escolhaAoMenosUmTipoAntes =>
      'Choose at least one type before turning it on.';

  @override
  String get importarDaListaBranca => 'Import from whitelist';

  @override
  String get nenhumTipoDoYoutubeNaLista => 'No YouTube type in the whitelist.';

  @override
  String get tiposPorCanalPalavra => 'Types by channel/word';

  @override
  String get filtrosDeConteudoAntiDistracaoPor =>
      'Content filters & anti-distraction by platform (StayFocusd style)';

  @override
  String get configureFiltrosDeCssEHtml =>
      'Set up CSS and HTML filters for each app or social network. Remove dopamine triggers without blocking the sites entirely.';

  @override
  String get detoxGlobalTodosOsSites => 'Global detox (all sites)';

  @override
  String get modoPretoEBrancoGrayscaleDetox =>
      'Black and white mode (grayscale detox)';

  @override
  String get aplicaEscalaDeCinzaEmTodas =>
      'Applies grayscale to every page to discourage compulsive visual consumption.';

  @override
  String get bloquearNotificacoesEBadges => 'Block notifications and badges';

  @override
  String get removeSinosVermelhosEAlertasNumericos =>
      'Removes red bells and number badges on every site to avoid interruptions.';

  @override
  String get youtubeFocus => 'YouTube Focus';

  @override
  String get bloquearYoutubeShorts => 'Block YouTube Shorts';

  @override
  String get ocultaCarrosseisDeShortsNaHome =>
      'Hides Shorts carousels on the home page, in search and in the sidebar.';

  @override
  String get ocultarFeedDaHome => 'Hide home feed';

  @override
  String get ocultaTodasAsRecomendacoesAlgoritmicasDa =>
      'Hides all algorithmic recommendations on the YouTube home page.';

  @override
  String get ocultarVideosRelacionadosBarraLateral =>
      'Hide related videos (sidebar)';

  @override
  String get removeSugestoesDeVideosAoLado =>
      'Removes video suggestions next to the player to avoid distractions.';

  @override
  String get ocultarComentariosDoYoutube => 'Hide YouTube comments';

  @override
  String get ocultaTodaASecaoDeComentarios =>
      'Hides the whole comments section on every video.';

  @override
  String get instagramFocus => 'Instagram Focus';

  @override
  String get bloquearInstagramReels => 'Block Instagram Reels';

  @override
  String get removeAAbaEOCarrossel =>
      'Removes the Reels tab and short-video carousel on Instagram Web.';

  @override
  String get ocultarFeedPrincipalExplore => 'Hide main feed & Explore';

  @override
  String get ocultaOFeedInfinitoDePostagens =>
      'Hides the endless feed of posts and suggestions on the home page.';

  @override
  String get ocultarComentariosDoInstagram => 'Hide Instagram comments';

  @override
  String get ocultaComentariosSobPostagensEVideos =>
      'Hides comments under posts and videos.';

  @override
  String get tiktokFocus => 'TikTok Focus';

  @override
  String get bloquearFeedDeVideosRecomendados =>
      'Block recommended videos feed';

  @override
  String get bloqueiaOFluxoInfinitoDeVideos =>
      'Blocks TikTok\'s endless \"For You\" stream of short videos.';

  @override
  String get redditFocus => 'Reddit Focus';

  @override
  String get bloquearFeedPrincipalPopular => 'Block main / Popular feed';

  @override
  String get ocultaATimelineDePostsInfinitos =>
      'Hides the endless timeline of posts on r/all and the Reddit home page.';

  @override
  String get ocultarSecoesDeComentarios => 'Hide comment sections';

  @override
  String get ocultaAsArvoresDeDiscussaoE =>
      'Hides discussion trees and comments on Reddit posts.';

  @override
  String get bloquearConteudo18Nsfw => 'Block 18+ content (NSFW)';

  @override
  String get escondePostsNsfwNosFeedsE =>
      'Hides NSFW posts in feeds and search and blocks 18+ subreddits and posts. Can\'t be turned off while Anti-Bypass is on.';

  @override
  String get xTwitterFocus => 'X / Twitter Focus';

  @override
  String get bloquearTimelineFeedPrincipal => 'Block timeline / main feed';

  @override
  String get ocultaATimelineParaVoceE =>
      'Hides the \"For you\" and \"Following\" timelines on X (Twitter).';

  @override
  String get ocultarAssuntosDoMomentoTrending => 'Hide trending topics';

  @override
  String get removeABarraLateralDeTendencias =>
      'Removes the trends and exploratory news sidebar.';

  @override
  String get bloquearConteudo18Sensivel => 'Block 18+ content (sensitive)';

  @override
  String get escondePostsComMidiaSensivelE =>
      'Hides posts with sensitive media and blocks profiles marked as sensitive. Can\'t be turned off while Anti-Bypass is on.';

  @override
  String get linkedinFocus => 'LinkedIn Focus';

  @override
  String get bloquearFeedDeNoticiasDoLinkedin => 'Block LinkedIn news feed';

  @override
  String get ocultaATimelineDePostagensPara =>
      'Hides the post timeline so you focus only on messages and profiles.';

  @override
  String get hudFlutuanteNosNavegadoresPilula =>
      'Floating HUD in browsers (pill)';

  @override
  String get opacidadeDaPilulaAlfa => 'Pill opacity (alpha)';

  @override
  String get controlaATransparenciaDaPilulaRecolhida =>
      'Controls the transparency of the collapsed pill and the closed eye in browsers.';

  @override
  String get tamanhoDaPilula => 'Pill size';

  @override
  String get ajustaAEscalaDaPilulaE =>
      'Adjusts the pill scale and the closed-eye diameter (always equal to the pill height).';

  @override
  String get aoEsconderPilulaMostrarIconeDe =>
      'When hiding the pill, show a draggable eye icon';

  @override
  String get quandoAtivoMinimizarTransformaAPilula =>
      'When on, minimizing turns the pill into a draggable round closed-eye button of the same height; when off, it hides completely (Alt+Shift+C shows it again).';

  @override
  String get launchersJogosSteamApiHeroicEpic =>
      'Launchers & games (Steam API, Heroic, Epic, GOG, Lutris)';

  @override
  String get antiCheatAtivoRemocaoBloqueada =>
      'Anti-Bypass on (removal blocked)';

  @override
  String get ativarFiltroEmLaunchersLojasDe =>
      'Turn on filter in launchers & game stores';

  @override
  String get bloqueiaJogosEmExecucaoPaginasDe =>
      'Blocks running games, store pages, guides, discussions and artwork by name or tag via the Steam API. Adding is always allowed; removing requires Anti-Bypass off.';

  @override
  String get antiCheatAtivoDesativeOAnti3 =>
      'Anti-Bypass on: turn off Anti-Bypass to turn off the launcher filter.';

  @override
  String get tagsProibidasSteamApi => 'Forbidden tags (Steam API)';

  @override
  String get buscarTagNaSteamApiEx =>
      'Search a tag on the Steam API (e.g. Action, Souls-like, Horror, FPS)...';

  @override
  String get nomesDeJogosProibidos => 'Forbidden game names';

  @override
  String get buscarJogoNaSteamApiEx =>
      'Search a game on the Steam API (e.g. Counter-Strike 2, Elden Ring)...';

  @override
  String get protegerLojaComunidadeDentroDaSteam =>
      'Protect store/community inside Steam/Heroic (proxy + NSS)';

  @override
  String ocultarJogosDetectadosP0(Object p0) {
    return 'Hide detected games ($p0)';
  }

  @override
  String get consultarJogosDosLaunchersSteamApi =>
      'Look up launcher games (Steam API)';

  @override
  String get nenhumJogoInstaladoDetectadoNosLaunchers =>
      'No installed game detected in local launchers (Steam, Heroic, Lutris, Bottles).';

  @override
  String get bloquearJogo => '+ Block game';

  @override
  String tagCanonicaSteamApiP0(Object p0) {
    return 'Steam API canonical tag: $p0';
  }

  @override
  String get sugestoesSteamApi => 'Steam API suggestions:';

  @override
  String enviaP0ParaASteamApi(Object p0) {
    return 'Sends \"$p0\" to the Steam API';
  }

  @override
  String get desativarTodos => 'Turn all off';

  @override
  String get ativarTodos => 'Turn all on';

  @override
  String get nomeDoFeriado => 'Holiday name';

  @override
  String get exFeriasAniversario => 'E.g. vacation, birthday';

  @override
  String get feriados => 'Holidays';

  @override
  String hojeEFeriadoP0AsCotas(Object p0) {
    return 'Today is a holiday: $p0 — the sessions\' holiday quotas apply.';
  }

  @override
  String get aCotaDeFeriadoEDefinida =>
      'The holiday quota is set in each session (like the weekend one).';

  @override
  String get proximosFeriados => 'Upcoming holidays';

  @override
  String get feriadosPersonalizados => 'Custom holidays';

  @override
  String get comOAntiBurlaLigadoNao =>
      'With Anti-Bypass on you can\'t add holidays (only remove).';

  @override
  String get adicionarUmaDataComACota =>
      'Add a date that uses the sessions\' holiday quota';

  @override
  String get adicionarData => 'Add date';

  @override
  String get antiBurlaLigadoAdicionarFeriadosEsta =>
      'Anti-Bypass on: adding holidays is blocked.';

  @override
  String get nenhum => 'None.';

  @override
  String get remover => 'Remove';

  @override
  String varreduraConcluidaP0ProcessosAuditadosQuarentena(Object p0) {
    return 'Scan finished. $p0 processes audited/quarantined.';
  }

  @override
  String get inspecaoDeBinariosQuarentena => 'Program inspection & quarantine';

  @override
  String get protecaoContraBinariosNaoEmpacotadosPelo =>
      'Protection against programs not packaged by pacman or run outside /usr/bin';

  @override
  String get escanearProcessos => 'Scan processes';

  @override
  String get nenhumProcessoNaoConfiavelEmQuarentena =>
      'No untrusted process in quarantine!';

  @override
  String get cliqueEmEscanearProcessosParaAuditar =>
      'Click \"Scan processes\" to audit running programs outside the official system.';

  @override
  String get aprovarBinario => 'Approve program';

  @override
  String get rejeitarBloquear => 'Reject & block';

  @override
  String get modoAntiCheatAtivo => 'Anti-Bypass mode on!';

  @override
  String oChronosEstaNoModoNuke(Object p0, Object p1) {
    return 'Chronos is in Nuke mode (${p0}m left). You can\'t $p1 until the timer ends.';
  }

  @override
  String naoEPermitidoP0EnquantoO(Object p0) {
    return 'You can\'t $p0 while Anti-Bypass is on. To change rules, first solve the Anti-Bypass strict typing challenge.';
  }

  @override
  String get entendido => 'Understood';

  @override
  String get resolverDesafio => 'Solve challenge';

  @override
  String get desbloquearEntidades => 'unblock items';

  @override
  String get removerRegrasDeBloqueio => 'remove block rules';

  @override
  String get editarTempoDeBloqueioEAgendamento =>
      'edit block time and schedule';

  @override
  String finsDeSemanaP0(Object p0) {
    return 'Weekends: $p0';
  }

  @override
  String tempoDeTelaP0P1P2(Object p0, Object p1, Object p2) {
    return 'Screen time: $p0$p1 • $p2';
  }

  @override
  String get renomear => 'Rename';

  @override
  String get nome => 'Name';

  @override
  String get adicionarAppsOuSitesAoGrupo =>
      'add apps or sites to the group (only renaming is allowed)';

  @override
  String get editarGruposDeListaBranca => 'edit whitelist groups';

  @override
  String get adicionarGruposDeListaBranca => 'add whitelist groups';

  @override
  String get removerGrupoDeListaBranca => 'Remove whitelist group';

  @override
  String get desejaRealmenteRemoverEsteGrupoDe =>
      'Really remove this whitelist group? Its apps and sites will no longer be protected and will be counted or blocked again.';

  @override
  String get removerAplicativoDoGrupoDeBloqueio =>
      'remove an app from the block group';

  @override
  String get removerDoGrupoDeBloqueio => 'Remove from block group';

  @override
  String desejaRealmenteRemoverP0DesteGrupo(Object p0) {
    return 'Really remove \"$p0\" from this block group?';
  }

  @override
  String erroAoRemoverAplicativoP0(Object p0) {
    return 'Error removing app: $p0';
  }

  @override
  String get removerDaListaBranca => 'Remove from whitelist';

  @override
  String desejaRemoverP0DestaListaBranca(Object p0) {
    return 'Remove \"$p0\" from this whitelist? The app will no longer be protected from blocks.';
  }

  @override
  String erroAoRemoverDaListaBranca(Object p0) {
    return 'Error removing from whitelist: $p0';
  }

  @override
  String get t0mBloqueioTotal => '0m (full block)';

  @override
  String p0AplicativoS(Object p0) {
    return '$p0 app(s)';
  }

  @override
  String p0SiteSPalavraS(Object p0) {
    return '$p0 site(s)/word(s)';
  }

  @override
  String get permitirSomente => 'Allow only';

  @override
  String get bloquear => 'Block';

  @override
  String janelaP0P1P2(Object p0, Object p1, Object p2) {
    return 'Window: $p0 $p1-$p2';
  }

  @override
  String get extensaoProtecaoDosNavegadores => 'Extension & browser protection';

  @override
  String get oChronosAplicaAExtensaoEm =>
      'Chronos applies the extension in Chromium browsers and the selective proxy + CA in Firefox, fully offline.';

  @override
  String navegadoresInstaladosDetectadosP0(Object p0) {
    return 'Installed browsers detected ($p0):';
  }

  @override
  String servidorLocalAtivoNaPortaP0(Object p0) {
    return 'Local server running on port $p0';
  }

  @override
  String get chromeAbertoEmChromeExtensionsCole =>
      'Chrome opened at chrome://extensions! Paste the copied path when loading unpacked.';

  @override
  String get firefoxAbertoEmAboutPoliciesPara =>
      'Firefox opened at about:policies to inspect the local policies.';

  @override
  String get terminalAbertoParaAutorizacaoDoChronos =>
      'Terminal opened for the Chronos Guard authorization!';

  @override
  String get comandoCopiadoExecuteNoTerminalPara =>
      'Command copied! Run it in the terminal to install the Guard.';

  @override
  String get configurando => 'Configuring...';

  @override
  String get comandoGuardCopiadoParaOTerminal =>
      'Guard command copied for the terminal!';

  @override
  String sessoesBloqueiosP0(Object p0) {
    return 'Sessions & blocks ($p0)';
  }

  @override
  String listaBrancaWhitelistP0(Object p0) {
    return 'Whitelist ($p0)';
  }

  @override
  String conflitosEncontradosP0(Object p0) {
    return 'Conflicts found ($p0)';
  }

  @override
  String eMaisP0(Object p0) {
    return '… and $p0 more.';
  }

  @override
  String get extensaoWeb => 'Web extension';

  @override
  String get novaSessaoDeBloqueio => 'New block session';

  @override
  String sessoesConfiguradasP0(Object p0) {
    return 'Configured sessions ($p0)';
  }

  @override
  String get nenhumaSessaoCriadaAindaCliqueEm =>
      'No sessions created yet.\nClick \"New block session\" to group apps or sites.';

  @override
  String get catracaTravadaAumentosProibidos =>
      'Ratchet locked (increases forbidden)';

  @override
  String get recolher => 'Collapse';

  @override
  String get expandir => 'Expand';

  @override
  String get editarTempoDeBloqueio => 'Edit block time';

  @override
  String get adicionarAppsSitesAoGrupo => 'Add apps / sites to the group';

  @override
  String get focarNoDashboard => 'Focus on the dashboard';

  @override
  String get desbloquear => 'Unblock';

  @override
  String get bloquearCompletamente => 'Block completely';

  @override
  String get removerSessao => 'Remove session';

  @override
  String get recolherItensDaSessao => 'Collapse session items';

  @override
  String get expandirParaVerTodosOsApps => 'Expand to see every app and site';

  @override
  String get adicionarAplicativosSitesPermitidoNoAnti =>
      'Add apps / sites (allowed with Anti-Bypass)';

  @override
  String get sessaoSelecionada => 'Selected session';

  @override
  String aplicativosBloqueadosP0(Object p0) {
    return 'Blocked apps ($p0):';
  }

  @override
  String removerP0DoGrupoAntiCheat(Object p0) {
    return 'Remove $p0 from the group (Anti-Bypass restricted)';
  }

  @override
  String sitesEPalavrasChaveBloqueadosP0(Object p0) {
    return 'Blocked sites and keywords ($p0):';
  }

  @override
  String get nenhumAplicativoOuSiteListadoNesta =>
      'No app or site listed in this session.';

  @override
  String gruposDeListaBrancaP0(Object p0) {
    return 'Whitelist groups ($p0)';
  }

  @override
  String get nenhumGrupoDeListaBrancaCriado =>
      'No whitelist group created.\nWhitelisted apps and sites are protected from blocks and closing.';

  @override
  String get protecaoTotal => 'FULL PROTECTION';

  @override
  String p0TiposYoutube(Object p0) {
    return '$p0 YouTube types';
  }

  @override
  String get itensProtegidosContraContagemDeTempo =>
      'Items protected from screen time counting and automatic closing';

  @override
  String youtubePermitidoP0(Object p0) {
    return 'YouTube allowed: $p0';
  }

  @override
  String get recolherItens => 'Collapse items';

  @override
  String get expandirItens => 'Expand items';

  @override
  String get editarGrupo => 'Edit group';

  @override
  String get removerGrupo => 'Remove group';

  @override
  String aplicativosProtegidosP0(Object p0) {
    return 'Protected apps ($p0):';
  }

  @override
  String removerP0DaListaBranca(Object p0) {
    return 'Remove $p0 from the whitelist';
  }

  @override
  String sitesEPalavrasProtegidosP0(Object p0) {
    return 'Protected sites and words ($p0):';
  }

  @override
  String tiposDoYoutubePermitidosP0(Object p0) {
    return 'Allowed YouTube types ($p0):';
  }

  @override
  String get registroDeBurlas => 'Tampering log';

  @override
  String get cofreDoChronosAtivoComO =>
      'Chronos vault on: with Anti-Bypass on, editing the database, stopping the service, deleting the autostart or changing the clock is undone in seconds and recorded here.';

  @override
  String get cofreDoChronosNaoInstaladoInstale =>
      'Chronos vault not installed: install/update the browser protection (Chronos Guard) to turn on the Anti-Bypass layers.';

  @override
  String relogioDoSistemaCorrigidoEmP0(Object p0) {
    return 'System clock corrected by $p0 min (Chronos uses the trusted time).';
  }

  @override
  String penalidadeAtivaTodasAsSessoesBloqueadas(Object p0) {
    return 'Penalty active: every session blocked until $p0.';
  }

  @override
  String get aoDetectarUmaBurla => 'When tampering is detected';

  @override
  String get restaurarERegistrar => 'Restore and record';

  @override
  String get restaurarRegistrarEBloquearTudoAte =>
      'Restore, record and block everything until midnight';

  @override
  String get comOAntiBurlaAtivoNao =>
      'With Anti-Bypass on you can\'t switch back to the lighter option.';

  @override
  String get nenhumaTentativaDeBurlaRegistrada =>
      'No tampering attempts recorded.';

  @override
  String get bancoEditado => 'Database edited';

  @override
  String get bancoApagado => 'Database deleted';

  @override
  String get servicoParado => 'Service stopped';

  @override
  String get servicoApagado => 'Service deleted';

  @override
  String get autostartApagado => 'Autostart deleted';

  @override
  String get relogioAlterado => 'Clock changed';

  @override
  String get desbloqueioRecusado => 'Unlock refused';

  @override
  String get historicoDeBurlas => 'Tampering history';

  @override
  String p0EventoS(Object p0) {
    return '$p0 event(s)';
  }

  @override
  String get nenhumaBurlaNestePeriodo => 'No tampering in this period.';

  @override
  String get naoEPossivelDesinstalar => 'Can\'t uninstall';

  @override
  String get oAntiBurlaEstaAtivoEnquanto =>
      'Anti-Bypass is on. While it is on, Chronos can\'t be closed or uninstalled.';

  @override
  String get desinstalarOChronos => 'Uninstall Chronos?';

  @override
  String get istoRemoveOChronosDoComputador =>
      'This removes Chronos from the computer: the background app, the browser extension, the system protection (may ask for your password), autostart and the Chronos service.';

  @override
  String get apagarTambemMeusDados => 'Also delete my data';

  @override
  String get regrasHistoricoDeUsoEConfiguracoes =>
      'Rules, usage history and settings. Without this they stay saved for a reinstall.';

  @override
  String get desinstalar => 'Uninstall';

  @override
  String get atualizacaoAutomaticaSoFuncionaNaVersao =>
      'Automatic updates only work in the installed version (not in development builds).';

  @override
  String oChronosJaEstaNaVersao(Object p0) {
    return 'Chronos is already on the latest version ($p0).';
  }

  @override
  String get baixando => 'Downloading…';

  @override
  String get verificandoAssinatura => 'Checking signature…';

  @override
  String get instalando => 'Installing…';

  @override
  String get atualizandoAProtecaoDoSistemaPode =>
      'Updating the system protection (may ask for your password)…';

  @override
  String get reiniciandoOChronos => 'Restarting Chronos…';

  @override
  String get aProtecaoDoSistemaGuardNao =>
      'The system protection (Guard) wasn\'t updated now. You can update it later in Settings.';

  @override
  String novaVersaoDoChronosP0(Object p0) {
    return 'New Chronos version: $p0';
  }

  @override
  String voceEstaNaVersaoP0Deseja(Object p0) {
    return 'You are on version $p0. Update now?';
  }

  @override
  String falhaNaAtualizacaoP0(Object p0) {
    return 'Update failed: $p0';
  }

  @override
  String get depois => 'Later';

  @override
  String get tentarNovamente => 'Try again';

  @override
  String get atualizarAgora => 'Update now';

  @override
  String get deUmNomeAoTipoNovo => 'Give the new type a name.';

  @override
  String get tiposDoYoutubePorCanalOu => 'YouTube types by channel or word';

  @override
  String get exCanalFlowPodcastContaComo =>
      'E.g. the channel \"Flow Podcast\" counts as Podcasts; the word \"minecraft\" creates the type \"Minecraft\". Separate several channels or words with commas.';

  @override
  String get tipo => 'Type';

  @override
  String get novoTipo => 'New type…';

  @override
  String get nomeDoTipo => 'Type name';

  @override
  String get canais => 'Channels';

  @override
  String get palavrasNoTituloTags => 'Words in title/tags';

  @override
  String get adicionarRegra => 'Add rule';

  @override
  String hojeP0(Object p0) {
    return ' Today: $p0.';
  }

  @override
  String get escolhaDosPaisSuffix => ' (parents\' choice)';

  @override
  String get guiaAnonimaSeraBloqueadaSuffix =>
      ' — incognito will be blocked again';

  @override
  String get safesearchNosNavegadoresSuffix => ' + SafeSearch in browsers';

  @override
  String get todosOsNavegadoresJaPermitemAnonimo =>
      'Every browser already allows the extension in incognito.';

  @override
  String get iaDeImagensNaTelaInteira => 'Whole-screen image AI (local)';

  @override
  String get iaTelaInteiraDescricao =>
      'Checks the focused window every ~2 s in any app (not only browsers) and covers the screen if +18 content shows up. Everything stays on this computer; nothing is saved. Uses some CPU.';

  @override
  String get iaTelaInteiraNaoSuportada =>
      'Only available on Hyprland with grim installed.';

  @override
  String get conteudoAdultoDetectadoNaTela => '+18 content detected';

  @override
  String coberturaTelaTexto(String window) {
    return 'Chronos found adult content in the window \"$window\". Close or change it before going back.';
  }

  @override
  String get entendiVoltar => 'Got it, go back';

  @override
  String appBloqueadoTitulo(String app) {
    return '$app is blocked';
  }

  @override
  String get motivoQuota => 'Today\'s time limit is used up.';

  @override
  String get motivoJanela => 'This time of day is blocked.';

  @override
  String get motivoForcado => 'This app is fully blocked.';

  @override
  String get motivoPenalidade => 'Penalty active after a bypass attempt.';

  @override
  String get motivoLazer => 'Mandatory leisure break in progress.';

  @override
  String get appFechadoPeloChronos => 'Chronos closed the app.';

  @override
  String get extVersaoAtualizada => '(up to date)';

  @override
  String extVersaoPendente(String version) {
    return '→ $version pending';
  }

  @override
  String extFirefoxPrecisaAssinar(String version) {
    return '→ $version waiting for Mozilla signing (run scripts/run-release.sh)';
  }

  @override
  String extVersaoDisponivel(String version) {
    return 'Available version: $version';
  }

  @override
  String get contaDaCriancaProtegida => 'Protected child account';

  @override
  String contaProtegidaDescricao(String user) {
    return 'The account \"$user\" is not an administrator: it can\'t remove Chronos. Wi-Fi, USB drives, printers, Bluetooth, power off and installing apps from the official repositories still work.';
  }

  @override
  String contaEhAdministradoraAviso(String user) {
    return 'The account \"$user\" is an administrator (sudo) and can remove Chronos as root. Protect it: it stops being an administrator and Chronos allows only everyday actions. Asks for another administrator\'s password (the guardian\'s).';
  }

  @override
  String contaSemAdministrador(String user) {
    return 'The account \"$user\" is already not an administrator: it can\'t remove Chronos.';
  }

  @override
  String get protegerEstaConta => 'Protect this account';

  @override
  String get devolverAdministrador => 'Give administrator access back';

  @override
  String get feitoValeNoProximoLogin => 'Done. Takes effect at the next login.';

  @override
  String get guardNaoInstaladoAtiveAProtecao =>
      'Chronos Guard is not installed: turn on browser protection first.';

  @override
  String get autorizacaoCancelada => 'Authorization cancelled.';

  @override
  String get textosDesafioExplicacao =>
      'Your texts replace the default ones: the challenge draws only from them. Without your own, it uses the defaults. At least 120 characters each. Can\'t be changed while Anti-Bypass is on.';

  @override
  String get recusarTextosFaceis => 'Refuse texts that are too easy';

  @override
  String get recusarTextosFaceisDescricao =>
      'Blocks texts with repeated words, few different letters, keyboard sequences or chunks copied several times.';

  @override
  String get semTextosUsaOsPadrao =>
      'No texts of your own: the challenge uses the default texts.';

  @override
  String get adicionarTexto => 'Add text';

  @override
  String get editarTexto => 'Edit text';

  @override
  String p0Caracteres(int count) {
    return '$count characters';
  }

  @override
  String get textoAprovado => 'Text accepted.';

  @override
  String get ok => 'OK';
}
