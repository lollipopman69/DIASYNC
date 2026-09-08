import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'doctor_patient_view.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});
  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _searchResult;
  String? _searchResultUid;
  bool _searching = false;
  String? _searchError;
  String _doctorName = '';
  List<String> _assignedPatients = [];

  @override
  void initState() {
    super.initState();
    _loadDoctorName();
  }

  Future<void> _loadDoctorName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    var doc = await FirebaseFirestore.instance.collection('doctors').doc(uid).get();

    if (!doc.exists) {
      final patientDoc = await FirebaseFirestore.instance.collection('patients').doc(uid).get();
      final name = patientDoc.data()?['name'] ?? 'Doctor';
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      await FirebaseFirestore.instance.collection('doctors').doc(uid).set({
        'name': name,
        'email': email,
        'assignedPatients': [],
      });
      if (mounted) setState(() => _doctorName = name);
    } else {
      final data = doc.data()!;
      if (mounted) setState(() {
        _doctorName = data['name'] ?? 'Doctor';
        _assignedPatients = List<String>.from(data['assignedPatients'] ?? []);
      });
    }
  }

  Future<void> _searchPatient() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _searchResult = null;
      _searchError = null;
      _searchResultUid = null;
    });

    try {
      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('patients')
          .where('email', isEqualTo: query)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('patients')
            .where('patientID', isEqualTo: query)
            .limit(1)
            .get();
      }

      if (snap.docs.isEmpty) {
        setState(() => _searchError = 'No patient found');
      } else {
        final doc = snap.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        // Skip if result is a doctor account
        if ((data['role'] ?? 'patient') == 'doctor') {
          setState(() => _searchError = 'No patient found');
          return;
        }
        setState(() {
          _searchResult = data;
          _searchResultUid = doc.id;
        });
      }
    } catch (e) {
      setState(() => _searchError = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _assignPatient(String patientUid, String patientName) async {
    final doctorUid = FirebaseAuth.instance.currentUser?.uid;
    if (doctorUid == null) return;

    final batch = FirebaseFirestore.instance.batch();

    batch.set(
      FirebaseFirestore.instance.collection('patients').doc(patientUid),
      {'doctorId': doctorUid, 'doctorName': 'Dr. $_doctorName'},
      SetOptions(merge: true),
    );

    batch.set(
      FirebaseFirestore.instance.collection('doctors').doc(doctorUid),
      {
        'name': _doctorName,
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
        'assignedPatients': FieldValue.arrayUnion([patientUid]),
      },
      SetOptions(merge: true),
    );

    try {
      await batch.commit();

      // Refresh list manually
      final doc = await FirebaseFirestore.instance.collection('doctors').doc(doctorUid).get();
      if (mounted) {
        setState(() {
          _assignedPatients = List<String>.from(doc.data()?['assignedPatients'] ?? []);
          _searchResult = null;
          _searchResultUid = null;
        });
        _searchCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$patientName assigned successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removePatient(String patientUid) async {
    final doctorUid = FirebaseAuth.instance.currentUser?.uid;
    if (doctorUid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        title: const Text('Remove Patient', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to remove this patient?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance.collection('patients').doc(patientUid),
        {'doctorId': '', 'doctorName': ''},
        SetOptions(merge: true),
      );
      batch.set(
        FirebaseFirestore.instance.collection('doctors').doc(doctorUid),
        {'assignedPatients': FieldValue.arrayRemove([patientUid])},
        SetOptions(merge: true),
      );
      await batch.commit();

      final doc = await FirebaseFirestore.instance.collection('doctors').doc(doctorUid).get();
      if (mounted) setState(() {
        _assignedPatients = List<String>.from(doc.data()?['assignedPatients'] ?? []);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final doctorUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1525),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DiASync', style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Dr. $_doctorName', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Colors.white54), onPressed: _logout),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Find Patient', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search by email or patient ID',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                        filled: true,
                        fillColor: const Color(0xFF1A2035),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onSubmitted: (_) => _searchPatient(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searching ? null : _searchPatient,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4FC3F7),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _searching
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Search', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),

              if (_searchError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Text(_searchError!, style: const TextStyle(color: Colors.red)),
                  ]),
                ),
              ],

              if (_searchResult != null && _searchResultUid != null) ...[
                const SizedBox(height: 12),
                _SearchResultCard(
                  data: _searchResult!,
                  patientUid: _searchResultUid!,
                  currentDoctorUid: doctorUid,
                  onAssign: () => _assignPatient(_searchResultUid!, _searchResult!['name'] ?? 'Patient'),
                  onView: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DoctorPatientView(patientUid: _searchResultUid!, patientName: _searchResult!['name'] ?? 'Patient'),
                  )),
                ),
              ],

              const SizedBox(height: 24),
              const Text('My Patients', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),

              if (_assignedPatients.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: const Color(0xFF1A2035), borderRadius: BorderRadius.circular(16)),
                  child: const Center(child: Text('No patients assigned yet', style: TextStyle(color: Colors.white38))),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _assignedPatients.length,
                  itemBuilder: (_, i) => _AssignedPatientTile(
                    patientUid: _assignedPatients[i],
                    onView: (uid, name) => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DoctorPatientView(patientUid: uid, patientName: name),
                    )),
                    onRemove: _removePatient,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String patientUid;
  final String currentDoctorUid;
  final VoidCallback onAssign;
  final VoidCallback onView;

  const _SearchResultCard({required this.data, required this.patientUid, required this.currentDoctorUid, required this.onAssign, required this.onView});

  @override
  Widget build(BuildContext context) {
    final alreadyAssigned = (data['doctorId'] ?? '') == currentDoctorUid;
    final hasOtherDoctor = (data['doctorId'] ?? '').isNotEmpty && !alreadyAssigned;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2035),
        border: Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const CircleAvatar(backgroundColor: Color(0xFF4FC3F7), radius: 20, child: Icon(Icons.person, color: Colors.black, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              Text(data['email'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
          ]),
          if (hasOtherDoctor) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: const Text('Already assigned to another doctor', style: TextStyle(color: Colors.orange, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onView,
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF4FC3F7), side: const BorderSide(color: Color(0xFF4FC3F7))),
                child: const Text('View'),
              ),
            ),
            if (!alreadyAssigned) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAssign,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FC3F7), foregroundColor: Colors.black),
                  child: const Text('Assign to Me'),
                ),
              ),
            ] else ...[
              const SizedBox(width: 8),
              const Expanded(child: Center(child: Text('Already your patient', style: TextStyle(color: Colors.green, fontSize: 12)))),
            ],
          ]),
        ],
      ),
    );
  }
}

class _AssignedPatientTile extends StatelessWidget {
  final String patientUid;
  final Function(String uid, String name) onView;
  final Function(String uid) onRemove;

  const _AssignedPatientTile({required this.patientUid, required this.onView, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('patients').doc(patientUid).get(),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        if (!snap.data!.exists) return const SizedBox.shrink();
        final data = snap.data!.data() as Map<String, dynamic>;
        final name = data['name'] ?? 'Unknown';

        return GestureDetector(
          onLongPress: () => onRemove(patientUid),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1A2035), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Color(0xFF1E3A5F), radius: 20, child: Icon(Icons.person, color: Color(0xFF4FC3F7), size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  Text(data['email'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ])),
                TextButton(
                  onPressed: () => onView(patientUid, name),
                  child: const Text('View', style: TextStyle(color: Color(0xFF4FC3F7))),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}