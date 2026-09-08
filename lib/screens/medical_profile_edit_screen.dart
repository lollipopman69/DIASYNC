import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MedicalProfileEditScreen extends StatefulWidget {
  final String patientUid;
  final String patientName;
  final Map<String, dynamic> currentData;

  const MedicalProfileEditScreen({
    super.key,
    required this.patientUid,
    required this.patientName,
    required this.currentData,
  });

  @override
  State<MedicalProfileEditScreen> createState() => _MedicalProfileEditScreenState();
}

class _MedicalProfileEditScreenState extends State<MedicalProfileEditScreen> {
  late TextEditingController _minCtrl;
  late TextEditingController _maxCtrl;
  late TextEditingController _basalCtrl;
  late String _insulinType;
  bool _saving = false;

  final _insulinTypes = ['Rapid-Acting', 'Short-Acting', 'Intermediate-Acting', 'Long-Acting', 'Ultra Long-Acting'];

  @override
  void initState() {
    super.initState();
    _minCtrl = TextEditingController(text: '${widget.currentData['targetGlucoseMin'] ?? 70}');
    _maxCtrl = TextEditingController(text: '${widget.currentData['targetGlucoseMax'] ?? 180}');
    _basalCtrl = TextEditingController(text: '${widget.currentData['basalRate'] ?? 0.8}');
    _insulinType = widget.currentData['insulinType'] ?? 'Rapid-Acting';
    if (!_insulinTypes.contains(_insulinType)) _insulinType = 'Rapid-Acting';
  }

  Future<void> _save() async {
    final min = double.tryParse(_minCtrl.text.trim());
    final max = double.tryParse(_maxCtrl.text.trim());
    final basal = double.tryParse(_basalCtrl.text.trim());

    if (min == null || max == null || basal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid numbers'), backgroundColor: Colors.red));
      return;
    }
    if (min >= max) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Min must be less than Max'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('medicalProfiles').doc(widget.patientUid).update({
        'targetGlucoseMin': min,
        'targetGlucoseMax': max,
        'insulinType': _insulinType,
        'basalRate': basal,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medical profile updated'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1525),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Edit Medical Profile', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          Text(widget.patientName, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Glucose Targets', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _numField(_minCtrl, 'Min (mg/dL)', Icons.arrow_downward)),
                const SizedBox(width: 12),
                Expanded(child: _numField(_maxCtrl, 'Max (mg/dL)', Icons.arrow_upward)),
              ]),
              const SizedBox(height: 20),
              const Text('Insulin', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: const Color(0xFF1A2035), borderRadius: BorderRadius.circular(12)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _insulinType,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1A2035),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    items: _insulinTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => _insulinType = v!),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _numField(_basalCtrl, 'Basal Rate (U/hr)', Icons.water_drop_outlined),
              const SizedBox(height: 8),
              const Text('Units per hour delivered continuously by the pump', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4FC3F7),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled: true,
        fillColor: const Color(0xFF1A2035),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}