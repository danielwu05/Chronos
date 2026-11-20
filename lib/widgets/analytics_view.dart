import 'package:chronos_app/services/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:chronos_app/src/rust/api/simple.dart';
import 'package:chronos_app/src/rust/api/youtube.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  AnalyticsSummaryDto? _summary;
  List<YtExemptTotalDto> _ytExemptToday = const [];
  List<YtExemptTotalDto> _ytExempt7d = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _loading = true);
    try {
      final s = await getAnalyticsSummary();
      final ytToday = await getYoutubeExemptTotals(days: 1);
      final yt7d = await getYoutubeExemptTotals(days: 7);
      if (mounted) {
        setState(() {
          _summary = s;
          _ytExemptToday = ytToday;
          _ytExempt7d = yt7d;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0 && minutes > 0) {
      return tr.p0HP1M(hours, minutes);
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}m';
    }
  }

  IconData _getIconForType(String targetType) {
    switch (targetType.toUpperCase()) {
      case 'SITE':
      case 'SITE_GROUP':
        return Icons.public;
      case 'GROUP':
        return Icons.sports_esports;
      case 'KEYWORD':
        return Icons.key;
      case 'APP':
      default:
        return Icons.apps;
    }
  }

  Color _getColorForType(String targetType) {
    switch (targetType.toUpperCase()) {
      case 'SITE':
      case 'SITE_GROUP':
        return Colors.blueAccent;
      case 'GROUP':
        return Colors.purpleAccent;
      case 'KEYWORD':
        return Colors.orangeAccent;
      case 'APP':
      default:
        return Colors.tealAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final s = _summary;
    final totalToday = s?.totalConsumedTodaySeconds ?? 0;
    final total7d = s?.totalConsumed7DSeconds ?? 0;
    final avg7d = s?.dailyAverage7DSeconds ?? 0;
    final peakLabel = (s?.peakDayLabel.isNotEmpty ?? false) ? s!.peakDayLabel : tr.semDados;
    final peakSeconds = s?.peakDaySeconds ?? 0;
    final compPercent = s?.comparisonVsPrevWeekPercent ?? 0.0;
    final topEntities = s?.topEntities7D ?? [];
    final dailyBreakdown = s?.dailyBreakdown7D ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;

        return RefreshIndicator(
          onRefresh: _loadSummary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header com Título e Botão de Atualizar
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 620;
                    final textColumn = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr.estatisticasDeTempoDeTela,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr.consumoConsolidadoTendenciasSemanaisERanking,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    );

                    final refreshButton = FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(tr.atualizar, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _loadSummary,
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          textColumn,
                          const SizedBox(height: 12),
                          refreshButton,
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: textColumn),
                        const SizedBox(width: 14),
                        refreshButton,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),

                // 4 Cards de Métricas Principais (KPIs)
                if (isWide)
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: tr.consumoHoje,
                          value: _formatDuration(totalToday),
                          subtitle: tr.tempoEmAppsSitesMonitorados,
                          icon: Icons.today,
                          color: Colors.tealAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: tr.mediaSemanal,
                          value: '${_formatDuration(avg7d)} / dia',
                          subtitle: tr.baseadoNosUltimos7Dias,
                          icon: Icons.date_range,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: tr.diaDePico,
                          value: peakSeconds > 0 ? _formatDuration(peakSeconds) : '0m',
                          subtitle: peakLabel,
                          icon: Icons.show_chart,
                          color: Colors.amberAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: tr.tendenciaVsSemanaAnterior,
                          value: compPercent == 0.0
                              ? tr.estavel
                              : '${compPercent > 0 ? '+' : ''}${compPercent.toStringAsFixed(1)}%',
                          subtitle: compPercent > 0 ? tr.maisTempoDeTela : tr.menosTempoDeTela,
                          icon: compPercent > 0 ? Icons.trending_up : Icons.trending_down,
                          color: compPercent > 0 ? Colors.redAccent : Colors.greenAccent,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              title: tr.consumoHoje,
                              value: _formatDuration(totalToday),
                              subtitle: tr.appsSitesMonitorados,
                              icon: Icons.today,
                              color: Colors.tealAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              title: tr.mediaDiaria,
                              value: '${_formatDuration(avg7d)}/dia',
                              subtitle: tr.ultimos7Dias,
                              icon: Icons.date_range,
                              color: Colors.blueAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricCard(
                              title: tr.diaDePico,
                              value: peakSeconds > 0 ? _formatDuration(peakSeconds) : '0m',
                              subtitle: peakLabel,
                              icon: Icons.show_chart,
                              color: Colors.amberAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              title: tr.tendencia,
                              value: compPercent == 0.0
                                  ? tr.estavel
                                  : '${compPercent > 0 ? '+' : ''}${compPercent.toStringAsFixed(1)}%',
                              subtitle: compPercent > 0 ? tr.maisTela : tr.menosTela,
                              icon: compPercent > 0 ? Icons.trending_up : Icons.trending_down,
                              color: compPercent > 0 ? Colors.redAccent : Colors.greenAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                if (_ytExemptToday.isNotEmpty || _ytExempt7d.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _MetricCard(
                    title: tr.tempoIsentoNoYoutubeListaBranca,
                    value: _formatDuration(_ytExemptToday.fold<int>(0, (a, e) => a + e.seconds.toInt())),
                    subtitle: [
                      'Hoje — não descontou do tempo de tela',
                      for (final e in _ytExempt7d) tr.p0P1Em7Dias(e.label, _formatDuration(e.seconds.toInt())),
                    ].join('\n'),
                    icon: Icons.smart_display,
                    color: Colors.redAccent,
                  ),
                ],
                const SizedBox(height: 24),

                // Gráfico de Barras dos Últimos 7 Dias
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.bar_chart, color: Colors.tealAccent, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  tr.consumoDiarioNosUltimos7Dias,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                            Text(
                              tr.totalP0(_formatDuration(total7d)),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.tealAccent : Colors.teal.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (dailyBreakdown.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(tr.nenhumDadoDiarioRegistrado, style: TextStyle(color: Colors.white54)),
                            ),
                          )
                        else
                          SizedBox(
                            height: 190,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: dailyBreakdown.map((item) {
                                final maxSeconds = peakSeconds > 0 ? peakSeconds : 1;
                                final fraction = (item.consumedSeconds / maxSeconds).clamp(0.04, 1.0);

                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        // Valor em tempo acima da barra
                                        Text(
                                          _formatDuration(item.consumedSeconds),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: item.isToday ? FontWeight.bold : FontWeight.normal,
                                            color: item.isToday
                                                ? Colors.tealAccent
                                                : (isDark ? Colors.white60 : Colors.black54),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),

                                        // Barra estilizada
                                        Flexible(
                                          child: FractionallySizedBox(
                                            heightFactor: fraction,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                  colors: item.isToday
                                                      ? [Colors.teal.shade900, Colors.tealAccent]
                                                      : (item.consumedSeconds > 0
                                                          ? [Colors.teal.shade900.withValues(alpha: 0.7), Colors.teal.shade400]
                                                          : [Colors.grey.shade800, Colors.grey.shade700]),
                                                ),
                                                borderRadius: BorderRadius.circular(6),
                                                border: item.isToday
                                                    ? Border.all(color: Colors.tealAccent, width: 1.5)
                                                    : null,
                                                boxShadow: item.isToday
                                                    ? [
                                                        BoxShadow(
                                                          color: Colors.tealAccent.withValues(alpha: 0.3),
                                                          blurRadius: 8,
                                                          offset: const Offset(0, 2),
                                                        )
                                                      ]
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),

                                        // Rótulo do Dia da Semana
                                        Text(
                                          item.dayLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: item.isToday ? FontWeight.bold : FontWeight.w600,
                                            color: item.isToday
                                                ? Colors.tealAccent
                                                : (isDark ? Colors.white70 : Colors.black87),
                                          ),
                                        ),
                                        if (item.dateStr.isNotEmpty)
                                          Text(
                                            item.dateStr,
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: isDark ? Colors.white38 : Colors.black38,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Top 5 Apps & Sites Mais Consumidos
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.leaderboard, color: Colors.purpleAccent, size: 22),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tr.top5AppsSitesMaisConsumidos,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (topEntities.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                tr.nenhumaAtividadeRegistradaNaSemanaAinda,
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: topEntities.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = topEntities[index];
                              final color = _getColorForType(item.targetType);
                              final icon = _getIconForType(item.targetType);
                              final rank = index + 1;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF16191E) : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDark ? Colors.white10 : Colors.black12,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        // Posição no ranking
                                        Container(
                                          width: 24,
                                          height: 24,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: rank == 1
                                                ? Colors.amber.shade900.withValues(alpha: 0.5)
                                                : (isDark ? Colors.white12 : Colors.black12),
                                            shape: BoxShape.circle,
                                            border: rank == 1
                                                ? Border.all(color: Colors.amberAccent, width: 1)
                                                : null,
                                          ),
                                          child: Text(
                                            '$rank',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: rank == 1 ? Colors.amberAccent : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),

                                        // Ícone
                                        Icon(icon, size: 20, color: color),
                                        const SizedBox(width: 10),

                                        // Nome do app/site
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.displayName,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                item.targetType,
                                                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Tempo e Porcentagem
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _formatDuration(item.consumedSeconds),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'monospace',
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                            ),
                                            Text(
                                              tr.p0DoTotal(item.percentage.toStringAsFixed(1)),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.white54 : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Barra horizontal de proporção
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: (item.percentage / 100.0).clamp(0.01, 1.0),
                                        minHeight: 6,
                                        backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                        valueColor: AlwaysStoppedAnimation<Color>(color),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
