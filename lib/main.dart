import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_html/html.dart' as html;
import 'package:csv/csv.dart';
import 'dart:typed_data';

const firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyBwJa6ddO_iTUWhu5JUDUsFHvg0h41C1C0",
  appId: "1:533540745340:web:5e661c93bb21834b81d9f9",
  messagingSenderId: "533540745340",
  projectId: "tax-tracker-89fb6",
  authDomain: "tax-tracker-89fb6.firebaseapp.com",
  storageBucket: "tax-tracker-89fb6.firebasestorage.app",
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const TaxTrackerApp());
}

class Expense {
  final DateTime date;
  final String supplier;
  final String category;
  final String description;
  final double amount;
  final String entity;
  final int colorValue;
  final String? receiptUrl;

  Expense({
    required this.date, required this.supplier, required this.category, 
    required this.description, required this.amount, required this.entity, 
    required this.colorValue, this.receiptUrl
  });

  Map<String, dynamic> toMap() => {
    'date': date.toIso8601String(), 'supplier': supplier, 'category': category,
    'description': description, 'amount': amount, 'entity': entity, 
    'colorValue': colorValue, 'receiptUrl': receiptUrl,
    'timestamp': FieldValue.serverTimestamp(), 
  };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
    date: DateTime.parse(map['date']), supplier: map['supplier'], 
    category: map['category'], description: map['description'], 
    amount: (map['amount'] as num).toDouble(), entity: map['entity'], 
    colorValue: map['colorValue'], receiptUrl: map['receiptUrl']
  );
}

class TaxTrackerApp extends StatelessWidget {
  const TaxTrackerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
      home: const AuthGate(), 
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) return const MainScaffold();
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(), password: _passwordController.text.trim(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login Failed'), backgroundColor: Colors.red));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.blueGrey),
              const SizedBox(height: 20),
              const Text("Tax Tracker Secure Login", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
              const SizedBox(height: 30),
              _isLoading ? const CircularProgressIndicator() : FilledButton(
                onPressed: _signIn, style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text("Log In", style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});
  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;
  List<Expense> _myExpenses = [];

  @override
  void initState() {
    super.initState();
    _startLiveCloudSync();
  }

  void _startLiveCloudSync() {
    FirebaseFirestore.instance.collection('expenses').orderBy('timestamp', descending: true).snapshots().listen((snapshot) {
      setState(() { _myExpenses = snapshot.docs.map((doc) => Expense.fromMap(doc.data())).toList(); });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tax Tracker"),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          AddExpenseScreen(onSaveComplete: () => setState(() => _index = 1)),
          LedgerScreen(expenses: _myExpenses),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'History'),
        ],
      ),
    );
  }
}

class AddExpenseScreen extends StatefulWidget {
  final VoidCallback onSaveComplete;
  const AddExpenseScreen({super.key, required this.onSaveComplete});
  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  String entity = 'Biz';
  DateTime selectedDate = DateTime.now();
  final _supplierController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descController = TextEditingController();
  final _amtController = TextEditingController();
  
