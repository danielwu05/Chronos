import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:chronos_app/services/browser_extension_installer.dart';
import 'package:chronos_app/services/chronos_guard_service.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
import 'package:chronos_app/widgets/add_block_dialog.dart';
import 'package:chronos_app/widgets/browser_protection_panel.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onOnboardingCompleted;

  const OnboardingScreen({super.key, required this.onOnboardingCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _AppRuleDraft {
  final String entityId;
  final String displayName;
  final IconData icon;
  bool isEnabled = true;
  int quotaMinutes; // em minutos
  bool isCompletelyBlocked = false;
  String targetType; // 'APP', 'SITE', 'KEYWORD', 'GROUP'
  String pattern;
  int? weekendQuotaMinutes;
  String? scheduleJson;

  _AppRuleDraft({
    required this.entityId,
    required this.displayName,
    required this.icon,
    required this.quotaMinutes,
    this.targetType = 'GROUP',
    this.pattern = '',
    this.weekendQuotaMinutes,
    this.scheduleJson,
  });
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // Steps: 0: Modo, 1: Papel Parental, 2: Pareamento, 3: Personalização de Bloqueio (Pessoal)
  int _currentStep = 0;
  String _deviceRole = 'NONE'; // 'NONE', 'PARENT' ou 'CHILD'
  OnboardingStateDto? _initialState;
  bool _loading = true;

  // Personalização de Bloqueio (Modo Pessoal)
  bool _enableRatchet24h = true;
  bool _enableOverlay = true;
  bool _enableMediaPause = true;
  BrowserInstallResult? _browserInstallResult;
  ChronosGuardStatus? _guardStatus;
  bool _scanningBrowsers = false;

  // Sem presets de sites ou apps pré-configurados
  final List<_AppRuleDraft> _personalRules = [];

  // Controllers para pareamento parental
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _codeInputController = TextEditingController();
  bool _isPairedSuccess = false;
  String _pairingMessage = '';

  @override
  void initState() {
    super.initState();
    _loadState();
    _checkBrowsers();
  }

  Future<void> _checkBrowsers() async {
    if (mounted) setState(() => _scanningBrowsers = true);
    try {
      final res = await BrowserExtensionInstaller.installAll(forceMandatory: true);
      final guard = await ChronosGuardService.checkStatus();
      if (mounted) {
        setState(() {
          _browserInstallResult = res;
          _guardStatus = guard;
          _scanningBrowsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _scanningBrowsers = false);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _codeInputController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final s = await getOnboardingState();
      if (mounted) {
        setState(() {
          _initialState = s;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finishSelfControlWithCustomization() async {
    // 0. Instalação obrigatória da extensão e políticas em todos os navegadores do dispositivo
    await BrowserExtensionInstaller.installAll(forceMandatory: true);

    // 1. Salva cada regra personalizada no SQLite
    for (final draft in _personalRules) {
      if (!draft.isEnabled) continue;
      final quotaSec = draft.isCompletelyBlocked ? 0 : draft.quotaMinutes * 60;
      await saveRule(
        entityId: draft.entityId,
        displayName: draft.displayName,
        dailyQuotaSeconds: quotaSec,
        mode: 'SELF_CONTROL',
        targetType: draft.targetType,
        pattern: draft.pattern.isNotEmpty ? draft.pattern : draft.entityId,
        weekendQuotaSeconds: draft.weekendQuotaMinutes != null ? draft.weekendQuotaMinutes! * 60 : null,
        scheduleJson: draft.scheduleJson,
      );

      if (draft.isCompletelyBlocked) {
        await toggleEntityBlock(entityId: draft.entityId, blocked: true);
      }

      // Se a trava da catraca de 24h foi ativada
      if (_enableRatchet24h) {
        await lockRatchet(entityId: draft.entityId, hours: 24);
      }
    }

    // 2. Conclui o onboarding
    // Keep the language shown during the setup.
    await setPrimaryLanguage(lang: kAppLanguages.firstWhere((l) => localeForCode(l.$1) == appLocale.value, orElse: () => kAppLanguages.first).$1);
    final res = await saveOnboardingChoice(
      appMode: 'SELF_CONTROL',
      deviceRole: 'NONE',
      pairingSecret: null,
    );

    if (!mounted) return;
    if (res.success) {
      widget.onOnboardingCompleted();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message), backgroundColor: Colors.red.shade800),
      );
    }
  }

  Future<void> _addNewBlockDraft() async {
    final result = await AddBlockDialog.show(context);
    if (result == null) return;

    final existingIdx = _personalRules.indexWhere((r) => r.entityId == result.entityId);
    if (existingIdx != -1) {
      setState(() {
        _personalRules[existingIdx].isEnabled = true;
        _personalRules[existingIdx].quotaMinutes = (result.dailyQuotaSeconds ~/ 60);
        _personalRules[existingIdx].isCompletelyBlocked = result.isCompletelyBlocked;
        _personalRules[existingIdx].pattern = result.pattern;
        _personalRules[existingIdx].scheduleJson = result.scheduleJson;
      });
      return;
    }

    IconData icon = Icons.apps;
    if (result.targetType == 'SITE') icon = Icons.public;
    if (result.targetType == 'KEYWORD') icon = Icons.key;
    if (result.targetType == 'GROUP') icon = Icons.sports_esports;

    setState(() {
      _personalRules.add(
        _AppRuleDraft(
          entityId: result.entityId,
          displayName: result.displayName,
          icon: icon,
          quotaMinutes: result.isCompletelyBlocked ? 0 : (result.dailyQuotaSeconds ~/ 60),
          targetType: result.targetType,
          pattern: result.pattern,
          weekendQuotaMinutes: result.weekendQuotaSeconds != null ? result.weekendQuotaSeconds! ~/ 60 : null,
          scheduleJson: result.scheduleJson,
        )..isCompletelyBlocked = result.isCompletelyBlocked,
      );
    });
  }

  Future<void> _finishParentalSetup() async {
    await BrowserExtensionInstaller.installAll(forceMandatory: true);
    // Keep the language shown during the setup.
    await setPrimaryLanguage(lang: kAppLanguages.firstWhere((l) => localeForCode(l.$1) == appLocale.value, orElse: () => kAppLanguages.first).$1);
    final res = await saveOnboardingChoice(
      appMode: 'PARENTAL',
      deviceRole: _deviceRole,
      pairingSecret: _passwordController.text.trim().isNotEmpty
          ? _passwordController.text.trim()
          : null,
    );
    if (!mounted) return;
    if (res.success) {
      widget.onOnboardingCompleted();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message), backgroundColor: Colors.red.shade800),
      );
    }
  }

  Future<void> _tryPairCode(String codeOrPassword) async {
    if (codeOrPassword.trim().isEmpty) return;
    final res = await verifyAndPairDevice(codeOrPassword: codeOrPassword.trim());
    if (!mounted) return;
    setState(() {
      _isPairedSuccess = res.success;
      _pairingMessage = res.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF101215),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildCurrentStepWidget(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepWidget() {
    switch (_currentStep) {
      case 0:
        return _buildStep1ModeSelection();
      case 1:
        return _buildStep2ParentalRoleSelection();
      case 2:
        return _buildStep3Pairing();
      case 3:
        return _buildStepPersonalBlockCustomization();
      default:
        return _buildStep1ModeSelection();
    }
  }

  // STEP 0: Seleção de Modo (Pessoal vs Parental)
  /// First choice of the setup: app language (pre-selected from the system language).
  Widget _buildLanguagePicker() {
    final current = kAppLanguages.firstWhere(
      (l) => localeForCode(l.$1) == appLocale.value,
      orElse: () => kAppLanguages.first,
    ).$1;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 220,
        child: DropdownButtonFormField<String>(
          initialValue: current,
          isDense: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.translate_outlined, size: 18),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [for (final (code, label) in kAppLanguages) DropdownMenuItem(value: code, child: Text(label))],
          onChanged: (code) async {
            if (code == null) return;
            final res = await setPrimaryLanguage(lang: code);
            setAppLanguageCode(res.success && res.message.isNotEmpty ? res.message : code);
          },
        ),
      ),
    );
  }

  Widget _buildStep1ModeSelection() {
    return Column(
      key: const ValueKey('step_0_mode'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLanguagePicker(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade900.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.tealAccent, width: 1.5),
              ),
              child: const Icon(Icons.hourglass_empty_rounded, color: Colors.tealAccent, size: 36),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          tr.bemVindoAoChronos,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          tr.seuMotorDeFocoEstritoE,
          style: TextStyle(color: Colors.white70, fontSize: 15),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Opção 1: Controle Pessoal
        _SelectionCard(
          icon: Icons.psychology_outlined,
          iconColor: Colors.tealAccent,
          title: tr.controlePessoalAutoControle,
          subtitle: tr.paraGerenciarSeuProprioTempoE,
          features: [
            'Personalização de tempo de tela e bloqueios sob medida para seus hábitos.',
            tr.modoCatracaRatchetReducoesSaoImediatas,
            tr.t2TokensMensaisDeEmergencia1h,
            tr.bloqueioAtivoComSobreposicaoDeJanela,
          ],
          buttonText: tr.configurarBloqueiosPessoais,
          buttonColor: Colors.teal.shade700,
          onPressed: () {
            setState(() {
              _currentStep = 3; // Vai para a Personalização de Bloqueio
            });
          },
        ),

        const SizedBox(height: 18),

        // Opção 2: Controle Parental
        _SelectionCard(
          icon: Icons.family_restroom_outlined,
          iconColor: Colors.purpleAccent,
          title: tr.controleParentalSupervisao,
          subtitle: tr.paraPaisEResponsaveisGerenciaremDispositivos,
          features: [
            'Autoridade remota: Regras e limites controlados pelo dispositivo do responsável.',
            tr.dispositivoDoDependenteProtegidoContraAlteracoes,
            tr.pareamentoSeguroViaQrCodeOu,
            tr.gestaoDeAprovacaoDeBinariosE,
          ],
          buttonText: tr.configurarControleParental,
          buttonColor: Colors.purple.shade700,
          onPressed: () {
            setState(() {
              _currentStep = 1;
            });
          },
        ),
      ],
    );
  }

  // STEP 3: Personalização de Bloqueio no Modo Pessoal
  Widget _buildStepPersonalBlockCustomization() {
    return Column(
      key: const ValueKey('step_3_personal_customization'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _currentStep = 0),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr.personalizacaoDeBloqueioTempoDeTela,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    tr.ajusteOTempoDeTelaDiario,
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Card Obrigatório: Varredura e Instalação em Todos os Navegadores do Dispositivo
        _buildMandatoryBrowserCard(),

        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr.distracoesABloquear,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal.shade900.withValues(alpha: 0.5),
                foregroundColor: Colors.tealAccent,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr.adicionarAppOuSite),
              onPressed: _addNewBlockDraft,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Lista de Aplicativos para Bloqueio / Tempo de Tela
        if (_personalRules.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1E23),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                Icon(Icons.shield_outlined, color: Colors.tealAccent, size: 32),
                SizedBox(height: 8),
                Text(
                  tr.nenhumaSessaoPreConfiguradaCliqueEm,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ...List.generate(_personalRules.length, (index) {
          final draft = _personalRules[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: draft.isEnabled ? const Color(0xFF1B1E23) : Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: draft.isEnabled ? Colors.tealAccent.withValues(alpha: 0.3) : Colors.white10,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(draft.icon, color: draft.isEnabled ? Colors.tealAccent : Colors.grey, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          draft.displayName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: draft.isEnabled ? Colors.white : Colors.white38,
                          ),
                        ),
                      ),
                      Switch(
                        value: draft.isEnabled,
                        activeThumbColor: Colors.tealAccent,
                        onChanged: (val) {
                          setState(() => draft.isEnabled = val);
                        },
                      ),
                    ],
                  ),
                  if (draft.isEnabled) ...[
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          tr.tempoDeTelaDiario,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: Text(tr.bloqueioTotal),
                                selected: draft.isCompletelyBlocked,
                                onSelected: (sel) {
                                  setState(() {
                                    draft.isCompletelyBlocked = true;
                                    draft.quotaMinutes = 0;
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: Text(tr.t15Min),
                                selected: !draft.isCompletelyBlocked && draft.quotaMinutes == 15,
                                onSelected: (sel) {
                                  setState(() {
                                    draft.isCompletelyBlocked = false;
                                    draft.quotaMinutes = 15;
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: Text(tr.t30Min),
                                selected: !draft.isCompletelyBlocked && draft.quotaMinutes == 30,
                                onSelected: (sel) {
                                  setState(() {
                                    draft.isCompletelyBlocked = false;
                                    draft.quotaMinutes = 30;
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: Text(tr.t1Hora),
                                selected: !draft.isCompletelyBlocked && draft.quotaMinutes == 60,
                                onSelected: (sel) {
                                  setState(() {
                                    draft.isCompletelyBlocked = false;
                                    draft.quotaMinutes = 60;
                                  });
                                },
                              ),
                              ChoiceChip(
                                label: Text(tr.t2Horas),
                                selected: !draft.isCompletelyBlocked && draft.quotaMinutes == 120,
                                onSelected: (sel) {
                                  setState(() {
                                    draft.isCompletelyBlocked = false;
                                    draft.quotaMinutes = 120;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 8),

        // Card de Diretrizes de Enforcement & Catraca
        Card(
          color: Colors.teal.shade900.withValues(alpha: 0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.teal.shade700.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.tealAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      tr.diretrizesDeEnforcementDoChronos,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr.ativarTravaDaCatraca24hIniciais, style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    tr.impedeAumentosDeTempoDeTela,
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  value: _enableRatchet24h,
                  activeThumbColor: Colors.tealAccent,
                  onChanged: (val) => setState(() => _enableRatchet24h = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr.sequestroVisualDeFocoAlwaysOn, style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    tr.maximizaETravaAJanelaDo,
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  value: _enableOverlay,
                  activeThumbColor: Colors.tealAccent,
                  onChanged: (val) => setState(() => _enableOverlay = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr.pausaAtivaDeMidiaPlayerctlMpris2, style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    tr.interrompeAutomaticamenteVideosEMusicasEm,
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  value: _enableMediaPause,
                  activeThumbColor: Colors.tealAccent,
                  onChanged: (val) => setState(() => _enableMediaPause = val),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.teal.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _finishSelfControlWithCustomization,
          child: Text(
            tr.salvarBloqueiosEIniciarChronos,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // STEP 2: Papel no Modo Parental (Pai vs Filho)
  Widget _buildStep2ParentalRoleSelection() {
    return Column(
      key: const ValueKey('step_1_parental_role'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _currentStep = 0),
            ),
            const SizedBox(width: 8),
            Text(
              tr.controleParental,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tr.qualEOPapelDesteComputador,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 24),

        // Dispositivo Pai
        _SelectionCard(
          icon: Icons.admin_panel_settings_outlined,
          iconColor: Colors.amberAccent,
          title: tr.dispositivoDoResponsavelPaiMae,
          subtitle: tr.esteComputadorTeraAutoridadeParaControlar,
          features: [
            'Acesso completo para alterar tempo de tela e aprovar tempo adicional.',
            tr.recebeSolicitacoesDeEmergenciaEAprovacoes,
            tr.conectaAoComputadorDoFilhoUsando,
          ],
          buttonText: tr.configurarComoDispositivoPai,
          buttonColor: Colors.amber.shade800,
          onPressed: () {
            setState(() {
              _deviceRole = 'PARENT';
              _currentStep = 2;
            });
          },
        ),

        const SizedBox(height: 18),

        // Dispositivo Filho
        _SelectionCard(
          icon: Icons.child_care_outlined,
          iconColor: Colors.blueAccent,
          title: tr.dispositivoDoDependenteFilho,
          subtitle: tr.esteComputadorSeraMonitoradoEProtegido,
          features: [
            'O daemon monitora janelas e mídia em segundo plano.',
            tr.asAlteracoesDeTempoDeTela,
            tr.exibeQrCodeECodigoPin,
          ],
          buttonText: tr.configurarComoDispositivoFilho,
          buttonColor: Colors.blue.shade700,
          onPressed: () {
            setState(() {
              _deviceRole = 'CHILD';
              _currentStep = 2;
            });
          },
        ),
      ],
    );
  }

  // STEP 3: Pareamento (QR Code ou Senha)
  Widget _buildStep3Pairing() {
    final isChild = _deviceRole == 'CHILD';
    final pairCode = _initialState?.pairingCode ?? 'CHR-8492';
    final qrData = _initialState?.pairingPayloadQr ?? 'chronos://pair?code=$pairCode';

    return Column(
      key: const ValueKey('step_2_pairing'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _currentStep = 1),
            ),
            const SizedBox(width: 8),
            Text(
              isChild ? tr.pareamentoDispositivoFilho : tr.pareamentoDispositivoDoResponsavel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isChild
              ? tr.conecteEsteComputadorAoAplicativoDo
              : tr.escaneieOQrCodeOuInsira,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 24),

        Card(
          color: const Color(0xFF1B1E23),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DefaultTabController(
              length: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TabBar(
                    indicatorColor: Colors.purpleAccent,
                    tabs: [
                      Tab(icon: Icon(Icons.qr_code_2), text: tr.viaQrCode),
                      Tab(icon: Icon(Icons.password), text: tr.viaSenhaPin),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 280,
                    child: TabBarView(
                      children: [
                        // ABA 1: QR CODE
                        isChild
                            ? _buildChildQrTab(qrData, pairCode)
                            : _buildParentQrTab(),

                        // ABA 2: SENHA / PIN
                        isChild
                            ? _buildChildPasswordTab(pairCode)
                            : _buildParentPasswordTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        if (_pairingMessage.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: _isPairedSuccess ? Colors.teal.shade900.withValues(alpha: 0.4) : Colors.red.shade900.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _isPairedSuccess ? Colors.tealAccent : Colors.redAccent),
            ),
            child: Row(
              children: [
                Icon(
                  _isPairedSuccess ? Icons.check_circle : Icons.error_outline,
                  color: _isPairedSuccess ? Colors.tealAccent : Colors.redAccent,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(_pairingMessage)),
              ],
            ),
          ),

        _buildMandatoryBrowserCard(),

        const SizedBox(height: 20),

        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.purple.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _finishParentalSetup,
          child: Text(
            isChild ? tr.concluirEIniciarProtecao : tr.concluirEAbrirPainelDoResponsavel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildMandatoryBrowserCard() {
    final browsers = _browserInstallResult?.browsers ?? const <DetectedBrowser>[];

    void showSnack(String msg, bool ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: ok ? Colors.teal.shade700 : Colors.orange.shade800,
        ),
      );
    }

    return Card(
      color: const Color(0xFF141F2A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  radius: 20,
                  child: Icon(Icons.extension, color: Colors.white, size: 22),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr.protecaoObrigatoriaEmTodosOsNavegadores,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        tr.configuraTodosOsNavegadoresDoDispositivo,
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            BrowserSetupFlowStepper(
              hasPackages: _browserInstallResult?.success == true,
              guardStatus: _guardStatus,
              browsers: browsers,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent.shade700),
              icon: _scanningBrowsers
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.security_update_good, size: 17),
              label: Text(
                _scanningBrowsers
                    ? tr.instalandoConfigurando
                    : tr.instalarAtualizarEmTodosOsNavegadores,
                style: const TextStyle(fontSize: 12.5),
              ),
              onPressed: _scanningBrowsers
                  ? null
                  : () async {
                      setState(() => _scanningBrowsers = true);
                      try {
                        await runUnifiedBrowserSetupFlow(
                          context,
                          isAntiCheatActive: false,
                          onRefresh: _checkBrowsers,
                          onFeedback: showSnack,
                          onPolkitFallback: () async {
                            final launched = await ChronosGuardService.launchInstallerInTerminal();
                            showSnack(
                              launched
                                  ? tr.terminalAbertoDigiteSuaSenhaSudo
                                  : tr.executeManualmenteP0(ChronosGuardService.getInstallCliCommand()),
                              launched,
                            );
                          },
                        );
                      } finally {
                        if (mounted) setState(() => _scanningBrowsers = false);
                      }
                    },
            ),
            if (_browserInstallResult != null) ...[
              const SizedBox(height: 10),
              Text(
                _browserInstallResult!.message,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _browserInstallResult!.success ? Colors.tealAccent : Colors.orangeAccent,
                ),
              ),
            ],
            if (browsers.isNotEmpty) ...[
              const SizedBox(height: 10),
              BrowserStatusChipsWrap(
                browsers: browsers,
                onFeedback: showSnack,
                onRequestRelaunch: (browser) async {
                  await showConfirmRelaunchBrowsersDialog(
                    context,
                    [browser],
                    onCompleted: _checkBrowsers,
                    onFeedback: showSnack,
                  );
                },
              ),
            ],
            const SizedBox(height: 6),
            ManualBrowserFallbackTile(
              browsers: browsers,
              onFeedback: showSnack,
              onShowGuardTerminal: () async {
                final launched = await ChronosGuardService.launchInstallerInTerminal();
                showSnack(
                  launched
                      ? tr.terminalAbertoDigiteSuaSenhaSudo2
                      : tr.executeNoTerminalP0(ChronosGuardService.getInstallCliCommand()),
                  launched,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildQrTab(String qrData, String pairCode) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: 160,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr.aponteODispositivoDoResponsavelPara,
          style: TextStyle(color: Colors.white70, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildParentQrTab() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.qr_code_scanner, size: 64, color: Colors.purpleAccent),
        const SizedBox(height: 12),
        Text(
          tr.seEstiverUsandoAVersaoMobile,
          style: TextStyle(color: Colors.white70, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeInputController,
          decoration: InputDecoration(
            labelText: tr.ouColeAChaveUriDo,
            hintText: tr.chronosPairId,
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => _tryPairCode(_codeInputController.text),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChildPasswordTab(String pairCode) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          tr.codigoPinDePareamentoDesteDispositivo,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
          ),
          child: Text(
            pairCode,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: Colors.purpleAccent,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: tr.definirSenhaMestraDeDesbloqueioLocal,
            hintText: tr.digiteUmaSenhaParaAlterarTempo,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildParentPasswordTab() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          tr.digiteOCodigoPinOuSenha,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeInputController,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 3, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: tr.chrXxxxOuSenha,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.link),
          label: Text(tr.validarEParear),
          onPressed: () => _tryPairCode(_codeInputController.text),
        ),
      ],
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<String> features;
  final String buttonText;
  final Color buttonColor;
  final VoidCallback onPressed;

  const _SelectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.buttonText,
    required this.buttonColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1B1E23),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: iconColor.withValues(alpha: 0.25), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: Colors.white10),
            const SizedBox(height: 10),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, size: 16, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: buttonColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: onPressed,
                child: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
