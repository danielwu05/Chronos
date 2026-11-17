import 'package:flutter/material.dart';
import 'package:chronos_app/src/rust/api/simple.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  AnalyticsSummaryDto? _summary;
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
      if (mounted) {
        setState(() {
          _summary = s;
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
      return '${hours}h ${minutes}m';
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
    final peakLabel = (s?.peakDayLabel.isNotEmpty ?? false) ? s!.peakDayLabel : 'Sem dados';
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
                          'Estatísticas de Tempo de Tela',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Consumo consolidado, tendências semanais e ranking de aplicativos e sites.',
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
                      label: const Text('Atualizar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                          title: 'Consumo Hoje',
                          value: _formatDuration(totalToday),
                          subtitle: 'Tempo em apps/sites monitorados',
                          icon: Icons.today,
                          color: Colors.tealAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Média Semanal',
                          value: '${_formatDuration(avg7d)} / dia',
                          subtitle: 'Baseado nos últimos 7 dias',
                          icon: Icons.date_range,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Dia de Pico',
                          value: peakSeconds > 0 ? _formatDuration(peakSeconds) : '0m',
                          subtitle: peakLabel,
                          icon: Icons.show_chart,
                          color: Colors.amberAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Tendência vs. Semana Anterior',
                          value: compPercent == 0.0
                              ? 'Estável'
                              : '${compPercent > 0 ? '+' : ''}${compPercent.toStringAsFixed(1)}%',
                          subtitle: compPercent > 0 ? 'Mais tempo de tela' : 'Menos tempo de tela',
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
                              title: 'Consumo Hoje',
                              value: _formatDuration(totalToday),
                              subtitle: 'Apps/sites monitorados',
                              icon: Icons.today,
                              color: Colors.tealAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              title: 'Média Diária',
                              value: '${_formatDuration(avg7d)}/dia',
                              subtitle: 'Últimos 7 dias',
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
                              title: 'Dia de Pico',
                              value: peakSeconds > 0 ? _formatDuration(peakSeconds) : '0m',
                              subtitle: peakLabel,
                              icon: Icons.show_chart,
                              color: Colors.amberAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MetricCard(
                              title: 'Tendência',
                              value: compPercent == 0.0
                                  ? 'Estável'
                                  : '${compPercent > 0 ? '+' : ''}${compPercent.toStringAsFixed(1)}%',
                              subtitle: compPercent > 0 ? 'Mais tela' : 'Menos tela',
                              icon: compPercent > 0 ? Icons.trending_up : Icons.trending_down,
                              color: compPercent > 0 ? Colors.redAccent : Colors.greenAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                            const Row(
                              children: [
                                Icon(Icons.bar_chart, color: Colors.tealAccent, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Consumo Diário nos Últimos 7 Dias',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                            Text(
                              'Total: ${_formatDuration(total7d)}',
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
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text('Nenhum dado diário registrado.', style: TextStyle(color: Colors.white54)),
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
                        const Row(
                          children: [
                            Icon(Icons.leaderboard, color: Colors.purpleAccent, size: 22),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Top 5 Apps & Sites Mais Consumidos (Últimos 7 Dias)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (topEntities.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'Nenhuma atividade registrada na semana ainda.',
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
                                              '${item.percentage.toStringAsFixed(1)}% do total',
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
