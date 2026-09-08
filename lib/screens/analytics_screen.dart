import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _auth      = FirebaseAuth.instance;

  late TabController _tabController;

  List<Map<String, dynamic>> _readings = [];
  bool _loading = true;

  double _avgGlucose  = 0;
  double _minGlucose  = 0;
  double _maxGlucose  = 0;
  double _timeInRange = 0;
  double _timeLow     = 0;
  double _timeHigh    = 0;

  List<FlSpot>            _lineSpots = [];
  List<BarChartGroupData> _barGroups = [];
  List<String>            _barLabels = [];

  // Heatmap: hour (0-23) -> avg glucose
  List<double> _hourlyAvg = List.filled(24, 0);

  // Scatter: all readings as FlSpot(hour_of_day, glucose)
  List<FlSpot> _scatterSpots = [];

   double _low          = 70;
   double _high         = 180;
   double _criticalLow  = 54;
   double _criticalHigh = 300;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────
  // Data
  // ────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final uid = _auth.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final profileDoc = await _firestore.collection('medicalProfiles').doc(uid).get();
    final profileData = profileDoc.data();
    if (profileData != null) {
      _low  = (profileData['targetGlucoseMin'] ?? 70).toDouble();
      _high = (profileData['targetGlucoseMax'] ?? 180).toDouble();
          }
    try {
      final snap = await _firestore
          .collection('glucoseReadings')
          .where('patientID', isEqualTo: uid)
          .get();

      final readings = snap.docs.map((d) => d.data()).toList();
      readings.sort((a, b) {
        final ta = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return ta.compareTo(tb);
      });

      _readings = readings;
      final now = DateTime.now();
      _computeStats(readings);
      _buildLineChart(readings, now);
      _buildBarChart(readings, now);
      _buildHourlyHeatmap(readings);
      _buildScatter(readings, now);
    } catch (e) {
      debugPrint('Analytics load error: $e');
    }

    setState(() => _loading = false);
  }

  void _computeStats(List<Map<String, dynamic>> readings) {
    if (readings.isEmpty) return;
    final values = readings
        .map((r) => (r['glucoseLevel'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    if (values.isEmpty) return;

    _avgGlucose  = values.reduce((a, b) => a + b) / values.length;
    _minGlucose  = values.reduce((a, b) => a < b ? a : b);
    _maxGlucose  = values.reduce((a, b) => a > b ? a : b);
    _timeInRange = values.where((v) => v >= _low && v <= _high).length / values.length * 100;
    _timeLow     = values.where((v) => v < _low).length  / values.length * 100;
    _timeHigh    = values.where((v) => v > _high).length / values.length * 100;
  }

  void _buildLineChart(List<Map<String, dynamic>> readings, DateTime now) {
    final cutoff = now.subtract(const Duration(hours: 24));
    final recent = readings.where((r) {
      final ts = r['timestamp'];
      if (ts == null) return false;
      try { return (ts as Timestamp).toDate().isAfter(cutoff); }
      catch (_) { return false; }
    }).toList();

    _lineSpots = recent.map((r) {
      final ts  = (r['timestamp'] as Timestamp).toDate();
      final val = (r['glucoseLevel'] as num?)?.toDouble() ?? 0;
      final x   = ts.difference(cutoff).inMinutes / 60.0;
      return FlSpot(x, val);
    }).toList();
  }

  void _buildBarChart(List<Map<String, dynamic>> readings, DateTime now) {
    final today  = DateTime(now.year, now.month, now.day);
    final groups = <int, List<double>>{};

    for (final r in readings) {
      final ts = r['timestamp'];
      if (ts == null) continue;
      try {
        final dt  = (ts as Timestamp).toDate();
        final day = DateTime(dt.year, dt.month, dt.day);
        final idx = today.difference(day).inDays;
        if (idx < 0 || idx > 6) continue;
        final val = (r['glucoseLevel'] as num?)?.toDouble();
        if (val != null) (groups[idx] ??= []).add(val);
      } catch (_) {}
    }

    _barLabels = List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return '${d.month}/${d.day}';
    });

    _barGroups = List.generate(7, (i) {
      final dayIdx = 6 - i;
      final vals   = groups[dayIdx] ?? [];
      final avg    = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: avg,
            color: _barColor(avg),
            width: 18,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    });
  }

  void _buildHourlyHeatmap(List<Map<String, dynamic>> readings) {
    final hourBuckets = <int, List<double>>{};
    for (final r in readings) {
      final ts = r['timestamp'];
      if (ts == null) continue;
      try {
        final dt  = (ts as Timestamp).toDate();
        final val = (r['glucoseLevel'] as num?)?.toDouble();
        if (val != null) (hourBuckets[dt.hour] ??= []).add(val);
      } catch (_) {}
    }
    _hourlyAvg = List.generate(24, (h) {
      final vals = hourBuckets[h] ?? [];
      return vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
    });
  }

  void _buildScatter(List<Map<String, dynamic>> readings, DateTime now) {
    final cutoff = now.subtract(const Duration(days: 7));
    _scatterSpots = [];
    for (final r in readings) {
      final ts = r['timestamp'];
      if (ts == null) continue;
      try {
        final dt  = (ts as Timestamp).toDate();
        if (dt.isBefore(cutoff)) continue;
        final val = (r['glucoseLevel'] as num?)?.toDouble();
        if (val != null) {
          final x = dt.hour + dt.minute / 60.0;
          _scatterSpots.add(FlSpot(x, val));
        }
      } catch (_) {}
    }
  }

  // ────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────

  Color _barColor(double v) {
    if (v == 0)    return Colors.white12;
    if (v < _low)  return const Color(0xFFE65100);
    if (v > _high) return const Color(0xFFFF6F00);
    return const Color(0xFF2E7D32);
  }

  Color _glucoseColor(double v) {
    if (v <= 0)           return Colors.transparent;
    if (v < _criticalLow) return const Color(0xFFB71C1C);
    if (v < _low)         return const Color(0xFFE65100);
    if (v > _criticalHigh)return const Color(0xFF7B1FA2);
    if (v > _high)        return const Color(0xFFFF6F00);
    return const Color(0xFF2E7D32);
  }

  Color _lineColor(double v) {
    if (v < _low)  return const Color(0xFFE65100);
    if (v > _high) return const Color(0xFFFF6F00);
    return const Color(0xFF4FC3F7);
  }

  // ────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D2E),
        title: const Text('Analytics',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4FC3F7),
          labelColor: const Color(0xFF4FC3F7),
          unselectedLabelColor: Colors.white38,
          isScrollable: true,
          tabs: const [
            Tab(text: '24H Line'),
            Tab(text: '7D Bar'),
            Tab(text: 'Heatmap'),
            Tab(text: 'Distribution'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _statsRow(),
                    const SizedBox(height: 14),
                    _tirCard(),
                    const SizedBox(height: 14),
                    _donutCard(),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 340,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _lineChartCard(),
                          _barChartCard(),
                          _heatmapCard(),
                          _scatterCard(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  // ────────────────────────────────────────────────
  // Stat widgets
  // ────────────────────────────────────────────────

  Widget _statsRow() {
    return Row(
      children: [
        Expanded(child: _statTile('Avg', '${_avgGlucose.toStringAsFixed(0)}', 'mg/dL', const Color(0xFF4FC3F7))),
        const SizedBox(width: 8),
        Expanded(child: _statTile('Min', '${_minGlucose.toStringAsFixed(0)}', 'mg/dL', const Color(0xFF66BB6A))),
        const SizedBox(width: 8),
        Expanded(child: _statTile('Max', '${_maxGlucose.toStringAsFixed(0)}', 'mg/dL', const Color(0xFFFF6F00))),
      ],
    );
  }

  Widget _statTile(String label, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)),
        Text(unit, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    );
  }

  Widget _tirCard() {
    final pct = _timeInRange.clamp(0.0, 100.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
             Text('Time in Range (70–180)',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text('${pct.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: Color(0xFF4FC3F7), fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 10,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                pct >= 70 ? const Color(0xFF2E7D32) : pct >= 50 ? const Color(0xFFFF6F00) : const Color(0xFFB71C1C),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Target: ≥ 70%', style: TextStyle(color: Colors.white30, fontSize: 11)),
        ],
      ),
    );
  }

  // ── Donut chart ───────────────────────────────

  Widget _donutCard() {
    final inRange = _timeInRange.clamp(0.0, 100.0);
    final low     = _timeLow.clamp(0.0, 100.0);
    final high    = _timeHigh.clamp(0.0, 100.0);
    final other   = (100 - inRange - low - high).clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Glucose Distribution',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                height: 140,
                width: 140,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: [
                      PieChartSectionData(
                        value: inRange, color: const Color(0xFF2E7D32),
                        title: '${inRange.toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        radius: 30,
                      ),
                      PieChartSectionData(
                        value: high, color: const Color(0xFFFF6F00),
                        title: '${high.toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        radius: 30,
                      ),
                      PieChartSectionData(
                        value: low, color: const Color(0xFFE65100),
                        title: '${low.toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        radius: 30,
                      ),
                      if (other > 0)
                        PieChartSectionData(
                          value: other, color: Colors.white12,
                          title: '', radius: 30,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legend(const Color(0xFF2E7D32), 'In Range', '${inRange.toStringAsFixed(1)}%'),
                    const SizedBox(height: 10),
                    _legend(const Color(0xFFFF6F00), 'High (>${_high.toInt()})', '${high.toStringAsFixed(1)}%'),
                    const SizedBox(height: 10),
                    _legend(const Color(0xFFE65100), 'Low (<${_low.toInt()})', '${low.toStringAsFixed(1)}%'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label, String value) {
    return Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    ]);
  }

  // ── Line chart ────────────────────────────────

  Widget _lineChartCard() {
    if (_lineSpots.isEmpty) return _emptyState('No data in last 24 hours');

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
            child: Text('Last 24 Hours', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 40, maxY: 320,
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                  getDrawingVerticalLine:   (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 36, interval: 60,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  )),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 22, interval: 6,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}h', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  )),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                extraLinesData: ExtraLinesData(horizontalLines: [
                  HorizontalLine(y: _low,  color: Colors.orange.withOpacity(0.5),     strokeWidth: 1, dashArray: [5, 4],
                    label: HorizontalLineLabel(show: true, alignment: Alignment.topRight,
                      style: const TextStyle(color: Colors.orange, fontSize: 10), labelResolver: (_) => 'Low')),
                  HorizontalLine(y: _high, color: Colors.deepOrange.withOpacity(0.5), strokeWidth: 1, dashArray: [5, 4],
                    label: HorizontalLineLabel(show: true, alignment: Alignment.topRight,
                      style: const TextStyle(color: Colors.deepOrange, fontSize: 10), labelResolver: (_) => 'High')),
                ]),
                lineBarsData: [
                  LineChartBarData(
                    spots: _lineSpots,
                    isCurved: true, curveSmoothness: 0.3,
                    color: const Color(0xFF4FC3F7), barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                          radius: 3, color: _lineColor(spot.y), strokeWidth: 0),
                    ),
                    belowBarData: BarAreaData(show: true, color: const Color(0xFF4FC3F7).withOpacity(0.08)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bar chart ─────────────────────────────────

  Widget _barChartCard() {
    if (_barGroups.every((g) => g.barRods.first.toY == 0)) {
      return _emptyState('No data in last 7 days');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
            child: Text('Daily Average (7 Days)', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: 320,
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 36, interval: 80,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  )),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 22,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= _barLabels.length) return const SizedBox();
                      return Text(_barLabels[i], style: const TextStyle(color: Colors.white38, fontSize: 9));
                    },
                  )),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                barGroups: _barGroups,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                      '${rod.toY.toStringAsFixed(0)} mg/dL',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Heatmap (hourly average) ───────────────────

  Widget _heatmapCard() {
    final hasData = _hourlyAvg.any((v) => v > 0);
    if (!hasData) return _emptyState('No data for heatmap');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Avg Glucose by Hour of Day',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          const Text('Tap a cell to see the value',
              style: TextStyle(color: Colors.white24, fontSize: 10)),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.2,
              ),
              itemCount: 24,
              itemBuilder: (_, h) {
                final avg = _hourlyAvg[h];
                final color = _glucoseColor(avg);
                return Tooltip(
                  message: avg > 0 ? '${h.toString().padLeft(2,'0')}:00\n${avg.toStringAsFixed(0)} mg/dL' : 'No data',
                  child: Container(
                    decoration: BoxDecoration(
                      color: avg > 0 ? color.withOpacity(0.7) : Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${h.toString().padLeft(2,'0')}h',
                            style: const TextStyle(color: Colors.white60, fontSize: 9)),
                        if (avg > 0)
                          Text('${avg.toStringAsFixed(0)}',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _heatLegend(const Color(0xFFB71C1C), 'Critical Low'),
              const SizedBox(width: 8),
              _heatLegend(const Color(0xFFE65100), 'Low'),
              const SizedBox(width: 8),
              _heatLegend(const Color(0xFF2E7D32), 'Normal'),
              const SizedBox(width: 8),
              _heatLegend(const Color(0xFFFF6F00), 'High'),
              const SizedBox(width: 8),
              _heatLegend(const Color(0xFF7B1FA2), 'Critical High'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heatLegend(Color color, String label) {
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 3),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
    ]);
  }

  // ── Scatter plot ──────────────────────────────

  Widget _scatterCard() {
    if (_scatterSpots.isEmpty) return _emptyState('No data for scatter plot');

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
            child: Text('Glucose by Time of Day (7 Days)', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Expanded(
            child: ScatterChart(
              ScatterChartData(
                minX: 0, maxX: 24,
                minY: 40, maxY: 320,
                scatterSpots: _scatterSpots.map((s) => ScatterSpot(
                  s.x, s.y,
                  dotPainter: FlDotCirclePainter(
                    radius: 3,
                    color: _glucoseColor(s.y).withOpacity(0.7),
                    strokeWidth: 0,
                  ),
                )).toList(),
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                  getDrawingVerticalLine:   (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 36, interval: 60,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  )),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 22, interval: 6,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}h', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  )),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1A1D2E), borderRadius: BorderRadius.circular(14)),
      child: Center(child: Text(msg, style: const TextStyle(color: Colors.white38))),
    );
  }
}