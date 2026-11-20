import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @chronosAntiCheatStrictFocusEngine.
  ///
  /// In pt, this message translates to:
  /// **'Chronos - Anti-Burla & Strict Focus Engine'**
  String get chronosAntiCheatStrictFocusEngine;

  /// No description provided for @chronosFocusEngine.
  ///
  /// In pt, this message translates to:
  /// **'Chronos Focus Engine'**
  String get chronosFocusEngine;

  /// No description provided for @reiniciarBancoDeDados.
  ///
  /// In pt, this message translates to:
  /// **'Reiniciar Banco de Dados?'**
  String get reiniciarBancoDeDados;

  /// No description provided for @desejaResetarCompletamenteOSqliteIntervalos.
  ///
  /// In pt, this message translates to:
  /// **'Deseja resetar completamente o SQLite? Intervalos serão limpos, a catraca será destravada e a configuração inicial será reiniciada.'**
  String get desejaResetarCompletamenteOSqliteIntervalos;

  /// No description provided for @cancelar.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get cancelar;

  /// No description provided for @reiniciarTudo.
  ///
  /// In pt, this message translates to:
  /// **'Reiniciar Tudo'**
  String get reiniciarTudo;

  /// No description provided for @parentalPai.
  ///
  /// In pt, this message translates to:
  /// **'Parental (Pai)'**
  String get parentalPai;

  /// No description provided for @parentalFilho.
  ///
  /// In pt, this message translates to:
  /// **'Parental (Filho)'**
  String get parentalFilho;

  /// No description provided for @autoControle.
  ///
  /// In pt, this message translates to:
  /// **'Auto-Controle'**
  String get autoControle;

  /// No description provided for @focoP0.
  ///
  /// In pt, this message translates to:
  /// **'Foco: {p0}'**
  String focoP0(Object p0);

  /// No description provided for @autoDeteccaoAtiva.
  ///
  /// In pt, this message translates to:
  /// **'Auto-Detecção Ativa'**
  String get autoDeteccaoAtiva;

  /// No description provided for @deteccaoAutomatica.
  ///
  /// In pt, this message translates to:
  /// **'Detecção Automática'**
  String get deteccaoAutomatica;

  /// No description provided for @antiCheatOff.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla: OFF'**
  String get antiCheatOff;

  /// No description provided for @nukeP0DP1.
  ///
  /// In pt, this message translates to:
  /// **'Nuke: {p0}d {p1}'**
  String nukeP0DP1(Object p0, Object p1);

  /// No description provided for @nukeP0.
  ///
  /// In pt, this message translates to:
  /// **'Nuke: {p0}'**
  String nukeP0(Object p0);

  /// No description provided for @antiCheatAtivo.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla Ativo'**
  String get antiCheatAtivo;

  /// No description provided for @refazerCadastroTrocarModo.
  ///
  /// In pt, this message translates to:
  /// **'Refazer Cadastro / Trocar Modo'**
  String get refazerCadastroTrocarModo;

  /// No description provided for @instalarExtensoesNosNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Instalar Extensões nos Navegadores'**
  String get instalarExtensoesNosNavegadores;

  /// No description provided for @sairDoAntiCheatDebug.
  ///
  /// In pt, this message translates to:
  /// **'🛠️ Sair do Anti-Burla (Debug)'**
  String get sairDoAntiCheatDebug;

  /// No description provided for @reiniciarBancoCompleto.
  ///
  /// In pt, this message translates to:
  /// **'Reiniciar Banco Completo'**
  String get reiniciarBancoCompleto;

  /// No description provided for @zerarConsumoDiario.
  ///
  /// In pt, this message translates to:
  /// **'Zerar Consumo Diário'**
  String get zerarConsumoDiario;

  /// No description provided for @destravarCatracaP0.
  ///
  /// In pt, this message translates to:
  /// **'Destravar Catraca ({p0})'**
  String destravarCatracaP0(Object p0);

  /// No description provided for @restaurarTokens2.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar Tokens (+2)'**
  String get restaurarTokens2;

  /// No description provided for @tempoDeTela.
  ///
  /// In pt, this message translates to:
  /// **'Tempo de Tela'**
  String get tempoDeTela;

  /// No description provided for @monitorEmTempoReal.
  ///
  /// In pt, this message translates to:
  /// **'Monitor em tempo real'**
  String get monitorEmTempoReal;

  /// No description provided for @estatisticas.
  ///
  /// In pt, this message translates to:
  /// **'Estatísticas'**
  String get estatisticas;

  /// No description provided for @metricasDeConsumo.
  ///
  /// In pt, this message translates to:
  /// **'Métricas de consumo'**
  String get metricasDeConsumo;

  /// No description provided for @regrasWhitelist.
  ///
  /// In pt, this message translates to:
  /// **'Regras & Whitelist'**
  String get regrasWhitelist;

  /// No description provided for @limitesEGrupos.
  ///
  /// In pt, this message translates to:
  /// **'Limites e grupos'**
  String get limitesEGrupos;

  /// No description provided for @configuracoes.
  ///
  /// In pt, this message translates to:
  /// **'Configurações'**
  String get configuracoes;

  /// No description provided for @aparenciaEAlertas.
  ///
  /// In pt, this message translates to:
  /// **'Aparência e alertas'**
  String get aparenciaEAlertas;

  /// No description provided for @quarentena.
  ///
  /// In pt, this message translates to:
  /// **'Quarentena'**
  String get quarentena;

  /// No description provided for @modoNukeBloqueios.
  ///
  /// In pt, this message translates to:
  /// **'Modo nuke & bloqueios'**
  String get modoNukeBloqueios;

  /// No description provided for @sqliteTestes.
  ///
  /// In pt, this message translates to:
  /// **'SQLite / Testes'**
  String get sqliteTestes;

  /// No description provided for @depuracaoDoBanco.
  ///
  /// In pt, this message translates to:
  /// **'Depuração do banco'**
  String get depuracaoDoBanco;

  /// No description provided for @chronos.
  ///
  /// In pt, this message translates to:
  /// **'Chronos'**
  String get chronos;

  /// No description provided for @focusEngine.
  ///
  /// In pt, this message translates to:
  /// **'Focus Engine'**
  String get focusEngine;

  /// No description provided for @alternarParaModoClaro.
  ///
  /// In pt, this message translates to:
  /// **'Alternar para Modo Claro'**
  String get alternarParaModoClaro;

  /// No description provided for @alternarParaModoEscuro.
  ///
  /// In pt, this message translates to:
  /// **'Alternar para Modo Escuro'**
  String get alternarParaModoEscuro;

  /// No description provided for @modoClaro.
  ///
  /// In pt, this message translates to:
  /// **'Modo Claro'**
  String get modoClaro;

  /// No description provided for @modoEscuro.
  ///
  /// In pt, this message translates to:
  /// **'Modo Escuro'**
  String get modoEscuro;

  /// No description provided for @estatisticasDeConsumoHistorico.
  ///
  /// In pt, this message translates to:
  /// **'Estatísticas de Consumo & Histórico'**
  String get estatisticasDeConsumoHistorico;

  /// No description provided for @regrasDeBloqueioWhitelist.
  ///
  /// In pt, this message translates to:
  /// **'Regras de Bloqueio & Whitelist'**
  String get regrasDeBloqueioWhitelist;

  /// No description provided for @configuracoesGeraisNotificacoes.
  ///
  /// In pt, this message translates to:
  /// **'Configurações Gerais & Notificações'**
  String get configuracoesGeraisNotificacoes;

  /// No description provided for @quarentenaModoNuke.
  ///
  /// In pt, this message translates to:
  /// **'Quarentena & Modo Nuke'**
  String get quarentenaModoNuke;

  /// No description provided for @bancoDeDadosTestesSqlite.
  ///
  /// In pt, this message translates to:
  /// **'Banco de Dados & Testes SQLite'**
  String get bancoDeDadosTestesSqlite;

  /// No description provided for @debugSairDoAntiCheat.
  ///
  /// In pt, this message translates to:
  /// **'🛠️ [DEBUG] Sair do Anti-Burla'**
  String get debugSairDoAntiCheat;

  /// No description provided for @instalarExtensoesEmNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Instalar Extensões em Navegadores'**
  String get instalarExtensoesEmNavegadores;

  /// No description provided for @acoesGlobais.
  ///
  /// In pt, this message translates to:
  /// **'Ações Globais'**
  String get acoesGlobais;

  /// No description provided for @telaDeCadastro.
  ///
  /// In pt, this message translates to:
  /// **'Tela de Cadastro'**
  String get telaDeCadastro;

  /// No description provided for @debugSairDoAntiCheatImediatamente.
  ///
  /// In pt, this message translates to:
  /// **'🛠️ [DEBUG] Sair do Anti-Burla Imediatamente'**
  String get debugSairDoAntiCheatImediatamente;

  /// No description provided for @instalarExtensoesEmTodosNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Instalar Extensões em Todos Navegadores'**
  String get instalarExtensoesEmTodosNavegadores;

  /// No description provided for @acoesConfiguracao.
  ///
  /// In pt, this message translates to:
  /// **'Ações & Configuração'**
  String get acoesConfiguracao;

  /// No description provided for @tempo.
  ///
  /// In pt, this message translates to:
  /// **'Tempo'**
  String get tempo;

  /// No description provided for @metricas.
  ///
  /// In pt, this message translates to:
  /// **'Métricas'**
  String get metricas;

  /// No description provided for @regras.
  ///
  /// In pt, this message translates to:
  /// **'Regras'**
  String get regras;

  /// No description provided for @ajustes.
  ///
  /// In pt, this message translates to:
  /// **'Ajustes'**
  String get ajustes;

  /// No description provided for @nuke.
  ///
  /// In pt, this message translates to:
  /// **'Nuke'**
  String get nuke;

  /// No description provided for @sqlite.
  ///
  /// In pt, this message translates to:
  /// **'SQLite'**
  String get sqlite;

  /// No description provided for @sincronizandoComOMotorDeMonitoramento.
  ///
  /// In pt, this message translates to:
  /// **'Sincronizando com o motor de monitoramento...'**
  String get sincronizandoComOMotorDeMonitoramento;

  /// No description provided for @tentarConectarAgora.
  ///
  /// In pt, this message translates to:
  /// **'Tentar Conectar Agora'**
  String get tentarConectarAgora;

  /// No description provided for @etapaInicialTesteAQualquerMomento.
  ///
  /// In pt, this message translates to:
  /// **'Etapa Inicial: teste a qualquer momento o cadastro e personalização de bloqueios.'**
  String get etapaInicialTesteAQualquerMomento;

  /// No description provided for @voltarAoCadastro.
  ///
  /// In pt, this message translates to:
  /// **'Voltar ao Cadastro'**
  String get voltarAoCadastro;

  /// No description provided for @p0SessoesAtivasSimultaneamenteOTempo.
  ///
  /// In pt, this message translates to:
  /// **'⚡ {p0} Sessões Ativas Simultaneamente! O tempo de tela está sendo cronometrado em paralelo.'**
  String p0SessoesAtivasSimultaneamenteOTempo(Object p0);

  /// No description provided for @sessao.
  ///
  /// In pt, this message translates to:
  /// **'Sessão'**
  String get sessao;

  /// No description provided for @emExecucao.
  ///
  /// In pt, this message translates to:
  /// **'Em execução'**
  String get emExecucao;

  /// No description provided for @tempoAtivo.
  ///
  /// In pt, this message translates to:
  /// **'TEMPO ATIVO'**
  String get tempoAtivo;

  /// No description provided for @consumidoHojeP0.
  ///
  /// In pt, this message translates to:
  /// **'Consumido hoje: {p0}'**
  String consumidoHojeP0(Object p0);

  /// No description provided for @limiteP0P1.
  ///
  /// In pt, this message translates to:
  /// **'Limite: {p0} ({p1}%)'**
  String limiteP0P1(Object p0, Object p1);

  /// No description provided for @catracaAtiva.
  ///
  /// In pt, this message translates to:
  /// **'Catraca Ativa'**
  String get catracaAtiva;

  /// No description provided for @tokensP02.
  ///
  /// In pt, this message translates to:
  /// **'Tokens: {p0}/2'**
  String tokensP02(Object p0);

  /// No description provided for @limiteDeTempoDeTelaP0.
  ///
  /// In pt, this message translates to:
  /// **'Limite de tempo de tela: {p0} ({p1}%)'**
  String limiteDeTempoDeTelaP0(Object p0, Object p1);

  /// No description provided for @controlesDeTempoDeTelaCatraca.
  ///
  /// In pt, this message translates to:
  /// **'Controles de Tempo de Tela & Catraca (Ratchet)'**
  String get controlesDeTempoDeTelaCatraca;

  /// No description provided for @reduzirTempoDeTelaTeste15s.
  ///
  /// In pt, this message translates to:
  /// **'Reduzir Tempo de Tela (Teste 15s)'**
  String get reduzirTempoDeTelaTeste15s;

  /// No description provided for @tentarAumentarTempoDeTela2h.
  ///
  /// In pt, this message translates to:
  /// **'Tentar Aumentar Tempo de Tela (+2h)'**
  String get tentarAumentarTempoDeTela2h;

  /// No description provided for @trancarCatraca24h.
  ///
  /// In pt, this message translates to:
  /// **'Trancar Catraca (24h)'**
  String get trancarCatraca24h;

  /// No description provided for @catracaTrancadaPor24hAumentosProibidos.
  ///
  /// In pt, this message translates to:
  /// **'Catraca trancada por 24h! Aumentos proibidos.'**
  String get catracaTrancadaPor24hAumentosProibidos;

  /// No description provided for @usarTokenDeEmergencia1h.
  ///
  /// In pt, this message translates to:
  /// **'Usar Token de Emergência (+1h)'**
  String get usarTokenDeEmergencia1h;

  /// No description provided for @bemVindoAoChronos.
  ///
  /// In pt, this message translates to:
  /// **'Bem-vindo ao Chronos'**
  String get bemVindoAoChronos;

  /// No description provided for @seuMotorDeFocoEstritoE.
  ///
  /// In pt, this message translates to:
  /// **'Seu motor de foco estrito e produtividade para Linux.\nComo você pretende utilizar este aplicativo?'**
  String get seuMotorDeFocoEstritoE;

  /// No description provided for @controlePessoalAutoControle.
  ///
  /// In pt, this message translates to:
  /// **'Controle Pessoal (Auto-Controle)'**
  String get controlePessoalAutoControle;

  /// No description provided for @paraGerenciarSeuProprioTempoE.
  ///
  /// In pt, this message translates to:
  /// **'Para gerenciar seu próprio tempo e estudos.'**
  String get paraGerenciarSeuProprioTempoE;

  /// No description provided for @modoCatracaRatchetReducoesSaoImediatas.
  ///
  /// In pt, this message translates to:
  /// **'Modo Catraca (Ratchet): Reduções são imediatas, aumentos são bloqueados.'**
  String get modoCatracaRatchetReducoesSaoImediatas;

  /// No description provided for @t2TokensMensaisDeEmergencia1h.
  ///
  /// In pt, this message translates to:
  /// **'2 Tokens mensais de emergência (+1h com penalidade de 24h de lazer travado).'**
  String get t2TokensMensaisDeEmergencia1h;

  /// No description provided for @bloqueioAtivoComSobreposicaoDeJanela.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueio ativo com sobreposição de janela e pausa automática de mídia.'**
  String get bloqueioAtivoComSobreposicaoDeJanela;

  /// No description provided for @configurarBloqueiosPessoais.
  ///
  /// In pt, this message translates to:
  /// **'Configurar Bloqueios Pessoais'**
  String get configurarBloqueiosPessoais;

  /// No description provided for @controleParentalSupervisao.
  ///
  /// In pt, this message translates to:
  /// **'Controle Parental (Supervisão)'**
  String get controleParentalSupervisao;

  /// No description provided for @paraPaisEResponsaveisGerenciaremDispositivos.
  ///
  /// In pt, this message translates to:
  /// **'Para pais e responsáveis gerenciarem dispositivos de dependentes.'**
  String get paraPaisEResponsaveisGerenciaremDispositivos;

  /// No description provided for @dispositivoDoDependenteProtegidoContraAlteracoes.
  ///
  /// In pt, this message translates to:
  /// **'Dispositivo do dependente protegido contra alterações e desvios.'**
  String get dispositivoDoDependenteProtegidoContraAlteracoes;

  /// No description provided for @pareamentoSeguroViaQrCodeOu.
  ///
  /// In pt, this message translates to:
  /// **'Pareamento seguro via QR Code ou Senha mestra.'**
  String get pareamentoSeguroViaQrCodeOu;

  /// No description provided for @gestaoDeAprovacaoDeBinariosE.
  ///
  /// In pt, this message translates to:
  /// **'Gestão de aprovação de binários e quarentena de aplicativos.'**
  String get gestaoDeAprovacaoDeBinariosE;

  /// No description provided for @configurarControleParental.
  ///
  /// In pt, this message translates to:
  /// **'Configurar Controle Parental'**
  String get configurarControleParental;

  /// No description provided for @personalizacaoDeBloqueioTempoDeTela.
  ///
  /// In pt, this message translates to:
  /// **'Personalização de Bloqueio & Tempo de Tela'**
  String get personalizacaoDeBloqueioTempoDeTela;

  /// No description provided for @ajusteOTempoDeTelaDiario.
  ///
  /// In pt, this message translates to:
  /// **'Ajuste o tempo de tela diário inicial e o nível de atrito estrito'**
  String get ajusteOTempoDeTelaDiario;

  /// No description provided for @distracoesABloquear.
  ///
  /// In pt, this message translates to:
  /// **'Distrações a Bloquear'**
  String get distracoesABloquear;

  /// No description provided for @adicionarAppOuSite.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar App ou Site'**
  String get adicionarAppOuSite;

  /// No description provided for @nenhumaSessaoPreConfiguradaCliqueEm.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma sessão pré-configurada.\nClique em \"Adicionar App ou Site\" acima para criar suas sessões personalizadas.'**
  String get nenhumaSessaoPreConfiguradaCliqueEm;

  /// No description provided for @tempoDeTelaDiario.
  ///
  /// In pt, this message translates to:
  /// **'Tempo de Tela Diário:'**
  String get tempoDeTelaDiario;

  /// No description provided for @bloqueioTotal.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueio Total'**
  String get bloqueioTotal;

  /// No description provided for @t15Min.
  ///
  /// In pt, this message translates to:
  /// **'15 min'**
  String get t15Min;

  /// No description provided for @t30Min.
  ///
  /// In pt, this message translates to:
  /// **'30 min'**
  String get t30Min;

  /// No description provided for @t1Hora.
  ///
  /// In pt, this message translates to:
  /// **'1 hora'**
  String get t1Hora;

  /// No description provided for @t2Horas.
  ///
  /// In pt, this message translates to:
  /// **'2 horas'**
  String get t2Horas;

  /// No description provided for @diretrizesDeEnforcementDoChronos.
  ///
  /// In pt, this message translates to:
  /// **'Diretrizes de Enforcement do Chronos'**
  String get diretrizesDeEnforcementDoChronos;

  /// No description provided for @ativarTravaDaCatraca24hIniciais.
  ///
  /// In pt, this message translates to:
  /// **'Ativar Trava da Catraca (24h iniciais)'**
  String get ativarTravaDaCatraca24hIniciais;

  /// No description provided for @impedeAumentosDeTempoDeTela.
  ///
  /// In pt, this message translates to:
  /// **'Impede aumentos de tempo de tela logo no primeiro dia. Você só poderá reduzir o tempo de tela.'**
  String get impedeAumentosDeTempoDeTela;

  /// No description provided for @sequestroVisualDeFocoAlwaysOn.
  ///
  /// In pt, this message translates to:
  /// **'Sequestro Visual de Foco (Always-on-top Fullscreen)'**
  String get sequestroVisualDeFocoAlwaysOn;

  /// No description provided for @maximizaETravaAJanelaDo.
  ///
  /// In pt, this message translates to:
  /// **'Maximiza e trava a janela do Chronos por cima ao estourar o tempo de tela.'**
  String get maximizaETravaAJanelaDo;

  /// No description provided for @pausaAtivaDeMidiaPlayerctlMpris2.
  ///
  /// In pt, this message translates to:
  /// **'Pausa Ativa de Mídia (playerctl / MPRIS2)'**
  String get pausaAtivaDeMidiaPlayerctlMpris2;

  /// No description provided for @interrompeAutomaticamenteVideosEMusicasEm.
  ///
  /// In pt, this message translates to:
  /// **'Interrompe automaticamente vídeos e músicas em segundo plano.'**
  String get interrompeAutomaticamenteVideosEMusicasEm;

  /// No description provided for @salvarBloqueiosEIniciarChronos.
  ///
  /// In pt, this message translates to:
  /// **'Salvar Bloqueios e Iniciar Chronos'**
  String get salvarBloqueiosEIniciarChronos;

  /// No description provided for @controleParental.
  ///
  /// In pt, this message translates to:
  /// **'Controle Parental'**
  String get controleParental;

  /// No description provided for @qualEOPapelDesteComputador.
  ///
  /// In pt, this message translates to:
  /// **'Qual é o papel deste computador na família?'**
  String get qualEOPapelDesteComputador;

  /// No description provided for @dispositivoDoResponsavelPaiMae.
  ///
  /// In pt, this message translates to:
  /// **'Dispositivo do Responsável (Pai / Mãe)'**
  String get dispositivoDoResponsavelPaiMae;

  /// No description provided for @esteComputadorTeraAutoridadeParaControlar.
  ///
  /// In pt, this message translates to:
  /// **'Este computador terá autoridade para controlar regras e tempo de tela.'**
  String get esteComputadorTeraAutoridadeParaControlar;

  /// No description provided for @recebeSolicitacoesDeEmergenciaEAprovacoes.
  ///
  /// In pt, this message translates to:
  /// **'Recebe solicitações de emergência e aprovações de quarentena.'**
  String get recebeSolicitacoesDeEmergenciaEAprovacoes;

  /// No description provided for @conectaAoComputadorDoFilhoUsando.
  ///
  /// In pt, this message translates to:
  /// **'Conecta ao computador do filho usando QR Code ou Senha.'**
  String get conectaAoComputadorDoFilhoUsando;

  /// No description provided for @configurarComoDispositivoPai.
  ///
  /// In pt, this message translates to:
  /// **'Configurar como Dispositivo Pai'**
  String get configurarComoDispositivoPai;

  /// No description provided for @dispositivoDoDependenteFilho.
  ///
  /// In pt, this message translates to:
  /// **'Dispositivo do Dependente (Filho)'**
  String get dispositivoDoDependenteFilho;

  /// No description provided for @esteComputadorSeraMonitoradoEProtegido.
  ///
  /// In pt, this message translates to:
  /// **'Este computador será monitorado e protegido contra distrações.'**
  String get esteComputadorSeraMonitoradoEProtegido;

  /// No description provided for @asAlteracoesDeTempoDeTela.
  ///
  /// In pt, this message translates to:
  /// **'As alterações de tempo de tela exigem autorização ou senha do responsável.'**
  String get asAlteracoesDeTempoDeTela;

  /// No description provided for @exibeQrCodeECodigoPin.
  ///
  /// In pt, this message translates to:
  /// **'Exibe QR Code e código PIN para ser conectado pelo responsável.'**
  String get exibeQrCodeECodigoPin;

  /// No description provided for @configurarComoDispositivoFilho.
  ///
  /// In pt, this message translates to:
  /// **'Configurar como Dispositivo Filho'**
  String get configurarComoDispositivoFilho;

  /// No description provided for @chronosPairCodeP0.
  ///
  /// In pt, this message translates to:
  /// **'chronos://pair?code={p0}'**
  String chronosPairCodeP0(Object p0);

  /// No description provided for @pareamentoDispositivoFilho.
  ///
  /// In pt, this message translates to:
  /// **'Pareamento: Dispositivo Filho'**
  String get pareamentoDispositivoFilho;

  /// No description provided for @pareamentoDispositivoDoResponsavel.
  ///
  /// In pt, this message translates to:
  /// **'Pareamento: Dispositivo do Responsável'**
  String get pareamentoDispositivoDoResponsavel;

  /// No description provided for @conecteEsteComputadorAoAplicativoDo.
  ///
  /// In pt, this message translates to:
  /// **'Conecte este computador ao aplicativo do responsável utilizando QR Code ou Código PIN/Senha.'**
  String get conecteEsteComputadorAoAplicativoDo;

  /// No description provided for @escaneieOQrCodeOuInsira.
  ///
  /// In pt, this message translates to:
  /// **'Escaneie o QR Code ou insira o Código PIN exibido na tela do dispositivo do filho.'**
  String get escaneieOQrCodeOuInsira;

  /// No description provided for @viaQrCode.
  ///
  /// In pt, this message translates to:
  /// **'Via QR Code'**
  String get viaQrCode;

  /// No description provided for @viaSenhaPin.
  ///
  /// In pt, this message translates to:
  /// **'Via Senha / PIN'**
  String get viaSenhaPin;

  /// No description provided for @concluirEIniciarProtecao.
  ///
  /// In pt, this message translates to:
  /// **'Concluir e Iniciar Proteção'**
  String get concluirEIniciarProtecao;

  /// No description provided for @concluirEAbrirPainelDoResponsavel.
  ///
  /// In pt, this message translates to:
  /// **'Concluir e Abrir Painel do Responsável'**
  String get concluirEAbrirPainelDoResponsavel;

  /// No description provided for @protecaoObrigatoriaEmTodosOsNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Proteção Obrigatória em Todos os Navegadores'**
  String get protecaoObrigatoriaEmTodosOsNavegadores;

  /// No description provided for @configuraTodosOsNavegadoresDoDispositivo.
  ///
  /// In pt, this message translates to:
  /// **'Configura todos os navegadores do dispositivo para exibir o tempo restante de uso e aplicar filtros HTML/CSS (Shorts, Feed da Home, Grayscale). A remoção só é liberada após verificação Anti-Burla.'**
  String get configuraTodosOsNavegadoresDoDispositivo;

  /// No description provided for @instalandoConfigurando.
  ///
  /// In pt, this message translates to:
  /// **'Instalando & Configurando...'**
  String get instalandoConfigurando;

  /// No description provided for @instalarAtualizarEmTodosOsNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Instalar / Atualizar em Todos os Navegadores'**
  String get instalarAtualizarEmTodosOsNavegadores;

  /// No description provided for @terminalAbertoDigiteSuaSenhaSudo.
  ///
  /// In pt, this message translates to:
  /// **'Terminal aberto! Digite sua senha sudo uma vez para concluir o Guard.'**
  String get terminalAbertoDigiteSuaSenhaSudo;

  /// No description provided for @executeManualmenteP0.
  ///
  /// In pt, this message translates to:
  /// **'Execute manualmente: {p0}'**
  String executeManualmenteP0(Object p0);

  /// No description provided for @terminalAbertoDigiteSuaSenhaSudo2.
  ///
  /// In pt, this message translates to:
  /// **'Terminal aberto! Digite sua senha sudo uma única vez.'**
  String get terminalAbertoDigiteSuaSenhaSudo2;

  /// No description provided for @executeNoTerminalP0.
  ///
  /// In pt, this message translates to:
  /// **'Execute no terminal: {p0}'**
  String executeNoTerminalP0(Object p0);

  /// No description provided for @aponteODispositivoDoResponsavelPara.
  ///
  /// In pt, this message translates to:
  /// **'Aponte o dispositivo do responsável para escanear este QR Code.'**
  String get aponteODispositivoDoResponsavelPara;

  /// No description provided for @seEstiverUsandoAVersaoMobile.
  ///
  /// In pt, this message translates to:
  /// **'Se estiver usando a versão mobile ou câmera, aponte para o QR Code na tela do filho.'**
  String get seEstiverUsandoAVersaoMobile;

  /// No description provided for @ouColeAChaveUriDo.
  ///
  /// In pt, this message translates to:
  /// **'Ou cole a chave/URI do QR Code aqui'**
  String get ouColeAChaveUriDo;

  /// No description provided for @chronosPairId.
  ///
  /// In pt, this message translates to:
  /// **'chronos://pair?id=...'**
  String get chronosPairId;

  /// No description provided for @codigoPinDePareamentoDesteDispositivo.
  ///
  /// In pt, this message translates to:
  /// **'Código PIN de Pareamento deste Dispositivo:'**
  String get codigoPinDePareamentoDesteDispositivo;

  /// No description provided for @definirSenhaMestraDeDesbloqueioLocal.
  ///
  /// In pt, this message translates to:
  /// **'Definir Senha Mestra de Desbloqueio Local (Opcional)'**
  String get definirSenhaMestraDeDesbloqueioLocal;

  /// No description provided for @digiteUmaSenhaParaAlterarTempo.
  ///
  /// In pt, this message translates to:
  /// **'Digite uma senha para alterar tempo de tela presencialmente'**
  String get digiteUmaSenhaParaAlterarTempo;

  /// No description provided for @digiteOCodigoPinOuSenha.
  ///
  /// In pt, this message translates to:
  /// **'Digite o Código PIN ou Senha exibida na tela do filho:'**
  String get digiteOCodigoPinOuSenha;

  /// No description provided for @chrXxxxOuSenha.
  ///
  /// In pt, this message translates to:
  /// **'CHR-XXXX ou Senha'**
  String get chrXxxxOuSenha;

  /// No description provided for @validarEParear.
  ///
  /// In pt, this message translates to:
  /// **'Validar e Parear'**
  String get validarEParear;

  /// No description provided for @orgKdeStatusnotifierwatcher.
  ///
  /// In pt, this message translates to:
  /// **'org.kde.StatusNotifierWatcher'**
  String get orgKdeStatusnotifierwatcher;

  /// No description provided for @abrirChronos.
  ///
  /// In pt, this message translates to:
  /// **'Abrir Chronos'**
  String get abrirChronos;

  /// No description provided for @desinstalarChronos.
  ///
  /// In pt, this message translates to:
  /// **'Desinstalar Chronos…'**
  String get desinstalarChronos;

  /// No description provided for @antiBurlaAtivoOChronosNao.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla ativo: o Chronos não pode ser desinstalado enquanto ele estiver ligado.'**
  String get antiBurlaAtivoOChronosNao;

  /// No description provided for @chronosFocus.
  ///
  /// In pt, this message translates to:
  /// **'Chronos Focus'**
  String get chronosFocus;

  /// No description provided for @chronosMonitoramentoAtivo.
  ///
  /// In pt, this message translates to:
  /// **'Chronos - Monitoramento Ativo'**
  String get chronosMonitoramentoAtivo;

  /// No description provided for @oAplicativoP0EstaSendoMonitorado.
  ///
  /// In pt, this message translates to:
  /// **'O aplicativo \"{p0}\" está sendo monitorado na sessão \"{p1}\".'**
  String oAplicativoP0EstaSendoMonitorado(Object p0, Object p1);

  /// No description provided for @chronosTempoDeTelaRestante.
  ///
  /// In pt, this message translates to:
  /// **'Chronos - Tempo de Tela Restante'**
  String get chronosTempoDeTelaRestante;

  /// No description provided for @p0RestamApenasP1MinutoP2.
  ///
  /// In pt, this message translates to:
  /// **'{p0}: Restam apenas {p1} min de tempo de tela!'**
  String p0RestamApenasP1MinutoP2(Object p0, Object p1);

  /// No description provided for @chronosTempoDeTelaEsgotado.
  ///
  /// In pt, this message translates to:
  /// **'Chronos - Tempo de Tela Esgotado'**
  String get chronosTempoDeTelaEsgotado;

  /// No description provided for @p0OTempoDeTelaDiario.
  ///
  /// In pt, this message translates to:
  /// **'{p0}: O tempo de tela diário foi completamente esgotado!'**
  String p0OTempoDeTelaDiario(Object p0);

  /// No description provided for @chronosAlertaPeriodicoP0Min.
  ///
  /// In pt, this message translates to:
  /// **'Chronos - Alerta Periódico ({p0} min)'**
  String chronosAlertaPeriodicoP0Min(Object p0);

  /// No description provided for @p0P1MinUtilizadosHojeRestam.
  ///
  /// In pt, this message translates to:
  /// **'{p0}: {p1} min utilizados hoje • Restam {p2} min de tempo de tela.'**
  String p0P1MinUtilizadosHojeRestam(Object p0, Object p1, Object p2);

  /// No description provided for @todas.
  ///
  /// In pt, this message translates to:
  /// **'Todas'**
  String get todas;

  /// No description provided for @jogos.
  ///
  /// In pt, this message translates to:
  /// **'Jogos'**
  String get jogos;

  /// No description provided for @navegadores.
  ///
  /// In pt, this message translates to:
  /// **'Navegadores'**
  String get navegadores;

  /// No description provided for @comunicacao.
  ///
  /// In pt, this message translates to:
  /// **'Comunicação'**
  String get comunicacao;

  /// No description provided for @internet.
  ///
  /// In pt, this message translates to:
  /// **'Internet'**
  String get internet;

  /// No description provided for @midia.
  ///
  /// In pt, this message translates to:
  /// **'Mídia'**
  String get midia;

  /// No description provided for @desenvolvimento.
  ///
  /// In pt, this message translates to:
  /// **'Desenvolvimento'**
  String get desenvolvimento;

  /// No description provided for @escritorio.
  ///
  /// In pt, this message translates to:
  /// **'Escritório'**
  String get escritorio;

  /// No description provided for @graficos.
  ///
  /// In pt, this message translates to:
  /// **'Gráficos'**
  String get graficos;

  /// No description provided for @educacao.
  ///
  /// In pt, this message translates to:
  /// **'Educação'**
  String get educacao;

  /// No description provided for @sistema.
  ///
  /// In pt, this message translates to:
  /// **'Sistema'**
  String get sistema;

  /// No description provided for @utilitarios.
  ///
  /// In pt, this message translates to:
  /// **'Utilitários'**
  String get utilitarios;

  /// No description provided for @outros.
  ///
  /// In pt, this message translates to:
  /// **'Outros'**
  String get outros;

  /// No description provided for @adicionarTagP0.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar Tag: {p0}'**
  String adicionarTagP0(Object p0);

  /// No description provided for @nomeDaTagExRedesSociais.
  ///
  /// In pt, this message translates to:
  /// **'Nome da Tag (ex: Redes Sociais, Trabalho, Jogos)'**
  String get nomeDaTagExRedesSociais;

  /// No description provided for @adicionarTag.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar Tag'**
  String get adicionarTag;

  /// No description provided for @p0JaFoiAdicionadoAoGrupo.
  ///
  /// In pt, this message translates to:
  /// **'\"{p0}\" já foi adicionado ao grupo.'**
  String p0JaFoiAdicionadoAoGrupo(Object p0);

  /// No description provided for @sessaoDeFoco.
  ///
  /// In pt, this message translates to:
  /// **'Sessão de Foco'**
  String get sessaoDeFoco;

  /// No description provided for @listaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Lista Branca'**
  String get listaBranca;

  /// No description provided for @selecionePeloMenosUmAplicativoOu.
  ///
  /// In pt, this message translates to:
  /// **'Selecione pelo menos um aplicativo ou site para o grupo.'**
  String get selecionePeloMenosUmAplicativoOu;

  /// No description provided for @p0HP1Min.
  ///
  /// In pt, this message translates to:
  /// **'{p0} h {p1} min'**
  String p0HP1Min(Object p0, Object p1);

  /// No description provided for @editarGrupoDeListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Editar Grupo de Lista Branca'**
  String get editarGrupoDeListaBranca;

  /// No description provided for @novoGrupoDeListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Novo Grupo de Lista Branca'**
  String get novoGrupoDeListaBranca;

  /// No description provided for @adicionarAplicativosSitesAoGrupo.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar Aplicativos / Sites ao Grupo'**
  String get adicionarAplicativosSitesAoGrupo;

  /// No description provided for @editarSessaoDeFoco.
  ///
  /// In pt, this message translates to:
  /// **'Editar Sessão de Foco'**
  String get editarSessaoDeFoco;

  /// No description provided for @criarSessaoDeFoco.
  ///
  /// In pt, this message translates to:
  /// **'Criar Sessão de Foco'**
  String get criarSessaoDeFoco;

  /// No description provided for @appsESitesNaListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Apps e sites na lista branca NUNCA serão bloqueados nem finalizados, mesmo se estiverem em outros grupos.'**
  String get appsESitesNaListaBranca;

  /// No description provided for @digiteONomeDoGrupoDe.
  ///
  /// In pt, this message translates to:
  /// **'Digite o nome do grupo de lista branca (ex: Ferramentas de Estudo)...'**
  String get digiteONomeDoGrupoDe;

  /// No description provided for @digiteONomeDaSessaoDe.
  ///
  /// In pt, this message translates to:
  /// **'Digite o nome da sessão de foco (ex: Distrações e Lazer)...'**
  String get digiteONomeDaSessaoDe;

  /// No description provided for @nomeDoGrupoDeListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Nome do Grupo de Lista Branca'**
  String get nomeDoGrupoDeListaBranca;

  /// No description provided for @nomeDaSessaoDeFoco.
  ///
  /// In pt, this message translates to:
  /// **'Nome da Sessão de Foco'**
  String get nomeDaSessaoDeFoco;

  /// No description provided for @aplicativosP0.
  ///
  /// In pt, this message translates to:
  /// **'Aplicativos ({p0})'**
  String aplicativosP0(Object p0);

  /// No description provided for @sitesEPalavrasP0.
  ///
  /// In pt, this message translates to:
  /// **'Sites e Palavras ({p0})'**
  String sitesEPalavrasP0(Object p0);

  /// No description provided for @youtubeP0.
  ///
  /// In pt, this message translates to:
  /// **'YouTube ({p0})'**
  String youtubeP0(Object p0);

  /// No description provided for @p0AppsP1Sites.
  ///
  /// In pt, this message translates to:
  /// **'{p0} apps • {p1} sites'**
  String p0AppsP1Sites(Object p0, Object p1);

  /// No description provided for @salvarListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Salvar Lista Branca'**
  String get salvarListaBranca;

  /// No description provided for @salvarAppsNoGrupo.
  ///
  /// In pt, this message translates to:
  /// **'Salvar Apps no Grupo'**
  String get salvarAppsNoGrupo;

  /// No description provided for @avancarTempoDeTelaRegras.
  ///
  /// In pt, this message translates to:
  /// **'Avançar: Tempo de Tela & Regras'**
  String get avancarTempoDeTelaRegras;

  /// No description provided for @buscarPorNomeExecutavelOuTag.
  ///
  /// In pt, this message translates to:
  /// **'Buscar por nome, executável ou tag (ex: Jogos, Mídia)...'**
  String get buscarPorNomeExecutavelOuTag;

  /// No description provided for @selecionarTudo.
  ///
  /// In pt, this message translates to:
  /// **'Selecionar Tudo'**
  String get selecionarTudo;

  /// No description provided for @limpar.
  ///
  /// In pt, this message translates to:
  /// **'Limpar'**
  String get limpar;

  /// No description provided for @carregandoAplicativosInstalados.
  ///
  /// In pt, this message translates to:
  /// **'Carregando aplicativos instalados...'**
  String get carregandoAplicativosInstalados;

  /// No description provided for @nenhumAplicativoEncontradoParaOFiltro.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum aplicativo encontrado para o filtro/tag.'**
  String get nenhumAplicativoEncontradoParaOFiltro;

  /// No description provided for @limparFiltroDeTag.
  ///
  /// In pt, this message translates to:
  /// **'Limpar Filtro de Tag'**
  String get limparFiltroDeTag;

  /// No description provided for @jaNoGrupo.
  ///
  /// In pt, this message translates to:
  /// **'Já no grupo'**
  String get jaNoGrupo;

  /// No description provided for @tag.
  ///
  /// In pt, this message translates to:
  /// **'+ Tag'**
  String get tag;

  /// No description provided for @videosDessesTiposNaoDescontamO.
  ///
  /// In pt, this message translates to:
  /// **'Vídeos desses tipos não descontam o tempo de tela do YouTube. Use o teto para limitar quanto tempo por dia fica isento (vazio = sem teto).'**
  String get videosDessesTiposNaoDescontamO;

  /// No description provided for @tetoMinDia.
  ///
  /// In pt, this message translates to:
  /// **'Teto (min/dia)'**
  String get tetoMinDia;

  /// No description provided for @semTeto.
  ///
  /// In pt, this message translates to:
  /// **'sem teto'**
  String get semTeto;

  /// No description provided for @digiteDominioOuPalavraChaveEx.
  ///
  /// In pt, this message translates to:
  /// **'Digite domínio ou palavra-chave (ex: youtube.com, reels, shorts)...'**
  String get digiteDominioOuPalavraChaveEx;

  /// No description provided for @adicionar.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar'**
  String get adicionar;

  /// No description provided for @sitesEPalavrasChaveAdicionadosP0.
  ///
  /// In pt, this message translates to:
  /// **'Sites e Palavras-Chave Adicionados ({p0}):'**
  String sitesEPalavrasChaveAdicionadosP0(Object p0);

  /// No description provided for @limparNovos.
  ///
  /// In pt, this message translates to:
  /// **'Limpar Novos'**
  String get limparNovos;

  /// No description provided for @limparTodos.
  ///
  /// In pt, this message translates to:
  /// **'Limpar Todos'**
  String get limparTodos;

  /// No description provided for @nenhumSiteOuPalavraChaveAdicionado.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum site ou palavra-chave adicionado ainda nesta sessão.'**
  String get nenhumSiteOuPalavraChaveAdicionado;

  /// No description provided for @p0JaNoGrupo.
  ///
  /// In pt, this message translates to:
  /// **'{p0} (Já no grupo)'**
  String p0JaNoGrupo(Object p0);

  /// No description provided for @editarTempoDeBloqueioP0.
  ///
  /// In pt, this message translates to:
  /// **'Editar Tempo de Bloqueio: {p0}'**
  String editarTempoDeBloqueioP0(Object p0);

  /// No description provided for @tempoDeTelaP0.
  ///
  /// In pt, this message translates to:
  /// **'Tempo de Tela: {p0}'**
  String tempoDeTelaP0(Object p0);

  /// No description provided for @sessaoP0.
  ///
  /// In pt, this message translates to:
  /// **'Sessão: {p0}'**
  String sessaoP0(Object p0);

  /// No description provided for @grupoDeFocoUnificado.
  ///
  /// In pt, this message translates to:
  /// **'GRUPO DE FOCO UNIFICADO'**
  String get grupoDeFocoUnificado;

  /// No description provided for @p0AplicativosEP1SitesInclusos.
  ///
  /// In pt, this message translates to:
  /// **'{p0} aplicativos e {p1} sites inclusos.'**
  String p0AplicativosEP1SitesInclusos(Object p0, Object p1);

  /// No description provided for @todosOsAplicativosESitesDesta.
  ///
  /// In pt, this message translates to:
  /// **'Todos os aplicativos e sites desta sessão compartilham a mesma cota diária de tempo de tela.'**
  String get todosOsAplicativosESitesDesta;

  /// No description provided for @limiteDeTempoDeTelaRelogio.
  ///
  /// In pt, this message translates to:
  /// **'Limite de Tempo de Tela (Relógio Digital):'**
  String get limiteDeTempoDeTelaRelogio;

  /// No description provided for @bloqueioTotal2.
  ///
  /// In pt, this message translates to:
  /// **'BLOQUEIO TOTAL'**
  String get bloqueioTotal2;

  /// No description provided for @nenhumAcessoPermitidoDuranteODia.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum acesso permitido durante o dia'**
  String get nenhumAcessoPermitidoDuranteODia;

  /// No description provided for @p0DeUsoPermitido.
  ///
  /// In pt, this message translates to:
  /// **'{p0} de uso permitido'**
  String p0DeUsoPermitido(Object p0);

  /// No description provided for @bloquearTotalmente0MinDeTempo.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Totalmente (0 min de tempo de tela)'**
  String get bloquearTotalmente0MinDeTempo;

  /// No description provided for @impedeQualquerInicializacaoDoGrupoImediatamente.
  ///
  /// In pt, this message translates to:
  /// **'Impede qualquer inicialização do grupo imediatamente'**
  String get impedeQualquerInicializacaoDoGrupoImediatamente;

  /// No description provided for @tempoDeTelaDiferenciadoNoFinal.
  ///
  /// In pt, this message translates to:
  /// **'Tempo de tela diferenciado no Final de Semana'**
  String get tempoDeTelaDiferenciadoNoFinal;

  /// No description provided for @permiteConfigurarMaisTempoParaSabado.
  ///
  /// In pt, this message translates to:
  /// **'Permite configurar mais tempo para sábado e domingo'**
  String get permiteConfigurarMaisTempoParaSabado;

  /// No description provided for @tempoFimDeSemanaP0.
  ///
  /// In pt, this message translates to:
  /// **'Tempo Fim de Semana: {p0}'**
  String tempoFimDeSemanaP0(Object p0);

  /// No description provided for @tempoDeTelaDiferenciadoEmFeriados.
  ///
  /// In pt, this message translates to:
  /// **'Tempo de tela diferenciado em Feriados'**
  String get tempoDeTelaDiferenciadoEmFeriados;

  /// No description provided for @valeNosFeriadosNacionaisENas.
  ///
  /// In pt, this message translates to:
  /// **'Vale nos feriados nacionais e nas datas que você adicionar em Configurações. Tem prioridade sobre o fim de semana.{p0}'**
  String valeNosFeriadosNacionaisENas(Object p0);

  /// No description provided for @tempoEmFeriadosP0.
  ///
  /// In pt, this message translates to:
  /// **'Tempo em Feriados: {p0}'**
  String tempoEmFeriadosP0(Object p0);

  /// No description provided for @diasDaSemanaAtivos.
  ///
  /// In pt, this message translates to:
  /// **'Dias da Semana Ativos:'**
  String get diasDaSemanaAtivos;

  /// No description provided for @todos.
  ///
  /// In pt, this message translates to:
  /// **'Todos'**
  String get todos;

  /// No description provided for @diasUteis.
  ///
  /// In pt, this message translates to:
  /// **'Dias Úteis'**
  String get diasUteis;

  /// No description provided for @finsDeSemana.
  ///
  /// In pt, this message translates to:
  /// **'Fins de Semana'**
  String get finsDeSemana;

  /// No description provided for @seg.
  ///
  /// In pt, this message translates to:
  /// **'Seg'**
  String get seg;

  /// No description provided for @ter.
  ///
  /// In pt, this message translates to:
  /// **'Ter'**
  String get ter;

  /// No description provided for @qua.
  ///
  /// In pt, this message translates to:
  /// **'Qua'**
  String get qua;

  /// No description provided for @qui.
  ///
  /// In pt, this message translates to:
  /// **'Qui'**
  String get qui;

  /// No description provided for @sex.
  ///
  /// In pt, this message translates to:
  /// **'Sex'**
  String get sex;

  /// No description provided for @sab.
  ///
  /// In pt, this message translates to:
  /// **'Sáb'**
  String get sab;

  /// No description provided for @dom.
  ///
  /// In pt, this message translates to:
  /// **'Dom'**
  String get dom;

  /// No description provided for @bloqueioPorJanelaDeHorario.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueio por Janela de Horário'**
  String get bloqueioPorJanelaDeHorario;

  /// No description provided for @bloqueiaOGrupoDentroDeUm.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueia o grupo dentro de um horário fixo do dia'**
  String get bloqueiaOGrupoDentroDeUm;

  /// No description provided for @inicioP0.
  ///
  /// In pt, this message translates to:
  /// **'Início: {p0}'**
  String inicioP0(Object p0);

  /// No description provided for @fimP0.
  ///
  /// In pt, this message translates to:
  /// **'Fim: {p0}'**
  String fimP0(Object p0);

  /// No description provided for @modo.
  ///
  /// In pt, this message translates to:
  /// **'Modo:'**
  String get modo;

  /// No description provided for @bloquearDentro.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Dentro'**
  String get bloquearDentro;

  /// No description provided for @permitirSomenteDentro.
  ///
  /// In pt, this message translates to:
  /// **'Permitir Somente Dentro'**
  String get permitirSomenteDentro;

  /// No description provided for @notificacaoPorTempoRestante.
  ///
  /// In pt, this message translates to:
  /// **'Notificação por Tempo Restante'**
  String get notificacaoPorTempoRestante;

  /// No description provided for @avisaAos155E1.
  ///
  /// In pt, this message translates to:
  /// **'Avisa aos 15, 5 e 1 minuto restantes antes de encerrar o tempo de tela'**
  String get avisaAos155E1;

  /// No description provided for @notificacaoPeriodica.
  ///
  /// In pt, this message translates to:
  /// **'Notificação Periódica'**
  String get notificacaoPeriodica;

  /// No description provided for @emiteLembretesRegularesEnquantoASessao.
  ///
  /// In pt, this message translates to:
  /// **'Emite lembretes regulares enquanto a sessão estiver em uso'**
  String get emiteLembretesRegularesEnquantoASessao;

  /// No description provided for @intervaloDaNotificacaoPeriodica.
  ///
  /// In pt, this message translates to:
  /// **'Intervalo da Notificação Periódica:'**
  String get intervaloDaNotificacaoPeriodica;

  /// No description provided for @aCadaP0Min.
  ///
  /// In pt, this message translates to:
  /// **'A cada {p0} min'**
  String aCadaP0Min(Object p0);

  /// No description provided for @salvarGrupoDeFoco.
  ///
  /// In pt, this message translates to:
  /// **'Salvar Grupo de Foco'**
  String get salvarGrupoDeFoco;

  /// No description provided for @permitaAExtensaoNoAnonimo.
  ///
  /// In pt, this message translates to:
  /// **'Permita a extensão no anônimo'**
  String get permitaAExtensaoNoAnonimo;

  /// No description provided for @abrirNosNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Abrir nos navegadores'**
  String get abrirNosNavegadores;

  /// No description provided for @entendi.
  ///
  /// In pt, this message translates to:
  /// **'Entendi'**
  String get entendi;

  /// No description provided for @guiaAnonimaBloqueadaNosNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Guia anônima bloqueada nos navegadores.'**
  String get guiaAnonimaBloqueadaNosNavegadores;

  /// No description provided for @guiaAnonimaLiberada.
  ///
  /// In pt, this message translates to:
  /// **'Guia anônima liberada.'**
  String get guiaAnonimaLiberada;

  /// No description provided for @nenhumNavegadorChromiumEncontrado.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum navegador Chromium encontrado.'**
  String get nenhumNavegadorChromiumEncontrado;

  /// No description provided for @abertoEmP0.
  ///
  /// In pt, this message translates to:
  /// **'Aberto em {p0}: ligue \"Permitir no modo anônimo\" na extensão Chronos.'**
  String abertoEmP0(Object p0);

  /// No description provided for @ativarProtecaoPorDns.
  ///
  /// In pt, this message translates to:
  /// **'Ativar proteção por DNS?'**
  String get ativarProtecaoPorDns;

  /// No description provided for @oDnsFamiliaPassaAValer.
  ///
  /// In pt, this message translates to:
  /// **'O DNS família passa a valer para o computador inteiro. Isso pode tirar funcionalidades de alguns apps e redes:\n\n• redes de faculdade, empresa ou hotel que bloqueiam DNS externo podem ficar sem internet;\n• sites e serviços internos da rede (intranet, impressoras por nome) podem não abrir;\n• VPNs, jogos online, apps de streaming ou containers (Docker) podem falhar em resolver endereços;\n• o DNS do roteador e o \"DNS seguro\" dos navegadores deixam de ser usados.\n\nDesligar depois pede a senha de administrador, e fica bloqueado com o Anti-Burla ativo.'**
  String get oDnsFamiliaPassaAValer;

  /// No description provided for @entendiAtivar.
  ///
  /// In pt, this message translates to:
  /// **'Entendi, ativar'**
  String get entendiAtivar;

  /// No description provided for @filtroDeConteudoAdulto.
  ///
  /// In pt, this message translates to:
  /// **'Filtro de Conteúdo Adulto'**
  String get filtroDeConteudoAdulto;

  /// No description provided for @modoParentalOFiltroFicaSempre.
  ///
  /// In pt, this message translates to:
  /// **'Modo parental: o filtro fica sempre ligado.'**
  String get modoParentalOFiltroFicaSempre;

  /// No description provided for @ativarFiltro.
  ///
  /// In pt, this message translates to:
  /// **'Ativar filtro'**
  String get ativarFiltro;

  /// No description provided for @bloqueiaSitesAdultosComATela.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueia sites adultos com a tela de bloqueio do Chronos.'**
  String get bloqueiaSitesAdultosComATela;

  /// No description provided for @bloquearGuiaAnonimaEConvidado.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear guia anônima e convidado'**
  String get bloquearGuiaAnonimaEConvidado;

  /// No description provided for @impedeJanelasAnonimasPrivadasEO.
  ///
  /// In pt, this message translates to:
  /// **'Impede janelas anônimas/privadas e o modo convidado em todos os navegadores{p0}. Liberar pede senha de administrador e fica bloqueado com o Anti-Burla ativo.'**
  String impedeJanelasAnonimasPrivadasEO(Object p0);

  /// No description provided for @permitirAExtensaoNoAnonimoAbrir.
  ///
  /// In pt, this message translates to:
  /// **'Permitir a extensão no anônimo (abrir nos navegadores)'**
  String get permitirAExtensaoNoAnonimoAbrir;

  /// No description provided for @extensaoPermitidaNoAnonimoEmP0.
  ///
  /// In pt, this message translates to:
  /// **'Extensão permitida no anônimo em {p0} navegador(es) aberto(s).'**
  String extensaoPermitidaNoAnonimoEmP0(Object p0);

  /// No description provided for @extensaoSemPermissaoNoAnonimoEm.
  ///
  /// In pt, this message translates to:
  /// **'Extensão sem permissão no anônimo em {p0} de {p1} navegador(es){p2}.'**
  String extensaoSemPermissaoNoAnonimoEm(Object p0, Object p1, Object p2);

  /// No description provided for @filtroLigadoMasNadaEstaBloqueando.
  ///
  /// In pt, this message translates to:
  /// **'Filtro ligado, mas nada está bloqueando: ligue a lista de sites adultos, o SafeSearch ou o DNS.'**
  String get filtroLigadoMasNadaEstaBloqueando;

  /// No description provided for @listaDeSitesAdultos.
  ///
  /// In pt, this message translates to:
  /// **'Lista de sites adultos'**
  String get listaDeSitesAdultos;

  /// No description provided for @p0SitesConhecidosAtualizaTodaSemana.
  ///
  /// In pt, this message translates to:
  /// **'{p0} sites conhecidos (atualiza toda semana).'**
  String p0SitesConhecidosAtualizaTodaSemana(Object p0);

  /// No description provided for @baixandoALista.
  ///
  /// In pt, this message translates to:
  /// **'Baixando a lista…'**
  String get baixandoALista;

  /// No description provided for @iaDeImagensLocal.
  ///
  /// In pt, this message translates to:
  /// **'IA de imagens (local)'**
  String get iaDeImagensLocal;

  /// No description provided for @desfocaImagensAteUmModeloDe.
  ///
  /// In pt, this message translates to:
  /// **'Desfoca imagens até um modelo de IA rodando no seu computador analisar; as +18 continuam desfocadas e páginas com várias são bloqueadas. Nada é enviado para fora.'**
  String get desfocaImagensAteUmModeloDe;

  /// No description provided for @safesearchForcado.
  ///
  /// In pt, this message translates to:
  /// **'SafeSearch forçado'**
  String get safesearchForcado;

  /// No description provided for @googleBingEDuckduckgoEmModo.
  ///
  /// In pt, this message translates to:
  /// **'Google, Bing e DuckDuckGo em modo seguro; YouTube em Modo Restrito.'**
  String get googleBingEDuckduckgoEmModo;

  /// No description provided for @protecaoPorDnsComputadorInteiro.
  ///
  /// In pt, this message translates to:
  /// **'Proteção por DNS (computador inteiro)'**
  String get protecaoPorDnsComputadorInteiro;

  /// No description provided for @usaUmDnsFamiliaEmTodo.
  ///
  /// In pt, this message translates to:
  /// **'Usa um DNS família em todo o sistema: vale para qualquer navegador e app. Aplicado pelo Chronos Guard (desligar pede senha de administrador).'**
  String get usaUmDnsFamiliaEmTodo;

  /// No description provided for @servicoDeDnsFamilia.
  ///
  /// In pt, this message translates to:
  /// **'Serviço de DNS família'**
  String get servicoDeDnsFamilia;

  /// No description provided for @dnsDoChronosDesligadoMasO.
  ///
  /// In pt, this message translates to:
  /// **'DNS do Chronos desligado, mas o DNS da rede (roteador/provedor) já filtra conteúdo adulto — só vale nesta rede.'**
  String get dnsDoChronosDesligadoMasO;

  /// No description provided for @dnsDoSistemaNormalSemDns.
  ///
  /// In pt, this message translates to:
  /// **'DNS do sistema: normal (sem DNS família).'**
  String get dnsDoSistemaNormalSemDns;

  /// No description provided for @dnsDoSistemaP0AtivoP1.
  ///
  /// In pt, this message translates to:
  /// **'DNS do sistema: {p0} ativo{p1}.'**
  String dnsDoSistemaP0AtivoP1(Object p0, Object p1);

  /// No description provided for @registrarTentativas.
  ///
  /// In pt, this message translates to:
  /// **'Registrar tentativas'**
  String get registrarTentativas;

  /// No description provided for @anotaDataESiteDeCada.
  ///
  /// In pt, this message translates to:
  /// **'Anota data e site de cada bloqueio{p0}.'**
  String anotaDataESiteDeCada(Object p0);

  /// No description provided for @ultimasTentativas.
  ///
  /// In pt, this message translates to:
  /// **'Últimas tentativas'**
  String get ultimasTentativas;

  /// No description provided for @verHistoricoCompleto.
  ///
  /// In pt, this message translates to:
  /// **'Ver histórico completo'**
  String get verHistoricoCompleto;

  /// No description provided for @excecoesSitesNuncaBloqueadosPorEste.
  ///
  /// In pt, this message translates to:
  /// **'Exceções (sites nunca bloqueados por este filtro)'**
  String get excecoesSitesNuncaBloqueadosPorEste;

  /// No description provided for @exSiteDaEscolaCom.
  ///
  /// In pt, this message translates to:
  /// **'ex.: site-da-escola.com'**
  String get exSiteDaEscolaCom;

  /// No description provided for @hoje.
  ///
  /// In pt, this message translates to:
  /// **'Hoje'**
  String get hoje;

  /// No description provided for @t7Dias.
  ///
  /// In pt, this message translates to:
  /// **'7 dias'**
  String get t7Dias;

  /// No description provided for @t30Dias.
  ///
  /// In pt, this message translates to:
  /// **'30 dias'**
  String get t30Dias;

  /// No description provided for @tudo.
  ///
  /// In pt, this message translates to:
  /// **'Tudo'**
  String get tudo;

  /// No description provided for @listaDeSites.
  ///
  /// In pt, this message translates to:
  /// **'lista de sites'**
  String get listaDeSites;

  /// No description provided for @reddit.
  ///
  /// In pt, this message translates to:
  /// **'Reddit'**
  String get reddit;

  /// No description provided for @iaDeImagens.
  ///
  /// In pt, this message translates to:
  /// **'IA de imagens'**
  String get iaDeImagens;

  /// No description provided for @historicoDeTentativas.
  ///
  /// In pt, this message translates to:
  /// **'Histórico de tentativas'**
  String get historicoDeTentativas;

  /// No description provided for @p0TentativaS.
  ///
  /// In pt, this message translates to:
  /// **'{p0} tentativa(s)'**
  String p0TentativaS(Object p0);

  /// No description provided for @nenhumaTentativaNestePeriodo.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma tentativa neste período.'**
  String get nenhumaTentativaNestePeriodo;

  /// No description provided for @fechar.
  ///
  /// In pt, this message translates to:
  /// **'Fechar'**
  String get fechar;

  /// No description provided for @p0HP1M.
  ///
  /// In pt, this message translates to:
  /// **'{p0}h {p1}m'**
  String p0HP1M(Object p0, Object p1);

  /// No description provided for @semDados.
  ///
  /// In pt, this message translates to:
  /// **'Sem dados'**
  String get semDados;

  /// No description provided for @estatisticasDeTempoDeTela.
  ///
  /// In pt, this message translates to:
  /// **'Estatísticas de Tempo de Tela'**
  String get estatisticasDeTempoDeTela;

  /// No description provided for @consumoConsolidadoTendenciasSemanaisERanking.
  ///
  /// In pt, this message translates to:
  /// **'Consumo consolidado, tendências semanais e ranking de aplicativos e sites.'**
  String get consumoConsolidadoTendenciasSemanaisERanking;

  /// No description provided for @atualizar.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar'**
  String get atualizar;

  /// No description provided for @consumoHoje.
  ///
  /// In pt, this message translates to:
  /// **'Consumo Hoje'**
  String get consumoHoje;

  /// No description provided for @tempoEmAppsSitesMonitorados.
  ///
  /// In pt, this message translates to:
  /// **'Tempo em apps/sites monitorados'**
  String get tempoEmAppsSitesMonitorados;

  /// No description provided for @mediaSemanal.
  ///
  /// In pt, this message translates to:
  /// **'Média Semanal'**
  String get mediaSemanal;

  /// No description provided for @baseadoNosUltimos7Dias.
  ///
  /// In pt, this message translates to:
  /// **'Baseado nos últimos 7 dias'**
  String get baseadoNosUltimos7Dias;

  /// No description provided for @diaDePico.
  ///
  /// In pt, this message translates to:
  /// **'Dia de Pico'**
  String get diaDePico;

  /// No description provided for @tendenciaVsSemanaAnterior.
  ///
  /// In pt, this message translates to:
  /// **'Tendência vs. Semana Anterior'**
  String get tendenciaVsSemanaAnterior;

  /// No description provided for @estavel.
  ///
  /// In pt, this message translates to:
  /// **'Estável'**
  String get estavel;

  /// No description provided for @maisTempoDeTela.
  ///
  /// In pt, this message translates to:
  /// **'Mais tempo de tela'**
  String get maisTempoDeTela;

  /// No description provided for @menosTempoDeTela.
  ///
  /// In pt, this message translates to:
  /// **'Menos tempo de tela'**
  String get menosTempoDeTela;

  /// No description provided for @appsSitesMonitorados.
  ///
  /// In pt, this message translates to:
  /// **'Apps/sites monitorados'**
  String get appsSitesMonitorados;

  /// No description provided for @mediaDiaria.
  ///
  /// In pt, this message translates to:
  /// **'Média Diária'**
  String get mediaDiaria;

  /// No description provided for @ultimos7Dias.
  ///
  /// In pt, this message translates to:
  /// **'Últimos 7 dias'**
  String get ultimos7Dias;

  /// No description provided for @tendencia.
  ///
  /// In pt, this message translates to:
  /// **'Tendência'**
  String get tendencia;

  /// No description provided for @maisTela.
  ///
  /// In pt, this message translates to:
  /// **'Mais tela'**
  String get maisTela;

  /// No description provided for @menosTela.
  ///
  /// In pt, this message translates to:
  /// **'Menos tela'**
  String get menosTela;

  /// No description provided for @tempoIsentoNoYoutubeListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Tempo Isento no YouTube (Lista Branca)'**
  String get tempoIsentoNoYoutubeListaBranca;

  /// No description provided for @p0P1Em7Dias.
  ///
  /// In pt, this message translates to:
  /// **'{p0}: {p1} em 7 dias'**
  String p0P1Em7Dias(Object p0, Object p1);

  /// No description provided for @consumoDiarioNosUltimos7Dias.
  ///
  /// In pt, this message translates to:
  /// **'Consumo Diário nos Últimos 7 Dias'**
  String get consumoDiarioNosUltimos7Dias;

  /// No description provided for @totalP0.
  ///
  /// In pt, this message translates to:
  /// **'Total: {p0}'**
  String totalP0(Object p0);

  /// No description provided for @nenhumDadoDiarioRegistrado.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum dado diário registrado.'**
  String get nenhumDadoDiarioRegistrado;

  /// No description provided for @top5AppsSitesMaisConsumidos.
  ///
  /// In pt, this message translates to:
  /// **'Top 5 Apps & Sites Mais Consumidos (Últimos 7 Dias)'**
  String get top5AppsSitesMaisConsumidos;

  /// No description provided for @nenhumaAtividadeRegistradaNaSemanaAinda.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma atividade registrada na semana ainda.'**
  String get nenhumaAtividadeRegistradaNaSemanaAinda;

  /// No description provided for @p0DoTotal.
  ///
  /// In pt, this message translates to:
  /// **'{p0}% do total'**
  String p0DoTotal(Object p0);

  /// No description provided for @colarNaoEPermitidoDigiteO.
  ///
  /// In pt, this message translates to:
  /// **'❌ Colar não é permitido: digite o texto.'**
  String get colarNaoEPermitidoDigiteO;

  /// No description provided for @erroDetectadoNoModoStayfocusdQualquer.
  ///
  /// In pt, this message translates to:
  /// **'❌ Erro detectado! No modo StayFocusd, qualquer caractere incorreto reseta o texto por completo. Digite com atenção máxima!'**
  String get erroDetectadoNoModoStayfocusdQualquer;

  /// No description provided for @selecioneUmaDuracaoValidaMaiorQue.
  ///
  /// In pt, this message translates to:
  /// **'Selecione uma duração válida maior que 0 minutos para o Modo Nuke.'**
  String get selecioneUmaDuracaoValidaMaiorQue;

  /// No description provided for @ativarOAntiBurla.
  ///
  /// In pt, this message translates to:
  /// **'Ativar o Anti-Burla?'**
  String get ativarOAntiBurla;

  /// No description provided for @enquantoOAntiBurlaEstiverAtivo.
  ///
  /// In pt, this message translates to:
  /// **'Enquanto o Anti-Burla estiver ativo:\n\n• o Chronos NÃO poderá ser desinstalado;\n• ele continua rodando em segundo plano e reabre sozinho se for fechado;\n• regras, filtros e extensões não podem ser afrouxados.\n\n{p0}'**
  String enquantoOAntiBurlaEstiverAtivo(Object p0);

  /// No description provided for @noModoNukeIssoSoAcaba.
  ///
  /// In pt, this message translates to:
  /// **'No Modo Nuke isso só acaba quando o tempo terminar.'**
  String get noModoNukeIssoSoAcaba;

  /// No description provided for @paraDesativarSeraPrecisoCompletarO.
  ///
  /// In pt, this message translates to:
  /// **'Para desativar será preciso completar o desafio.'**
  String get paraDesativarSeraPrecisoCompletarO;

  /// No description provided for @modoNukeAtivadoPorP0Configuracoes.
  ///
  /// In pt, this message translates to:
  /// **'☢️ Modo Nuke Ativado por {p0}! Configurações e extensões travadas.'**
  String modoNukeAtivadoPorP0Configuracoes(Object p0);

  /// No description provided for @modoAntiCheatAtivadoComDesafio.
  ///
  /// In pt, this message translates to:
  /// **'🛡️ Modo Anti-Burla Ativado com Desafio Estrito!'**
  String get modoAntiCheatAtivadoComDesafio;

  /// No description provided for @erroAoAtivarP0.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao ativar: {p0}'**
  String erroAoAtivarP0(Object p0);

  /// No description provided for @antiCheatDesativadoComSucessoModificacoes.
  ///
  /// In pt, this message translates to:
  /// **'🔓 Anti-Burla desativado com sucesso! Modificações liberadas.'**
  String get antiCheatDesativadoComSucessoModificacoes;

  /// No description provided for @erroP0.
  ///
  /// In pt, this message translates to:
  /// **'Erro: {p0}'**
  String erroP0(Object p0);

  /// No description provided for @protecaoAntiCheatAtiva.
  ///
  /// In pt, this message translates to:
  /// **'Proteção Anti-Burla Ativa'**
  String get protecaoAntiCheatAtiva;

  /// No description provided for @configurarModoAntiCheat.
  ///
  /// In pt, this message translates to:
  /// **'Configurar Modo Anti-Burla'**
  String get configurarModoAntiCheat;

  /// No description provided for @oAntiCheatImpedeVoceDe.
  ///
  /// In pt, this message translates to:
  /// **'O Anti-Burla impede você de burlar o Chronos, bloquear ou aumentar limites nos momentos de fraqueza, e protege a extensão contra remoção.'**
  String get oAntiCheatImpedeVoceDe;

  /// No description provided for @escolhaOMetodoDeTravamento.
  ///
  /// In pt, this message translates to:
  /// **'Escolha o Método de Travamento:'**
  String get escolhaOMetodoDeTravamento;

  /// No description provided for @desafioDeDigitacaoEstritoEstiloStayfocusd.
  ///
  /// In pt, this message translates to:
  /// **'Desafio de Digitação Estrito (Estilo StayFocusd)'**
  String get desafioDeDigitacaoEstritoEstiloStayfocusd;

  /// No description provided for @qualquerTentativaDeDesativarOuAumentar.
  ///
  /// In pt, this message translates to:
  /// **'Qualquer tentativa de desativar ou aumentar limites de tempo de tela exige redigitar um texto de compromisso extenso sem nenhum erro. Errou um caractere? O texto é resetado!'**
  String get qualquerTentativaDeDesativarOuAumentar;

  /// No description provided for @modoNukeBloqueioTotalPorTempo.
  ///
  /// In pt, this message translates to:
  /// **'Modo Nuke (Bloqueio Total por Tempo)'**
  String get modoNukeBloqueioTotalPorTempo;

  /// No description provided for @trava100OChronosPorUm.
  ///
  /// In pt, this message translates to:
  /// **'Trava 100% o Chronos por um período de tempo. Durante esse período, NÃO EXISTE forma de destravar ou alterar nada até o tempo acabar.'**
  String get trava100OChronosPorUm;

  /// No description provided for @duracaoDoTravamentoNukeScrollPara.
  ///
  /// In pt, this message translates to:
  /// **'Duração do Travamento Nuke (Scroll para ajustar):'**
  String get duracaoDoTravamentoNukeScrollPara;

  /// No description provided for @ativarModoNukeP0.
  ///
  /// In pt, this message translates to:
  /// **'ATIVAR MODO NUKE ({p0})'**
  String ativarModoNukeP0(Object p0);

  /// No description provided for @ativarAntiCheatRestrito.
  ///
  /// In pt, this message translates to:
  /// **'ATIVAR ANTI-CHEAT RESTRITO'**
  String get ativarAntiCheatRestrito;

  /// No description provided for @modoNukeEmAndamento.
  ///
  /// In pt, this message translates to:
  /// **'MODO NUKE EM ANDAMENTO'**
  String get modoNukeEmAndamento;

  /// No description provided for @nenhumaAlteracaoDeTempoDeTela.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma alteração de tempo de tela, regra ou desinstalação de extensão é permitida até que este tempo expire.'**
  String get nenhumaAlteracaoDeTempoDeTela;

  /// No description provided for @desafioDeDigitacaoStayfocusd.
  ///
  /// In pt, this message translates to:
  /// **'Desafio de Digitação StayFocusd'**
  String get desafioDeDigitacaoStayfocusd;

  /// No description provided for @paraDestravarOAplicativoELiberar.
  ///
  /// In pt, this message translates to:
  /// **'Para destravar o aplicativo e liberar edições, digite exatamente o texto abaixo sem cometer um único erro:'**
  String get paraDestravarOAplicativoELiberar;

  /// No description provided for @progressoP0P1Caracteres.
  ///
  /// In pt, this message translates to:
  /// **'Progresso: {p0} / {p1} caracteres'**
  String progressoP0P1Caracteres(Object p0, Object p1);

  /// No description provided for @comeceADigitarOTextoAqui.
  ///
  /// In pt, this message translates to:
  /// **'Comece a digitar o texto aqui...'**
  String get comeceADigitarOTextoAqui;

  /// No description provided for @destravarAntiCheat.
  ///
  /// In pt, this message translates to:
  /// **'DESTRAVAR ANTI-CHEAT'**
  String get destravarAntiCheat;

  /// No description provided for @debugDesativarAntiCheatImediatamente.
  ///
  /// In pt, this message translates to:
  /// **'🛠️ Debug: Desativar Anti-Burla Imediatamente'**
  String get debugDesativarAntiCheatImediatamente;

  /// No description provided for @debugAntiCheatENukeDesativados.
  ///
  /// In pt, this message translates to:
  /// **'🛠️ [DEBUG] Anti-Burla e Nuke desativados com sucesso!'**
  String get debugAntiCheatENukeDesativados;

  /// No description provided for @instalarAtualizarExtensaoEmTodosNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Instalar / Atualizar Extensão em Todos Navegadores'**
  String get instalarAtualizarExtensaoEmTodosNavegadores;

  /// No description provided for @pacoteEmbutido.
  ///
  /// In pt, this message translates to:
  /// **'Pacote Embutido'**
  String get pacoteEmbutido;

  /// No description provided for @atualizarGuard.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar Guard'**
  String get atualizarGuard;

  /// No description provided for @politicaGuard.
  ///
  /// In pt, this message translates to:
  /// **'Política Guard'**
  String get politicaGuard;

  /// No description provided for @ativoNosNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Ativo nos Navegadores'**
  String get ativoNosNavegadores;

  /// No description provided for @nenhumNavegadorSuportadoDetectado.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum navegador suportado detectado.'**
  String get nenhumNavegadorSuportadoDetectado;

  /// No description provided for @protegidoPeloProxySeletivoLocal127.
  ///
  /// In pt, this message translates to:
  /// **'Protegido pelo Proxy Seletivo Local (127.0.0.1:4546) + Certificado CA — o Firefox Release não lista .xpi sem assinatura Mozilla em about:addons, mas bloqueios e filtros HTML/CSS operam normalmente.'**
  String get protegidoPeloProxySeletivoLocal127;

  /// No description provided for @instalacaoManualFallbackAvancado.
  ///
  /// In pt, this message translates to:
  /// **'Instalação Manual / Fallback Avançado'**
  String get instalacaoManualFallbackAvancado;

  /// No description provided for @baixarChromeZip.
  ///
  /// In pt, this message translates to:
  /// **'Baixar Chrome (.zip)'**
  String get baixarChromeZip;

  /// No description provided for @extensaoSalvaEmP0.
  ///
  /// In pt, this message translates to:
  /// **'Extensão salva em: {p0}'**
  String extensaoSalvaEmP0(Object p0);

  /// No description provided for @erroAoSalvarZipEmDownloads.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao salvar zip em Downloads.'**
  String get erroAoSalvarZipEmDownloads;

  /// No description provided for @baixarFirefoxXpi.
  ///
  /// In pt, this message translates to:
  /// **'Baixar Firefox (.xpi)'**
  String get baixarFirefoxXpi;

  /// No description provided for @erroAoSalvarXpiEmDownloads.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao salvar xpi em Downloads.'**
  String get erroAoSalvarXpiEmDownloads;

  /// No description provided for @ativarNoChromeManual.
  ///
  /// In pt, this message translates to:
  /// **'Ativar no Chrome (Manual)'**
  String get ativarNoChromeManual;

  /// No description provided for @ativarNoFirefoxManual.
  ///
  /// In pt, this message translates to:
  /// **'Ativar no Firefox (Manual)'**
  String get ativarNoFirefoxManual;

  /// No description provided for @comandoTerminalGuard.
  ///
  /// In pt, this message translates to:
  /// **'Comando Terminal (Guard)'**
  String get comandoTerminalGuard;

  /// No description provided for @reiniciarNavegadoresParaAtivar.
  ///
  /// In pt, this message translates to:
  /// **'Reiniciar Navegadores para Ativar?'**
  String get reiniciarNavegadoresParaAtivar;

  /// No description provided for @osSeguintesNavegadoresJaEstaoAbertos.
  ///
  /// In pt, this message translates to:
  /// **'Os seguintes navegadores já estão abertos e precisam ser fechados e reabertos para carregar a extensão Chronos:\n\n{p0}\n\nDeseja fechar e reabrir esses navegadores agora?'**
  String osSeguintesNavegadoresJaEstaoAbertos(Object p0);

  /// No description provided for @agoraNao.
  ///
  /// In pt, this message translates to:
  /// **'Agora Não'**
  String get agoraNao;

  /// No description provided for @fecharEReabrirAgora.
  ///
  /// In pt, this message translates to:
  /// **'Fechar e Reabrir Agora'**
  String get fecharEReabrirAgora;

  /// No description provided for @navegadoresReiniciadosP0.
  ///
  /// In pt, this message translates to:
  /// **'Navegadores reiniciados ({p0})!'**
  String navegadoresReiniciadosP0(Object p0);

  /// No description provided for @acessoBloqueadoPeloChronos.
  ///
  /// In pt, this message translates to:
  /// **'ACESSO BLOQUEADO PELO CHRONOS'**
  String get acessoBloqueadoPeloChronos;

  /// No description provided for @oTempoDeTelaDiarioPara.
  ///
  /// In pt, this message translates to:
  /// **'O tempo de tela diário para {p0} foi completamente esgotado.'**
  String oTempoDeTelaDiarioPara(Object p0);

  /// No description provided for @reproducaoMprisPausadaAutomaticamente.
  ///
  /// In pt, this message translates to:
  /// **'Reprodução MPRIS pausada automaticamente.'**
  String get reproducaoMprisPausadaAutomaticamente;

  /// No description provided for @janelaSobrepostaAtivaEnquantoOApp.
  ///
  /// In pt, this message translates to:
  /// **'Janela sobreposta ativa enquanto o app distrator estiver em foco.'**
  String get janelaSobrepostaAtivaEnquantoOApp;

  /// No description provided for @usarTokenDeEmergencia1hP0.
  ///
  /// In pt, this message translates to:
  /// **'Usar Token de Emergência (+1h) [{p0}/2]'**
  String usarTokenDeEmergencia1hP0(Object p0);

  /// No description provided for @avisoConsumirUmTokenDeEmergencia.
  ///
  /// In pt, this message translates to:
  /// **'Aviso: Consumir um token de emergência bloqueia todas as atividades de lazer por 24h!'**
  String get avisoConsumirUmTokenDeEmergencia;

  /// No description provided for @nenhumTokenDeEmergenciaRestantePara.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum Token de Emergência restante para este mês. Retorne aos seus estudos e foco!'**
  String get nenhumTokenDeEmergenciaRestantePara;

  /// No description provided for @idiomaPrincipalSteamApiDefinidoPara.
  ///
  /// In pt, this message translates to:
  /// **'Idioma principal Steam API definido para English (US).'**
  String get idiomaPrincipalSteamApiDefinidoPara;

  /// No description provided for @idiomaPrincipalSteamApiDefinidoPara2.
  ///
  /// In pt, this message translates to:
  /// **'Idioma principal Steam API definido para Português (Brasil).'**
  String get idiomaPrincipalSteamApiDefinidoPara2;

  /// No description provided for @modoNukeAtivoRemocaoDaExtensao.
  ///
  /// In pt, this message translates to:
  /// **'Modo Nuke ativo: remoção da extensão bloqueada até o tempo expirar.'**
  String get modoNukeAtivoRemocaoDaExtensao;

  /// No description provided for @remocaoCanceladaConcluaAVerificacaoAnti.
  ///
  /// In pt, this message translates to:
  /// **'Remoção cancelada: conclua a verificação Anti-Burla para remover a extensão.'**
  String get remocaoCanceladaConcluaAVerificacaoAnti;

  /// No description provided for @antiCheatAindaAtivoRemocaoBloqueada.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla ainda ativo. Remoção bloqueada.'**
  String get antiCheatAindaAtivoRemocaoBloqueada;

  /// No description provided for @removerExtensaoPoliticas.
  ///
  /// In pt, this message translates to:
  /// **'Remover Extensão & Políticas?'**
  String get removerExtensaoPoliticas;

  /// No description provided for @verificacaoAntiCheatConcluidaIssoRemovera.
  ///
  /// In pt, this message translates to:
  /// **'Verificação Anti-Burla concluída. Isso removerá a extensão Chronos, os links External Extensions e o Chronos Guard (políticas de Chrome/Chromium/Firefox) de todos os navegadores até você reinstalar.\n\nConfirmar remoção?'**
  String get verificacaoAntiCheatConcluidaIssoRemovera;

  /// No description provided for @removerDeTodosOsNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Remover de Todos os Navegadores'**
  String get removerDeTodosOsNavegadores;

  /// No description provided for @filtrosAntiDistracaoSalvosComSucesso.
  ///
  /// In pt, this message translates to:
  /// **'Filtros anti-distração salvos com sucesso!'**
  String get filtrosAntiDistracaoSalvosComSucesso;

  /// No description provided for @p0JaEstaNaLista.
  ///
  /// In pt, this message translates to:
  /// **'\"{p0}\" já está na lista.'**
  String p0JaEstaNaLista(Object p0);

  /// No description provided for @antiCheatAtivoDesativeOAnti.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla ativo: desative o Anti-Burla para remover tags ou nomes de jogos.'**
  String get antiCheatAtivoDesativeOAnti;

  /// No description provided for @antiCheatAtivoDesativeOAnti2.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla ativo: desative o Anti-Burla para remover a proteção de loja dos launchers.'**
  String get antiCheatAtivoDesativeOAnti2;

  /// No description provided for @configuracoesGerais.
  ///
  /// In pt, this message translates to:
  /// **'Configurações Gerais'**
  String get configuracoesGerais;

  /// No description provided for @ajustesDeNotificacoesExtensoesLocaisModo.
  ///
  /// In pt, this message translates to:
  /// **'Ajustes de notificações, extensões locais, modo e segurança'**
  String get ajustesDeNotificacoesExtensoesLocaisModo;

  /// No description provided for @versaoEAtualizacoes.
  ///
  /// In pt, this message translates to:
  /// **'Versão e Atualizações'**
  String get versaoEAtualizacoes;

  /// No description provided for @chronosP0AsAtualizacoesSaoVerificadas.
  ///
  /// In pt, this message translates to:
  /// **'Chronos {p0} — as atualizações são verificadas ao abrir o app.'**
  String chronosP0AsAtualizacoesSaoVerificadas(Object p0);

  /// No description provided for @chronosP0BuildDeDesenvolvimentoSem.
  ///
  /// In pt, this message translates to:
  /// **'Chronos {p0} (build de desenvolvimento — sem atualização automática).'**
  String chronosP0BuildDeDesenvolvimentoSem(Object p0);

  /// No description provided for @procurarAtualizacoes.
  ///
  /// In pt, this message translates to:
  /// **'Procurar atualizações'**
  String get procurarAtualizacoes;

  /// No description provided for @desinstalarChronos2.
  ///
  /// In pt, this message translates to:
  /// **'Desinstalar Chronos'**
  String get desinstalarChronos2;

  /// No description provided for @notificacoesDeDesktop.
  ///
  /// In pt, this message translates to:
  /// **'Notificações de Desktop'**
  String get notificacoesDeDesktop;

  /// No description provided for @oModoNaoPerturbeDoSistema.
  ///
  /// In pt, this message translates to:
  /// **'O modo \"Não perturbe\" do sistema está ligado: as notificações do Chronos não vão aparecer até você desligá-lo.'**
  String get oModoNaoPerturbeDoSistema;

  /// No description provided for @verificar.
  ///
  /// In pt, this message translates to:
  /// **'Verificar'**
  String get verificar;

  /// No description provided for @notificarInicioDeAppMonitorado.
  ///
  /// In pt, this message translates to:
  /// **'Notificar Início de App Monitorado'**
  String get notificarInicioDeAppMonitorado;

  /// No description provided for @exibeUmaNotificacaoNoDesktopAvisando.
  ///
  /// In pt, this message translates to:
  /// **'Exibe uma notificação no desktop avisando que o app em execução está sendo cronometrado.'**
  String get exibeUmaNotificacaoNoDesktopAvisando;

  /// No description provided for @notificacaoDeAppMonitoradoAtivada.
  ///
  /// In pt, this message translates to:
  /// **'Notificação de app monitorado ativada'**
  String get notificacaoDeAppMonitoradoAtivada;

  /// No description provided for @notificacaoDeAppMonitoradoDesativada.
  ///
  /// In pt, this message translates to:
  /// **'Notificação de app monitorado desativada'**
  String get notificacaoDeAppMonitoradoDesativada;

  /// No description provided for @alertasDeTempoDeTelaRestante.
  ///
  /// In pt, this message translates to:
  /// **'Alertas de Tempo de Tela Restante'**
  String get alertasDeTempoDeTelaRestante;

  /// No description provided for @avisosAutomaticosQuandoRestarem15m5m.
  ///
  /// In pt, this message translates to:
  /// **'Avisos automáticos quando restarem 15m, 5m e 1m antes do término do tempo de tela diário.'**
  String get avisosAutomaticosQuandoRestarem15m5m;

  /// No description provided for @avisosPeriodicosDeUsoAtivo.
  ///
  /// In pt, this message translates to:
  /// **'Avisos Periódicos de Uso Ativo'**
  String get avisosPeriodicosDeUsoAtivo;

  /// No description provided for @lembretesEmIntervalosRegularesExA.
  ///
  /// In pt, this message translates to:
  /// **'Lembretes em intervalos regulares (ex: a cada 15 min) com o tempo já utilizado.'**
  String get lembretesEmIntervalosRegularesExA;

  /// No description provided for @extensoesDosNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Extensões dos Navegadores'**
  String get extensoesDosNavegadores;

  /// No description provided for @protegeTodosOsNavegadoresDoDispositivo.
  ///
  /// In pt, this message translates to:
  /// **'Protege todos os navegadores do dispositivo offline: extensão local nos Chromium (Chrome, Chromium, Brave, Edge, Vivaldi, Opera) e Proxy Seletivo Focus + CA Local no Firefox.'**
  String get protegeTodosOsNavegadoresDoDispositivo;

  /// No description provided for @navegadoresDetectadosNoSistema.
  ///
  /// In pt, this message translates to:
  /// **'Navegadores Detectados no Sistema:'**
  String get navegadoresDetectadosNoSistema;

  /// No description provided for @extensaoRemovidaAposVerificacaoAntiCheat.
  ///
  /// In pt, this message translates to:
  /// **'Extensão removida após verificação Anti-Burla. Clique abaixo para reinstalar em todos os navegadores.'**
  String get extensaoRemovidaAposVerificacaoAntiCheat;

  /// No description provided for @configurandoNavegadoresGuard.
  ///
  /// In pt, this message translates to:
  /// **'Configurando Navegadores & Guard...'**
  String get configurandoNavegadoresGuard;

  /// No description provided for @protecaoPermanenteDoSistemaAntiBurla.
  ///
  /// In pt, this message translates to:
  /// **'Proteção Permanente do Sistema (Anti-Burla de Navegadores)'**
  String get protecaoPermanenteDoSistemaAntiBurla;

  /// No description provided for @protecaoDoSistemaAtivaTrancada.
  ///
  /// In pt, this message translates to:
  /// **'Proteção do Sistema Ativa & Trancada'**
  String get protecaoDoSistemaAtivaTrancada;

  /// No description provided for @politicasForcadasAtivasEmChromeChromium.
  ///
  /// In pt, this message translates to:
  /// **'Políticas forçadas ativas em Chrome/Chromium/Brave/Edge/Vivaldi/Opera (CRX3 assinado) e Firefox Release (Proxy Seletivo Focus + CA Local + PAC, sem avisos em about:policies). Remoção de extensão e navegação anônima estão bloqueadas.'**
  String get politicasForcadasAtivasEmChromeChromium;

  /// No description provided for @reAplicarPoliticasDoSistema.
  ///
  /// In pt, this message translates to:
  /// **'Re-aplicar Políticas do Sistema'**
  String get reAplicarPoliticasDoSistema;

  /// No description provided for @politicasDoSistemaVerificadasERe.
  ///
  /// In pt, this message translates to:
  /// **'Políticas do sistema verificadas e re-aplicadas!'**
  String get politicasDoSistemaVerificadasERe;

  /// No description provided for @falhaAoReAplicarPoliticas.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao re-aplicar políticas.'**
  String get falhaAoReAplicarPoliticas;

  /// No description provided for @removendo.
  ///
  /// In pt, this message translates to:
  /// **'Removendo...'**
  String get removendo;

  /// No description provided for @removerExtensaoVerificarAntiCheat.
  ///
  /// In pt, this message translates to:
  /// **'Remover Extensão (Verificar Anti-Burla)'**
  String get removerExtensaoVerificarAntiCheat;

  /// No description provided for @oChronosGuardInstaladoPossuiPoliticas.
  ///
  /// In pt, this message translates to:
  /// **'O Chronos Guard instalado possui políticas antigas (ex.: ExtensionSettings sem assinatura no Firefox Release). Clique em \"Instalar / Atualizar em Todos os Navegadores\" acima para corrigir em 1 clique.'**
  String get oChronosGuardInstaladoPossuiPoliticas;

  /// No description provided for @oChronosGuardGravaPoliticasPermanentes.
  ///
  /// In pt, this message translates to:
  /// **'O Chronos Guard grava políticas permanentes em /etc/ (com sua autorização Polkit) para impedir desinstalação manual e navegação anônima. Use o botão principal acima para ativar em 1 clique.'**
  String get oChronosGuardGravaPoliticasPermanentes;

  /// No description provided for @atualizarGuardViaPolkit1Clique.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar Guard via Polkit (1 Clique)'**
  String get atualizarGuardViaPolkit1Clique;

  /// No description provided for @ativarGuardViaPolkit1Clique.
  ///
  /// In pt, this message translates to:
  /// **'Ativar Guard via Polkit (1 Clique)'**
  String get ativarGuardViaPolkit1Clique;

  /// No description provided for @modoDoAplicativoCadastro.
  ///
  /// In pt, this message translates to:
  /// **'Modo do Aplicativo & Cadastro'**
  String get modoDoAplicativoCadastro;

  /// No description provided for @modoAtivoP0.
  ///
  /// In pt, this message translates to:
  /// **'Modo Ativo: {p0}'**
  String modoAtivoP0(Object p0);

  /// No description provided for @configuradoComPinEProtecaoParental.
  ///
  /// In pt, this message translates to:
  /// **'Configurado com PIN e proteção parental de restrições.'**
  String get configuradoComPinEProtecaoParental;

  /// No description provided for @focadoEmAutonomiaComprometimentoPessoalE.
  ///
  /// In pt, this message translates to:
  /// **'Focado em autonomia, comprometimento pessoal e produtividade.'**
  String get focadoEmAutonomiaComprometimentoPessoalE;

  /// No description provided for @trocarModoRefazerCadastro.
  ///
  /// In pt, this message translates to:
  /// **'Trocar Modo / Refazer Cadastro'**
  String get trocarModoRefazerCadastro;

  /// No description provided for @antiCheatProtecaoContraBurlar.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla & Proteção Contra Burlar'**
  String get antiCheatProtecaoContraBurlar;

  /// No description provided for @modoNukeAtivoP0SRestantes.
  ///
  /// In pt, this message translates to:
  /// **'Modo Nuke Ativo ({p0}s restantes)'**
  String modoNukeAtivoP0SRestantes(Object p0);

  /// No description provided for @antiCheatAtivoDesafioStayfocusd.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla Ativo (Desafio StayFocusd)'**
  String get antiCheatAtivoDesafioStayfocusd;

  /// No description provided for @antiCheatDesativado.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla Desativado'**
  String get antiCheatDesativado;

  /// No description provided for @bloqueiaModificacoesDeRegrasAumentoDe.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueia modificações de regras, aumento de limites nos momentos de fraqueza e remoção de extensões.'**
  String get bloqueiaModificacoesDeRegrasAumentoDe;

  /// No description provided for @gerenciarAntiCheat.
  ///
  /// In pt, this message translates to:
  /// **'Gerenciar Anti-Burla'**
  String get gerenciarAntiCheat;

  /// No description provided for @ativarAntiCheat.
  ///
  /// In pt, this message translates to:
  /// **'Ativar Anti-Burla'**
  String get ativarAntiCheat;

  /// No description provided for @textosDoDesafio.
  ///
  /// In pt, this message translates to:
  /// **'Textos do desafio'**
  String get textosDoDesafio;

  /// No description provided for @antiBurlaAtivoOsTextosDo.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla ativo: os textos do desafio não podem ser alterados agora.'**
  String get antiBurlaAtivoOsTextosDo;

  /// No description provided for @gerenciamentoDeDadosLocaisOffline.
  ///
  /// In pt, this message translates to:
  /// **'Gerenciamento de Dados Locais (Offline)'**
  String get gerenciamentoDeDadosLocaisOffline;

  /// No description provided for @todasAsInformacoesRegrasETempos.
  ///
  /// In pt, this message translates to:
  /// **'Todas as informações, regras e tempos de tela do Chronos são armazenados 100% localmente no seu computador.'**
  String get todasAsInformacoesRegrasETempos;

  /// No description provided for @zerarConsumoDiarioDeHoje.
  ///
  /// In pt, this message translates to:
  /// **'Zerar Consumo Diário de Hoje'**
  String get zerarConsumoDiarioDeHoje;

  /// No description provided for @reiniciarBancoDeDadosCompleto.
  ///
  /// In pt, this message translates to:
  /// **'Reiniciar Banco de Dados Completo'**
  String get reiniciarBancoDeDadosCompleto;

  /// No description provided for @reiniciarBancoDeDados2.
  ///
  /// In pt, this message translates to:
  /// **'Reiniciar Banco de Dados'**
  String get reiniciarBancoDeDados2;

  /// No description provided for @atencaoIssoIraApagarTodasAs.
  ///
  /// In pt, this message translates to:
  /// **'Atenção: Isso irá apagar todas as regras de bloqueio criadas e redefinir o banco para o estado inicial. Deseja continuar?'**
  String get atencaoIssoIraApagarTodasAs;

  /// No description provided for @zerarTudo.
  ///
  /// In pt, this message translates to:
  /// **'Zerar Tudo'**
  String get zerarTudo;

  /// No description provided for @instalarProtecaoPermanente.
  ///
  /// In pt, this message translates to:
  /// **'Instalar Proteção Permanente'**
  String get instalarProtecaoPermanente;

  /// No description provided for @estaEtapaConfiguraOsArquivosDe.
  ///
  /// In pt, this message translates to:
  /// **'Esta etapa configura os arquivos de política oficiais em /etc/ e ativa o serviço do systemd para travar as extensões em definitivo contra burla.'**
  String get estaEtapaConfiguraOsArquivosDe;

  /// No description provided for @comoDesejaProsseguir.
  ///
  /// In pt, this message translates to:
  /// **'Como deseja prosseguir?'**
  String get comoDesejaProsseguir;

  /// No description provided for @opcao1CliqueEmAbrirTerminal.
  ///
  /// In pt, this message translates to:
  /// **'Opção 1: Clique em \"Abrir Terminal\" para abrir uma janela onde você digita sua senha do sudo UMA vez.\nOpção 2: Ou copie o comando abaixo e execute no seu terminal favorito:'**
  String get opcao1CliqueEmAbrirTerminal;

  /// No description provided for @copiarComando.
  ///
  /// In pt, this message translates to:
  /// **'Copiar Comando'**
  String get copiarComando;

  /// No description provided for @comandoCopiadoParaAAreaDe.
  ///
  /// In pt, this message translates to:
  /// **'Comando copiado para a área de transferência!'**
  String get comandoCopiadoParaAAreaDe;

  /// No description provided for @verificarStatus.
  ///
  /// In pt, this message translates to:
  /// **'Verificar Status'**
  String get verificarStatus;

  /// No description provided for @protecaoDoSistemaAtivaEConfirmada.
  ///
  /// In pt, this message translates to:
  /// **'Proteção do sistema ativa e confirmada!'**
  String get protecaoDoSistemaAtivaEConfirmada;

  /// No description provided for @protecaoAindaPendenteDeInstalacao.
  ///
  /// In pt, this message translates to:
  /// **'Proteção ainda pendente de instalação.'**
  String get protecaoAindaPendenteDeInstalacao;

  /// No description provided for @abrirTerminal.
  ///
  /// In pt, this message translates to:
  /// **'Abrir Terminal'**
  String get abrirTerminal;

  /// No description provided for @terminalAbertoDigiteSuaSenhaNa.
  ///
  /// In pt, this message translates to:
  /// **'Terminal aberto! Digite sua senha na janela para concluir.'**
  String get terminalAbertoDigiteSuaSenhaNa;

  /// No description provided for @naoFoiPossivelAbrirOTerminal.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível abrir o terminal automaticamente. Comando copiado!'**
  String get naoFoiPossivelAbrirOTerminal;

  /// No description provided for @ativarNoGoogleChrome.
  ///
  /// In pt, this message translates to:
  /// **'Ativar no Google Chrome'**
  String get ativarNoGoogleChrome;

  /// No description provided for @oGoogleChromeOficialBloqueiaInjecoes.
  ///
  /// In pt, this message translates to:
  /// **'O Google Chrome oficial bloqueia injeções ocultas por linha de comando por segurança. Para ativá-la, basta carregar a pasta local uma única vez (leva 10 segundos).'**
  String get oGoogleChromeOficialBloqueiaInjecoes;

  /// No description provided for @passoAPassoRapido.
  ///
  /// In pt, this message translates to:
  /// **'Passo a passo rápido:'**
  String get passoAPassoRapido;

  /// No description provided for @cliqueNoBotaoAbrirChromeAbaixo.
  ///
  /// In pt, this message translates to:
  /// **'Clique no botão \"Abrir Chrome\" abaixo. O Chrome abrirá em chrome://extensions e o caminho da pasta será copiado.'**
  String get cliqueNoBotaoAbrirChromeAbaixo;

  /// No description provided for @noChromeAtiveAChaveModo.
  ///
  /// In pt, this message translates to:
  /// **'No Chrome, ative a chave \"Modo do desenvolvedor\" no canto superior direito.'**
  String get noChromeAtiveAChaveModo;

  /// No description provided for @cliqueNoBotaoCarregarSemCompactacao.
  ///
  /// In pt, this message translates to:
  /// **'Clique no botão \"Carregar sem compactação\" (canto superior esquerdo).'**
  String get cliqueNoBotaoCarregarSemCompactacao;

  /// No description provided for @pressioneCtrlVOuSelecioneA.
  ///
  /// In pt, this message translates to:
  /// **'Pressione Ctrl+V ou selecione a pasta da extensão e confirme.'**
  String get pressioneCtrlVOuSelecioneA;

  /// No description provided for @copiarCaminho.
  ///
  /// In pt, this message translates to:
  /// **'Copiar Caminho'**
  String get copiarCaminho;

  /// No description provided for @caminhoCopiadoParaAAreaDe.
  ///
  /// In pt, this message translates to:
  /// **'Caminho copiado para a área de transferência!'**
  String get caminhoCopiadoParaAAreaDe;

  /// No description provided for @baixarZip.
  ///
  /// In pt, this message translates to:
  /// **'Baixar .zip'**
  String get baixarZip;

  /// No description provided for @arquivoSalvoEmP0.
  ///
  /// In pt, this message translates to:
  /// **'Arquivo salvo em: {p0}'**
  String arquivoSalvoEmP0(Object p0);

  /// No description provided for @erroAoGerarZipParaDownloads.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao gerar zip para Downloads.'**
  String get erroAoGerarZipParaDownloads;

  /// No description provided for @abrirChrome.
  ///
  /// In pt, this message translates to:
  /// **'Abrir Chrome'**
  String get abrirChrome;

  /// No description provided for @chromeAbertoCaminhoCopiadoParaA.
  ///
  /// In pt, this message translates to:
  /// **'Chrome aberto! Caminho copiado para a área de transferência.'**
  String get chromeAbertoCaminhoCopiadoParaA;

  /// No description provided for @ativarExtensaoNoFirefox.
  ///
  /// In pt, this message translates to:
  /// **'Ativar Extensão no Firefox'**
  String get ativarExtensaoNoFirefox;

  /// No description provided for @noFirefoxReleasePadraoAMozilla.
  ///
  /// In pt, this message translates to:
  /// **'No Firefox Release padrão, a Mozilla exige assinatura para .xpi externos — por isso a proteção permanente do Chronos funciona pelo Proxy Seletivo Local + Certificado CA via Chronos Guard. Para Firefox ESR/Dev/LibreWolf/Zen ou testes temporários em about:debugging, use o .xpi:'**
  String get noFirefoxReleasePadraoAMozilla;

  /// No description provided for @cliqueNoBotaoAbrirFirefoxAbaixo.
  ///
  /// In pt, this message translates to:
  /// **'Clique no botão \"Abrir Firefox\" abaixo para ir direto à aba de depuração.'**
  String get cliqueNoBotaoAbrirFirefoxAbaixo;

  /// No description provided for @cliqueNoBotaoCarregarExtensaoTemporaria.
  ///
  /// In pt, this message translates to:
  /// **'Clique no botão \"Carregar extensão temporária...\".'**
  String get cliqueNoBotaoCarregarExtensaoTemporaria;

  /// No description provided for @selecioneOArquivoManifestJsonNa.
  ///
  /// In pt, this message translates to:
  /// **'Selecione o arquivo \"manifest.json\" na pasta abaixo ou o arquivo .xpi em ~/Downloads.'**
  String get selecioneOArquivoManifestJsonNa;

  /// No description provided for @caminhoDoManifestJsonCopiado.
  ///
  /// In pt, this message translates to:
  /// **'Caminho do manifest.json copiado!'**
  String get caminhoDoManifestJsonCopiado;

  /// No description provided for @erroAoGerarXpiParaDownloads.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao gerar xpi para Downloads.'**
  String get erroAoGerarXpiParaDownloads;

  /// No description provided for @abrirFirefox.
  ///
  /// In pt, this message translates to:
  /// **'Abrir Firefox'**
  String get abrirFirefox;

  /// No description provided for @firefoxAbertoCaminhoCopiadoParaA.
  ///
  /// In pt, this message translates to:
  /// **'Firefox aberto! Caminho copiado para a área de transferência.'**
  String get firefoxAbertoCaminhoCopiadoParaA;

  /// No description provided for @aparenciaModoDeTema.
  ///
  /// In pt, this message translates to:
  /// **'Aparência & Modo de Tema'**
  String get aparenciaModoDeTema;

  /// No description provided for @personalizeOTemaVisualDoChronos.
  ///
  /// In pt, this message translates to:
  /// **'Personalize o tema visual do Chronos. O Modo Claro é otimizado para ambientes claros com alto contraste, e o Modo Escuro reduz o cansaço visual.'**
  String get personalizeOTemaVisualDoChronos;

  /// No description provided for @idiomaPrincipalTagsAutocompleteSteamApi.
  ///
  /// In pt, this message translates to:
  /// **'Idioma'**
  String get idiomaPrincipalTagsAutocompleteSteamApi;

  /// No description provided for @asTagsSaoEnviadasEmIngles.
  ///
  /// In pt, this message translates to:
  /// **'Idioma do app, das extensões e das telas de bloqueio. As tags da Steam aparecem neste idioma quando disponíveis.'**
  String get asTagsSaoEnviadasEmIngles;

  /// No description provided for @portuguesBr.
  ///
  /// In pt, this message translates to:
  /// **'Português (BR)'**
  String get portuguesBr;

  /// No description provided for @englishUs.
  ///
  /// In pt, this message translates to:
  /// **'English (US)'**
  String get englishUs;

  /// No description provided for @configBravesoftwareBraveBrowser.
  ///
  /// In pt, this message translates to:
  /// **'.config/BraveSoftware/Brave-Browser'**
  String get configBravesoftwareBraveBrowser;

  /// No description provided for @aoAtivarOAntiBurlaO.
  ///
  /// In pt, this message translates to:
  /// **'Se você cadastrar seus textos, o Chronos sorteia só entre eles (os textos padrão deixam de ser usados). Sem textos seus, usa os padrão. Escreva um texto por bloco, separados por uma linha em branco (mínimo de 120 caracteres cada). Não dá para alterar com o Anti-Burla ativo.'**
  String get aoAtivarOAntiBurlaO;

  /// No description provided for @seuTextoAqui.
  ///
  /// In pt, this message translates to:
  /// **'Seu texto aqui…'**
  String get seuTextoAqui;

  /// No description provided for @salvar.
  ///
  /// In pt, this message translates to:
  /// **'Salvar'**
  String get salvar;

  /// No description provided for @atualizacoesDaExtensao.
  ///
  /// In pt, this message translates to:
  /// **'Atualizações da extensão'**
  String get atualizacoesDaExtensao;

  /// No description provided for @atualizarExtensoesAutomaticamente.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar extensões automaticamente'**
  String get atualizarExtensoesAutomaticamente;

  /// No description provided for @quandoOChronosForAtualizadoOs.
  ///
  /// In pt, this message translates to:
  /// **'Quando o Chronos for atualizado, os navegadores instalam a nova extensão sozinhos.'**
  String get quandoOChronosForAtualizadoOs;

  /// No description provided for @firefoxAtualizaAoReabrirONavegador.
  ///
  /// In pt, this message translates to:
  /// **'Firefox: também atualiza pelo Chronos (versões assinadas).'**
  String get firefoxAtualizaAoReabrirONavegador;

  /// No description provided for @atualizarExtensoesAgora.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar extensões agora'**
  String get atualizarExtensoesAgora;

  /// No description provided for @pedidoEnviadoOChromeInstalaA.
  ///
  /// In pt, this message translates to:
  /// **'Pedido enviado. Os navegadores instalam a nova versão em alguns segundos.'**
  String get pedidoEnviadoOChromeInstalaA;

  /// No description provided for @mostrarApenasVideosDestesTipos.
  ///
  /// In pt, this message translates to:
  /// **'Mostrar apenas vídeos destes tipos'**
  String get mostrarApenasVideosDestesTipos;

  /// No description provided for @escolhaAoMenosUmTipoAbaixo.
  ///
  /// In pt, this message translates to:
  /// **'Escolha ao menos um tipo abaixo para ativar.'**
  String get escolhaAoMenosUmTipoAbaixo;

  /// No description provided for @aHomeEOsRelacionadosSo.
  ///
  /// In pt, this message translates to:
  /// **'A home e os relacionados só mostram os tipos escolhidos. A busca continua mostrando tudo (e desconta tempo).'**
  String get aHomeEOsRelacionadosSo;

  /// No description provided for @escolhaAoMenosUmTipoAntes.
  ///
  /// In pt, this message translates to:
  /// **'Escolha ao menos um tipo antes de ativar.'**
  String get escolhaAoMenosUmTipoAntes;

  /// No description provided for @importarDaListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Importar da Lista Branca'**
  String get importarDaListaBranca;

  /// No description provided for @nenhumTipoDoYoutubeNaLista.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum tipo do YouTube na Lista Branca.'**
  String get nenhumTipoDoYoutubeNaLista;

  /// No description provided for @tiposPorCanalPalavra.
  ///
  /// In pt, this message translates to:
  /// **'Tipos por canal/palavra'**
  String get tiposPorCanalPalavra;

  /// No description provided for @filtrosDeConteudoAntiDistracaoPor.
  ///
  /// In pt, this message translates to:
  /// **'Filtros de Conteúdo & Anti-Distração por Plataforma (Estilo StayFocusd)'**
  String get filtrosDeConteudoAntiDistracaoPor;

  /// No description provided for @configureFiltrosDeCssEHtml.
  ///
  /// In pt, this message translates to:
  /// **'Configure filtros de CSS e HTML específicos para cada aplicativo ou rede social. Elimine gatilhos de dopamina sem precisar bloquear os sites por completo.'**
  String get configureFiltrosDeCssEHtml;

  /// No description provided for @detoxGlobalTodosOsSites.
  ///
  /// In pt, this message translates to:
  /// **'Detox Global (Todos os Sites)'**
  String get detoxGlobalTodosOsSites;

  /// No description provided for @modoPretoEBrancoGrayscaleDetox.
  ///
  /// In pt, this message translates to:
  /// **'Modo Preto e Branco (Grayscale Detox)'**
  String get modoPretoEBrancoGrayscaleDetox;

  /// No description provided for @aplicaEscalaDeCinzaEmTodas.
  ///
  /// In pt, this message translates to:
  /// **'Aplica escala de cinza em todas as páginas para desestimular consumo compulsivo visual.'**
  String get aplicaEscalaDeCinzaEmTodas;

  /// No description provided for @bloquearNotificacoesEBadges.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Notificações e Badges'**
  String get bloquearNotificacoesEBadges;

  /// No description provided for @removeSinosVermelhosEAlertasNumericos.
  ///
  /// In pt, this message translates to:
  /// **'Remove sinos vermelhos e alertas numéricos em todos os sites para evitar interrupções.'**
  String get removeSinosVermelhosEAlertasNumericos;

  /// No description provided for @youtubeFocus.
  ///
  /// In pt, this message translates to:
  /// **'YouTube Focus'**
  String get youtubeFocus;

  /// No description provided for @bloquearYoutubeShorts.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear YouTube Shorts'**
  String get bloquearYoutubeShorts;

  /// No description provided for @ocultaCarrosseisDeShortsNaHome.
  ///
  /// In pt, this message translates to:
  /// **'Oculta carrosséis de Shorts na home, na busca e na barra lateral.'**
  String get ocultaCarrosseisDeShortsNaHome;

  /// No description provided for @ocultarFeedDaHome.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar Feed da Home'**
  String get ocultarFeedDaHome;

  /// No description provided for @ocultaTodasAsRecomendacoesAlgoritmicasDa.
  ///
  /// In pt, this message translates to:
  /// **'Oculta todas as recomendações algorítmicas da página inicial do YouTube.'**
  String get ocultaTodasAsRecomendacoesAlgoritmicasDa;

  /// No description provided for @ocultarVideosRelacionadosBarraLateral.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar Vídeos Relacionados (Barra Lateral)'**
  String get ocultarVideosRelacionadosBarraLateral;

  /// No description provided for @removeSugestoesDeVideosAoLado.
  ///
  /// In pt, this message translates to:
  /// **'Remove sugestões de vídeos ao lado do reprodutor para evitar distrações.'**
  String get removeSugestoesDeVideosAoLado;

  /// No description provided for @ocultarComentariosDoYoutube.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar Comentários do YouTube'**
  String get ocultarComentariosDoYoutube;

  /// No description provided for @ocultaTodaASecaoDeComentarios.
  ///
  /// In pt, this message translates to:
  /// **'Oculta toda a seção de comentários em qualquer vídeo.'**
  String get ocultaTodaASecaoDeComentarios;

  /// No description provided for @instagramFocus.
  ///
  /// In pt, this message translates to:
  /// **'Instagram Focus'**
  String get instagramFocus;

  /// No description provided for @bloquearInstagramReels.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Instagram Reels'**
  String get bloquearInstagramReels;

  /// No description provided for @removeAAbaEOCarrossel.
  ///
  /// In pt, this message translates to:
  /// **'Remove a aba e o carrossel de vídeos curtos Reels no Instagram Web.'**
  String get removeAAbaEOCarrossel;

  /// No description provided for @ocultarFeedPrincipalExplore.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar Feed Principal & Explore'**
  String get ocultarFeedPrincipalExplore;

  /// No description provided for @ocultaOFeedInfinitoDePostagens.
  ///
  /// In pt, this message translates to:
  /// **'Oculta o feed infinito de postagens e sugestões da página inicial.'**
  String get ocultaOFeedInfinitoDePostagens;

  /// No description provided for @ocultarComentariosDoInstagram.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar Comentários do Instagram'**
  String get ocultarComentariosDoInstagram;

  /// No description provided for @ocultaComentariosSobPostagensEVideos.
  ///
  /// In pt, this message translates to:
  /// **'Oculta comentários sob postagens e vídeos.'**
  String get ocultaComentariosSobPostagensEVideos;

  /// No description provided for @tiktokFocus.
  ///
  /// In pt, this message translates to:
  /// **'TikTok Focus'**
  String get tiktokFocus;

  /// No description provided for @bloquearFeedDeVideosRecomendados.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Feed de Vídeos Recomendados'**
  String get bloquearFeedDeVideosRecomendados;

  /// No description provided for @bloqueiaOFluxoInfinitoDeVideos.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueia o fluxo infinito de vídeos curtos \"Para Você\" no TikTok.'**
  String get bloqueiaOFluxoInfinitoDeVideos;

  /// No description provided for @redditFocus.
  ///
  /// In pt, this message translates to:
  /// **'Reddit Focus'**
  String get redditFocus;

  /// No description provided for @bloquearFeedPrincipalPopular.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Feed Principal / Popular'**
  String get bloquearFeedPrincipalPopular;

  /// No description provided for @ocultaATimelineDePostsInfinitos.
  ///
  /// In pt, this message translates to:
  /// **'Oculta a timeline de posts infinitos no r/all e na página inicial do Reddit.'**
  String get ocultaATimelineDePostsInfinitos;

  /// No description provided for @ocultarSecoesDeComentarios.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar Seções de Comentários'**
  String get ocultarSecoesDeComentarios;

  /// No description provided for @ocultaAsArvoresDeDiscussaoE.
  ///
  /// In pt, this message translates to:
  /// **'Oculta as árvores de discussão e comentários em posts do Reddit.'**
  String get ocultaAsArvoresDeDiscussaoE;

  /// No description provided for @bloquearConteudo18Nsfw.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Conteúdo +18 (NSFW)'**
  String get bloquearConteudo18Nsfw;

  /// No description provided for @escondePostsNsfwNosFeedsE.
  ///
  /// In pt, this message translates to:
  /// **'Esconde posts NSFW nos feeds e na busca e bloqueia subreddits e posts +18. Com o Anti-Burla ativo não pode ser desligado.'**
  String get escondePostsNsfwNosFeedsE;

  /// No description provided for @xTwitterFocus.
  ///
  /// In pt, this message translates to:
  /// **'X / Twitter Focus'**
  String get xTwitterFocus;

  /// No description provided for @bloquearTimelineFeedPrincipal.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Timeline / Feed Principal'**
  String get bloquearTimelineFeedPrincipal;

  /// No description provided for @ocultaATimelineParaVoceE.
  ///
  /// In pt, this message translates to:
  /// **'Oculta a timeline \"Para Você\" e \"Seguindo\" no X (Twitter).'**
  String get ocultaATimelineParaVoceE;

  /// No description provided for @ocultarAssuntosDoMomentoTrending.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar Assuntos do Momento (Trending)'**
  String get ocultarAssuntosDoMomentoTrending;

  /// No description provided for @removeABarraLateralDeTendencias.
  ///
  /// In pt, this message translates to:
  /// **'Remove a barra lateral de tendências e notícias exploratórias.'**
  String get removeABarraLateralDeTendencias;

  /// No description provided for @bloquearConteudo18Sensivel.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Conteúdo +18 (Sensível)'**
  String get bloquearConteudo18Sensivel;

  /// No description provided for @escondePostsComMidiaSensivelE.
  ///
  /// In pt, this message translates to:
  /// **'Esconde posts com mídia sensível e bloqueia perfis marcados como sensíveis. Com o Anti-Burla ativo não pode ser desligado.'**
  String get escondePostsComMidiaSensivelE;

  /// No description provided for @linkedinFocus.
  ///
  /// In pt, this message translates to:
  /// **'LinkedIn Focus'**
  String get linkedinFocus;

  /// No description provided for @bloquearFeedDeNoticiasDoLinkedin.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Feed de Notícias do LinkedIn'**
  String get bloquearFeedDeNoticiasDoLinkedin;

  /// No description provided for @ocultaATimelineDePostagensPara.
  ///
  /// In pt, this message translates to:
  /// **'Oculta a timeline de postagens para focar apenas em mensagens e perfis diretos.'**
  String get ocultaATimelineDePostagensPara;

  /// No description provided for @hudFlutuanteNosNavegadoresPilula.
  ///
  /// In pt, this message translates to:
  /// **'HUD Flutuante nos Navegadores (Pílula)'**
  String get hudFlutuanteNosNavegadoresPilula;

  /// No description provided for @opacidadeDaPilulaAlfa.
  ///
  /// In pt, this message translates to:
  /// **'Opacidade da Pílula (Alfa)'**
  String get opacidadeDaPilulaAlfa;

  /// No description provided for @controlaATransparenciaDaPilulaRecolhida.
  ///
  /// In pt, this message translates to:
  /// **'Controla a transparência da pílula recolhida e do olho fechado nos navegadores.'**
  String get controlaATransparenciaDaPilulaRecolhida;

  /// No description provided for @tamanhoDaPilula.
  ///
  /// In pt, this message translates to:
  /// **'Tamanho da Pílula'**
  String get tamanhoDaPilula;

  /// No description provided for @ajustaAEscalaDaPilulaE.
  ///
  /// In pt, this message translates to:
  /// **'Ajusta a escala da pílula e o diâmetro do olho fechado (sempre igual à altura da pílula).'**
  String get ajustaAEscalaDaPilulaE;

  /// No description provided for @aoEsconderPilulaMostrarIconeDe.
  ///
  /// In pt, this message translates to:
  /// **'Ao esconder pílula, mostrar ícone de Olho arrastável'**
  String get aoEsconderPilulaMostrarIconeDe;

  /// No description provided for @quandoAtivoMinimizarTransformaAPilula.
  ///
  /// In pt, this message translates to:
  /// **'Quando ativo, minimizar transforma a pílula em um botão circular com olho fechado arrastável do mesmo tamanho (altura) da pílula; desligado, oculta totalmente (Alt+Shift+C reexibe).'**
  String get quandoAtivoMinimizarTransformaAPilula;

  /// No description provided for @launchersJogosSteamApiHeroicEpic.
  ///
  /// In pt, this message translates to:
  /// **'Launchers & Jogos (Steam API, Heroic, Epic, GOG, Lutris)'**
  String get launchersJogosSteamApiHeroicEpic;

  /// No description provided for @antiCheatAtivoRemocaoBloqueada.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla Ativo (Remoção Bloqueada)'**
  String get antiCheatAtivoRemocaoBloqueada;

  /// No description provided for @ativarFiltroEmLaunchersLojasDe.
  ///
  /// In pt, this message translates to:
  /// **'Ativar Filtro em Launchers & Lojas de Jogos'**
  String get ativarFiltroEmLaunchersLojasDe;

  /// No description provided for @bloqueiaJogosEmExecucaoPaginasDe.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueia jogos em execução, páginas de loja, guias, discussões e artworks por nome ou tag via Steam API. Adicionar é sempre livre; remover exige Anti-Burla desativado.'**
  String get bloqueiaJogosEmExecucaoPaginasDe;

  /// No description provided for @antiCheatAtivoDesativeOAnti3.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla ativo: desative o Anti-Burla para desligar o filtro de launchers.'**
  String get antiCheatAtivoDesativeOAnti3;

  /// No description provided for @tagsProibidasSteamApi.
  ///
  /// In pt, this message translates to:
  /// **'Tags Proibidas (Steam API)'**
  String get tagsProibidasSteamApi;

  /// No description provided for @buscarTagNaSteamApiEx.
  ///
  /// In pt, this message translates to:
  /// **'Buscar tag na Steam API (ex: Ação, Souls-like, Terror, FPS)...'**
  String get buscarTagNaSteamApiEx;

  /// No description provided for @nomesDeJogosProibidos.
  ///
  /// In pt, this message translates to:
  /// **'Nomes de Jogos Proibidos'**
  String get nomesDeJogosProibidos;

  /// No description provided for @buscarJogoNaSteamApiEx.
  ///
  /// In pt, this message translates to:
  /// **'Buscar jogo na Steam API (ex: Counter-Strike 2, Elden Ring)...'**
  String get buscarJogoNaSteamApiEx;

  /// No description provided for @protegerLojaComunidadeDentroDaSteam.
  ///
  /// In pt, this message translates to:
  /// **'Proteger Loja/Comunidade dentro da Steam/Heroic (Proxy + NSS)'**
  String get protegerLojaComunidadeDentroDaSteam;

  /// No description provided for @ocultarJogosDetectadosP0.
  ///
  /// In pt, this message translates to:
  /// **'Ocultar Jogos Detectados ({p0})'**
  String ocultarJogosDetectadosP0(Object p0);

  /// No description provided for @consultarJogosDosLaunchersSteamApi.
  ///
  /// In pt, this message translates to:
  /// **'Consultar Jogos dos Launchers (Steam API)'**
  String get consultarJogosDosLaunchersSteamApi;

  /// No description provided for @nenhumJogoInstaladoDetectadoNosLaunchers.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum jogo instalado detectado nos launchers locais (Steam, Heroic, Lutris, Bottles).'**
  String get nenhumJogoInstaladoDetectadoNosLaunchers;

  /// No description provided for @bloquearJogo.
  ///
  /// In pt, this message translates to:
  /// **'+ Bloquear Jogo'**
  String get bloquearJogo;

  /// No description provided for @tagCanonicaSteamApiP0.
  ///
  /// In pt, this message translates to:
  /// **'Tag canônica Steam API: {p0}'**
  String tagCanonicaSteamApiP0(Object p0);

  /// No description provided for @sugestoesSteamApi.
  ///
  /// In pt, this message translates to:
  /// **'Sugestões Steam API:'**
  String get sugestoesSteamApi;

  /// No description provided for @enviaP0ParaASteamApi.
  ///
  /// In pt, this message translates to:
  /// **'Envia \"{p0}\" para a Steam API'**
  String enviaP0ParaASteamApi(Object p0);

  /// No description provided for @desativarTodos.
  ///
  /// In pt, this message translates to:
  /// **'Desativar todos'**
  String get desativarTodos;

  /// No description provided for @ativarTodos.
  ///
  /// In pt, this message translates to:
  /// **'Ativar todos'**
  String get ativarTodos;

  /// No description provided for @nomeDoFeriado.
  ///
  /// In pt, this message translates to:
  /// **'Nome do feriado'**
  String get nomeDoFeriado;

  /// No description provided for @exFeriasAniversario.
  ///
  /// In pt, this message translates to:
  /// **'Ex.: Férias, Aniversário'**
  String get exFeriasAniversario;

  /// No description provided for @feriados.
  ///
  /// In pt, this message translates to:
  /// **'Feriados'**
  String get feriados;

  /// No description provided for @hojeEFeriadoP0AsCotas.
  ///
  /// In pt, this message translates to:
  /// **'Hoje é feriado: {p0} — as cotas de feriado das sessões estão valendo.'**
  String hojeEFeriadoP0AsCotas(Object p0);

  /// No description provided for @aCotaDeFeriadoEDefinida.
  ///
  /// In pt, this message translates to:
  /// **'A cota de feriado é definida em cada sessão (como a de fim de semana).'**
  String get aCotaDeFeriadoEDefinida;

  /// No description provided for @proximosFeriados.
  ///
  /// In pt, this message translates to:
  /// **'Próximos feriados'**
  String get proximosFeriados;

  /// No description provided for @feriadosPersonalizados.
  ///
  /// In pt, this message translates to:
  /// **'Feriados personalizados'**
  String get feriadosPersonalizados;

  /// No description provided for @comOAntiBurlaLigadoNao.
  ///
  /// In pt, this message translates to:
  /// **'Com o Anti-Burla ligado não é possível adicionar feriados (só remover).'**
  String get comOAntiBurlaLigadoNao;

  /// No description provided for @adicionarUmaDataComACota.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar uma data com a cota de feriado das sessões'**
  String get adicionarUmaDataComACota;

  /// No description provided for @adicionarData.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar data'**
  String get adicionarData;

  /// No description provided for @antiBurlaLigadoAdicionarFeriadosEsta.
  ///
  /// In pt, this message translates to:
  /// **'Anti-Burla ligado: adicionar feriados está bloqueado.'**
  String get antiBurlaLigadoAdicionarFeriadosEsta;

  /// No description provided for @nenhum.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum.'**
  String get nenhum;

  /// No description provided for @remover.
  ///
  /// In pt, this message translates to:
  /// **'Remover'**
  String get remover;

  /// No description provided for @varreduraConcluidaP0ProcessosAuditadosQuarentena.
  ///
  /// In pt, this message translates to:
  /// **'Varredura concluída. {p0} processos auditados/quarentenados.'**
  String varreduraConcluidaP0ProcessosAuditadosQuarentena(Object p0);

  /// No description provided for @inspecaoDeBinariosQuarentena.
  ///
  /// In pt, this message translates to:
  /// **'Inspeção de Binários & Quarentena'**
  String get inspecaoDeBinariosQuarentena;

  /// No description provided for @protecaoContraBinariosNaoEmpacotadosPelo.
  ///
  /// In pt, this message translates to:
  /// **'Proteção contra binários não empacotados pelo pacman ou executados fora de /usr/bin'**
  String get protecaoContraBinariosNaoEmpacotadosPelo;

  /// No description provided for @escanearProcessos.
  ///
  /// In pt, this message translates to:
  /// **'Escanear Processos'**
  String get escanearProcessos;

  /// No description provided for @nenhumProcessoNaoConfiavelEmQuarentena.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum processo não confiável em quarentena!'**
  String get nenhumProcessoNaoConfiavelEmQuarentena;

  /// No description provided for @cliqueEmEscanearProcessosParaAuditar.
  ///
  /// In pt, this message translates to:
  /// **'Clique em \"Escanear Processos\" para auditar binários ativos fora do sistema oficial.'**
  String get cliqueEmEscanearProcessosParaAuditar;

  /// No description provided for @aprovarBinario.
  ///
  /// In pt, this message translates to:
  /// **'Aprovar Binário'**
  String get aprovarBinario;

  /// No description provided for @rejeitarBloquear.
  ///
  /// In pt, this message translates to:
  /// **'Rejeitar & Bloquear'**
  String get rejeitarBloquear;

  /// No description provided for @modoAntiCheatAtivo.
  ///
  /// In pt, this message translates to:
  /// **'Modo Anti-Burla Ativo!'**
  String get modoAntiCheatAtivo;

  /// No description provided for @oChronosEstaNoModoNuke.
  ///
  /// In pt, this message translates to:
  /// **'O Chronos está no Modo Nuke (restam {p0}m). Não é permitido {p1} até que o cronômetro expire.'**
  String oChronosEstaNoModoNuke(Object p0, Object p1);

  /// No description provided for @naoEPermitidoP0EnquantoO.
  ///
  /// In pt, this message translates to:
  /// **'Não é permitido {p0} enquanto o Anti-Burla estiver ativo. Para alterar regras, você deve primeiro resolver o desafio de digitação estrito do Anti-Burla.'**
  String naoEPermitidoP0EnquantoO(Object p0);

  /// No description provided for @entendido.
  ///
  /// In pt, this message translates to:
  /// **'Entendido'**
  String get entendido;

  /// No description provided for @resolverDesafio.
  ///
  /// In pt, this message translates to:
  /// **'Resolver Desafio'**
  String get resolverDesafio;

  /// No description provided for @desbloquearEntidades.
  ///
  /// In pt, this message translates to:
  /// **'desbloquear entidades'**
  String get desbloquearEntidades;

  /// No description provided for @removerRegrasDeBloqueio.
  ///
  /// In pt, this message translates to:
  /// **'remover regras de bloqueio'**
  String get removerRegrasDeBloqueio;

  /// No description provided for @editarTempoDeBloqueioEAgendamento.
  ///
  /// In pt, this message translates to:
  /// **'editar tempo de bloqueio e agendamento'**
  String get editarTempoDeBloqueioEAgendamento;

  /// No description provided for @finsDeSemanaP0.
  ///
  /// In pt, this message translates to:
  /// **'Fins de semana: {p0}'**
  String finsDeSemanaP0(Object p0);

  /// No description provided for @tempoDeTelaP0P1P2.
  ///
  /// In pt, this message translates to:
  /// **'Tempo de tela: {p0}{p1} • {p2}'**
  String tempoDeTelaP0P1P2(Object p0, Object p1, Object p2);

  /// No description provided for @renomear.
  ///
  /// In pt, this message translates to:
  /// **'Renomear'**
  String get renomear;

  /// No description provided for @nome.
  ///
  /// In pt, this message translates to:
  /// **'Nome'**
  String get nome;

  /// No description provided for @adicionarAppsOuSitesAoGrupo.
  ///
  /// In pt, this message translates to:
  /// **'adicionar apps ou sites ao grupo (só renomear é permitido)'**
  String get adicionarAppsOuSitesAoGrupo;

  /// No description provided for @editarGruposDeListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'editar grupos de lista branca'**
  String get editarGruposDeListaBranca;

  /// No description provided for @adicionarGruposDeListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'adicionar grupos de lista branca'**
  String get adicionarGruposDeListaBranca;

  /// No description provided for @removerGrupoDeListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Remover Grupo de Lista Branca'**
  String get removerGrupoDeListaBranca;

  /// No description provided for @desejaRealmenteRemoverEsteGrupoDe.
  ///
  /// In pt, this message translates to:
  /// **'Deseja realmente remover este grupo de lista branca? Os aplicativos e sites configurados nele deixarão de ser protegidos e voltarão a ser contabilizados ou bloqueados.'**
  String get desejaRealmenteRemoverEsteGrupoDe;

  /// No description provided for @removerAplicativoDoGrupoDeBloqueio.
  ///
  /// In pt, this message translates to:
  /// **'remover aplicativo do grupo de bloqueio'**
  String get removerAplicativoDoGrupoDeBloqueio;

  /// No description provided for @removerDoGrupoDeBloqueio.
  ///
  /// In pt, this message translates to:
  /// **'Remover do Grupo de Bloqueio'**
  String get removerDoGrupoDeBloqueio;

  /// No description provided for @desejaRealmenteRemoverP0DesteGrupo.
  ///
  /// In pt, this message translates to:
  /// **'Deseja realmente remover \"{p0}\" deste grupo de bloqueio?'**
  String desejaRealmenteRemoverP0DesteGrupo(Object p0);

  /// No description provided for @erroAoRemoverAplicativoP0.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao remover aplicativo: {p0}'**
  String erroAoRemoverAplicativoP0(Object p0);

  /// No description provided for @removerDaListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Remover da Lista Branca'**
  String get removerDaListaBranca;

  /// No description provided for @desejaRemoverP0DestaListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Deseja remover \"{p0}\" desta lista branca? O app deixará de ser protegido contra bloqueios.'**
  String desejaRemoverP0DestaListaBranca(Object p0);

  /// No description provided for @erroAoRemoverDaListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao remover da lista branca: {p0}'**
  String erroAoRemoverDaListaBranca(Object p0);

  /// No description provided for @t0mBloqueioTotal.
  ///
  /// In pt, this message translates to:
  /// **'0m (Bloqueio Total)'**
  String get t0mBloqueioTotal;

  /// No description provided for @p0AplicativoS.
  ///
  /// In pt, this message translates to:
  /// **'{p0} aplicativo(s)'**
  String p0AplicativoS(Object p0);

  /// No description provided for @p0SiteSPalavraS.
  ///
  /// In pt, this message translates to:
  /// **'{p0} site(s)/palavra(s)'**
  String p0SiteSPalavraS(Object p0);

  /// No description provided for @permitirSomente.
  ///
  /// In pt, this message translates to:
  /// **'Permitir somente'**
  String get permitirSomente;

  /// No description provided for @bloquear.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear'**
  String get bloquear;

  /// No description provided for @janelaP0P1P2.
  ///
  /// In pt, this message translates to:
  /// **'Janela: {p0} {p1}-{p2}'**
  String janelaP0P1P2(Object p0, Object p1, Object p2);

  /// No description provided for @extensaoProtecaoDosNavegadores.
  ///
  /// In pt, this message translates to:
  /// **'Extensão & Proteção dos Navegadores'**
  String get extensaoProtecaoDosNavegadores;

  /// No description provided for @oChronosAplicaAExtensaoEm.
  ///
  /// In pt, this message translates to:
  /// **'O Chronos aplica a extensão em navegadores Chromium e o Proxy Seletivo + CA no Firefox de forma totalmente offline.'**
  String get oChronosAplicaAExtensaoEm;

  /// No description provided for @navegadoresInstaladosDetectadosP0.
  ///
  /// In pt, this message translates to:
  /// **'Navegadores instalados detectados ({p0}):'**
  String navegadoresInstaladosDetectadosP0(Object p0);

  /// No description provided for @servidorLocalAtivoNaPortaP0.
  ///
  /// In pt, this message translates to:
  /// **'Servidor local ativo na porta {p0}'**
  String servidorLocalAtivoNaPortaP0(Object p0);

  /// No description provided for @chromeAbertoEmChromeExtensionsCole.
  ///
  /// In pt, this message translates to:
  /// **'Chrome aberto em chrome://extensions! Cole o caminho copiado ao carregar sem compactação.'**
  String get chromeAbertoEmChromeExtensionsCole;

  /// No description provided for @firefoxAbertoEmAboutPoliciesPara.
  ///
  /// In pt, this message translates to:
  /// **'Firefox aberto em about:policies para inspeção das políticas locais.'**
  String get firefoxAbertoEmAboutPoliciesPara;

  /// No description provided for @terminalAbertoParaAutorizacaoDoChronos.
  ///
  /// In pt, this message translates to:
  /// **'Terminal aberto para autorização do Chronos Guard!'**
  String get terminalAbertoParaAutorizacaoDoChronos;

  /// No description provided for @comandoCopiadoExecuteNoTerminalPara.
  ///
  /// In pt, this message translates to:
  /// **'Comando copiado! Execute no terminal para instalar o Guard.'**
  String get comandoCopiadoExecuteNoTerminalPara;

  /// No description provided for @configurando.
  ///
  /// In pt, this message translates to:
  /// **'Configurando...'**
  String get configurando;

  /// No description provided for @comandoGuardCopiadoParaOTerminal.
  ///
  /// In pt, this message translates to:
  /// **'Comando Guard copiado para o terminal!'**
  String get comandoGuardCopiadoParaOTerminal;

  /// No description provided for @sessoesBloqueiosP0.
  ///
  /// In pt, this message translates to:
  /// **'Sessões & Bloqueios ({p0})'**
  String sessoesBloqueiosP0(Object p0);

  /// No description provided for @listaBrancaWhitelistP0.
  ///
  /// In pt, this message translates to:
  /// **'Lista Branca / Whitelist ({p0})'**
  String listaBrancaWhitelistP0(Object p0);

  /// No description provided for @conflitosEncontradosP0.
  ///
  /// In pt, this message translates to:
  /// **'Conflitos encontrados ({p0})'**
  String conflitosEncontradosP0(Object p0);

  /// No description provided for @eMaisP0.
  ///
  /// In pt, this message translates to:
  /// **'… e mais {p0}.'**
  String eMaisP0(Object p0);

  /// No description provided for @extensaoWeb.
  ///
  /// In pt, this message translates to:
  /// **'Extensão Web'**
  String get extensaoWeb;

  /// No description provided for @novaSessaoDeBloqueio.
  ///
  /// In pt, this message translates to:
  /// **'Nova Sessão de Bloqueio'**
  String get novaSessaoDeBloqueio;

  /// No description provided for @sessoesConfiguradasP0.
  ///
  /// In pt, this message translates to:
  /// **'Sessões Configuradas ({p0})'**
  String sessoesConfiguradasP0(Object p0);

  /// No description provided for @nenhumaSessaoCriadaAindaCliqueEm.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma sessão criada ainda.\nClique em \"Nova Sessão de Bloqueio\" para agrupar apps ou sites.'**
  String get nenhumaSessaoCriadaAindaCliqueEm;

  /// No description provided for @catracaTravadaAumentosProibidos.
  ///
  /// In pt, this message translates to:
  /// **'Catraca Travada (Aumentos proibidos)'**
  String get catracaTravadaAumentosProibidos;

  /// No description provided for @recolher.
  ///
  /// In pt, this message translates to:
  /// **'Recolher'**
  String get recolher;

  /// No description provided for @expandir.
  ///
  /// In pt, this message translates to:
  /// **'Expandir'**
  String get expandir;

  /// No description provided for @editarTempoDeBloqueio.
  ///
  /// In pt, this message translates to:
  /// **'Editar Tempo de Bloqueio'**
  String get editarTempoDeBloqueio;

  /// No description provided for @adicionarAppsSitesAoGrupo.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar Apps / Sites ao Grupo'**
  String get adicionarAppsSitesAoGrupo;

  /// No description provided for @focarNoDashboard.
  ///
  /// In pt, this message translates to:
  /// **'Focar no Dashboard'**
  String get focarNoDashboard;

  /// No description provided for @desbloquear.
  ///
  /// In pt, this message translates to:
  /// **'Desbloquear'**
  String get desbloquear;

  /// No description provided for @bloquearCompletamente.
  ///
  /// In pt, this message translates to:
  /// **'Bloquear Completamente'**
  String get bloquearCompletamente;

  /// No description provided for @removerSessao.
  ///
  /// In pt, this message translates to:
  /// **'Remover Sessão'**
  String get removerSessao;

  /// No description provided for @recolherItensDaSessao.
  ///
  /// In pt, this message translates to:
  /// **'Recolher itens da sessão'**
  String get recolherItensDaSessao;

  /// No description provided for @expandirParaVerTodosOsApps.
  ///
  /// In pt, this message translates to:
  /// **'Expandir para ver todos os apps e sites'**
  String get expandirParaVerTodosOsApps;

  /// No description provided for @adicionarAplicativosSitesPermitidoNoAnti.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar Aplicativos / Sites (Permitido no Anti-Burla)'**
  String get adicionarAplicativosSitesPermitidoNoAnti;

  /// No description provided for @sessaoSelecionada.
  ///
  /// In pt, this message translates to:
  /// **'Sessão selecionada'**
  String get sessaoSelecionada;

  /// No description provided for @aplicativosBloqueadosP0.
  ///
  /// In pt, this message translates to:
  /// **'Aplicativos Bloqueados ({p0}):'**
  String aplicativosBloqueadosP0(Object p0);

  /// No description provided for @removerP0DoGrupoAntiCheat.
  ///
  /// In pt, this message translates to:
  /// **'Remover {p0} do grupo (Anti-Burla restrito)'**
  String removerP0DoGrupoAntiCheat(Object p0);

  /// No description provided for @sitesEPalavrasChaveBloqueadosP0.
  ///
  /// In pt, this message translates to:
  /// **'Sites e Palavras-Chave Bloqueados ({p0}):'**
  String sitesEPalavrasChaveBloqueadosP0(Object p0);

  /// No description provided for @nenhumAplicativoOuSiteListadoNesta.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum aplicativo ou site listado nesta sessão.'**
  String get nenhumAplicativoOuSiteListadoNesta;

  /// No description provided for @gruposDeListaBrancaP0.
  ///
  /// In pt, this message translates to:
  /// **'Grupos de Lista Branca ({p0})'**
  String gruposDeListaBrancaP0(Object p0);

  /// No description provided for @nenhumGrupoDeListaBrancaCriado.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum grupo de lista branca criado.\nApps e sites em listas brancas são protegidos contra bloqueios e finalizações.'**
  String get nenhumGrupoDeListaBrancaCriado;

  /// No description provided for @protecaoTotal.
  ///
  /// In pt, this message translates to:
  /// **'PROTEÇÃO TOTAL'**
  String get protecaoTotal;

  /// No description provided for @p0TiposYoutube.
  ///
  /// In pt, this message translates to:
  /// **'{p0} tipos YouTube'**
  String p0TiposYoutube(Object p0);

  /// No description provided for @itensProtegidosContraContagemDeTempo.
  ///
  /// In pt, this message translates to:
  /// **'Itens protegidos contra contagem de tempo de tela e fechamento automático'**
  String get itensProtegidosContraContagemDeTempo;

  /// No description provided for @youtubePermitidoP0.
  ///
  /// In pt, this message translates to:
  /// **'YouTube permitido: {p0}'**
  String youtubePermitidoP0(Object p0);

  /// No description provided for @recolherItens.
  ///
  /// In pt, this message translates to:
  /// **'Recolher itens'**
  String get recolherItens;

  /// No description provided for @expandirItens.
  ///
  /// In pt, this message translates to:
  /// **'Expandir itens'**
  String get expandirItens;

  /// No description provided for @editarGrupo.
  ///
  /// In pt, this message translates to:
  /// **'Editar Grupo'**
  String get editarGrupo;

  /// No description provided for @removerGrupo.
  ///
  /// In pt, this message translates to:
  /// **'Remover Grupo'**
  String get removerGrupo;

  /// No description provided for @aplicativosProtegidosP0.
  ///
  /// In pt, this message translates to:
  /// **'Aplicativos Protegidos ({p0}):'**
  String aplicativosProtegidosP0(Object p0);

  /// No description provided for @removerP0DaListaBranca.
  ///
  /// In pt, this message translates to:
  /// **'Remover {p0} da lista branca'**
  String removerP0DaListaBranca(Object p0);

  /// No description provided for @sitesEPalavrasProtegidosP0.
  ///
  /// In pt, this message translates to:
  /// **'Sites e Palavras Protegidos ({p0}):'**
  String sitesEPalavrasProtegidosP0(Object p0);

  /// No description provided for @tiposDoYoutubePermitidosP0.
  ///
  /// In pt, this message translates to:
  /// **'Tipos do YouTube permitidos ({p0}):'**
  String tiposDoYoutubePermitidosP0(Object p0);

  /// No description provided for @registroDeBurlas.
  ///
  /// In pt, this message translates to:
  /// **'Registro de burlas'**
  String get registroDeBurlas;

  /// No description provided for @cofreDoChronosAtivoComO.
  ///
  /// In pt, this message translates to:
  /// **'Cofre do Chronos ativo: com o Anti-Burla ligado, editar o banco, parar o serviço, apagar o autostart ou mudar o relógio é desfeito em segundos e anotado aqui.'**
  String get cofreDoChronosAtivoComO;

  /// No description provided for @cofreDoChronosNaoInstaladoInstale.
  ///
  /// In pt, this message translates to:
  /// **'Cofre do Chronos não instalado: instale/atualize a proteção dos navegadores (Chronos Guard) para ativar as camadas do Anti-Burla.'**
  String get cofreDoChronosNaoInstaladoInstale;

  /// No description provided for @relogioDoSistemaCorrigidoEmP0.
  ///
  /// In pt, this message translates to:
  /// **'Relógio do sistema corrigido em {p0} min (o Chronos usa a hora confiável).'**
  String relogioDoSistemaCorrigidoEmP0(Object p0);

  /// No description provided for @penalidadeAtivaTodasAsSessoesBloqueadas.
  ///
  /// In pt, this message translates to:
  /// **'Penalidade ativa: todas as sessões bloqueadas até {p0}.'**
  String penalidadeAtivaTodasAsSessoesBloqueadas(Object p0);

  /// No description provided for @aoDetectarUmaBurla.
  ///
  /// In pt, this message translates to:
  /// **'Ao detectar uma burla'**
  String get aoDetectarUmaBurla;

  /// No description provided for @restaurarERegistrar.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar e registrar'**
  String get restaurarERegistrar;

  /// No description provided for @restaurarRegistrarEBloquearTudoAte.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar, registrar e bloquear tudo até a meia-noite'**
  String get restaurarRegistrarEBloquearTudoAte;

  /// No description provided for @comOAntiBurlaAtivoNao.
  ///
  /// In pt, this message translates to:
  /// **'Com o Anti-Burla ativo não dá para voltar para a opção mais leve.'**
  String get comOAntiBurlaAtivoNao;

  /// No description provided for @nenhumaTentativaDeBurlaRegistrada.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma tentativa de burla registrada.'**
  String get nenhumaTentativaDeBurlaRegistrada;

  /// No description provided for @bancoEditado.
  ///
  /// In pt, this message translates to:
  /// **'Banco editado'**
  String get bancoEditado;

  /// No description provided for @bancoApagado.
  ///
  /// In pt, this message translates to:
  /// **'Banco apagado'**
  String get bancoApagado;

  /// No description provided for @servicoParado.
  ///
  /// In pt, this message translates to:
  /// **'Serviço parado'**
  String get servicoParado;

  /// No description provided for @servicoApagado.
  ///
  /// In pt, this message translates to:
  /// **'Serviço apagado'**
  String get servicoApagado;

  /// No description provided for @autostartApagado.
  ///
  /// In pt, this message translates to:
  /// **'Autostart apagado'**
  String get autostartApagado;

  /// No description provided for @relogioAlterado.
  ///
  /// In pt, this message translates to:
  /// **'Relógio alterado'**
  String get relogioAlterado;

  /// No description provided for @desbloqueioRecusado.
  ///
  /// In pt, this message translates to:
  /// **'Desbloqueio recusado'**
  String get desbloqueioRecusado;

  /// No description provided for @historicoDeBurlas.
  ///
  /// In pt, this message translates to:
  /// **'Histórico de burlas'**
  String get historicoDeBurlas;

  /// No description provided for @p0EventoS.
  ///
  /// In pt, this message translates to:
  /// **'{p0} evento(s)'**
  String p0EventoS(Object p0);

  /// No description provided for @nenhumaBurlaNestePeriodo.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma burla neste período.'**
  String get nenhumaBurlaNestePeriodo;

  /// No description provided for @naoEPossivelDesinstalar.
  ///
  /// In pt, this message translates to:
  /// **'Não é possível desinstalar'**
  String get naoEPossivelDesinstalar;

  /// No description provided for @oAntiBurlaEstaAtivoEnquanto.
  ///
  /// In pt, this message translates to:
  /// **'O Anti-Burla está ativo. Enquanto ele estiver ligado, o Chronos não pode ser fechado nem desinstalado.'**
  String get oAntiBurlaEstaAtivoEnquanto;

  /// No description provided for @desinstalarOChronos.
  ///
  /// In pt, this message translates to:
  /// **'Desinstalar o Chronos?'**
  String get desinstalarOChronos;

  /// No description provided for @istoRemoveOChronosDoComputador.
  ///
  /// In pt, this message translates to:
  /// **'Isto remove o Chronos do computador: o app em segundo plano, a extensão dos navegadores, a proteção do sistema (pode pedir sua senha), o início automático e o serviço do Chronos.'**
  String get istoRemoveOChronosDoComputador;

  /// No description provided for @apagarTambemMeusDados.
  ///
  /// In pt, this message translates to:
  /// **'Apagar também meus dados'**
  String get apagarTambemMeusDados;

  /// No description provided for @regrasHistoricoDeUsoEConfiguracoes.
  ///
  /// In pt, this message translates to:
  /// **'Regras, histórico de uso e configurações. Sem isso, ficam salvos para uma reinstalação.'**
  String get regrasHistoricoDeUsoEConfiguracoes;

  /// No description provided for @desinstalar.
  ///
  /// In pt, this message translates to:
  /// **'Desinstalar'**
  String get desinstalar;

  /// No description provided for @atualizacaoAutomaticaSoFuncionaNaVersao.
  ///
  /// In pt, this message translates to:
  /// **'Atualização automática só funciona na versão instalada (não em builds de desenvolvimento).'**
  String get atualizacaoAutomaticaSoFuncionaNaVersao;

  /// No description provided for @oChronosJaEstaNaVersao.
  ///
  /// In pt, this message translates to:
  /// **'O Chronos já está na versão mais recente ({p0}).'**
  String oChronosJaEstaNaVersao(Object p0);

  /// No description provided for @baixando.
  ///
  /// In pt, this message translates to:
  /// **'Baixando…'**
  String get baixando;

  /// No description provided for @verificandoAssinatura.
  ///
  /// In pt, this message translates to:
  /// **'Verificando assinatura…'**
  String get verificandoAssinatura;

  /// No description provided for @instalando.
  ///
  /// In pt, this message translates to:
  /// **'Instalando…'**
  String get instalando;

  /// No description provided for @atualizandoAProtecaoDoSistemaPode.
  ///
  /// In pt, this message translates to:
  /// **'Atualizando a proteção do sistema (pode pedir sua senha)…'**
  String get atualizandoAProtecaoDoSistemaPode;

  /// No description provided for @reiniciandoOChronos.
  ///
  /// In pt, this message translates to:
  /// **'Reiniciando o Chronos…'**
  String get reiniciandoOChronos;

  /// No description provided for @aProtecaoDoSistemaGuardNao.
  ///
  /// In pt, this message translates to:
  /// **'A proteção do sistema (Guard) não foi atualizada agora. Você pode atualizá-la depois em Configurações.'**
  String get aProtecaoDoSistemaGuardNao;

  /// No description provided for @novaVersaoDoChronosP0.
  ///
  /// In pt, this message translates to:
  /// **'Nova versão do Chronos: {p0}'**
  String novaVersaoDoChronosP0(Object p0);

  /// No description provided for @voceEstaNaVersaoP0Deseja.
  ///
  /// In pt, this message translates to:
  /// **'Você está na versão {p0}. Deseja atualizar agora?'**
  String voceEstaNaVersaoP0Deseja(Object p0);

  /// No description provided for @falhaNaAtualizacaoP0.
  ///
  /// In pt, this message translates to:
  /// **'Falha na atualização: {p0}'**
  String falhaNaAtualizacaoP0(Object p0);

  /// No description provided for @depois.
  ///
  /// In pt, this message translates to:
  /// **'Depois'**
  String get depois;

  /// No description provided for @tentarNovamente.
  ///
  /// In pt, this message translates to:
  /// **'Tentar novamente'**
  String get tentarNovamente;

  /// No description provided for @atualizarAgora.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar agora'**
  String get atualizarAgora;

  /// No description provided for @deUmNomeAoTipoNovo.
  ///
  /// In pt, this message translates to:
  /// **'Dê um nome ao tipo novo.'**
  String get deUmNomeAoTipoNovo;

  /// No description provided for @tiposDoYoutubePorCanalOu.
  ///
  /// In pt, this message translates to:
  /// **'Tipos do YouTube por canal ou palavra'**
  String get tiposDoYoutubePorCanalOu;

  /// No description provided for @exCanalFlowPodcastContaComo.
  ///
  /// In pt, this message translates to:
  /// **'Ex.: canal \"Flow Podcast\" conta como Podcasts; palavra \"minecraft\" cria o tipo \"Minecraft\". Separe vários canais ou palavras por vírgula.'**
  String get exCanalFlowPodcastContaComo;

  /// No description provided for @tipo.
  ///
  /// In pt, this message translates to:
  /// **'Tipo'**
  String get tipo;

  /// No description provided for @novoTipo.
  ///
  /// In pt, this message translates to:
  /// **'Novo tipo…'**
  String get novoTipo;

  /// No description provided for @nomeDoTipo.
  ///
  /// In pt, this message translates to:
  /// **'Nome do tipo'**
  String get nomeDoTipo;

  /// No description provided for @canais.
  ///
  /// In pt, this message translates to:
  /// **'Canais'**
  String get canais;

  /// No description provided for @palavrasNoTituloTags.
  ///
  /// In pt, this message translates to:
  /// **'Palavras no título/tags'**
  String get palavrasNoTituloTags;

  /// No description provided for @adicionarRegra.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar regra'**
  String get adicionarRegra;

  /// No description provided for @hojeP0.
  ///
  /// In pt, this message translates to:
  /// **' Hoje: {p0}.'**
  String hojeP0(Object p0);

  /// No description provided for @escolhaDosPaisSuffix.
  ///
  /// In pt, this message translates to:
  /// **' (escolha dos pais)'**
  String get escolhaDosPaisSuffix;

  /// No description provided for @guiaAnonimaSeraBloqueadaSuffix.
  ///
  /// In pt, this message translates to:
  /// **' — a guia anônima será bloqueada de novo'**
  String get guiaAnonimaSeraBloqueadaSuffix;

  /// No description provided for @safesearchNosNavegadoresSuffix.
  ///
  /// In pt, this message translates to:
  /// **' + SafeSearch nos navegadores'**
  String get safesearchNosNavegadoresSuffix;

  /// No description provided for @todosOsNavegadoresJaPermitemAnonimo.
  ///
  /// In pt, this message translates to:
  /// **'Todos os navegadores já permitem a extensão no anônimo.'**
  String get todosOsNavegadoresJaPermitemAnonimo;

  /// No description provided for @iaDeImagensNaTelaInteira.
  ///
  /// In pt, this message translates to:
  /// **'IA de imagens na tela inteira (local)'**
  String get iaDeImagensNaTelaInteira;

  /// No description provided for @iaTelaInteiraDescricao.
  ///
  /// In pt, this message translates to:
  /// **'Analisa a janela em foco a cada ~2 s em qualquer app (não só navegador) e cobre a tela se aparecer conteúdo +18. Tudo no computador, nada é gravado. Usa um pouco de CPU.'**
  String get iaTelaInteiraDescricao;

  /// No description provided for @iaTelaInteiraNaoSuportada.
  ///
  /// In pt, this message translates to:
  /// **'Disponível só no Hyprland com o grim instalado.'**
  String get iaTelaInteiraNaoSuportada;

  /// No description provided for @conteudoAdultoDetectadoNaTela.
  ///
  /// In pt, this message translates to:
  /// **'Conteúdo +18 detectado'**
  String get conteudoAdultoDetectadoNaTela;

  /// No description provided for @coberturaTelaTexto.
  ///
  /// In pt, this message translates to:
  /// **'O Chronos encontrou conteúdo adulto na janela \"{window}\". Feche ou troque o conteúdo antes de voltar.'**
  String coberturaTelaTexto(String window);

  /// No description provided for @entendiVoltar.
  ///
  /// In pt, this message translates to:
  /// **'Entendi, voltar'**
  String get entendiVoltar;

  /// No description provided for @appBloqueadoTitulo.
  ///
  /// In pt, this message translates to:
  /// **'{app} está bloqueado'**
  String appBloqueadoTitulo(String app);

  /// No description provided for @motivoQuota.
  ///
  /// In pt, this message translates to:
  /// **'O limite de tempo de hoje acabou.'**
  String get motivoQuota;

  /// No description provided for @motivoJanela.
  ///
  /// In pt, this message translates to:
  /// **'Este horário está bloqueado.'**
  String get motivoJanela;

  /// No description provided for @motivoForcado.
  ///
  /// In pt, this message translates to:
  /// **'Este app está bloqueado por completo.'**
  String get motivoForcado;

  /// No description provided for @motivoPenalidade.
  ///
  /// In pt, this message translates to:
  /// **'Penalidade ativa por tentativa de burla.'**
  String get motivoPenalidade;

  /// No description provided for @motivoLazer.
  ///
  /// In pt, this message translates to:
  /// **'Pausa obrigatória de lazer em andamento.'**
  String get motivoLazer;

  /// No description provided for @appFechadoPeloChronos.
  ///
  /// In pt, this message translates to:
  /// **'O Chronos fechou o app.'**
  String get appFechadoPeloChronos;

  /// No description provided for @extVersaoAtualizada.
  ///
  /// In pt, this message translates to:
  /// **'(atualizada)'**
  String get extVersaoAtualizada;

  /// No description provided for @extVersaoPendente.
  ///
  /// In pt, this message translates to:
  /// **'→ {version} pendente'**
  String extVersaoPendente(String version);

  /// No description provided for @extFirefoxPrecisaAssinar.
  ///
  /// In pt, this message translates to:
  /// **'→ {version} aguardando assinatura da Mozilla (rode scripts/run-release.sh)'**
  String extFirefoxPrecisaAssinar(String version);

  /// No description provided for @extVersaoDisponivel.
  ///
  /// In pt, this message translates to:
  /// **'Versão disponível: {version}'**
  String extVersaoDisponivel(String version);

  /// No description provided for @contaDaCriancaProtegida.
  ///
  /// In pt, this message translates to:
  /// **'Conta da criança protegida'**
  String get contaDaCriancaProtegida;

  /// No description provided for @contaProtegidaDescricao.
  ///
  /// In pt, this message translates to:
  /// **'A conta \"{user}\" não é administradora: não consegue remover o Chronos. Wi-Fi, pendrive, impressora, Bluetooth, desligar e instalar programas dos repositórios oficiais continuam liberados.'**
  String contaProtegidaDescricao(String user);

  /// No description provided for @contaEhAdministradoraAviso.
  ///
  /// In pt, this message translates to:
  /// **'A conta \"{user}\" é administradora (sudo) e pode remover o Chronos como root. Proteja a conta: ela deixa de ser administradora e o Chronos libera só as ações do dia a dia. Pede a senha de outra conta administradora (a do responsável).'**
  String contaEhAdministradoraAviso(String user);

  /// No description provided for @contaSemAdministrador.
  ///
  /// In pt, this message translates to:
  /// **'A conta \"{user}\" já não é administradora: não consegue remover o Chronos.'**
  String contaSemAdministrador(String user);

  /// No description provided for @protegerEstaConta.
  ///
  /// In pt, this message translates to:
  /// **'Proteger esta conta'**
  String get protegerEstaConta;

  /// No description provided for @devolverAdministrador.
  ///
  /// In pt, this message translates to:
  /// **'Devolver acesso de administrador'**
  String get devolverAdministrador;

  /// No description provided for @feitoValeNoProximoLogin.
  ///
  /// In pt, this message translates to:
  /// **'Feito. Vale a partir do próximo login.'**
  String get feitoValeNoProximoLogin;

  /// No description provided for @guardNaoInstaladoAtiveAProtecao.
  ///
  /// In pt, this message translates to:
  /// **'Chronos Guard não instalado: ative a proteção dos navegadores antes.'**
  String get guardNaoInstaladoAtiveAProtecao;

  /// No description provided for @autorizacaoCancelada.
  ///
  /// In pt, this message translates to:
  /// **'Autorização cancelada.'**
  String get autorizacaoCancelada;

  /// No description provided for @textosDesafioExplicacao.
  ///
  /// In pt, this message translates to:
  /// **'Seus textos substituem os textos padrão: o desafio sorteia só entre eles. Sem textos seus, usa os padrão. Mínimo de 120 caracteres cada. Não dá para alterar com o Anti-Burla ativo.'**
  String get textosDesafioExplicacao;

  /// No description provided for @recusarTextosFaceis.
  ///
  /// In pt, this message translates to:
  /// **'Recusar textos fáceis demais'**
  String get recusarTextosFaceis;

  /// No description provided for @recusarTextosFaceisDescricao.
  ///
  /// In pt, this message translates to:
  /// **'Bloqueia textos com palavras repetidas, poucas letras diferentes, sequências de teclado ou trechos copiados várias vezes.'**
  String get recusarTextosFaceisDescricao;

  /// No description provided for @semTextosUsaOsPadrao.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum texto seu: o desafio usa os textos padrão.'**
  String get semTextosUsaOsPadrao;

  /// No description provided for @adicionarTexto.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar texto'**
  String get adicionarTexto;

  /// No description provided for @editarTexto.
  ///
  /// In pt, this message translates to:
  /// **'Editar texto'**
  String get editarTexto;

  /// No description provided for @p0Caracteres.
  ///
  /// In pt, this message translates to:
  /// **'{count} caracteres'**
  String p0Caracteres(int count);

  /// No description provided for @textoAprovado.
  ///
  /// In pt, this message translates to:
  /// **'Texto aprovado.'**
  String get textoAprovado;

  /// No description provided for @ok.
  ///
  /// In pt, this message translates to:
  /// **'OK'**
  String get ok;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