  Uint8List? _receiptBytes; 
  bool _isSaving = false;

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null && picked != selectedDate) setState(() => selectedDate = picked);
  }

  Future<void> _takePhoto() async {
    await SystemChannels.platform.invokeMethod('SystemSound.play', 'click'); 
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 50, preferredCameraDevice: CameraDevice.rear);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() => _receiptBytes = bytes);
      }
    } catch (e) {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() => _receiptBytes = bytes);
      }
    }
  }

  Future<void> _saveEverything() async {
    if (_amtController.text.isEmpty) return;
    setState(() => _isSaving = true);

    String? uploadedUrl;
    if (_receiptBytes != null) {
      try {
        final fileName = 'receipts/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instanceFor(app: Firebase.app()).ref().child(fileName);
        await ref.putData(_receiptBytes!);
        uploadedUrl = await ref.getDownloadURL();
      } catch (storageError) {
        // Fallback or ignore
      }
    }

    final colorMap = {'Biz': Colors.green.value, 'BnB': Colors.blue.value, 'Reno': Colors.orange.value};
    final newExpense = Expense(
      date: selectedDate, supplier: _supplierController.text.isEmpty ? "Unknown" : _supplierController.text,
      category: _categoryController.text.isEmpty ? "General" : _categoryController.text, description: _descController.text,
      amount: double.parse(_amtController.text), entity: entity, colorValue: colorMap[entity]!,
      receiptUrl: uploadedUrl 
    );

    await FirebaseFirestore.instance.collection('expenses').add(newExpense.toMap());

    _amtController.clear(); _supplierController.clear(); _categoryController.clear(); _descController.clear();
    setState(() { _receiptBytes = null; _isSaving = false; });
    widget.onSaveComplete();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Biz', label: Text('Biz')),
              ButtonSegment(value: 'BnB', label: Text('Airbnb')),
              ButtonSegment(value: 'Reno', label: Text('Reno')),
            ],
            selected: {entity},
            onSelectionChanged: (set) => setState(() => entity = set.first),
          ),
          const SizedBox(height: 20),
          TextField(controller: _amtController, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontSize: 40), decoration: const InputDecoration(prefixText: '\$ ', labelText: 'Amount')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () => _pickDate(context), icon: const Icon(Icons.calendar_today), label: Text("Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}"), style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft)),
          const SizedBox(height: 10),
          TextField(controller: _supplierController, decoration: const InputDecoration(labelText: 'Supplier')),
          TextField(controller: _categoryController, decoration: const InputDecoration(labelText: 'Category')),
          TextField(controller: _descController, decoration: const InputDecoration(labelText: 'Notes')),
          const SizedBox(height: 20),
          if (_receiptBytes != null) 
            Container(height: 150, decoration: BoxDecoration(border: Border.all(color: Colors.grey), image: DecorationImage(image: MemoryImage(_receiptBytes!), fit: BoxFit.contain))),
          OutlinedButton.icon(
            onPressed: _takePhoto, 
            icon: Icon(_receiptBytes == null ? Icons.camera_alt : Icons.check, color: _receiptBytes == null ? null : Colors.green), 
            label: Text(_receiptBytes == null ? "Attach Receipt Photo" : "Photo Attached! (Tap to retake)")
          ),
          const SizedBox(height: 30),
          _isSaving 
            ? const Center(child: CircularProgressIndicator()) 
            : FilledButton(
                onPressed: _saveEverything, 
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text("Save Expense"),
              ),
        ],
      ),
    );
  }
}

class LedgerScreen extends StatelessWidget {
  final List<Expense> expenses;
  const LedgerScreen({super.key, required this.expenses});

  Future<void> _deleteExpense(String supplier, double amount, DateTime date) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('expenses')
        .where('supplier', isEqualTo: supplier)
        .where('amount', isEqualTo: amount)
        .where('date', isEqualTo: date.toIso8601String())
        .get();
    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  void _exportToExcelCSV() {
    if (expenses.isEmpty) return;
    List<List<dynamic>> rows = [
      ["Date", "Supplier", "Category", "Amount (AUD)", "Entity", "Notes", "Receipt Link"]
    ];
    for (var e in expenses) {
      rows.add([
        "${e.date.day}/${e.date.month}/${e.date.year}", e.supplier, e.category,
        e.amount, e.entity, e.description, e.receiptUrl ?? "No Receipt"
      ]);
    }
    String csvData = const ListToCsvConverter().convert(rows);
    final blob = html.Blob([csvData], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", "Tax_Tracker_Export_${DateTime.now().year}.csv")
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (expenses.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total Entries: ${expenses.length}", style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
                FilledButton.icon(
                  onPressed: _exportToExcelCSV,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text("Export CSV"),
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                ),
              ],
            ),
          ),
        Expanded(
          child: expenses.isEmpty 
            ? const Center(child: Text("No entries yet."))
            : ListView.builder(
                itemCount: expenses.length,
                itemBuilder: (context, i) {
                  final e = expenses[i];
                  return Dismissible(
                    key: Key("${e.supplier}_${e.amount}_${e.date.millisecondsSinceEpoch}"),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red, alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("Delete Entry?"),
                          content: Text("Permanently delete entry for ${e.supplier}?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                    },
                    onDismissed: (direction) {
                      _deleteExpense(e.supplier, e.amount, e.date);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${e.supplier} deleted")));
                    },
                    child: ListTile(
                      leading: Icon(Icons.circle, color: Color(e.colorValue)),
                      title: Text("${e.supplier} - \$${e.amount.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${e.entity} • ${e.category}\n${e.date.day}/${e.date.month}/${e.date.year}"),
                      isThreeLine: true,
                      trailing: e.receiptUrl != null 
                        ? IconButton(
                            icon: const Icon(Icons.receipt_long, color: Colors.blue),
                            onPressed: () => showDialog(
                              context: context, 
                              builder: (_) => AlertDialog(
                                contentPadding: EdgeInsets.zero,
                                content: InteractiveViewer(child: Image.network(e.receiptUrl!)),
                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))]
                              )
                            ),
                          )
                        : null,
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }
}