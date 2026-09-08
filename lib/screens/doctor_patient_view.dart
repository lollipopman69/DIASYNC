import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'medical_profile_edit_screen.dart';

class DoctorPatientView extends StatefulWidget {
  final String patientUid;
  final String patientName;

  const DoctorPatientView({super.key, required this.patientUid, required this.patientName});

  @override
  State<DoctorPatientView> createState() => _DoctorPatientViewState();
}

class _DoctorPatientViewState extends State<DoctorPatientView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1525),
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.patientName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const Text('Patient View', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4FC3F7),
          labelColor: const Color(0xFF4FC3F7),
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Medical Profile'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(patientUid: widget.patientUid),
          _MedicalProfileTab(patientUid: widget.patientUid, patientName: widget.patientName),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final String patientUid;
  const _OverviewTab({required this.patientUid});

  Color _glucoseColor(double g, double min, double max) {
    if (g < 54 || g > 300) return Colors.red;
    if (g < min || g > max) return Colors.orange;
    return Colors.green;
  }

  String _glucoseLabel(double g, double min, double max) {
    if (g < 54) return 'CRITICAL LOW';
    if (g < min) return 'LOW';
    if (g > 300) return 'CRITICAL HIGH';
    if (g > max) return 'HIGH';
    return 'NORMAL';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('medicalProfiles').doc(patientUid).snapshots(),
      builder: (context, profileSnap) {
        final profileData = profileSnap.data?.data() as Map<String, dynamic>?;
        final double targetMin = (profileData?['targetGlucoseMin'] ?? 70).toDouble();
        final double targetMax = (profileData?['targetGlucoseMax'] ?? 180).toDouble();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('glucoseReadings')
              .where('patientID', isEqualTo: patientUid)
              .orderBy('timestamp', descending: true)
              .limit(50)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)));
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('No glucose data', style: TextStyle(color: Colors.white38)));

            final latest = docs.first.data() as Map<String, dynamic>;
            final latestGlucose = (latest['glucoseLevel'] ?? 0).toDouble();
            final latestTime = latest['timestamp'] is DateTime
                ? latest['timestamp'] as DateTime
                : (latest['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

            final chartDocs = docs.reversed.toList();
            final spots = chartDocs.asMap().entries.map((e) {
              final d = e.value.data() as Map<String, dynamic>;
              return FlSpot(e.key.toDouble(), (d['glucoseLevel'] ?? 0).toDouble());
            }).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2035),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _glucoseColor(latestGlucose, targetMin, targetMax).withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Latest Reading', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${latestGlucose.toStringAsFixed(0)}',
                              style: TextStyle(color: _glucoseColor(latestGlucose, targetMin, targetMax), fontSize: 42, fontWeight: FontWeight.bold)),
                          const Padding(padding: EdgeInsets.only(bottom: 8, left: 4),
                              child: Text('mg/dL', style: TextStyle(color: Colors.white38, fontSize: 14))),
                        ]),
                        Text(DateFormat('MMM d, HH:mm').format(latestTime),
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            color: _glucoseColor(latestGlucose, targetMin, targetMax).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(_glucoseLabel(latestGlucose, targetMin, targetMax),
                            style: TextStyle(color: _glucoseColor(latestGlucose, targetMin, targetMax),
                                fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF1A2035), borderRadius: BorderRadius.circular(20)),
                    child: Text('Target Range: ${targetMin.toInt()} – ${targetMax.toInt()} mg/dL',
                        style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12)),
                  ),

                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF1A2035), borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Recent Glucose Trend',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: LineChart(LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 60,
                            getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
                          ),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(sideTitles: SideTitles(
                                showTitles: true, reservedSize: 36, interval: 60,
                                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 10)))),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          minY: 40,
                          maxY: 320,
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              color: const Color(0xFF4FC3F7),
                              barWidth: 2,
                              dotData: FlDotData(show: false),
                              belowBarData: BarAreaData(show: true, color: const Color(0xFF4FC3F7).withOpacity(0.1)),
                            ),
                            LineChartBarData(
                              spots: [FlSpot(0, targetMin), FlSpot(spots.length.toDouble(), targetMin)],
                              isCurved: false,
                              color: Colors.green.withOpacity(0.5),
                              barWidth: 1,
                              dotData: FlDotData(show: false),
                              dashArray: [4, 4],
                            ),
                            LineChartBarData(
                              spots: [FlSpot(0, targetMax), FlSpot(spots.length.toDouble(), targetMax)],
                              isCurved: false,
                              color: Colors.orange.withOpacity(0.5),
                              barWidth: 1,
                              dotData: FlDotData(show: false),
                              dashArray: [4, 4],
                            ),
                          ],
                        )),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 20),

                  Row(children: [
                    _statCard('Readings', '${docs.length}', Icons.timeline),
                    const SizedBox(width: 10),
                    _statCard('Avg Glucose',
                        '${(docs.map((d) => ((d.data() as Map)['glucoseLevel'] ?? 0) as num).reduce((a, b) => a + b) / docs.length).toStringAsFixed(0)} mg/dL',
                        Icons.show_chart),
                  ]),

                  const SizedBox(height: 20),
                  _RecentAlerts(patientUid: patientUid),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF1A2035), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: const Color(0xFF4FC3F7), size: 18),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ── Doctor alert widget with resolve button ──────────────

class _RecentAlerts extends StatefulWidget {
  final String patientUid;
  const _RecentAlerts({required this.patientUid});

  @override
  State<_RecentAlerts> createState() => _RecentAlertsState();
}

class _RecentAlertsState extends State<_RecentAlerts> {
  bool _showResolved = false;

  Future<void> _resolveAlert(String docId) async {
    await FirebaseFirestore.instance.collection('alerts').doc(docId).update({
      'resolved': true,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Alerts',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
            GestureDetector(
              onTap: () => setState(() => _showResolved = !_showResolved),
              child: Text(
                _showResolved ? 'Hide Resolved' : 'Show Resolved',
                style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('alerts')
              .where('patientID', isEqualTo: widget.patientUid)
              .orderBy('timestamp', descending: true)
              .limit(10)
              .snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const SizedBox();
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Text('No recent alerts',
                  style: TextStyle(color: Colors.white38, fontSize: 13));
            }

            final filtered = docs.where((doc) {
              final resolved = (doc.data() as Map<String, dynamic>)['resolved'] == true;
              return _showResolved ? true : !resolved;
            }).toList();

            if (filtered.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text('All alerts resolved', style: TextStyle(color: Colors.green, fontSize: 13)),
                ]),
              );
            }

            return Column(
              children: filtered.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final ts = (d['timestamp'] as Timestamp?)?.toDate();
                final resolved = d['resolved'] == true;
                final resolvedAt = (d['resolvedAt'] as Timestamp?)?.toDate();
                final type = d['type'] as String? ?? 'INFO';
                final color = type == 'CRITICAL'
                    ? Colors.red
                    : type == 'LOW'
                        ? const Color(0xFFE65100)
                        : type == 'HIGH'
                            ? Colors.orange
                            : Colors.white38;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: resolved
                        ? const Color(0xFF1A2035).withOpacity(0.5)
                        : const Color(0xFF1A2035),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: resolved ? Colors.white12 : color.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          resolved ? Icons.check_circle : Icons.warning_amber,
                          color: resolved ? Colors.green : color,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(d['message'] ?? '',
                              style: TextStyle(
                                color: resolved ? Colors.white38 : Colors.white70,
                                fontSize: 13,
                                decoration: resolved ? TextDecoration.lineThrough : null,
                              )),
                        ),
                        if (!resolved)
                          GestureDetector(
                            onTap: () => _resolveAlert(doc.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.4)),
                              ),
                              child: const Text('Resolve',
                                  style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (ts != null)
                            Text(DateFormat('MM/dd HH:mm').format(ts),
                                style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          if (resolved && resolvedAt != null)
                            Text('Resolved ${DateFormat('MM/dd HH:mm').format(resolvedAt)}',
                                style: const TextStyle(color: Colors.green, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _MedicalProfileTab extends StatelessWidget {
  final String patientUid;
  final String patientName;
  const _MedicalProfileTab({required this.patientUid, required this.patientName});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('medicalProfiles').doc(patientUid).snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)));
        if (!snap.data!.exists) return const Center(child: Text('No medical profile', style: TextStyle(color: Colors.white38)));

        final data = snap.data!.data() as Map<String, dynamic>;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _profileRow('Target Glucose Min', '${data['targetGlucoseMin'] ?? 70} mg/dL', Icons.arrow_downward),
              _profileRow('Target Glucose Max', '${data['targetGlucoseMax'] ?? 180} mg/dL', Icons.arrow_upward),
              _profileRow('Insulin Type', data['insulinType'] ?? 'Rapid-Acting', Icons.medication_outlined),
              _profileRow('Basal Rate', '${data['basalRate'] ?? 0.8} U/hr', Icons.water_drop_outlined),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => MedicalProfileEditScreen(
                        patientUid: patientUid, patientName: patientName, currentData: data),
                  )),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Medical Profile',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4FC3F7),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _profileRow(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A2035), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF4FC3F7), size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14))),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      ]),
    );
  }
}